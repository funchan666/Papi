import Foundation
import SwiftUI
import Supabase
import UniformTypeIdentifiers

struct CoffeeReceipt: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var kind:Kind = .information
    enum Kind:Equatable {case information,safety,review,session,welcome,insufficient,purchase}
}
@MainActor final class CoffeeHouse: ObservableObject {
    @Published private(set) var state: CoffeeArchive
    @Published var notice: CoffeeReceipt?
    @Published private(set) var storageAvailable = true
    @Published var activeRoomID: String?
    @Published var selectedTab = 0
    @Published var roomMicRequested = false
    @Published private(set) var accountAction:AccountTransition?
    @Published private(set) var checkoutActive = false
    @Published private(set) var loginInProgress=false
    @Published private(set) var cloudConnectionInProgress=false
    @Published private(set) var cloudWallet: CoffeeCloud.WalletSnapshot?
    @Published private(set) var cloudWalletBusy=false
    @Published private(set) var cloudWalletUnavailable=false
    @Published private(set) var cloudSubmissions: [CoffeeCloud.Moment]?
    @Published private(set) var cloudSubmissionsBusy=false
    @Published private(set) var cloudBrewBusy=false
    @Published private(set) var cloudBrewNeedsAttention=false
    @Published private(set) var cloudBrewHistory: [CoffeeCloud.BrewBookHistory]?
    @Published private(set) var cloudBrewHistoryBusy=false
    @Published private(set) var cloudProfiles: [CoffeeCloud.Profile]?
    @Published private(set) var cloudFollows: [CoffeeCloud.Follow] = []
    @Published private(set) var cloudFriendships: [CoffeeCloud.Friendship] = []
    @Published private(set) var cloudBlocks: [CoffeeCloud.Block] = []
    @Published private(set) var cloudReports: [CoffeeCloud.Report] = []
    @Published private(set) var cloudMessages: [CoffeeCloud.Message] = []
    @Published private(set) var cloudMessagesUnavailable=false
    @Published private(set) var cloudSocialBusy=false
    private var savedSnapshotExpected=false
    private var brewSyncDebounce:Task<Void,Never>?
    init() {
        do {let saved=try CoffeeVault.read();state=saved ?? CoffeeArchive();savedSnapshotExpected=saved != nil}
        catch { state = CoffeeArchive(); storageAvailable = false
            notice = .init(title: "Saved data unavailable", message: error.localizedDescription) }
        if storageAvailable {cleanupPendingMedia()}
    }
    @discardableResult func commit(_ mutate: (inout CoffeeArchive) throws -> Void) -> Bool {
        guard accountAction==nil,!loginInProgress else {return false}
        guard storageAvailable else { inform("Saved data unavailable", "Unlock the device and use Retry in Settings. Your saved data will not be overwritten."); return false }
        let priorBrewGeneration=state.cloudBrewGeneration
        var next = state
        do {
            try mutate(&next)
            try CoffeeVault.write(next)
            savedSnapshotExpected=true
            state = next
            if next.cloudAccountID != nil,next.cloudBrewGeneration != priorBrewGeneration,!cloudBrewBusy {
                brewSyncDebounce?.cancel()
                brewSyncDebounce=Task {
                    do {try await Task.sleep(for:.milliseconds(700))} catch {return}
                    await syncCloudBrewBook()
                }
            }
            return true
        } catch {
            if let vaultError=error as? CoffeeVault.VaultError,case .verification=vaultError {savedSnapshotExpected=true}
            storageAvailable = false; inform("Could not save", error.localizedDescription + " Reopen the app or retry local storage before making more changes."); return false
        }
    }
    func reload() {
        guard accountAction==nil,!checkoutActive,!loginInProgress else{return}
        do {
            if let saved=try CoffeeVault.read() {state=saved;savedSnapshotExpected=true}
            else if savedSnapshotExpected {throw CoffeeVault.VaultError.missingSnapshot}
            storageAvailable=true;cleanupPendingMedia()
        } catch {storageAvailable=false;inform("Saved data unavailable",error.localizedDescription)}
    }
    func inform(_ title: String, _ message: String) { notice = .init(title:title,message:message) }
    func login() async {
        guard !loginInProgress,!state.signedIn,accountAction==nil,storageAvailable else{return}
        loginInProgress=true;defer{loginInProgress=false}
        let clock=ContinuousClock()
        let transitionEnd=clock.now.advanced(by:.milliseconds(450))
        var next=state
        let welcomeID="welcome-"+next.passport.id.uuidString
        if next.acceptedPolicyVersion==nil,next.welcomeGrant==nil,!next.coinMovements.contains(where:{$0.id==welcomeID}) {
            let reward=CoffeeEconomy.welcomeCoins
            next.coinBalance += reward
            next.welcomeGrant=WelcomeGrant(coins:reward)
            next.coinMovements.insert(.init(id:welcomeID,delta:reward,reason:"First brew welcome gift"),at:0)
        }
        next.signedIn=true;next.acceptedPolicyVersion=CoffeePolicyLibrary.version
        let snapshot=next
        do {
            try await Task.detached(priority:.userInitiated){try CoffeeVault.write(snapshot)}.value
            savedSnapshotExpected=true
            // Keep the visual transition legible without delaying a slower save any further.
            try? await clock.sleep(until:transitionEnd)
            state=next;selectedTab=0;presentWelcomeIfNeeded()
        } catch {
            if let vaultError=error as? CoffeeVault.VaultError,case .verification=vaultError {savedSnapshotExpected=true}
            storageAvailable=false
            inform("Could not save",error.localizedDescription + " Reopen the app or retry local storage before making more changes.")
        }
    }
    func presentWelcomeIfNeeded() {
        guard state.signedIn, let grant=state.welcomeGrant, !grant.acknowledged, notice == nil else{return}
        notice = .init(title:"Your first brew is on Papi",message:"\(grant.coins) welcome coins are already in your wallet.",kind:.welcome)
    }
    /// Called only after the online policy is published and explicitly accepted.
    /// The existing device ID, wallet, drafts and transaction records are kept.
    func connectCloudAccount() async throws {
        let requiredPolicy = "2026-10-27-online-1"
        guard state.signedIn, storageAvailable, accountAction == nil, !loginInProgress, !cloudConnectionInProgress,
              !checkoutActive, state.purchaseIntents.isEmpty, state.activePurchaseToken == nil,
              CoffeePolicyLibrary.version == requiredPolicy, state.acceptedPolicyVersion == requiredPolicy else {
            throw CoffeeCloud.ConnectionError.actionUnavailable
        }
        cloudConnectionInProgress = true
        defer { cloudConnectionInProgress = false }
        let owner = state.passport.id
        if state.cloudAccountID == nil, state.cloudBootstrapPending != true {
            try await CoffeeCloud.shared.requireFreshBootstrap()
            guard state.passport.id == owner, state.signedIn,
                  commit({ $0.cloudBootstrapPending = true }) else {
                throw CoffeeCloud.ConnectionError.actionUnavailable
            }
        }
        let account = try await CoffeeCloud.shared.openGuest(expectedID: state.cloudAccountID,
            passport: state.passport, hasPendingBootstrap: state.cloudBootstrapPending == true)
        guard state.passport.id == owner, state.signedIn,
              commit({ $0.cloudAccountID = account; $0.cloudBootstrapPending = false }) else {
            throw CoffeeCloud.ConnectionError.actionUnavailable
        }
        await refreshCloudWallet()
        await syncCloudBrewBook()
        await refreshCloudSocial()
    }
    var usesCloudWallet: Bool { state.cloudAccountID != nil }
    var availableBalance: Int? { usesCloudWallet ? cloudWallet?.balance : state.coinBalance }
    var collectedItems: [String:Int] {
        guard usesCloudWallet else { return state.collectiblesOwned }
        return Dictionary(uniqueKeysWithValues: (cloudWallet?.collectibles ?? []).map { ($0.collectible_id, $0.quantity) })
    }
    var checkinCount: Int { usesCloudWallet ? (cloudWallet?.checkins.count ?? 0) : state.checkinDays.count }
    var currentExperience: Int? { usesCloudWallet ? cloudWallet?.experience : state.experience }

    func refreshCloudWallet() async {
        guard let account=state.cloudAccountID, state.signedIn, !cloudWalletBusy else { return }
        cloudWalletBusy=true
        defer { cloudWalletBusy=false }
        do {
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn, state.cloudAccountID==account else { return }
            cloudWallet=snapshot;cloudWalletUnavailable=false
        } catch {
            guard state.cloudAccountID==account else { return }
            cloudWallet=nil;cloudWalletUnavailable=true
        }
    }

    func refreshCloudSubmissions() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSubmissionsBusy else {return}
        cloudSubmissionsBusy=true
        defer {cloudSubmissionsBusy=false}
        do {
            let items=try await CoffeeCloud.shared.ownMoments(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudSubmissions=items
        } catch {
            guard state.cloudAccountID==account else {return}
            cloudSubmissions=nil
        }
    }

    func refreshCloudSocial() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy else {return}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            let profiles=try await CoffeeCloud.shared.profiles(for:account)
            let follows=try await CoffeeCloud.shared.follows(for:account)
            let friendships=try await CoffeeCloud.shared.friendshipRequests(for:account)
            let blocks=try await CoffeeCloud.shared.blocks(for:account)
            let reports=try await CoffeeCloud.shared.reports(for:account)
            let messages=try await CoffeeCloud.shared.messages(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudProfiles=profiles;cloudFollows=follows;cloudFriendships=friendships;cloudBlocks=blocks;cloudReports=reports;cloudMessages=messages;cloudMessagesUnavailable=false
        } catch {
            guard state.cloudAccountID==account else {return}
            cloudProfiles=nil
        }
    }

    func refreshCloudMessages() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy else {return}
        if cloudProfiles==nil {await refreshCloudSocial();return}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            let messages=try await CoffeeCloud.shared.messages(for:account)
            let follows=try await CoffeeCloud.shared.follows(for:account)
            let known=Set((cloudProfiles ?? []).map(\.id)).union([account])
            let participants=Set(messages.flatMap{[$0.sender_id,$0.recipient_id]})
            var profiles=cloudProfiles
            if !participants.isSubset(of:known) {profiles=try await CoffeeCloud.shared.profiles(for:account)}
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudMessages=messages;cloudFollows=follows;cloudProfiles=profiles;cloudMessagesUnavailable=false
        } catch {if state.cloudAccountID==account {cloudMessagesUnavailable=true}}
    }

    func changeCloudFollow(_ member:UUID,enabled:Bool) async {
        guard let account=state.cloudAccountID,state.signedIn,member != account,!cloudSocialBusy else {return}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            try await CoffeeCloud.shared.setFollow(member,account:account,enabled:enabled)
            let follows=try await CoffeeCloud.shared.follows(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            guard follows.contains(where:{$0.follower_id==account && $0.followed_id==member}) == enabled else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            cloudFollows=follows
        } catch {
            guard state.cloudAccountID==account else {return}
            // A failed response does not establish whether the server applied it.
            if let follows=try? await CoffeeCloud.shared.follows(for:account),state.signedIn,state.cloudAccountID==account {
                cloudFollows=follows
                if follows.contains(where:{$0.follower_id==account && $0.followed_id==member}) == enabled {return}
            }
            inform("Follow needs attention", "The change could not be confirmed. Please try again.")
        }
    }

    func saveCloudProfile(name:String,biography:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy else {return false}
        let pending:PendingCloudProfile
        if let saved=state.pendingCloudProfile {
            guard saved.accountID==account,saved.name==name,saved.biography==biography else {
                inform("Profile needs attention", "Retry the saved profile changes first.");return false
            }
            pending=saved
        } else {
            guard let revision=cloudProfiles?.first(where:{$0.id==account})?.revision else {
                inform("Profile unavailable", "Refresh your profile and try again.");return false
            }
            pending = .init(accountID:account,name:name,biography:biography,revision:revision)
            guard commit({$0.pendingCloudProfile=pending}) else {return false}
        }
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            let profile=try await CoffeeCloud.shared.updateProfile(name:pending.name,biography:pending.biography,revision:pending.revision,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudProfile?.revision==pending.revision else {return false}
            guard commit({value in
                value.passport.name=pending.name;value.passport.bio=pending.biography;value.pendingCloudProfile=nil
            }) else {return false}
            if var profiles=cloudProfiles,let index=profiles.firstIndex(where:{$0.id==account}) {profiles[index]=profile;cloudProfiles=profiles}
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            if let connectionError=error as? CoffeeCloud.ConnectionError,case .profileConflict=connectionError {
                guard commit({$0.pendingCloudProfile=nil}) else {return false}
                cloudProfiles=try? await CoffeeCloud.shared.profiles(for:account)
                inform("Profile changed", "Your profile changed elsewhere. Your edits remain on this page; review them and save again.")
                return false
            }
            inform("Profile needs attention", "The save could not be confirmed. Retry the saved changes.")
            return false
        }
    }

    func changeCloudBlock(_ member:UUID,enabled:Bool) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,member != account,!cloudSocialBusy else {return false}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            do {try await CoffeeCloud.shared.setBlock(member,account:account,enabled:enabled)}
            catch {
                let current=try await CoffeeCloud.shared.blocks(for:account)
                guard current.contains(where:{$0.blocker_id==account && $0.blocked_id==member}) == enabled else {throw error}
            }
            let blocks=try await CoffeeCloud.shared.blocks(for:account)
            let follows=try await CoffeeCloud.shared.follows(for:account)
            let friendships=try await CoffeeCloud.shared.friendshipRequests(for:account)
            let profiles=try await CoffeeCloud.shared.profiles(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return false}
            guard blocks.contains(where:{$0.blocker_id==account && $0.blocked_id==member}) == enabled else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            cloudBlocks=blocks;cloudFollows=follows;cloudFriendships=friendships;cloudProfiles=profiles
            inform(enabled ? "User blocked":"User unblocked",enabled ? "This person's content and conversations are hidden.":"The block has been removed. Following and friendship are not restored automatically.")
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            cloudProfiles=nil
            inform("Block needs attention", "The change could not be confirmed. Refresh and try again.")
            return false
        }
    }

    func requestCloudFriendship(_ member:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy,member != account else {return}
        let pending:PendingCloudFriendship
        if let saved=state.pendingCloudFriendship {
            guard saved.accountID==account,saved.recipientID==member else {inform("Friend request unavailable", "Retry the earlier request before starting another.");return}
            pending=saved
        } else {
            pending = .init(id:UUID(),accountID:account,recipientID:member)
            guard commit({$0.pendingCloudFriendship=pending}) else {return}
        }
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            do {_ = try await CoffeeCloud.shared.requestFriendship(member,account:account,requestID:pending.id)}
            catch {
                let current=try await CoffeeCloud.shared.friendshipRequests(for:account)
                guard current.contains(where:{$0.id==pending.id || (($0.status=="pending" || $0.status=="accepted") && (($0.requester_id==account && $0.recipient_id==member) || ($0.requester_id==member && $0.recipient_id==account)))}) else {throw error}
            }
            let requests=try await CoffeeCloud.shared.friendshipRequests(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudFriendship?.id==pending.id else {return}
            guard commit({$0.pendingCloudFriendship=nil}) else {return}
            cloudFriendships=requests
        } catch {
            guard state.cloudAccountID==account else {return}
            if let databaseError=error as? PostgrestError,databaseError.code=="P0001",databaseError.message=="Mutual following required" {
                _ = commit({$0.pendingCloudFriendship=nil})
                inform("Follow each other first", "Both people must follow each other before requesting friendship.");return
            }
            inform("Friend request unavailable", "The request could not be confirmed. Retry the saved request.")
        }
    }

    func answerCloudFriendship(_ id:UUID,accepted:Bool) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy else {return}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        let desired=accepted ? "accepted":"declined"
        do {
            do {try await CoffeeCloud.shared.respondToFriendship(id,accepted:accepted,account:account)}
            catch {
                let current=try await CoffeeCloud.shared.friendshipRequests(for:account)
                guard current.contains(where:{$0.id==id && $0.recipient_id==account && $0.status==desired}) else {throw error}
            }
            let requests=try await CoffeeCloud.shared.friendshipRequests(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudFriendships=requests
        } catch {if state.cloudAccountID==account {inform("Friend request unavailable", "The answer could not be confirmed. Please try again.")}}
    }

    func cancelCloudFriendship(_ id:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy else {return}
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            do {try await CoffeeCloud.shared.cancelFriendship(id,account:account)}
            catch {
                let current=try await CoffeeCloud.shared.friendshipRequests(for:account)
                guard !current.contains(where:{$0.id==id}) else {throw error}
            }
            let requests=try await CoffeeCloud.shared.friendshipRequests(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudFriendships=requests
        } catch {if state.cloudAccountID==account {inform("Friend request unavailable", "The change could not be confirmed. Please try again.")}}
    }

    func submitCloudReport(_ target:SafetyTarget,reason:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy,
              let subject=UUID(uuidString:target.contentReference),!reason.isEmpty else {return false}
        let kind:String
        switch target.kind {case .user:kind="profile";case .post:kind="post";case .comment:kind="comment";case .message:kind="message";case .room:return false}
        let pending:PendingCloudReport
        if let saved=state.pendingCloudReport {
            guard saved.accountID==account,saved.target.id==target.id,saved.reason==reason else {
                inform("Report needs attention", "Retry the earlier report before submitting another.");return false
            }
            pending=saved
        } else {
            pending = .init(id:UUID(),accountID:account,target:target,reason:reason)
            guard commit({$0.pendingCloudReport=pending}) else {return false}
        }
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            try await CoffeeCloud.shared.report(kind,subject:subject,reason:reason,account:account,reportID:pending.id)
            let reports=try await CoffeeCloud.shared.reports(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudReport?.id==pending.id else {return false}
            guard commit({$0.pendingCloudReport=nil}) else {return false}
            cloudReports=reports
            notice = .init(title:"Report submitted",message:"Your report was sent for review and the item is hidden from your lists.",kind:.safety)
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            inform("Report needs attention", "The result could not be confirmed. Retry the saved report.")
            return false
        }
    }

    func sendCloudMessage(to id:String,text:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy,
              let recipient=UUID(uuidString:id),recipient != account else {return false}
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else {return false}
        guard clean.unicodeScalars.count<=2000 else {inform("Note is too long", "Keep your note under 2,000 characters. Your text has been kept.");return false}
        guard validateCommunityText(clean) else {return false}
        guard state.letterPhotos[id]==nil,state.letterVoiceNotes[id]==nil else {
            inform("Attachment unavailable", "Your photo or voice draft is kept. Send text after removing the attachment.");return false
        }
        let pending:PendingCloudMessage
        if let saved=state.pendingCloudMessage {
            guard saved.accountID==account,saved.recipientID==recipient,saved.body==clean else {
                inform("Message needs attention", "Retry the earlier message before sending another.");return false
            }
            pending=saved
        } else {
            guard isMutual(id) else {inform("Follow each other first", "Both people must follow each other before sending messages. Your draft has been kept.");return false}
            pending = .init(id:UUID(),accountID:account,recipientID:recipient,body:clean)
            guard commit({$0.pendingCloudMessage=pending}) else {return false}
        }
        cloudSocialBusy=true
        defer {cloudSocialBusy=false}
        do {
            try await CoffeeCloud.shared.sendMessage(pending.body,to:recipient,account:account,messageID:pending.id)
            let messages=try await CoffeeCloud.shared.messages(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudMessage?.id==pending.id else {return false}
            guard commit({value in
                value.pendingCloudMessage=nil
                if value.letterDrafts[id]?.trimmingCharacters(in:.whitespacesAndNewlines)==pending.body {value.letterDrafts.removeValue(forKey:id)}
            }) else {return false}
            cloudMessages=messages;cloudMessagesUnavailable=false
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            if let databaseError=error as? PostgrestError,databaseError.code=="P0001",databaseError.message=="Mutual following required" {
                _ = commit({$0.pendingCloudMessage=nil})
                inform("Follow each other first", "Both people must follow each other before sending messages. Your draft has been kept.")
                return false
            }
            if let databaseError=error as? PostgrestError,databaseError.code=="P0001",databaseError.message=="Invalid message" {
                _ = commit({$0.pendingCloudMessage=nil})
                inform("Message unavailable", "The message was not sent. Your draft has been kept.")
                return false
            }
            inform("Message needs attention", "The result could not be confirmed. Retry the saved message.")
            return false
        }
    }

    func retryPendingCloudMessage() async {
        guard let pending=state.pendingCloudMessage else {return}
        if await sendCloudMessage(to:pending.recipientID.uuidString,text:pending.body) {
            inform("Message sent", "Your message was sent.")
        }
    }

    func syncCloudBrewBook() async {
        guard let account=state.cloudAccountID,state.signedIn,storageAvailable,!cloudBrewBusy else {return}
        guard state.cloudBrewConflict != true else {cloudBrewNeedsAttention=true;return}
        cloudBrewBusy=true
        defer {cloudBrewBusy=false}
        do {
            let remote=try await CoffeeCloud.shared.brewBook(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            if state.cloudBrewRevision == nil {
                if let remoteBook=remote.contents {
                    guard state.brewNotebook==nil,state.pendingCloudBrewWrite==nil else {
                        _ = commit({$0.cloudBrewConflict=true});cloudBrewNeedsAttention=true;return
                    }
                    guard commit({value in
                        value.brewNotebook=remoteBook;value.cloudBrewRevision=remote.revision
                        value.cloudBrewGeneration=0;value.cloudBrewSyncedGeneration=0
                    }) else {return}
                } else {
                    guard commit({value in
                        value.cloudBrewRevision=remote.revision
                        value.cloudBrewGeneration=value.cloudBrewGeneration ?? 0
                        value.cloudBrewSyncedGeneration=value.brewNotebook==nil ? (value.cloudBrewGeneration ?? 0):-1
                    }) else {return}
                }
            } else if state.pendingCloudBrewWrite==nil,remote.revision != state.cloudBrewRevision {
                _ = commit({$0.cloudBrewConflict=true});cloudBrewNeedsAttention=true;return
            }

            while state.signedIn,state.cloudAccountID==account,state.cloudBrewConflict != true {
                let pending:PendingCloudBrewWrite
                if let existing=state.pendingCloudBrewWrite {
                    guard existing.accountID==account else {cloudBrewNeedsAttention=true;return}
                    pending=existing
                } else {
                    let generation=state.cloudBrewGeneration ?? 0
                    guard generation != state.cloudBrewSyncedGeneration else {cloudBrewNeedsAttention=false;return}
                    guard let revision=state.cloudBrewRevision else {cloudBrewNeedsAttention=true;return}
                    let encoded=try await CoffeeCloud.shared.encodeBrewBook(state.brewNotebook ?? BrewNotebook())
                    guard state.signedIn,state.cloudAccountID==account else {return}
                    if generation != (state.cloudBrewGeneration ?? 0) {continue}
                    pending = .init(id:UUID(),accountID:account,revision:revision,generation:generation,encodedBook:encoded)
                    guard commit({$0.pendingCloudBrewWrite=pending}) else {return}
                }
                let result=try await CoffeeCloud.shared.saveBrewBook(requestID:pending.id,revision:pending.revision,
                    encodedBook:pending.encodedBook,account:account)
                guard state.signedIn,state.cloudAccountID==account,state.pendingCloudBrewWrite?.id==pending.id else {return}
                if result.current_revision != result.committed_revision {
                    _ = commit({$0.cloudBrewConflict=true});cloudBrewNeedsAttention=true;return
                }
                guard commit({value in
                    value.cloudBrewRevision=result.committed_revision
                    value.cloudBrewSyncedGeneration=pending.generation
                    value.pendingCloudBrewWrite=nil
                }) else {return}
                cloudBrewHistory=nil
            }
        } catch {
            guard state.cloudAccountID==account else {return}
            if let databaseError=error as? PostgrestError,databaseError.code=="P0001",databaseError.message=="Brew book revision conflict" {
                _ = commit({$0.cloudBrewConflict=true})
            }
            cloudBrewNeedsAttention=true
        }
    }

    func resolveCloudBrewConflict(useCloud:Bool) async {
        guard let account=state.cloudAccountID,state.signedIn,state.cloudBrewConflict==true,!cloudBrewBusy,brewBook.activePour==nil else {return}
        cloudBrewBusy=true
        defer {cloudBrewBusy=false}
        do {
            let remote=try await CoffeeCloud.shared.brewBook(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.cloudBrewConflict==true else {return}
            guard commit({value in
                if useCloud {
                    if let local=value.brewNotebook {
                        var backups=value.cloudBrewLocalBackups ?? []
                        backups.append(local);value.cloudBrewLocalBackups=backups
                    }
                    value.brewNotebook=remote.contents
                }
                let generation=(value.cloudBrewGeneration ?? 0)+1
                value.cloudBrewGeneration=generation
                value.cloudBrewSyncedGeneration=useCloud ? generation:-1
                value.cloudBrewRevision=remote.revision
                value.pendingCloudBrewWrite=nil;value.cloudBrewConflict=false
            }) else {return}
            cloudBrewNeedsAttention=false;cloudBrewHistory=nil
            if !useCloud {cloudBrewBusy=false;await syncCloudBrewBook()}
        } catch {
            guard state.cloudAccountID==account else {return}
            cloudBrewNeedsAttention=true
            inform("Brew book unavailable", "Your notes are still saved here. Check your connection and try again.")
        }
    }

    func restoreLastLocalBrewBackup() {
        guard state.cloudBrewConflict != true,!cloudBrewBusy,brewBook.activePour==nil,let saved=state.cloudBrewLocalBackups?.last else {return}
        _ = commit {value in
            var backups=value.cloudBrewLocalBackups ?? []
            if let current=value.brewNotebook {backups.append(current)}
            value.cloudBrewLocalBackups=backups
            value.setBrewNotebook(saved)
        }
    }

    func refreshCloudBrewHistory() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudBrewHistoryBusy else {return}
        cloudBrewHistoryBusy=true
        defer {cloudBrewHistoryBusy=false}
        do {
            let history=try await CoffeeCloud.shared.brewBookHistory(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudBrewHistory=history
        } catch {if state.cloudAccountID==account {cloudBrewHistory=nil}}
    }

    func restoreCloudBrewHistory(_ revision:Int) {
        guard state.cloudBrewConflict != true,!cloudBrewBusy,brewBook.activePour==nil,
              let previous=cloudBrewHistory?.first(where:{$0.revision==revision}) else {return}
        _ = commit {value in
            var backups=value.cloudBrewLocalBackups ?? []
            if let current=value.brewNotebook {backups.append(current)}
            value.cloudBrewLocalBackups=backups
            value.setBrewNotebook(previous.contents)
        }
    }

    func deleteCloudSubmission(_ id:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSubmissionsBusy,!cloudWalletBusy else {return}
        if let pending=state.pendingCloudPostDeletion {
            guard pending.accountID==account,pending.postID==id else {
                inform("Removal needs attention", "Finish removing the previous post before starting another.");return
            }
        } else {
            guard commit({$0.pendingCloudPostDeletion = .init(accountID:account,postID:id)}) else {return}
        }
        cloudSubmissionsBusy=true
        defer {cloudSubmissionsBusy=false}
        do {
            try await CoffeeCloud.shared.deleteMoment(id,account:account)
            let items=try await CoffeeCloud.shared.ownMoments(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudPostDeletion?.postID==id else {return}
            guard commit({$0.pendingCloudPostDeletion=nil}) else {return}
            cloudSubmissions=items
            inform("Post removed", "Your post and its online media have been removed.")
        } catch {
            guard state.cloudAccountID==account else {return}
            cloudSubmissions=nil
            inform("Removal needs attention", "The removal could not be confirmed. Retry to finish removing the post and its online media.")
        }
    }

    func cloudCheckIn() async {
        guard let account=state.cloudAccountID, state.signedIn, cloudWallet != nil, !cloudWalletBusy else { return }
        cloudWalletBusy=true
        defer { cloudWalletBusy=false }
        do {
            let result=try await CoffeeCloud.shared.checkIn(account:account)
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn, state.cloudAccountID==account else { return }
            cloudWallet=snapshot;cloudWalletUnavailable=false
            inform(result.awarded ? "Check-in complete":"Already checked in",
                   result.awarded ? "\(result.reward) coins have been added to your wallet.":"Come back after 00:00 UTC for your next reward.")
        } catch {
            guard state.cloudAccountID==account else { return }
            cloudWallet=nil;cloudWalletUnavailable=true
            inform("Check-in needs attention", "The result could not be confirmed. Refresh your wallet before trying again.")
        }
    }

    func cloudCollect(_ gift:CoffeeCollectible, quantity:Int) async {
        guard let account=state.cloudAccountID, state.signedIn, cloudWallet != nil, !cloudWalletBusy,
              (1...99).contains(quantity) else { return }
        let pending:PendingCloudCollectible
        if let saved=state.pendingCloudCollectible {
            guard saved.accountID==account, saved.item==gift.id, saved.quantity==quantity else {
                inform("Purchase needs attention", "Retry your previous backpack selection before starting another one.");return
            }
            pending=saved
        } else {
            pending = .init(id:UUID(),accountID:account,item:gift.id,quantity:quantity)
            guard commit({$0.pendingCloudCollectible=pending}) else { return }
        }
        cloudWalletBusy=true
        defer { cloudWalletBusy=false }
        do {
            _ = try await CoffeeCloud.shared.collect(item:pending.item,quantity:pending.quantity,orderID:pending.id,account:account)
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn, state.cloudAccountID==account,
                  state.pendingCloudCollectible?.id==pending.id else { return }
            guard commit({$0.pendingCloudCollectible=nil}) else { return }
            cloudWallet=snapshot;cloudWalletUnavailable=false
            inform("Added to your backpack", "\(gift.name) × \(quantity) is saved to your account.")
        } catch {
            guard state.cloudAccountID==account else { return }
            if let databaseError=error as? PostgrestError, databaseError.code=="P0001", databaseError.message=="Insufficient coins" {
                _ = commit({$0.pendingCloudCollectible=nil})
                inform("Not enough coins", "Your backpack selection was not purchased.")
                return
            }
            cloudWallet=nil;cloudWalletUnavailable=true
            inform("Purchase needs attention", "The result could not be confirmed. Refresh and retry the same selection; it will not be charged twice.")
        }
    }

    func cloudUnlockRecipe(_ recipe:BrewRecipe) async {
        guard let account=state.cloudAccountID, state.signedIn, cloudWallet != nil, !cloudWalletBusy else { return }
        cloudWalletBusy=true
        defer { cloudWalletBusy=false }
        do {
            _ = try await CoffeeCloud.shared.unlockRecipe(recipe.id,account:account)
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn, state.cloudAccountID==account else { return }
            cloudWallet=snapshot;cloudWalletUnavailable=false
            notice = .init(title:"A new recipe for your shelf",message:"Your recipe is ready. Every future pour with it is free.",kind:.purchase)
        } catch {
            guard state.cloudAccountID==account else { return }
            if let databaseError=error as? PostgrestError, databaseError.code=="P0001", databaseError.message=="Insufficient coins" {
                inform("Not enough coins", "This recipe was not unlocked.")
                return
            }
            cloudWallet=nil;cloudWalletUnavailable=true
            inform("Recipe needs attention", "The result could not be confirmed. Refresh your wallet and try again.")
        }
    }
    func cloudSubmitMoment() async -> Bool {
        guard let account=state.cloudAccountID, state.signedIn, cloudWallet != nil, !cloudWalletBusy else {return false}
        let draft=state.momentDraft
        let pending:PendingCloudMoment
        if let saved=state.pendingCloudMoment {
            guard saved.accountID==account, saved.media==draft.media, saved.caption==draft.text, saved.isVideo==draft.isVideo else {
                inform("Submission needs attention", "Return to the saved draft and retry its pending submission.");return false
            }
            pending=saved
        } else {
            guard let media=draft.media, media.hasPrefix("local/\(state.passport.id.uuidString)/"),
                  let file=CoffeeMedia.url(media),file.isFileURL else {
                inform("Add a photo or video", "Choose a photo or video saved on this device.");return false
            }
            guard !draft.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
                inform("Add a caption", "Tell the story behind this coffee moment.");return false
            }
            guard draft.text.count<=2000,validateCommunityText(draft.text) else {return false}
            guard let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,
                  size<=52_428_800 else {
                inform("Media too large", "Choose a photo or video smaller than 50 MB. Your draft has been kept.");return false
            }
            let type=UTType(filenameExtension:file.pathExtension)?.preferredMIMEType
            let allowed=draft.isVideo ? ["video/mp4","video/quicktime"]:["image/jpeg","image/png","image/heic"]
            guard let type,allowed.contains(type) else {
                inform("Unsupported media", "Choose a JPEG, PNG, HEIC, MP4 or QuickTime file. Your draft has been kept.");return false
            }
            pending = .init(id:UUID(),accountID:account,caption:draft.text,media:media,isVideo:draft.isVideo)
            guard commit({$0.pendingCloudMoment=pending}) else {return false}
        }
        guard let file=CoffeeMedia.url(pending.media),file.isFileURL,
              let contentType=UTType(filenameExtension:file.pathExtension)?.preferredMIMEType else {
            inform("Media unavailable", "The saved file could not be opened. The submission has not been cleared.");return false
        }
        cloudWalletBusy=true
        defer {cloudWalletBusy=false}
        do {
            let path=try await CoffeeCloud.shared.uploadMedia(file:file,objectID:pending.id,contentType:contentType,account:account)
            _ = try await CoffeeCloud.shared.submitMoment(id:pending.id,caption:pending.caption,path:path,
                kind:pending.isVideo ? "video":"photo",account:account)
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudMoment?.id==pending.id else {return false}
            guard commit({value in
                value.pendingCloudMoment=nil
                if value.momentDraft.media==pending.media && value.momentDraft.text==pending.caption && value.momentDraft.isVideo==pending.isVideo {
                    value.momentDraft=MomentDraft()
                }
            }) else {return false}
            cloudWallet=snapshot;cloudWalletUnavailable=false
            await refreshCloudSubmissions()
            notice = .init(title:"Post submitted for review",message:"Your post is pending review and is not public yet.",kind:.review)
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            if let databaseError=error as? PostgrestError, databaseError.code=="P0001", databaseError.message=="Insufficient coins" {
                guard commit({$0.pendingCloudMoment=nil}) else {return false}
                inform("Not enough coins", "Your post was not submitted. Your draft has been kept.")
                return false
            }
            cloudWallet=nil;cloudWalletUnavailable=true
            inform("Submission needs attention", "The result could not be confirmed. Refresh your wallet and retry the saved submission.")
            return false
        }
    }
    func acknowledgeWelcome() {
        if commit({$0.welcomeGrant?.acknowledged=true}) {notice=nil}
    }
    func beginCheckout() -> Bool {
        guard !checkoutActive,accountAction==nil,!loginInProgress,!cloudWalletBusy,storageAvailable,state.signedIn else{return false}
        checkoutActive=true;return true
    }
    func endCheckout() {checkoutActive=false}
    func insufficientCoins(cost:Int) {
        notice = .init(title:"A little more for your coffee reserve",message:"This needs \(cost) coins. Your balance is \(state.coinBalance). Your draft and selections are kept; recharge to continue.",kind:.insufficient)
    }
    func performAccountAction(_ action:AccountTransition) async {
        guard accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!cloudWalletBusy,!cloudSubmissionsBusy,!cloudBrewBusy,!cloudBrewHistoryBusy,!cloudSocialBusy,storageAvailable else{return}
        if action == .delete && (state.cloudAccountID != nil || state.cloudBootstrapPending == true) {
            inform("Account deletion needs attention", "Your online account has not been removed. Please try again when account deletion is available.")
            return
        }
        guard !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken==nil,state.pendingCloudCollectible==nil,state.pendingCloudMoment==nil,state.pendingCloudPostDeletion==nil,state.pendingCloudReport==nil,state.pendingCloudMessage==nil,state.pendingCloudFriendship==nil,state.pendingCloudProfile==nil else {
            inform("Purchase awaiting review","Resolve the purchase before changing accounts.");return
        }
        accountAction=action
        defer {accountAction=nil}
        var next=state
        if action == .delete {
            let oldID=state.passport.id
            next=CoffeeArchive()
            next.retiredGuestIDs=state.retiredGuestIDs.union([oldID])
            next.historicalTransactionIDs=state.historicalTransactionIDs.union(state.creditedTransactions)
            next.coinPurchaseTerms=state.coinPurchaseTerms
            next.pendingMediaDeletion=state.pendingMediaDeletion.union([oldID])
            next.language=state.language;next.sawOnboarding=false
        } else {next.signedIn=false;next.sawOnboarding=true}
        let snapshot=next
        do {
            try await Task.detached(priority:.userInitiated) {try CoffeeVault.write(snapshot)}.value
            savedSnapshotExpected=true
            brewSyncDebounce?.cancel();brewSyncDebounce=nil
            state=next;cloudWallet=nil;cloudWalletUnavailable=false;cloudSubmissions=nil;cloudBrewNeedsAttention=false;cloudBrewHistory=nil;cloudProfiles=nil;cloudFollows=[];cloudFriendships=[];cloudBlocks=[];cloudReports=[];cloudMessages=[];cloudMessagesUnavailable=false;activeRoomID=nil;roomMicRequested=false;selectedTab=0
            if action == .delete {
                let owners=next.pendingMediaDeletion
                try await Task.detached(priority:.userInitiated) {
                    for owner in owners {try CoffeeMedia.removeGuestDirectory(owner)}
                }.value
                next.pendingMediaDeletion=[]
                let cleaned=next
                try await Task.detached(priority:.userInitiated) {try CoffeeVault.write(cleaned)}.value
                state=next
            }
            notice = .init(title:action == .delete ? "Coffee account deleted":"Logged out",
                           message:action == .delete ? "Your coffee account and its media have been removed. Start a fresh coffee book from the introduction.":"Your saved profile, messages and drafts will be here when you return.",kind:.session)
        } catch {
            // Never overwrite a snapshot after an uncertain write or deletion.
            storageAvailable=false
            inform(action == .delete ? "Deletion needs attention":"Could not log out",error.localizedDescription)
        }
    }
    private func cleanupPendingMedia() {
        for owner in state.pendingMediaDeletion {
            do {
                try CoffeeMedia.removeGuestDirectory(owner)
                guard commit({$0.pendingMediaDeletion.remove(owner)}) else{return}
            } catch {
                inform("Media removal incomplete", "The guest profile was removed, but some local media could not be deleted. Unlock this device and reopen Papi to retry. No new guest can access those files.")
                return
            }
        }
    }
    func toggleLike(_ id: String) {guard post(id) != nil else{return}; _ = commit { if !$0.appreciatedMoments.insert(id).inserted { $0.appreciatedMoments.remove(id) } } }
    func toggleBookmark(_ id: String) {guard post(id) != nil else{return}; _ = commit { if !$0.keptMoments.insert(id).inserted { $0.keptMoments.remove(id) } } }
    func follow(_ id: String) {
        if usesCloudWallet {
            guard cloudProfiles != nil,let member=UUID(uuidString:id) else {return}
            let target = !isFollowing(id)
            Task {await changeCloudFollow(member,enabled:target)}
            return
        }
        guard id != state.passport.id.uuidString, !isUserHidden(id) else { return }
        _ = commit { if !$0.followedMembers.insert(id).inserted { $0.followedMembers.remove(id) } }
    }
    func addComment(momentID: String, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let post = post(momentID), !isUserHidden(post.authorID) else { return false }
        guard clean.count<=2000 else {inform("Note is too long","Keep your note under 2,000 characters. Your text has been kept.");return false}
        guard validateCommunityText(clean) else{return false}
        return commit { $0.tastingReplies.append(.init(momentID:momentID,text:clean,authorID:$0.passport.id.uuidString)) }
    }
    func publish() -> Bool {
        guard !usesCloudWallet else {inform("Post unavailable", "Your post could not be submitted. Your draft is saved.");return false}
        let draft = state.momentDraft
        let cost = CoffeeEconomy.postCost(isVideo:draft.isVideo)
        guard let media = draft.media, CoffeeMedia.url(media) != nil else { inform("Add a photo or video", "Choose a coffee moment before saving your post."); return false }
        guard !draft.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { inform("Add a caption", "Tell the story behind this coffee moment."); return false }
        guard validateCommunityText(draft.text) else{return false}
        guard state.coinBalance >= cost else {insufficientCoins(cost:cost);return false}
        return commit {
            let id = UUID().uuidString
            $0.coinBalance -= cost; $0.coinMovements.insert(.init(id:id,delta:-cost,reason:draft.isVideo ? "Video moment submission":"Photo moment submission"),at:0)
            $0.ownMoments.insert(.init(id:id,authorID:$0.passport.id.uuidString,media:media,isVideo:draft.isVideo,caption:draft.text,category:"My coffee",isOwnMoment:true,moderation:.awaitingSubmission),at:0)
            $0.experience += 10; $0.momentDraft = MomentDraft()
        }
    }
    func deletePost(_ id: String) { _ = commit { $0.ownMoments.removeAll { $0.id == id }; $0.tastingReplies.removeAll { $0.momentID == id }; $0.appreciatedMoments.remove(id); $0.keptMoments.remove(id) } }
    var dayKey: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT:0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from:Date())
    }
    var checkedInToday: Bool {
        guard usesCloudWallet else { return state.checkinDays.contains(dayKey) }
        guard let snapshot=cloudWallet else { return false }
        return dayKey==snapshot.server_day && snapshot.checkins.contains { $0.checkin_day==snapshot.server_day }
    }
    var nextCheckinReward: Int { (checkinCount % 7 + 1) * 10 }
    func checkIn() {
        guard !usesCloudWallet else {return}
        let day = dayKey; let reward = nextCheckinReward
        guard !state.checkinDays.contains(day) else { inform("Already checked in", "Come back after 00:00 UTC for your next reward."); return }
        if commit({
            $0.checkinDays.insert(day); $0.coinBalance += reward; $0.experience += 20
            $0.coinMovements.insert(.init(id:"checkin-"+day,delta:reward,reason:"Daily check-in"),at:0)
        }) { inform("Check-in complete", "\(reward) coins have been added to your wallet.") }
    }
    func collect(_ gift: CoffeeCollectible, quantity: Int) -> Bool {
        guard !usesCloudWallet else {return false}
        guard (1...99).contains(quantity), gift.cost <= Int.max / quantity else { return false }
        let total = gift.cost * quantity
        guard state.coinBalance >= total else {insufficientCoins(cost:total);return false}
        return commit {
            $0.coinBalance -= total; $0.collectiblesOwned[gift.id,default:0] += quantity
            $0.coinMovements.insert(.init(id:UUID().uuidString,delta:-total,reason:"\(gift.name) × \(quantity)"),at:0)
        }
    }
    func previewGift(_ gift: CoffeeCollectible, quantity: Int, context: String) {
        guard (1...99).contains(quantity) else { return }
        if commit({ $0.giftHistory.insert(.init(giftID:gift.id,quantity:quantity,context:context),at:0) }) {
            inform("Gift idea saved", "\(gift.name) × \(quantity). No recipient is connected; no coins or inventory were spent. You can collect this gift for your backpack.")
        }
    }
    @discardableResult func keepTableNote(_ room:CoffeeTable)->Bool {
        guard state.signedIn,isRoomVisible(room) else{return false}
        let note=(state.tableNotes[room.id] ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !note.isEmpty,note.count<=2000,validateCommunityText(note) else{return false}
        return commit {archive in
            var history=archive.tableNoteHistory ?? [:]
            history[room.id,default:[]].append(.init(text:note))
            archive.tableNoteHistory=history
            archive.tableNotes.removeValue(forKey:room.id)
        }
    }
    @discardableResult func enter(_ room: CoffeeTable)->Bool {
        guard isRoomVisible(room) else { return false }
        if commit({ $0.recentRooms.removeAll {$0 == room.id}; $0.recentRooms.insert(room.id,at:0) }) { activeRoomID = room.id;return true }
        return false
    }
    func hasChatDraft(_ id:String)->Bool {
        !(state.letterDrafts[id] ?? "").isEmpty || state.letterPhotos[id] != nil || state.letterVoiceNotes[id] != nil
    }
    func chatPreview(_ id:String)->String {
        if let text=state.letterDrafts[id],!text.isEmpty{return text}
        if state.letterPhotos[id] != nil{return text("Photo draft")}
        return text("Voice draft")
    }
    func clearChatDrafts() {
        guard state.pendingCloudMessage==nil else {inform("Message needs attention", "Retry the saved message before clearing drafts.");return}
        _ = commit {$0.letterDrafts.removeAll();$0.letterPhotos.removeAll();$0.letterVoiceNotes.removeAll()}
    }
}
