import Foundation
import SwiftUI

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
    private var savedSnapshotExpected=false
    init() {
        do {let saved=try CoffeeVault.read();state=saved ?? CoffeeArchive();savedSnapshotExpected=saved != nil}
        catch { state = CoffeeArchive(); storageAvailable = false
            notice = .init(title: "Local data unavailable", message: error.localizedDescription) }
        if storageAvailable {cleanupPendingMedia()}
    }
    @discardableResult func commit(_ mutate: (inout CoffeeArchive) throws -> Void) -> Bool {
        guard accountAction==nil,!loginInProgress else {return false}
        guard storageAvailable else { inform("Local data unavailable", "Unlock the device and use Retry in Settings. Your saved data will not be overwritten."); return false }
        var next = state
        do {
            try mutate(&next)
            try CoffeeVault.write(next)
            savedSnapshotExpected=true
            state = next
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
        } catch {storageAvailable=false;inform("Local data unavailable",error.localizedDescription)}
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
        next.signedIn=true;next.acceptedPolicyVersion="2026-10-22"
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
    func acknowledgeWelcome() {
        if commit({$0.welcomeGrant?.acknowledged=true}) {notice=nil}
    }
    func beginCheckout() -> Bool {
        guard !checkoutActive,accountAction==nil,!loginInProgress,storageAvailable,state.signedIn else{return false}
        checkoutActive=true;return true
    }
    func endCheckout() {checkoutActive=false}
    func insufficientCoins(cost:Int) {
        notice = .init(title:"A little more for your coffee reserve",message:"This needs \(cost) coins. Your balance is \(state.coinBalance). Your draft and selections are kept; recharge to continue.",kind:.insufficient)
    }
    func performAccountAction(_ action:AccountTransition) async {
        guard accountAction==nil,!loginInProgress,storageAvailable else{return}
        guard !checkoutActive,state.purchaseIntents.isEmpty,state.activePurchaseToken==nil else {
            inform("Purchase awaiting review","Resolve the purchase before changing this local guest.");return
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
            state=next;activeRoomID=nil;roomMicRequested=false;selectedTab=0
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
    var checkedInToday: Bool { state.checkinDays.contains(dayKey) }
    var nextCheckinReward: Int { (state.checkinDays.count % 7 + 1) * 10 }
    func checkIn() {
        let day = dayKey; let reward = nextCheckinReward
        guard !state.checkinDays.contains(day) else { inform("Already checked in", "Come back after 00:00 UTC for your next reward."); return }
        if commit({
            $0.checkinDays.insert(day); $0.coinBalance += reward; $0.experience += 20
            $0.coinMovements.insert(.init(id:"checkin-"+day,delta:reward,reason:"Daily check-in"),at:0)
        }) { inform("Check-in complete", "\(reward) coins have been added to your local wallet.") }
    }
    func collect(_ gift: CoffeeCollectible, quantity: Int) -> Bool {
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
            inform("Gift preview saved", "\(gift.name) × \(quantity). No recipient is connected; no coins or inventory were spent. You can collect this gift for your local backpack.")
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
        _ = commit {$0.letterDrafts.removeAll();$0.letterPhotos.removeAll();$0.letterVoiceNotes.removeAll()}
    }
}
