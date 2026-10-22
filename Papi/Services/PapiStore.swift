import Foundation
import SwiftUI

struct PapiNotice: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}
@MainActor final class PapiStore: ObservableObject {
    @Published private(set) var state: GuestState
    @Published var notice: PapiNotice?
    @Published private(set) var storageAvailable = true
    @Published var activeRoomID: String?
    @Published var selectedTab = 0
    @Published var roomMicRequested = false
    init() {
        do { state = try GuestVault.read() ?? GuestState() }
        catch { state = GuestState(); storageAvailable = false
            notice = .init(title: "Local data unavailable", message: error.localizedDescription) }
        if storageAvailable {cleanupPendingMedia()}
    }
    @discardableResult func commit(_ mutate: (inout GuestState) throws -> Void) -> Bool {
        guard storageAvailable else { inform("Local data unavailable", "Unlock the device and use Retry in Settings. Your saved data will not be overwritten."); return false }
        var next = state
        do {
            try mutate(&next)
            try GuestVault.write(next)
            state = next
            return true
        } catch { storageAvailable = false; inform("Could not save", error.localizedDescription + " Reopen the app or retry local storage before making more changes."); return false }
    }
    func reload() {
        do { if let saved = try GuestVault.read() { state = saved }; storageAvailable = true;cleanupPendingMedia() }
        catch { inform("Local data unavailable", error.localizedDescription) }
    }
    func inform(_ title: String, _ message: String) { notice = .init(title:title,message:message) }
    func login() {
        _ = commit { $0.signedIn = true; $0.acceptedPolicyVersion = "2026-10-21" }
    }
    func logout() {
        if commit({ $0.signedIn = false }) { activeRoomID = nil; roomMicRequested = false; selectedTab = 0 }
    }
    func deleteGuest() {
        guard state.purchaseIntents.isEmpty else {
            inform("Purchase awaiting review", "Resolve pending purchases before deleting this guest. This protects the original purchase owner."); return
        }
        let oldID = state.profile.id
        if commit({ value in
            let retired = value.retiredGuestIDs.union([oldID])
            let transactions = value.historicalTransactionIDs.union(value.creditedTransactions)
            let language = value.language
            let pending=value.pendingMediaDeletion.union([oldID])
            value = GuestState(); value.pendingMediaDeletion=pending; value.retiredGuestIDs = retired; value.historicalTransactionIDs = transactions
            value.language = language; value.sawOnboarding = true
        }) {
            cleanupPendingMedia()
            activeRoomID = nil; selectedTab = 0; roomMicRequested = false
        }
    }
    private func cleanupPendingMedia() {
        for owner in state.pendingMediaDeletion {
            do {
                try MediaFiles.removeGuestDirectory(owner)
                guard commit({$0.pendingMediaDeletion.remove(owner)}) else{return}
            } catch {
                inform("Media removal incomplete", "The guest profile was removed, but some local media could not be deleted. Unlock this device and reopen Papi to retry. No new guest can access those files.")
                return
            }
        }
    }
    var visiblePosts: [CoffeePost] {
        (state.localPosts + CoffeePost.editorial).filter { !state.blocked.contains($0.authorID) }
    }
    func post(_ id: String) -> CoffeePost? { (state.localPosts + CoffeePost.editorial).first { $0.id == id } }
    func toggleLike(_ id: String) { _ = commit { if !$0.likes.insert(id).inserted { $0.likes.remove(id) } } }
    func toggleBookmark(_ id: String) { _ = commit { if !$0.bookmarks.insert(id).inserted { $0.bookmarks.remove(id) } } }
    func follow(_ id: String) {
        guard id != state.profile.id.uuidString, !state.blocked.contains(id) else { return }
        _ = commit { if !$0.follows.insert(id).inserted { $0.follows.remove(id) } }
    }
    func block(_ id: String) {
        guard id != state.profile.id.uuidString else { return }
        _ = commit { $0.blocked.insert(id); $0.follows.remove(id) }
        if let roomID = activeRoomID, Room.previews.first(where: {$0.id == roomID})?.hostID == id { activeRoomID = nil }
    }
    func unblock(_ id: String) { _ = commit { $0.blocked.remove(id) } }
    func addComment(postID: String, text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let post = post(postID), !state.blocked.contains(post.authorID) else { return false }
        guard clean.count<=2000 else {inform("Note is too long","Keep your note under 2,000 characters. Your text has been kept.");return false}
        return commit { $0.comments.append(.init(postID:postID,text:clean)) }
    }
    func report(_ id: String, reason: String) {
        if commit({ $0.reports.append(.init(subjectID:id,reason:reason)) }) {
            inform("Report saved locally", "This report is stored on this device. No moderation service is connected, so it has not been sent to a platform.")
        }
    }
    func publish() -> Bool {
        let draft = state.postDraft
        guard let media = draft.media, MediaFiles.url(media) != nil else { inform("Add a photo or video", "Choose a coffee moment before saving your post."); return false }
        guard !draft.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { inform("Add a caption", "Tell the story behind this coffee moment."); return false }
        guard state.coins >= 10 else { inform("Not enough coins", "Saving a post costs 10 coins. You can collect coins with daily check-in."); return false }
        return commit {
            let id = UUID().uuidString
            $0.coins -= 10; $0.wallet.insert(.init(id:id,delta:-10,reason:"Local post"),at:0)
            $0.localPosts.insert(.init(id:id,authorID:$0.profile.id.uuidString,media:media,isVideo:draft.isVideo,caption:draft.text,category:"My coffee",isLocal:true),at:0)
            $0.experience += 10; $0.postDraft = JournalDraft()
        }
    }
    func deletePost(_ id: String) { _ = commit { $0.localPosts.removeAll { $0.id == id }; $0.comments.removeAll { $0.postID == id }; $0.likes.remove(id); $0.bookmarks.remove(id) } }
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
            $0.checkinDays.insert(day); $0.coins += reward; $0.experience += 20
            $0.wallet.insert(.init(id:"checkin-"+day,delta:reward,reason:"Daily check-in"),at:0)
        }) { inform("Check-in complete", "\(reward) coins have been added to your local wallet.") }
    }
    func collect(_ gift: Gift, quantity: Int) -> Bool {
        guard (1...99).contains(quantity), gift.cost <= Int.max / quantity else { return false }
        let total = gift.cost * quantity
        guard state.coins >= total else { inform("Not enough coins", "Collect more coins with daily check-in or open your wallet."); return false }
        return commit {
            $0.coins -= total; $0.inventory[gift.id,default:0] += quantity
            $0.wallet.insert(.init(id:UUID().uuidString,delta:-total,reason:"\(gift.name) × \(quantity)"),at:0)
        }
    }
    func previewGift(_ gift: Gift, quantity: Int, context: String) {
        guard (1...99).contains(quantity) else { return }
        if commit({ $0.giftHistory.insert(.init(giftID:gift.id,quantity:quantity,context:context),at:0) }) {
            inform("Gift preview saved", "\(gift.name) × \(quantity). No recipient is connected; no coins or inventory were spent. You can collect this gift for your local backpack.")
        }
    }
    func enter(_ room: Room) {
        guard !state.blocked.contains(room.hostID) else { return }
        if commit({ $0.recentRooms.removeAll {$0 == room.id}; $0.recentRooms.insert(room.id,at:0) }) { activeRoomID = room.id }
    }
    func sendChat(to personID: String, text: String) {
        guard !state.blocked.contains(personID) else {inform("Profile is blocked","Unblock this profile before using chat. Your draft has been kept.");return}
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        if !state.follows.contains(personID) { inform("Follow each other first", "Messages require mutual following. Your draft has been kept."); return }
        inform("Message not sent", "This profile is a local preview and cannot follow you back. Messaging will become available when a community service is connected. Your draft is saved.")
    }
    func hasChatDraft(_ id:String)->Bool {
        !(state.chatDrafts[id] ?? "").isEmpty || state.chatAttachments[id] != nil || state.voiceDrafts[id] != nil
    }
    func chatPreview(_ id:String)->String {
        if let text=state.chatDrafts[id],!text.isEmpty{return text}
        if state.chatAttachments[id] != nil{return text("Photo draft")}
        return text("Voice draft")
    }
    func clearChatDrafts() {
        _ = commit {$0.chatDrafts.removeAll();$0.chatAttachments.removeAll();$0.voiceDrafts.removeAll()}
    }
}
