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
    private static let onlinePolicyVersion="2026-10-27-online-1"
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
    @Published private(set) var cloudReferenceGuides:[CoffeeCloud.ReferenceGuide]?
    @Published private(set) var cloudSavedScenes:Set<String>?
    @Published private(set) var cloudSavedScenesBusy=false
    @Published private(set) var cloudReferencedProfiles:[UUID:CoffeeCloud.Profile] = [:]
    @Published private(set) var cloudFollows: [CoffeeCloud.Follow] = []
    @Published private(set) var cloudFriendships: [CoffeeCloud.Friendship] = []
    @Published private(set) var cloudBlocks: [CoffeeCloud.Block] = []
    @Published private(set) var cloudReports: [CoffeeCloud.Report] = []
    @Published private(set) var cloudMessages: [CoffeeCloud.Message] = []
    @Published private(set) var cloudMessagesUnavailable=false
    @Published private(set) var cloudSocialBusy=false
    @Published private(set) var cloudFeed:[CoffeeCloud.FeedMoment]?
    @Published private(set) var cloudFeedBusy=false
    @Published private(set) var cloudFeedHasMore=false
    @Published private(set) var cloudShelves:[String:[CoffeeCloud.FeedMoment]] = [:]
    @Published private(set) var cloudShelfHasMore:[String:Bool] = [:]
    @Published private(set) var cloudShelfBusy:Set<String> = []
    @Published private(set) var cloudComments:[UUID:[CoffeeCloud.Comment]] = [:]
    @Published private(set) var cloudCommentsHasMore:[UUID:Bool] = [:]
    @Published private(set) var cloudCommentsBusy=false
    @Published private(set) var editorialSummaries:[String:CoffeeCloud.EditorialSummary] = [:]
    @Published private(set) var editorialComments:[String:[CoffeeCloud.EditorialComment]] = [:]
    @Published private(set) var editorialReportedPosts:Set<String> = []
    @Published private(set) var editorialReportsReady=false
    @Published private(set) var editorialSummariesUnavailable=false
    @Published private(set) var editorialBusy=false
    @Published private(set) var cloudImageSummaries:[UUID:CoffeeCloud.ProfileImageSummary] = [:]
    @Published private(set) var cloudProfileImages:[UUID:[CoffeeCloud.ProfileImage]] = [:]
    @Published private(set) var cloudProfileImagesHasMore:[UUID:Bool] = [:]
    @Published private(set) var cloudProfileMediaBusy=false
    @Published private(set) var cloudConversations:[UUID:[CoffeeCloud.Message]] = [:]
    @Published private(set) var cloudConversationHasMore:[UUID:Bool] = [:]
    @Published private(set) var cloudConversationBusy:Set<UUID> = []
    @Published private(set) var cloudConversationUnavailable:Set<UUID> = []
    @Published private(set) var cloudCalls:[CoffeeCloud.CallSession]?
    @Published private(set) var cloudCallsBusy=false
    @Published private(set) var cloudVoiceTopics:[CoffeeCloud.VoiceTopic]?
    @Published private(set) var cloudVoiceTopicsBusy=false
    @Published private(set) var cloudVoiceBusy=false
    @Published private(set) var emailLinkBusy=false
    // Keep disabled until LiveKit credentials, session revocation and acceptance are verified.
    let liveCallsEnabled=true
    let liveVoiceEnabled=true
    // Enable only after email delivery, identity linking and recovery are verified.
    let emailLinkEnabled=false
    // Enable only when server deletion, revocation and recovery are verified.
    let cloudDeletionEnabled=true
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
        guard state.pendingCloudDeletionID==nil else {inform("Online deletion in progress", "Finish the saved deletion before changing this account.");return false}
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
    func login(acceptedPolicies:Bool) async {
        guard acceptedPolicies,!loginInProgress,!state.signedIn,accountAction==nil,storageAvailable else{return}
        loginInProgress=true;defer{loginInProgress=false}
        let clock=ContinuousClock()
        let transitionEnd=clock.now.advanced(by:.milliseconds(450))
        guard await PapiNetworkCoordinator.shared.probe(),!Task.isCancelled else {
            inform("Online connection needs attention","Your saved device data is kept. Check your connection and try again.");return
        }
        // Preserve the existing post-deletion recovery path and its device data.
        if state.deletedCloudAccountID == nil {
            guard state.pendingCloudDeletionID == nil,state.pendingCloudRecoveryID == nil,
                  !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken == nil else {
                inform("Account action needs attention","Finish the saved account or purchase activity before signing in.");return
            }
            if state.cloudAccountID == nil,state.cloudBootstrapPending != true {
                do {try await CoffeeCloud.shared.requireFreshBootstrap()}
                catch {inform("Online connection needs attention","Your saved device data is kept. Please try again.");return}
                var pending=state
                pending.cloudBootstrapPending=true
                do {
                    let snapshot=pending
                    try await Task.detached(priority:.userInitiated){try CoffeeVault.write(snapshot)}.value
                    savedSnapshotExpected=true;state=pending
                } catch {
                    storageAvailable=false;inform("Could not save","Your saved device data is kept. Unlock the device and retry.");return
                }
            }
            do {
                let account=try await CoffeeCloud.shared.openGuest(expectedID:state.cloudAccountID,
                    passport:state.passport,hasPendingBootstrap:state.cloudBootstrapPending == true)
                guard !Task.isCancelled,state.cloudAccountID == nil || state.cloudAccountID == account else {return}
                var connected=state
                connected.cloudAccountID=account;connected.cloudBootstrapPending=false
                do {
                    let snapshot=connected
                    try await Task.detached(priority:.userInitiated){try CoffeeVault.write(snapshot)}.value
                    savedSnapshotExpected=true;state=connected
                } catch {
                    storageAvailable=false;inform("Could not save","Your online session is kept. Unlock the device and retry.");return
                }
            } catch {
                PapiNetworkCoordinator.shared.markFailed()
                inform("Online connection needs attention","Your saved device data is kept. Check your connection and try again.");return
            }
        }
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
        let requiredPolicy = Self.onlinePolicyVersion
        guard state.signedIn, storageAvailable, accountAction == nil, !loginInProgress, !cloudConnectionInProgress,!emailLinkBusy,
              !checkoutActive, state.purchaseIntents.isEmpty, state.activePurchaseToken == nil,state.pendingCloudRecoveryID==nil,
              state.pendingCloudDeletionID==nil,state.deletedCloudAccountID==nil,
              CoffeePolicyLibrary.version == requiredPolicy, state.acceptedPolicyVersion == requiredPolicy else {
            throw CoffeeCloud.ConnectionError.actionUnavailable
        }
        cloudConnectionInProgress = true
        defer { cloudConnectionInProgress = false }
        guard await PapiNetworkCoordinator.shared.probe(),!Task.isCancelled else {
            throw CoffeeCloud.ConnectionError.actionUnavailable
        }
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
    var onlinePolicyRenewalRequired:Bool {
        state.signedIn && state.cloudAccountID == nil && state.pendingCloudRecoveryID == nil && state.pendingCloudDeletionID == nil && state.deletedCloudAccountID == nil &&
        CoffeePolicyLibrary.version == Self.onlinePolicyVersion && state.acceptedPolicyVersion != Self.onlinePolicyVersion
    }
    func acceptOnlinePolicy() {
        guard onlinePolicyRenewalRequired else{return}
        _ = commit {$0.acceptedPolicyVersion=Self.onlinePolicyVersion}
    }
    var cloudConnectionRequired:Bool {
        state.signedIn && state.cloudAccountID==nil && state.pendingCloudDeletionID==nil &&
        state.pendingCloudRecoveryID==nil && state.deletedCloudAccountID==nil &&
        CoffeePolicyLibrary.version==Self.onlinePolicyVersion && state.acceptedPolicyVersion==Self.onlinePolicyVersion
    }
    func resumeCloudConnection() async {
        guard cloudConnectionRequired,!loginInProgress,!cloudConnectionInProgress,storageAvailable else{return}
        do {try await connectCloudAccount()}
        catch {
            if cloudConnectionRequired {inform("Online connection needs attention", "Your saved device data is kept. Check your connection and try again.")}
        }
    }
    func prepareNewCloudAccount() async {
        guard state.signedIn,let deleted=state.deletedCloudAccountID,state.cloudAccountID==nil,
              state.pendingCloudDeletionID==nil,state.pendingCloudRecoveryID==nil,
              accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!emailLinkBusy,
              !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken==nil,storageAvailable else{return}
        do {
            try await CoffeeCloud.shared.requireFreshBootstrap()
            guard state.signedIn,state.deletedCloudAccountID==deleted,state.cloudAccountID==nil,
                  accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!emailLinkBusy,
                  !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken==nil,storageAvailable else{return}
            _ = commit { value in
                if let pending=value.pendingCloudBrewWrite {
                    value.retiredCloudBrewWrites=(value.retiredCloudBrewWrites ?? [])+[pending]
                }
                value.pendingCloudBrewWrite=nil
                value.cloudBrewRevision=nil;value.cloudBrewGeneration=nil;value.cloudBrewSyncedGeneration=nil;value.cloudBrewConflict=nil
                value.deletedCloudAccountID=nil;value.cloudBootstrapPending=false
                value.acceptedPolicyVersion=nil
            }
        } catch {
            inform("Online account needs attention", "Your device data is kept. A saved online session needs review before creating a new account.")
        }
    }
    var usesCloudWallet: Bool { state.cloudAccountID != nil }

    func requestEmailLink(_ address:String) async -> Bool {
        guard emailLinkEnabled,let account=state.cloudAccountID,state.signedIn,accountAction==nil,!loginInProgress,!checkoutActive,!emailLinkBusy else{return false}
        let email=address.trimmingCharacters(in:.whitespacesAndNewlines)
        guard email.count<=254,!email.contains(where:{$0.isWhitespace}),email.contains("@") else {
            inform("Check your email", "Enter the email address you want to use for this account.");return false
        }
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {
            try await CoffeeCloud.shared.beginEmailLink(email,account:account)
            guard state.signedIn,state.cloudAccountID==account else{return false}
            return true
        } catch {
            if state.cloudAccountID==account {inform("Email link needs attention", "The request could not be confirmed. Your guest account is unchanged; try again or finish a previous verification.")}
            return false
        }
    }
    func verifyEmailLink(_ address:String,code:String) async -> Bool {
        guard emailLinkEnabled,let account=state.cloudAccountID,state.signedIn,accountAction==nil,!loginInProgress,!checkoutActive,!emailLinkBusy else{return false}
        let email=address.trimmingCharacters(in:.whitespacesAndNewlines)
        let token=code.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !email.isEmpty,(6...8).contains(token.utf8.count),token.utf8.allSatisfy({(48...57).contains($0)}) else {
            inform("Check your code", "Enter the verification code sent to your email.");return false
        }
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {
            try await CoffeeCloud.shared.verifyEmailLink(email,code:token,account:account)
            guard state.signedIn,state.cloudAccountID==account else{return false}
            inform("Email linked", "Your guest account now has a verified email. Keep this device until account recovery is available.")
            return true
        } catch {
            if state.cloudAccountID==account {inform("Verification needs attention", "The result could not be confirmed. Your local coffee book is kept; retry the saved verification.")}
            return false
        }
    }
    func resumeEmailLink() async {
        guard emailLinkEnabled,let account=state.cloudAccountID,state.signedIn,accountAction==nil,!loginInProgress,!checkoutActive,!emailLinkBusy else{return}
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {
            let recovered=try await CoffeeCloud.shared.resumeEmailLink(account:account)
            if recovered,state.signedIn,state.cloudAccountID==account {inform("Email linked", "Your verified account session was recovered on this device.")}
        } catch {if state.cloudAccountID==account {inform("Verification needs attention", "Your saved verification is still protected on this device. Try again when connected.")}}
    }

    private var emailRecoveryAllowed:Bool {
        emailLinkEnabled && state.signedIn && !checkoutActive && state.purchaseIntents.isEmpty && state.activePurchaseToken==nil &&
        state.cloudAccountID==nil && state.cloudBootstrapPending != true && state.pendingCloudDeletionID==nil && state.deletedCloudAccountID==nil &&
        state.cloudBrewRevision==nil && state.pendingCloudBrewWrite==nil && state.pendingCloudMoment==nil &&
        state.pendingCloudPostDeletion==nil && state.pendingCloudCollectible==nil && state.pendingCloudRoomGift==nil && state.pendingCloudMessage==nil &&
        state.pendingCloudAttachment==nil && state.pendingCloudFriendship==nil && state.pendingCloudReport==nil &&
        state.pendingCloudProfile==nil && state.pendingCloudComment==nil && state.pendingCloudEditorialComment==nil && state.pendingCloudProfileImage==nil &&
        state.pendingCloudProfileImageRemoval==nil && state.pendingCloudCall==nil && state.pendingCloudCallEnd==nil && state.pendingCloudVoice==nil &&
        CoffeePolicyLibrary.version=="2026-10-27-online-1" && state.acceptedPolicyVersion=="2026-10-27-online-1"
    }
    func requestEmailRecovery(_ address:String) async -> Bool {
        guard emailRecoveryAllowed,state.pendingCloudRecoveryID==nil,accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!emailLinkBusy else{return false}
        let email=address.trimmingCharacters(in:.whitespacesAndNewlines)
        guard email.count<=254,!email.contains(where:{$0.isWhitespace}),email.contains("@") else {
            inform("Check your email", "Enter the email address you want to use for this account.");return false
        }
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {try await CoffeeCloud.shared.requestEmailRecovery(email);return true}
        catch {inform("Recovery needs attention", "The request could not be confirmed. Your device data is unchanged; try again or finish the saved recovery.");return false}
    }
    func verifyEmailRecovery(_ address:String,code:String) async -> Bool {
        guard emailRecoveryAllowed,state.pendingCloudRecoveryID==nil,accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!emailLinkBusy else{return false}
        let email=address.trimmingCharacters(in:.whitespacesAndNewlines),token=code.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !email.isEmpty,(6...8).contains(token.utf8.count),token.utf8.allSatisfy({(48...57).contains($0)}) else {
            inform("Check your code", "Enter the verification code sent to your email.");return false
        }
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {
            let account=try await CoffeeCloud.shared.verifyEmailRecovery(email,code:token)
            guard emailRecoveryAllowed,state.pendingCloudRecoveryID==nil,
                  commit({$0.pendingCloudRecoveryID=account}) else {return false}
            return try await finishEmailRecovery(account)
        } catch {
            inform("Recovery needs attention", "The result could not be confirmed. Your device data is kept; retry the saved recovery.")
            return false
        }
    }
    func resumeEmailRecovery() async -> Bool {
        guard emailRecoveryAllowed,accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!emailLinkBusy else{return false}
        emailLinkBusy=true;defer{emailLinkBusy=false}
        do {
            let account:UUID
            if let pending=state.pendingCloudRecoveryID {account=pending}
            else {
                try await CoffeeCloud.shared.requireFreshBootstrap()
                guard let saved=try await CoffeeCloud.shared.pendingEmailRecoveryAccount() else {
                    inform("No saved recovery", "Request a new verification code to recover your account.");return false
                }
                guard commit({$0.pendingCloudRecoveryID=saved}) else{return false}
                account=saved
            }
            return try await finishEmailRecovery(account)
        } catch {
            inform("Recovery needs attention", "The result could not be confirmed. Your device data is kept; retry the saved recovery.")
            return false
        }
    }
    private func finishEmailRecovery(_ account:UUID) async throws -> Bool {
        guard emailRecoveryAllowed,state.pendingCloudRecoveryID==account else{return false}
        try await CoffeeCloud.shared.finishEmailRecovery(account:account)
        let profiles=try await CoffeeCloud.shared.profiles(ids:[account],account:account)
        guard profiles.count==1,profiles[0].id==account,emailRecoveryAllowed,state.pendingCloudRecoveryID==account else {throw CoffeeCloud.ConnectionError.profileUnavailable}
        guard commit({$0.cloudAccountID=account;$0.pendingCloudRecoveryID=nil;$0.cloudBootstrapPending=false}) else{return false}
        await refreshCloudWallet();await syncCloudBrewBook();await refreshCloudSocial()
        inform("Account recovered", "Your online account is open. Existing device data is still saved here and has not been merged automatically.")
        return true
    }
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
        do {try await CoffeeCloud.shared.bootstrap(account:account)}
        catch {if state.cloudAccountID==account {cloudProfiles=nil};return}
        if let entries=try? await CoffeeCloud.shared.mediaCatalog(account:account),
           state.signedIn,state.cloudAccountID==account,let first=entries.first,
           entries.allSatisfy({$0.base_url==first.base_url && $0.asset==$0.item.asset}) {
            _ = CoffeeCollection.useCloud(baseURL:first.base_url,items:entries.map(\.item))
        }
        if let people=try? await CoffeeCloud.shared.editorialPeople(account:account),
           state.signedIn,state.cloudAccountID==account {
            _ = CoffeeCollection.useCloudPeople(people)
        }
        if let guides=try? await CoffeeCloud.shared.referenceGuides(account:account),
           state.signedIn,state.cloudAccountID==account,
           Set(guides.map(\.id)).count==guides.count {
            cloudReferenceGuides=guides
        }
        if let recipes=try? await CoffeeCloud.shared.brewRecipes(account:account),
           state.signedIn,state.cloudAccountID==account {
            _ = CoffeeCollection.useCloudRecipes(recipes)
        }
        if let gifts=try? await CoffeeCloud.shared.giftCatalog(account:account),
           state.signedIn,state.cloudAccountID==account {
            _ = CoffeeCollection.useCloudGifts(gifts)
        }
        do {
            let profiles=try await CoffeeCloud.shared.profiles(for:account)
            let imageSummaries=try await CoffeeCloud.shared.profileImageSummaries(profiles.map(\.id),account:account)
            let follows=try await CoffeeCloud.shared.follows(for:account)
            let friendships=try await CoffeeCloud.shared.friendshipRequests(for:account)
            let blocks=try await CoffeeCloud.shared.blocks(for:account)
            let reports=try await CoffeeCloud.shared.reports(for:account)
            let messages=try await CoffeeCloud.shared.messages(for:account)
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudProfiles=profiles;cloudImageSummaries=Dictionary(uniqueKeysWithValues:imageSummaries.map{($0.owner_id,$0)});cloudFollows=follows;cloudFriendships=friendships;cloudBlocks=blocks;cloudReports=reports;cloudMessages=messages;cloudMessagesUnavailable=false
            let knownAuthors=Set((cloudFeed ?? []).map(\.author_id))
                .union(cloudShelves.values.flatMap{$0.map(\.author_id)})
                .union(cloudComments.values.flatMap{$0.map(\.author_id)})
                .union(messages.flatMap{[$0.sender_id,$0.recipient_id]})
            await ensureCloudProfiles(knownAuthors)
        } catch {
            guard state.cloudAccountID==account else {return}
            cloudProfiles=nil
        }
    }

    func refreshSavedScenes() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSavedScenesBusy else{return}
        cloudSavedScenesBusy=true;defer{cloudSavedScenesBusy=false}
        do {
            let scenes=try await CoffeeCloud.shared.savedScenes(account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            cloudSavedScenes=scenes
        } catch {if state.cloudAccountID==account {cloudSavedScenes=nil}}
    }
    func setSavedScene(_ scene:String,enabled:Bool) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSavedScenesBusy,cloudSavedScenes != nil else{return}
        cloudSavedScenesBusy=true;defer{cloudSavedScenesBusy=false}
        do {
            try await CoffeeCloud.shared.setSavedScene(scene,enabled:enabled,account:account)
            let scenes=try await CoffeeCloud.shared.savedScenes(account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            cloudSavedScenes=scenes
        } catch {
            if state.cloudAccountID==account {cloudSavedScenes=nil;inform("Saved scenes unavailable","The update could not be confirmed. Please retry.")}
        }
    }

    func refreshCloudProfileImages(owner:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudProfileMediaBusy else{return}
        cloudProfileMediaBusy=true;defer{cloudProfileMediaBusy=false}
        do {
            let images=try await CoffeeCloud.shared.profileImages(owner:owner,account:account)
            let summaries=try await CoffeeCloud.shared.profileImageSummaries([owner],account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            cloudProfileImages[owner]=images;cloudProfileImagesHasMore[owner]=images.count==100
            cloudImageSummaries[owner]=summaries.first
        } catch {guard state.cloudAccountID==account else{return};cloudProfileImages.removeValue(forKey:owner);cloudProfileImagesHasMore.removeValue(forKey:owner);cloudImageSummaries.removeValue(forKey:owner)}
    }

    func loadMoreCloudProfileImages(owner:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudProfileMediaBusy,
              cloudProfileImagesHasMore[owner]==true,let last=cloudProfileImages[owner]?.last else{return}
        cloudProfileMediaBusy=true;defer{cloudProfileMediaBusy=false}
        do {
            let more=try await CoffeeCloud.shared.profileImages(owner:owner,account:account,before:last)
            guard state.signedIn,state.cloudAccountID==account,var current=cloudProfileImages[owner] else{return}
            let known=Set(current.map(\.id));current.append(contentsOf:more.filter{!known.contains($0.id)})
            cloudProfileImages[owner]=current;cloudProfileImagesHasMore[owner]=more.count==100
        } catch {if state.cloudAccountID==account {inform("Photos unavailable", "More photos could not be loaded. Please try again.")}}
    }

    func submitCloudProfileImage(reference:String,kind:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudProfileMediaBusy,["avatar","cover","album"].contains(kind) else{return false}
        let pending:PendingCloudProfileImage
        if let saved=state.pendingCloudProfileImage {
            guard saved.accountID==account,saved.reference==reference,saved.kind==kind else {inform("Photo needs attention", "Retry the saved photo first.");return false}
            pending=saved
        } else {
            guard reference.hasPrefix("local/\(state.passport.id.uuidString)/"),let file=CoffeeMedia.url(reference),file.isFileURL,
                  file.pathExtension.lowercased()=="jpg" else {inform("Photo unavailable", "Choose a photo saved on this device.");return false}
            guard let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=52_428_800 else {
                inform("Media too large", "Choose a photo smaller than 50 MB. Your original file has been kept.");return false
            }
            pending = .init(id:UUID(),accountID:account,reference:reference,kind:kind)
            guard commit({$0.pendingCloudProfileImage=pending}) else{return false}
        }
        guard let file=CoffeeMedia.url(pending.reference),file.isFileURL else {inform("Photo unavailable", "The original file is still needed for this upload.");return false}
        cloudProfileMediaBusy=true
        do {
            _ = try await CoffeeCloud.shared.uploadMedia(file:file,objectID:pending.id,contentType:"image/jpeg",account:account,profileImage:true)
            try await CoffeeCloud.shared.submitProfileImage(id:pending.id,kind:pending.kind,account:account)
            let item=try await CoffeeCloud.shared.profileImage(pending.id,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudProfileImage?.id==pending.id else {cloudProfileMediaBusy=false;return false}
            guard let item,item.owner_id==account,item.kind==pending.kind else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            guard commit({$0.pendingCloudProfileImage=nil}) else {cloudProfileMediaBusy=false;return false}
            cloudProfileMediaBusy=false
            await refreshCloudProfileImages(owner:account)
            inform("Photo submitted", "Your photo is visible to others after review.")
            return true
        } catch {
            cloudProfileMediaBusy=false
            guard state.cloudAccountID==account else{return false}
            inform("Photo needs attention", "The upload could not be confirmed. Retry the saved photo.")
            return false
        }
    }

    func removeCloudProfileImage(_ id:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudProfileMediaBusy else{return}
        if let pending=state.pendingCloudProfileImageRemoval {
            guard pending.accountID==account,pending.id==id else {inform("Removal needs attention", "Finish removing the previous photo first.");return}
        } else if !commit({$0.pendingCloudProfileImageRemoval = .init(id:id,accountID:account)}) {return}
        cloudProfileMediaBusy=true
        do {
            try await CoffeeCloud.shared.deleteProfileImage(id:id,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudProfileImageRemoval?.id==id else {cloudProfileMediaBusy=false;return}
            guard commit({$0.pendingCloudProfileImageRemoval=nil}) else {cloudProfileMediaBusy=false;return}
            cloudProfileMediaBusy=false
            await refreshCloudProfileImages(owner:account)
            inform("Photo removed", "The online photo has been removed. Your original file remains on this device.")
        } catch {
            cloudProfileMediaBusy=false
            guard state.cloudAccountID==account else{return}
            cloudProfileImages.removeValue(forKey:account);cloudProfileImagesHasMore.removeValue(forKey:account);cloudImageSummaries.removeValue(forKey:account)
            inform("Removal needs attention", "The online removal could not be confirmed. Retry the same photo.")
        }
    }

    func refreshCloudFeed() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudFeedBusy,!editorialBusy else{return}
        cloudFeedBusy=true;defer{cloudFeedBusy=false}
        if let entries=try? await CoffeeCloud.shared.editorialCatalog(account:account),
           state.signedIn,state.cloudAccountID==account {
            let conversations=entries.compactMap(\.conversation)
            _ = CoffeeCollection.useCloudEditorial(entries.map(\.moment),conversations:conversations)
        }
        do {
            let feed=try await CoffeeCloud.shared.recentMoments(for:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            cloudFeed=feed;cloudFeedHasMore=feed.count==50
            await ensureCloudProfiles(Set(feed.map(\.author_id)))
        } catch {
            guard state.cloudAccountID==account else{return}
            cloudFeed=nil;cloudFeedHasMore=false
        }
        do {
            let reported=try await CoffeeCloud.shared.editorialReportedPosts(account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            editorialReportedPosts=Set(reported.map(\.content_id));editorialReportsReady=true
        } catch {
            guard state.cloudAccountID==account else{return}
            editorialReportsReady=false
        }
        do {
            let summaries=try await CoffeeCloud.shared.editorialSummary(CoffeeMoment.editorial.map(\.id),account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            editorialSummaries=Dictionary(uniqueKeysWithValues:summaries.map{($0.content_id,$0)});editorialSummariesUnavailable=false
        } catch {
            guard state.cloudAccountID==account else{return}
            editorialSummaries=[:];editorialSummariesUnavailable=true
        }
    }

    func ensureCloudProfiles(_ ids:Set<UUID>) async {
        guard let account=state.cloudAccountID,state.signedIn else{return}
        let known=Set((cloudProfiles ?? []).map(\.id)).union(cloudReferencedProfiles.keys)
        let missing=Array(ids.subtracting(known))
        do {
            for start in stride(from:0,to:missing.count,by:80) {
                let batch=Array(missing[start..<min(start+80,missing.count)])
                let profiles=try await CoffeeCloud.shared.profiles(ids:batch,account:account)
                guard state.signedIn,state.cloudAccountID==account else{return}
                for profile in profiles {cloudReferencedProfiles[profile.id]=profile}
                if var now=cloudProfiles {
                    let existing=Set(now.map(\.id));now.append(contentsOf:profiles.filter{!existing.contains($0.id)});cloudProfiles=now
                }
            }
        } catch {if state.cloudAccountID != account {return}}
        let missingImages=Array(ids.subtracting(cloudImageSummaries.keys))
        do {
            for start in stride(from:0,to:missingImages.count,by:80) {
                let batch=Array(missingImages[start..<min(start+80,missingImages.count)])
                let summaries=try await CoffeeCloud.shared.profileImageSummaries(batch,account:account)
                guard state.signedIn,state.cloudAccountID==account else{return}
                for item in summaries {cloudImageSummaries[item.owner_id]=item}
            }
        } catch {return}
    }
    func refreshCloudVoiceTopics() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudVoiceTopicsBusy else{return}
        cloudVoiceTopicsBusy=true;defer{cloudVoiceTopicsBusy=false}
        do {let topics=try await CoffeeCloud.shared.voiceTopics(account:account);guard state.signedIn,state.cloudAccountID==account else{return};cloudVoiceTopics=topics}
        catch {if state.cloudAccountID==account {cloudVoiceTopics=nil}}
    }

    func startCloudVoice(_ topic:String) async -> PendingCloudVoice? {
        guard liveVoiceEnabled,let account=state.cloudAccountID,state.signedIn,!cloudVoiceBusy else{return nil}
        let session:PendingCloudVoice
        if let saved=state.pendingCloudVoice {
            guard saved.accountID==account,saved.topic==topic,!saved.closing else {
                inform("Voice session needs attention", "Finish the earlier voice session before joining another.");return nil
            }
            session=saved
        } else {
            guard cloudVoiceTopics?.contains(where:{$0.id==topic})==true else {return nil}
            session = .init(id:UUID(),accountID:account,topic:topic,closing:false)
            guard commit({$0.pendingCloudVoice=session}) else{return nil}
        }
        cloudVoiceBusy=true
        do {
            let accepted=try await CoffeeCloud.shared.voiceSession(topic:topic,id:session.id,account:account,operation:.enter)
            cloudVoiceBusy=false
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudVoice?.id==session.id else{return nil}
            if state.pendingCloudVoice?.closing==true {await finishCloudVoice(expectedID:session.id);return nil}
            guard accepted else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            return session
        } catch {
            cloudVoiceBusy=false
            guard state.cloudAccountID==account,state.pendingCloudVoice?.id==session.id else{return nil}
            if state.pendingCloudVoice?.closing==true {await finishCloudVoice(expectedID:session.id)}
            else {inform("Voice session needs attention", "The room could not be opened. Retry the saved session or finish it in Settings.")}
            return nil
        }
    }
    func finishCloudVoice(expectedID:UUID? = nil) async {
        guard let account=state.cloudAccountID,state.signedIn,let saved=state.pendingCloudVoice,saved.accountID==account else{return}
        guard expectedID==nil || expectedID==saved.id else{return}
        if !saved.closing, !commit({$0.pendingCloudVoice?.closing=true}) {return}
        guard !cloudVoiceBusy else{return}
        cloudVoiceBusy=true;defer{cloudVoiceBusy=false}
        do {
            let closed=try await CoffeeCloud.shared.voiceSession(topic:saved.topic,id:saved.id,account:account,operation:.leave)
            guard closed,state.signedIn,state.cloudAccountID==account,state.pendingCloudVoice?.id==saved.id else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            _ = commit({$0.pendingCloudVoice=nil})
        } catch {
            if state.cloudAccountID==account {inform("Voice session needs attention", "The room could not be closed yet. Retry in Settings.")}
        }
    }

    func loadMoreCloudFeed() async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudFeedBusy,cloudFeedHasMore,let last=cloudFeed?.last else{return}
        cloudFeedBusy=true;defer{cloudFeedBusy=false}
        do {
            let next=try await CoffeeCloud.shared.recentMoments(for:account,before:last)
            guard state.signedIn,state.cloudAccountID==account,var current=cloudFeed else{return}
            let existing=Set(current.map(\.id));current.append(contentsOf:next.filter{!existing.contains($0.id)})
            cloudFeed=current;cloudFeedHasMore=next.count==50
            await ensureCloudProfiles(Set(next.map(\.author_id)))
        } catch {guard state.cloudAccountID==account else{return};inform("Moments unavailable", "More moments could not be loaded. Please try again.")}
    }

    func cloudShelfKey(author:UUID?,saved:Bool)->String {
        saved ? "saved":"author:"+(author?.uuidString ?? "none")
    }

    func loadCloudShelf(author:UUID?,saved:Bool,more:Bool=false) async {
        guard let account=state.cloudAccountID,state.signedIn,(saved && author==nil) || (!saved && author != nil) else{return}
        let key=cloudShelfKey(author:author,saved:saved)
        guard !cloudShelfBusy.contains(key) else{return}
        if more && (cloudShelfHasMore[key] != true || cloudShelves[key]?.last == nil) {return}
        let cursor=more ? cloudShelves[key]?.last:nil
        cloudShelfBusy.insert(key);defer{cloudShelfBusy.remove(key)}
        do {
            let page=try await CoffeeCloud.shared.momentShelf(for:account,author:author,saved:saved,before:cursor)
            guard state.signedIn,state.cloudAccountID==account else{return}
            if more {
                var current=cloudShelves[key] ?? []
                let known=Set(current.map(\.id));current.append(contentsOf:page.filter{!known.contains($0.id)})
                cloudShelves[key]=current
            } else {cloudShelves[key]=page}
            cloudShelfHasMore[key]=page.count==50
            await ensureCloudProfiles(Set(page.map(\.author_id)))
        } catch {
            guard state.cloudAccountID==account else{return}
            if !more {cloudShelves.removeValue(forKey:key);cloudShelfHasMore.removeValue(forKey:key)}
            else {inform("Moments unavailable", "More moments could not be loaded. Please try again.")}
        }
    }

    private func updateCachedMoment(_ id:UUID,item:CoffeeCloud.FeedMoment?) {
        if var feed=cloudFeed,let index=feed.firstIndex(where:{$0.id==id}) {
            if let item {feed[index]=item} else {feed.remove(at:index)}
            cloudFeed=feed
        }
        for key in Array(cloudShelves.keys) {
            guard var shelf=cloudShelves[key],let index=shelf.firstIndex(where:{$0.id==id}) else {continue}
            if let item {shelf[index]=item} else {shelf.remove(at:index)}
            cloudShelves[key]=shelf
        }
    }

    func refreshCloudFeedItem(_ id:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudFeedBusy else{return}
        cloudFeedBusy=true;defer{cloudFeedBusy=false}
        do {
            let result=try await CoffeeCloud.shared.recentMoments(for:account,target:id)
            guard state.signedIn,state.cloudAccountID==account else{return}
            updateCachedMoment(id,item:result.first)
        } catch {guard state.cloudAccountID==account else{return};inform("Moments unavailable", "The moment could not be refreshed. Please try again.")}
    }

    func changeCloudReaction(_ id:UUID,bookmarks:Bool,enabled:Bool) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudFeedBusy else{return}
        cloudFeedBusy=true
        do {
            try await CoffeeCloud.shared.setReaction(id,account:account,bookmarks:bookmarks,enabled:enabled)
            let feed=try await CoffeeCloud.shared.recentMoments(for:account,target:id)
            guard state.signedIn,state.cloudAccountID==account else {cloudFeedBusy=false;return}
            updateCachedMoment(id,item:feed.first);cloudFeedBusy=false
        } catch {
            guard state.cloudAccountID==account else {cloudFeedBusy=false;return}
            cloudFeedBusy=false
            inform("Update needs attention", "The change could not be confirmed. Refresh the feed and try again.")
        }
    }

    func refreshEditorial(_ key:String) async {
        guard let account=state.cloudAccountID,state.signedIn,!editorialBusy else{return}
        editorialBusy=true;defer{editorialBusy=false}
        do {
            async let summary=CoffeeCloud.shared.editorialSummary([key],account:account)
            async let comments=CoffeeCloud.shared.editorialComments(key,account:account)
            let (summaries,notes)=try await (summary,comments)
            guard state.signedIn,state.cloudAccountID==account else{return}
            editorialSummaries[key]=summaries.first;editorialComments[key]=notes
            await ensureCloudProfiles(Set(notes.map(\.author_id)))
        } catch {if state.cloudAccountID==account {editorialSummaries.removeValue(forKey:key);editorialComments.removeValue(forKey:key)}}
    }
    func changeEditorialLike(_ key:String) async {
        guard let account=state.cloudAccountID,state.signedIn,!editorialBusy,!cloudFeedBusy,let item=editorialSummaries[key] else{return}
        editorialBusy=true
        do {
            try await CoffeeCloud.shared.setEditorialLike(key,enabled:!item.liked,account:account)
            let result=try await CoffeeCloud.shared.editorialSummary([key],account:account)
            guard state.signedIn,state.cloudAccountID==account else {editorialBusy=false;return}
            editorialSummaries[key]=result.first;editorialBusy=false
        } catch {editorialBusy=false;if state.cloudAccountID==account {inform("Update needs attention","The change could not be confirmed. Refresh and try again.")}}
    }
    @discardableResult func sendEditorialComment(_ key:String,text:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!editorialBusy else{return false}
        let body=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty,body.count<=2000,validateCommunityText(body) else{return false}
        let pending:PendingCloudEditorialComment
        if let saved=state.pendingCloudEditorialComment {
            guard saved.accountID==account,saved.momentID==key,saved.body==body else {inform("Comment needs attention","Finish the saved comment before sending another.");return false}
            pending=saved
        } else {
            pending = .init(id:UUID(),accountID:account,momentID:key,body:body)
            guard commit({$0.pendingCloudEditorialComment=pending}) else{return false}
        }
        editorialBusy=true
        do {
            try await CoffeeCloud.shared.sendEditorialComment(key,id:pending.id,body:pending.body,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudEditorialComment?.id==pending.id else {editorialBusy=false;return false}
            guard commit({$0.pendingCloudEditorialComment=nil}) else {editorialBusy=false;return false}
            editorialBusy=false;await refreshEditorial(key)
            inform("Comment submitted","Your comment is visible to others after review.");return true
        } catch {editorialBusy=false;if state.cloudAccountID==account {inform("Comment needs attention","The result could not be confirmed. Retry the saved comment.")};return false}
    }
    func removeEditorialComment(_ id:UUID,key:String) async {
        guard let account=state.cloudAccountID,state.signedIn,!editorialBusy else{return}
        editorialBusy=true
        do {try await CoffeeCloud.shared.deleteEditorialComment(id,account:account);editorialBusy=false;await refreshEditorial(key)}
        catch {editorialBusy=false;if state.cloudAccountID==account {inform("Comment needs attention","The removal could not be confirmed. Refresh and try again.")}}
    }

    func refreshCloudComments(_ moment:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudCommentsBusy else{return}
        cloudCommentsBusy=true;defer{cloudCommentsBusy=false}
        do {
            let comments=try await CoffeeCloud.shared.comments(for:moment,account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            cloudComments[moment]=comments;cloudCommentsHasMore[moment]=comments.count==100
            await ensureCloudProfiles(Set(comments.map(\.author_id)))
        } catch {
            guard state.cloudAccountID==account else{return}
            cloudComments.removeValue(forKey:moment)
            cloudCommentsHasMore.removeValue(forKey:moment)
        }
    }

    func loadEarlierCloudComments(_ moment:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudCommentsBusy,cloudCommentsHasMore[moment]==true,
              let last=cloudComments[moment]?.last else{return}
        cloudCommentsBusy=true;defer{cloudCommentsBusy=false}
        do {
            let more=try await CoffeeCloud.shared.comments(for:moment,account:account,before:last)
            guard state.signedIn,state.cloudAccountID==account,var current=cloudComments[moment] else{return}
            let known=Set(current.map(\.id));current.append(contentsOf:more.filter{!known.contains($0.id)})
            cloudComments[moment]=current;cloudCommentsHasMore[moment]=more.count==100
            await ensureCloudProfiles(Set(more.map(\.author_id)))
        } catch {if state.cloudAccountID==account {inform("Comments unavailable", "Earlier comments could not be loaded. Please try again.")}}
    }

    func submitCloudComment(moment:UUID,text:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudCommentsBusy else{return false}
        let body=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty,body.count<=2000,validateCommunityText(body) else{return false}
        let pending:PendingCloudComment
        if let saved=state.pendingCloudComment {
            guard saved.accountID==account,saved.momentID==moment,saved.body==body else {
                inform("Comment needs attention", "Finish the saved comment before sending another.");return false
            }
            pending=saved
        } else {
            pending = .init(id:UUID(),accountID:account,momentID:moment,body:body)
            guard commit({$0.pendingCloudComment=pending}) else{return false}
        }
        cloudCommentsBusy=true
        do {
            try await CoffeeCloud.shared.sendComment(pending.body,on:moment,account:account,commentID:pending.id)
            let confirmed=try await CoffeeCloud.shared.comment(pending.id,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudComment?.id==pending.id else {cloudCommentsBusy=false;return false}
            guard let confirmed,confirmed.author_id==account,confirmed.post_id==moment,confirmed.body==pending.body else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            guard commit({$0.pendingCloudComment=nil}) else {cloudCommentsBusy=false;return false}
            cloudCommentsBusy=false
            await refreshCloudComments(moment)
            await refreshCloudFeedItem(moment)
            inform("Comment submitted", "Your comment is visible to others after review.")
            return true
        } catch {
            cloudCommentsBusy=false
            guard state.cloudAccountID==account else{return false}
            inform("Comment needs attention", "The result could not be confirmed. Retry the saved comment.")
            return false
        }
    }

    func deleteCloudComment(_ id:UUID,moment:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudCommentsBusy else{return}
        cloudCommentsBusy=true
        do {
            try await CoffeeCloud.shared.deleteComment(id,account:account)
            let comments=try await CoffeeCloud.shared.comments(for:moment,account:account)
            guard state.signedIn,state.cloudAccountID==account else {cloudCommentsBusy=false;return}
            cloudComments[moment]=comments;cloudCommentsHasMore[moment]=comments.count==100;cloudCommentsBusy=false
            await refreshCloudFeedItem(moment)
        } catch {
            cloudCommentsBusy=false
            guard state.cloudAccountID==account else{return}
            inform("Comment needs attention", "The removal could not be confirmed. Refresh and try again.")
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
            let participants=Set(messages.flatMap{[$0.sender_id,$0.recipient_id]})
            guard state.signedIn,state.cloudAccountID==account else {return}
            cloudMessages=messages;cloudFollows=follows;cloudMessagesUnavailable=false
            await ensureCloudProfiles(participants)
        } catch {if state.cloudAccountID==account {cloudMessagesUnavailable=true}}
    }

    func refreshCloudConversation(_ peer:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudConversationBusy.contains(peer) else{return}
        cloudConversationBusy.insert(peer);defer{cloudConversationBusy.remove(peer)}
        do {
            let recent=try await CoffeeCloud.shared.conversation(for:peer,account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            let older=cloudConversations[peer] ?? []
            if recent.isEmpty {cloudConversations[peer]=[];cloudConversationHasMore[peer]=false}
            else {
                let known=Set(recent.map(\.id))
                cloudConversations[peer]=recent+older.filter{!known.contains($0.id)}
                if older.isEmpty || (older.count<100 && recent.count==100) {cloudConversationHasMore[peer]=recent.count==100}
            }
            cloudConversationUnavailable.remove(peer)
        } catch {if state.cloudAccountID==account {cloudConversationUnavailable.insert(peer)}}
    }

    func loadEarlierCloudConversation(_ peer:UUID) async {
        guard let account=state.cloudAccountID,state.signedIn,!cloudConversationBusy.contains(peer),cloudConversationHasMore[peer]==true,
              let last=cloudConversations[peer]?.last else{return}
        cloudConversationBusy.insert(peer);defer{cloudConversationBusy.remove(peer)}
        do {
            let older=try await CoffeeCloud.shared.conversation(for:peer,account:account,before:last)
            guard state.signedIn,state.cloudAccountID==account,var current=cloudConversations[peer] else{return}
            let known=Set(current.map(\.id));current.append(contentsOf:older.filter{!known.contains($0.id)})
            cloudConversations[peer]=current;cloudConversationHasMore[peer]=older.count==100;cloudConversationUnavailable.remove(peer)
        } catch {if state.cloudAccountID==account {cloudConversationUnavailable.insert(peer)}}
    }

    func refreshCloudCalls() async {
        guard liveCallsEnabled,let account=state.cloudAccountID,state.signedIn,!cloudCallsBusy else{return}
        cloudCallsBusy=true;defer{cloudCallsBusy=false}
        do {let calls=try await CoffeeCloud.shared.callSessions(account:account);guard state.cloudAccountID==account,state.signedIn else{return};cloudCalls=calls}
        catch {if state.cloudAccountID==account {cloudCalls=nil}}
    }

    func requestCloudCall(_ peer:UUID) async -> CoffeeCloud.CallSession? {
        guard liveCallsEnabled,let account=state.cloudAccountID,state.signedIn,!cloudCallsBusy,peer != account else{return nil}
        let pending:PendingCloudCall
        if let saved=state.pendingCloudCall {
            guard saved.accountID==account,saved.recipientID==peer else {inform("Call needs attention", "Retry the earlier request first.");return nil}
            pending=saved
        } else {
            guard isMutual(peer.uuidString) else {inform("Follow each other first", "Both people must follow each other before starting a call.");return nil}
            pending = .init(id:UUID(),accountID:account,recipientID:peer)
            guard commit({$0.pendingCloudCall=pending}) else{return nil}
        }
        cloudCallsBusy=true;defer{cloudCallsBusy=false}
        do {
            let id=try await CoffeeCloud.shared.requestCall(id:pending.id,recipient:peer,account:account)
            let calls=try await CoffeeCloud.shared.callSessions(account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudCall?.id==pending.id,
                  let call=calls.first(where:{$0.id==id}) else {throw CoffeeCloud.ConnectionError.actionUnavailable}
            guard commit({$0.pendingCloudCall=nil}) else{return nil}
            cloudCalls=calls
            guard ["pending","accepted"].contains(call.status),(cloudDate(call.expires_at) ?? .distantPast)>Date() else {
                inform("Call unavailable", "This request has expired. Start another call if you still want to connect.");return nil
            }
            return call
        } catch {if state.cloudAccountID==account {inform("Call needs attention", "The request could not be confirmed. Retry the saved request.")};return nil}
    }

    func answerCloudCall(_ id:UUID,accept:Bool) async -> Bool {
        guard liveCallsEnabled,let account=state.cloudAccountID,state.signedIn,!cloudCallsBusy else{return false}
        cloudCallsBusy=true;defer{cloudCallsBusy=false}
        do {
            let accepted=try await CoffeeCloud.shared.answerCall(id:id,accept:accept,account:account)
            let calls=try await CoffeeCloud.shared.callSessions(account:account)
            guard state.signedIn,state.cloudAccountID==account else{return false}
            cloudCalls=calls
            guard accepted,let session=calls.first(where:{$0.id==id}),session.status==(accept ? "accepted":"declined") else {inform("Call unavailable", "This call expired or is no longer available.");return false}
            return true
        } catch {if state.cloudAccountID==account {inform("Call needs attention", "The response could not be confirmed. Refresh and try again.")};return false}
    }

    func endCloudCall(_ id:UUID) async {
        guard liveCallsEnabled,let account=state.cloudAccountID,state.signedIn else{return}
        if let pending=state.pendingCloudCallEnd {guard pending.id==id,pending.accountID==account else{return}}
        else if !commit({$0.pendingCloudCallEnd = .init(id:id,accountID:account)}) {return}
        guard !cloudCallsBusy else{return}
        cloudCallsBusy=true;defer{cloudCallsBusy=false}
        do {
            try await CoffeeCloud.shared.endCall(id:id,account:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudCallEnd?.id==id else{return}
            guard commit({$0.pendingCloudCallEnd=nil}) else{return}
            cloudCalls=try? await CoffeeCloud.shared.callSessions(account:account)
        } catch {if state.cloudAccountID==account {inform("Call needs attention", "The call ended on this device. Retry confirming its server status.")}}
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
            // Keep the pre-cloud passport intact until the full migration is complete.
            guard commit({$0.pendingCloudProfile=nil}) else {return false}
            cloudReferencedProfiles[account]=profile
            if var profiles=cloudProfiles,let index=profiles.firstIndex(where:{$0.id==account}) {profiles[index]=profile;cloudProfiles=profiles}
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            if let connectionError=error as? CoffeeCloud.ConnectionError,case .profileConflict=connectionError {
                guard commit({$0.pendingCloudProfile=nil}) else {return false}
                cloudReferencedProfiles.removeValue(forKey:account)
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
            let knownAuthors=Set((cloudFeed ?? []).map(\.author_id))
                .union(cloudShelves.values.flatMap{$0.map(\.author_id)})
                .union(cloudComments.values.flatMap{$0.map(\.author_id)})
                .union(cloudMessages.flatMap{[$0.sender_id,$0.recipient_id]})
            await ensureCloudProfiles(knownAuthors)
            guard state.signedIn,state.cloudAccountID==account else{return false}
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
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy,!reason.isEmpty else {return false}
        let editorialKey=target.kind == .editorialComment ? target.parentReference:(target.kind == .post && target.contentReference.hasPrefix("editorial-") ? target.contentReference:nil)
        let subject=UUID(uuidString:target.contentReference)
        guard editorialKey != nil || subject != nil else{return false}
        if target.kind == .editorialComment && subject==nil {return false}
        let kind:String
        switch target.kind {case .user:kind="profile";case .post:kind="post";case .comment:kind="comment";case .message:kind="message";case .editorialComment:kind="comment";case .room:return false}
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
            var reports=cloudReports
            if let editorialKey {
                try await CoffeeCloud.shared.reportEditorial(editorialKey,comment:target.kind == .editorialComment ? subject:nil,reason:reason,id:pending.id,account:account)
            } else if let subject {
                try await CoffeeCloud.shared.report(kind,subject:subject,reason:reason,account:account,reportID:pending.id)
                reports=try await CoffeeCloud.shared.reports(for:account)
            }
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudReport?.id==pending.id else {return false}
            guard commit({value in
                value.pendingCloudReport=nil
                if editorialKey != nil {
                    var ledger=value.community ?? CorrespondenceLedger();ledger.hiddenTargets.insert(target.id);value.community=ledger
                }
            }) else {return false}
            cloudReports=reports
            if let editorialKey,target.kind == .post {editorialReportedPosts.insert(editorialKey)}
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

    func sendCloudAttachment(to id:String,reference:String,kind:String) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSocialBusy,let recipient=UUID(uuidString:id),recipient != account,
              ["photo","voice"].contains(kind) else{return false}
        let pending:PendingCloudAttachment
        if let saved=state.pendingCloudAttachment {
            guard saved.accountID==account,saved.recipientID==recipient,saved.reference==reference,saved.kind==kind else {
                inform("Attachment needs attention", "Retry the saved attachment first.");return false
            }
            pending=saved
        } else {
            guard isMutual(id) else {inform("Follow each other first", "Both people must follow each other before sending messages. Your draft has been kept.");return false}
            guard reference.hasPrefix("local/\(state.passport.id.uuidString)/"),let file=CoffeeMedia.url(reference),file.isFileURL,
                  file.pathExtension.lowercased()==(kind=="photo" ? "jpg":"m4a"),
                  let size=try? file.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=52_428_800 else {
                inform("Attachment unavailable", "Choose a photo or voice note under 50 MB. Your draft has been kept.");return false
            }
            pending = .init(id:UUID(),accountID:account,recipientID:recipient,reference:reference,kind:kind)
            guard commit({$0.pendingCloudAttachment=pending}) else{return false}
        }
        guard let file=CoffeeMedia.url(pending.reference),file.isFileURL else {inform("Attachment unavailable", "The original file is needed to retry.");return false}
        cloudSocialBusy=true
        do {
            _ = try await CoffeeCloud.shared.uploadMedia(file:file,objectID:pending.id,contentType:kind=="photo" ? "image/jpeg":"audio/mp4",account:account,messageAttachment:true)
            try await CoffeeCloud.shared.sendAttachment(kind,to:recipient,account:account,messageID:pending.id)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudAttachment?.id==pending.id else {cloudSocialBusy=false;return false}
            guard commit({value in
                value.pendingCloudAttachment=nil
                if kind=="photo",value.letterPhotos[id]==pending.reference {value.letterPhotos.removeValue(forKey:id)}
                if kind=="voice",value.letterVoiceNotes[id]==pending.reference {value.letterVoiceNotes.removeValue(forKey:id)}
            }) else {cloudSocialBusy=false;return false}
            cloudSocialBusy=false
            await refreshCloudMessages()
            return true
        } catch {
            cloudSocialBusy=false
            guard state.cloudAccountID==account else{return false}
            inform("Attachment needs attention", "The result could not be confirmed. Retry the saved attachment.")
            return false
        }
    }

    func sendCloudConversation(to id:String) async {
        guard let recipient=UUID(uuidString:id) else{return}
        if let pending=state.pendingCloudAttachment {
            guard pending.recipientID==recipient,await sendCloudAttachment(to:id,reference:pending.reference,kind:pending.kind) else{return}
        }
        let text=state.letterDrafts[id] ?? ""
        if !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
            guard await sendCloudMessage(to:id,text:text) else{return}
        }
        if let photo=state.letterPhotos[id] {guard await sendCloudAttachment(to:id,reference:photo,kind:"photo") else{return}}
        if let voice=state.letterVoiceNotes[id] {_ = await sendCloudAttachment(to:id,reference:voice,kind:"voice")}
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

    @discardableResult func deleteCloudSubmission(_ id:UUID) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudSubmissionsBusy,!cloudWalletBusy else {return false}
        if let pending=state.pendingCloudPostDeletion {
            guard pending.accountID==account,pending.postID==id else {
                inform("Removal needs attention", "Finish removing the previous post before starting another.");return false
            }
        } else {
            guard commit({$0.pendingCloudPostDeletion = .init(accountID:account,postID:id)}) else {return false}
        }
        cloudSubmissionsBusy=true
        defer {cloudSubmissionsBusy=false}
        do {
            try await CoffeeCloud.shared.deleteMoment(id,account:account)
            let items=try await CoffeeCloud.shared.ownMoments(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudPostDeletion?.postID==id else {return false}
            guard commit({$0.pendingCloudPostDeletion=nil}) else {return false}
            cloudSubmissions=items
            inform("Post removed", "Your post and its online media have been removed.")
            return true
        } catch {
            guard state.cloudAccountID==account else {return false}
            cloudSubmissions=nil
            inform("Removal needs attention", "The removal could not be confirmed. Retry to finish removing the post and its online media.")
            return false
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

    @discardableResult func cloudRoomGift(gift:CoffeeCollectible?,quantity:Int,topic:String,session:UUID,cancel:Bool=false) async -> Bool {
        guard let account=state.cloudAccountID,state.signedIn,!cloudWalletBusy else{return false}
        let pending:PendingCloudRoomGift
        if let saved=state.pendingCloudRoomGift {
            guard saved.accountID==account else{return false}
            if !cancel,let gift, (saved.giftID != gift.id || saved.quantity != quantity || saved.topic != topic || saved.sessionID != session) {
                inform("Gift needs attention","Finish your previous room gift before sending another.");return false
            }
            pending=saved
        } else {
            guard !cancel,let gift,(1...99).contains(quantity),cloudWallet != nil,
                  state.pendingCloudVoice?.accountID==account,state.pendingCloudVoice?.id==session,state.pendingCloudVoice?.topic==topic,state.pendingCloudVoice?.closing==false else{return false}
            pending = .init(id:UUID(),accountID:account,topic:topic,sessionID:session,giftID:gift.id,quantity:quantity)
            guard commit({$0.pendingCloudRoomGift=pending}) else{return false}
        }
        cloudWalletBusy=true;defer{cloudWalletBusy=false}
        do {
            let result=try await CoffeeCloud.shared.sendVoiceGift(pending,cancel:cancel,account:account)
            let snapshot=try await CoffeeCloud.shared.walletSnapshot(for:account)
            guard state.signedIn,state.cloudAccountID==account,state.pendingCloudRoomGift?.id==pending.id else{return false}
            guard commit({$0.pendingCloudRoomGift=nil}) else{return false}
            cloudWallet=snapshot;cloudWalletUnavailable=false
            if result.status=="settled" {inform("Gift sent","Your gift was shared with the room.");return true}
            if result.status=="insufficient" {inform("Not enough coins","This gift was not sent and no coins were spent.")}
            else {inform("Gift cancelled","This gift was not sent and no coins were spent.")}
            return false
        } catch {
            guard state.cloudAccountID==account else{return false}
            cloudWallet=nil;cloudWalletUnavailable=true
            inform("Gift needs attention","The result could not be confirmed. Retry or cancel the saved gift; it will not be charged twice.")
            return false
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
        guard !checkoutActive,accountAction==nil,!loginInProgress,!cloudWalletBusy,!emailLinkBusy,state.pendingCloudRecoveryID==nil,state.pendingCloudDeletionID==nil,storageAvailable,state.signedIn else{return false}
        checkoutActive=true;return true
    }
    func endCheckout() {checkoutActive=false}
    func insufficientCoins(cost:Int) {
        notice = .init(title:"A little more for your coffee reserve",message:"This needs \(cost) coins. Your balance is \(state.coinBalance). Your draft and selections are kept; recharge to continue.",kind:.insufficient)
    }
    func performAccountAction(_ action:AccountTransition) async {
        guard accountAction==nil,!loginInProgress,!cloudConnectionInProgress,!cloudWalletBusy,!cloudSubmissionsBusy,!cloudBrewBusy,!cloudBrewHistoryBusy,!cloudSocialBusy,!cloudFeedBusy,!editorialBusy,cloudShelfBusy.isEmpty,!cloudCommentsBusy,!cloudProfileMediaBusy,!cloudCallsBusy,!cloudVoiceTopicsBusy,!cloudVoiceBusy,!emailLinkBusy,cloudConversationBusy.isEmpty,storageAvailable else{return}
        if state.pendingCloudDeletionID != nil && action != .delete {inform("Account action needs attention","Finish the saved account deletion before changing accounts.");return}
        guard !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken==nil,state.pendingCloudRecoveryID==nil,state.pendingCloudCollectible==nil,state.pendingCloudRoomGift==nil,state.pendingCloudMoment==nil,state.pendingCloudPostDeletion==nil,state.pendingCloudReport==nil,state.pendingCloudMessage==nil,state.pendingCloudAttachment==nil,state.pendingCloudFriendship==nil,state.pendingCloudProfile==nil,state.pendingCloudComment==nil,state.pendingCloudEditorialComment==nil,state.pendingCloudProfileImage==nil,state.pendingCloudProfileImageRemoval==nil,state.pendingCloudCall==nil,state.pendingCloudCallEnd==nil,state.pendingCloudVoice==nil else {
            inform("Account action needs attention","Finish pending account or purchase activity before changing accounts.");return
        }
        if action == .delete,let account=state.cloudAccountID {
            guard cloudDeletionEnabled else {inform("Account deletion needs attention", "Your online account has not been removed. Please try again when account deletion is available.");return}
            await performCloudDeletion(account)
            return
        }
        if action == .delete && state.cloudBootstrapPending == true {
            inform("Account deletion needs attention", "Your online account has not been removed. Please try again when account deletion is available.");return
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
            state=next;resetCloudState()
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
    private func performCloudDeletion(_ account:UUID) async {
        guard state.pendingCloudDeletionID==nil || state.pendingCloudDeletionID==account else{return}
        accountAction = .delete
        defer {accountAction=nil}
        do {
            try await CoffeeCloud.shared.prepareDeletionReceipt(account:account)
            guard state.signedIn,state.cloudAccountID==account else{return}
            if state.pendingCloudDeletionID==nil {
                var pending=state;pending.pendingCloudDeletionID=account
                let pendingSnapshot=pending
                do {try await Task.detached(priority:.userInitiated){try CoffeeVault.write(pendingSnapshot)}.value}
                catch {storageAvailable=false;throw error}
                savedSnapshotExpected=true;state=pending
            }
            let finished=try await CoffeeCloud.shared.requestAccountDeletion(account:account)
            guard state.cloudAccountID==account,state.pendingCloudDeletionID==account else{return}
            guard finished else {inform("Online deletion in progress", "Your online deletion is still processing. Your device data is kept; retry in Settings.");return}
            try await CoffeeCloud.shared.clearDeletedSession(account:account)
            guard state.cloudAccountID==account,state.pendingCloudDeletionID==account else{return}
            var next=state
            next.cloudAccountID=nil;next.cloudBootstrapPending=false;next.pendingCloudDeletionID=nil
            next.deletedCloudAccountID=account;next.signedIn=false
            let snapshot=next
            do {try await Task.detached(priority:.userInitiated){try CoffeeVault.write(snapshot)}.value}
            catch {storageAvailable=false;throw error}
            savedSnapshotExpected=true;state=next;resetCloudState()
            try? await CoffeeCloud.shared.forgetDeletionReceipt(account:account)
            inform("Online account deleted", "The online account has been removed. Your existing device data remains saved on this device.")
        } catch {
            if state.cloudAccountID==account {inform("Account deletion needs attention", "The result could not be confirmed. Your device data and deletion retry are kept.")}
        }
    }
    private func resetCloudState() {
        cloudReferenceGuides=nil
        cloudSavedScenes=nil
        brewSyncDebounce?.cancel();brewSyncDebounce=nil
        cloudWallet=nil;cloudWalletUnavailable=false;cloudSubmissions=nil;cloudBrewNeedsAttention=false;cloudBrewHistory=nil
        cloudProfiles=nil;cloudReferencedProfiles=[:];cloudImageSummaries=[:];cloudProfileImages=[:];cloudProfileImagesHasMore=[:]
        cloudFollows=[];cloudFriendships=[];cloudBlocks=[];cloudReports=[];cloudMessages=[];cloudMessagesUnavailable=false
        cloudConversations=[:];cloudConversationHasMore=[:];cloudConversationUnavailable=[];cloudCalls=nil;cloudVoiceTopics=nil
        cloudFeed=nil;cloudFeedHasMore=false;cloudShelves=[:];cloudShelfHasMore=[:];cloudComments=[:];cloudCommentsHasMore=[:];editorialSummaries=[:];editorialComments=[:];editorialReportedPosts=[];editorialReportsReady=false;editorialSummariesUnavailable=false
        activeRoomID=nil;roomMicRequested=false;selectedTab=0
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
        guard state.pendingCloudMessage==nil,state.pendingCloudAttachment==nil else {inform("Message needs attention", "Retry the saved message before clearing drafts.");return}
        _ = commit {$0.letterDrafts.removeAll();$0.letterPhotos.removeAll();$0.letterVoiceNotes.removeAll()}
    }
}
