import Foundation
import Supabase
import CryptoKit

/// Owns the network identity independently of the device's existing archive ID.
actor CoffeeCloud {
    static let shared = CoffeeCloud()
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://cquoffowtjnxmgaxavym.supabase.co")!,
        supabaseKey: "sb_publishable_srmPaTaw81JT37tSvfmCww_vqBh73A5"
    )
    private let sessionKey = "sb-cquoffowtjnxmgaxavym-auth-token"

    struct Profile: Codable {
        let id: UUID
        let display_name: String
        let biography: String
        let avatar_path: String?
        let cover_path: String?
        let revision: Int?
    }

    struct Follow: Codable {
        let follower_id: UUID
        let followed_id: UUID
    }
    struct Message: Codable, Identifiable {
        let id: UUID
        let sender_id: UUID
        let recipient_id: UUID
        let body: String
        let created_at: String
    }
    struct Moment: Codable, Identifiable {
        let id: UUID
        let author_id: UUID
        let caption: String
        let media_path: String
        let media_kind: String
        let moderation_status: String
        let created_at: String
    }
    struct Comment: Codable, Identifiable {
        let id: UUID
        let post_id: UUID
        let author_id: UUID
        let body: String
        let moderation_status: String
        let created_at: String?
    }
    struct Wallet: Decodable {
        let balance: Int
    }
    struct CheckIn: Decodable {
        let day: String
        let total_days: Int
        let reward: Int
        let balance: Int
        let awarded: Bool
    }
    struct CheckInDay: Decodable {
        let checkin_day: String
        let reward: Int
    }
    struct Collectible: Decodable {
        let collectible_id: String
        let quantity: Int
    }
    struct Progress: Decodable { let experience: Int }
    struct WalletMovement: Decodable, Identifiable {
        let id: UUID
        let delta: Int
        let reason: String
        let created_at: String
        var date: Date? {
            let formatter=ISO8601DateFormatter()
            formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            if let date=formatter.date(from:created_at) { return date }
            formatter.formatOptions=[.withInternetDateTime]
            return formatter.date(from:created_at)
        }
    }
    struct WalletSnapshot: Decodable {
        let balance: Int
        let experience: Int
        let server_day: String
        let checkins: [CheckInDay]
        let collectibles: [Collectible]
        let recipes: [String]
        let movements: [WalletMovement]
    }
    struct BrewBookDocument: Decodable {
        let revision: Int
        let contents: BrewNotebook?
    }
    struct BrewBookWrite: Decodable {
        let committed_revision: Int
        let current_revision: Int
    }
    struct BrewBookHistory: Decodable, Identifiable {
        let revision: Int
        let contents: BrewNotebook
        let saved_at: String
        var id: Int {revision}
    }
    private struct PurchaseOrder: Codable {
        let id: UUID
        let owner_id: UUID
        let product_id: String
    }
    private struct PurchaseVerification: Encodable {
        let order_id: UUID
        let signed_transaction: String
    }
    private struct PurchaseSettlement: Decodable { let balance: Int }
    struct Block: Codable {
        let blocker_id: UUID
        let blocked_id: UUID
    }
    struct Reaction: Codable {
        let moment_id: UUID
        let member_id: UUID
    }
    struct Friendship: Decodable, Identifiable {
        let id: UUID
        let requester_id: UUID
        let recipient_id: UUID
        let status: String
        let created_at: String
    }
    struct Report: Codable {
        let id: UUID
        let reporter_id: UUID
        let subject_kind: String
        let subject_id: UUID
        let reason: String
    }
    private struct FriendRequest: Encodable { let p_id: UUID; let p_recipient: UUID }
    private struct FriendAnswer: Encodable { let p_id: UUID; let p_accept: Bool }
    private struct FriendCancel: Encodable { let p_id: UUID }
    private struct Unlock: Encodable { let recipe: String }
    private struct CollectionOrder: Encodable { let order_id: UUID; let item: String; let item_quantity: Int }
    private struct RemovedPost: Encodable { let post_id: UUID }
    private struct RemovedMedia: Encodable { let p_path: String }
    private struct BrewBookSave: Encodable { let p_request: UUID; let p_revision: Int; let p_contents: AnyJSON }
    private struct MessageSend: Encodable { let p_id: UUID; let p_recipient: UUID; let p_body: String }
    private struct PairAction: Encodable { let p_member: UUID; let p_enabled: Bool }
    private struct ProfilePatch: Encodable { let display_name: String; let biography: String }
    private struct Submission: Encodable {
        let moment_id: UUID
        let caption: String
        let media_path: String
        let media_kind: String
    }

    enum ConnectionError: LocalizedError {
        case missingSession, wrongAccount, profileUnavailable, sessionNotSaved, actionUnavailable, unboundSession, profileConflict
        var errorDescription: String? {
            switch self {
            case .missingSession: return "The saved guest session is unavailable. Your coffee book has not been changed."
            case .wrongAccount: return "The saved guest does not match this coffee book. Your data has not been changed."
            case .profileUnavailable: return "Your online profile is unavailable. Your coffee book has not been changed."
            case .sessionNotSaved: return "The guest session could not be saved securely. Please unlock the device and try again."
            case .actionUnavailable: return "This request is no longer available. Refresh and try again."
            case .unboundSession: return "A saved guest session needs review before it can be linked to this coffee book."
            case .profileConflict: return "This profile changed on another device. Your edits have been kept."
            }
        }
    }

    /// The caller must persist a bootstrap marker before creating a guest and may
    /// use it to recover an interrupted attempt. An unbound session alone is not
    /// evidence that it belongs to this local archive.
    func requireFreshBootstrap() throws {
        // The SDK treats a Keychain read error as a missing session; inspect the
        // same key directly before ever allowing creation of a replacement user.
        guard try KeychainLocalStorage().retrieve(key: sessionKey) == nil,
              client.auth.currentSession == nil else { throw ConnectionError.unboundSession }
    }

    func openGuest(expectedID: UUID?, passport: CoffeePassport, hasPendingBootstrap: Bool) async throws -> UUID {
        let session: Session
        if client.auth.currentSession != nil {
            guard expectedID != nil || hasPendingBootstrap else { throw ConnectionError.unboundSession }
            session = try await client.auth.session
        } else {
            guard expectedID == nil else { throw ConnectionError.missingSession }
            guard hasPendingBootstrap else { throw ConnectionError.unboundSession }
            guard try KeychainLocalStorage().retrieve(key: sessionKey) == nil else {
                throw ConnectionError.sessionNotSaved
            }
            session = try await client.auth.signInAnonymously()
            guard client.auth.currentSession?.user.id == session.user.id else {
                throw ConnectionError.sessionNotSaved
            }
        }
        let userID = session.user.id
        if let expectedID, expectedID != userID { throw ConnectionError.wrongAccount }

        let profiles: [Profile] = try await client.from("coffee_profiles")
            .select("id,display_name,biography,avatar_path,cover_path,revision")
            .eq("id", value: userID.uuidString.lowercased()).execute().value
        if profiles.isEmpty {
            guard expectedID == nil else { throw ConnectionError.profileUnavailable }
            let name = passport.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = Profile(id: userID, display_name: String((name.isEmpty ? "My coffee corner" : name).prefix(80)),
                                  biography: String(passport.bio.prefix(2000)), avatar_path: passport.avatar, cover_path: passport.cover, revision:nil)
            try await client.from("coffee_profiles").insert(profile).execute()
        }
        return userID
    }

    private func identity(_ expectedID: UUID) async throws -> UUID {
        guard client.auth.currentSession != nil else { throw ConnectionError.missingSession }
        let userID = try await client.auth.session.user.id
        guard userID == expectedID else { throw ConnectionError.wrongAccount }
        return userID
    }

    func profiles(for account: UUID) async throws -> [Profile] {
        _ = try await identity(account)
        return try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path,revision").execute().value
    }

    func updateProfile(name:String,biography:String,revision:Int,account:UUID) async throws -> Profile {
        let user=try await identity(account)
        let patch=ProfilePatch(display_name:name,biography:biography)
        do {
            let updated:[Profile] = try await client.from("coffee_profiles").update(patch)
                .eq("id",value:user.uuidString.lowercased()).eq("revision",value:revision)
                .select("id,display_name,biography,avatar_path,cover_path,revision").execute().value
            if let profile=updated.first,updated.count==1 {
                _ = try await identity(account)
                return profile
            }
        } catch {
            // Read back below: the update may have committed before a timeout.
            let current:[Profile] = try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path,revision")
                .eq("id",value:user.uuidString.lowercased()).execute().value
            if let profile=current.first,current.count==1,profile.display_name==name,profile.biography==biography {
                _ = try await identity(account)
                return profile
            }
            if let profile=current.first,current.count==1,let currentRevision=profile.revision,currentRevision>revision {
                throw ConnectionError.profileConflict
            }
            throw error
        }
        let current:[Profile] = try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path,revision")
            .eq("id",value:user.uuidString.lowercased()).execute().value
        guard let profile=current.first,current.count==1 else {throw ConnectionError.profileUnavailable}
        guard profile.display_name==name,profile.biography==biography else {throw ConnectionError.profileConflict}
        _ = try await identity(account)
        return profile
    }

    func moments(for account: UUID) async throws -> [Moment] {
        _ = try await identity(account)
        return try await client.from("coffee_posts").select().order("created_at", ascending: false).execute().value
    }

    func ownMoments(for account: UUID) async throws -> [Moment] {
        let user=try await identity(account)
        let moments:[Moment] = try await client.from("coffee_posts").select()
            .eq("author_id",value:user.uuidString.lowercased()).order("created_at",ascending:false).execute().value
        _ = try await identity(account)
        return moments
    }

    func deleteMoment(_ id: UUID, account: UUID) async throws {
        let user=try await identity(account)
        let path:String = try await client.rpc("remove_coffee_post",params:RemovedPost(post_id:id)).execute().value
        guard path.hasPrefix(user.uuidString.lowercased()+"/"),path.split(separator:"/").count==2,
              !path.contains("..") else {throw ConnectionError.actionUnavailable}
        _ = try await client.storage.from("coffee-media").remove(paths:[path])
        let remains:Bool = try await client.rpc("removed_coffee_media_exists",params:RemovedMedia(p_path:path)).execute().value
        guard !remains else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func comments(for moment: UUID, account: UUID) async throws -> [Comment] {
        _ = try await identity(account)
        return try await client.from("coffee_comments").select().eq("post_id", value: moment.uuidString.lowercased())
            .order("created_at", ascending: true).execute().value
    }

    func follows(for account: UUID) async throws -> [Follow] {
        _ = try await identity(account)
        return try await client.from("coffee_follows").select("follower_id,followed_id").execute().value
    }

    func setFollow(_ member: UUID, account: UUID, enabled: Bool) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("set_coffee_follow",params:PairAction(p_member:member,p_enabled:enabled)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func requestFriendship(_ member: UUID, account: UUID, requestID: UUID) async throws -> UUID {
        _ = try await identity(account)
        let id:UUID = try await client.rpc("request_coffee_friendship",params:FriendRequest(p_id:requestID,p_recipient:member)).execute().value
        _ = try await identity(account)
        return id
    }

    func friendshipRequests(for account: UUID) async throws -> [Friendship] {
        _ = try await identity(account)
        return try await client.from("coffee_friend_requests").select().order("created_at", ascending: false).execute().value
    }

    func respondToFriendship(_ requestID: UUID, accepted: Bool, account: UUID) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("answer_coffee_friendship",params:FriendAnswer(p_id:requestID,p_accept:accepted)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func cancelFriendship(_ requestID:UUID,account:UUID) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("cancel_coffee_friendship",params:FriendCancel(p_id:requestID)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func messages(for account: UUID) async throws -> [Message] {
        _ = try await identity(account)
        return try await client.from("coffee_messages").select().order("created_at", ascending: true).execute().value
    }

    func sendMessage(_ body: String, to recipient: UUID, account: UUID, messageID: UUID) async throws {
        _ = try await identity(account)
        let sent:Bool = try await client.rpc("send_coffee_message",params:MessageSend(p_id:messageID,p_recipient:recipient,p_body:body)).execute().value
        guard sent else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func sendComment(_ body: String, on moment: UUID, account: UUID, commentID: UUID) async throws {
        let user = try await identity(account)
        struct Draft: Encodable { let id: UUID; let post_id: UUID; let author_id: UUID; let body: String }
        try await client.from("coffee_comments").insert(Draft(id: commentID, post_id: moment, author_id: user, body: body)).execute()
    }

    func report(_ kind: String, subject: UUID, reason: String, account: UUID, reportID: UUID) async throws {
        let user = try await identity(account)
        let draft=Report(id:reportID,reporter_id:user,subject_kind:kind,subject_id:subject,reason:reason)
        do {try await client.from("coffee_reports").insert(draft).execute()}
        catch {
            let rows:[Report] = try await client.from("coffee_reports").select("id,reporter_id,subject_kind,subject_id,reason")
                .eq("id",value:reportID.uuidString.lowercased()).execute().value
            guard rows.count==1,let saved=rows.first,saved.reporter_id==user,saved.subject_kind==kind,
                  saved.subject_id==subject,saved.reason==reason else {throw error}
        }
        _ = try await identity(account)
    }

    func reports(for account:UUID) async throws -> [Report] {
        let user=try await identity(account)
        return try await client.from("coffee_reports").select("id,reporter_id,subject_kind,subject_id,reason")
            .eq("reporter_id",value:user.uuidString.lowercased()).execute().value
    }

    func setBlock(_ member: UUID, account: UUID, enabled: Bool) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("set_coffee_block",params:PairAction(p_member:member,p_enabled:enabled)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func blocks(for account: UUID) async throws -> [Block] {
        _ = try await identity(account)
        return try await client.from("coffee_blocks").select("blocker_id,blocked_id").execute().value
    }

    func reactions(for account: UUID, bookmarks: Bool) async throws -> [Reaction] {
        _ = try await identity(account)
        return try await client.from(bookmarks ? "coffee_bookmarks" : "coffee_likes")
            .select("moment_id,member_id").execute().value
    }

    func setReaction(_ moment: UUID, account: UUID, bookmarks: Bool, enabled: Bool) async throws {
        let user = try await identity(account)
        let table = bookmarks ? "coffee_bookmarks" : "coffee_likes"
        if enabled { try await client.from(table).insert(Reaction(moment_id: moment, member_id: user)).execute() }
        else {
            try await client.from(table).delete().eq("member_id", value: user.uuidString.lowercased())
                .eq("moment_id", value: moment.uuidString.lowercased()).execute()
        }
    }

    func wallet(for account: UUID) async throws -> Wallet {
        let user = try await identity(account)
        return try await client.from("coffee_wallets").select("balance").eq("owner_id", value: user.uuidString.lowercased())
            .single().execute().value
    }

    func walletSnapshot(for account: UUID) async throws -> WalletSnapshot {
        _ = try await identity(account)
        let snapshot: WalletSnapshot = try await client.rpc("coffee_wallet_snapshot").execute().value
        _ = try await identity(account)
        return snapshot
    }

    func brewBook(for account: UUID) async throws -> BrewBookDocument {
        let user=try await identity(account)
        let document:BrewBookDocument = try await client.from("coffee_brew_books").select("revision,contents")
            .eq("owner_id",value:user.uuidString.lowercased()).single().execute().value
        _ = try await identity(account)
        return document
    }

    func encodeBrewBook(_ book:BrewNotebook) throws -> Data {
        let encoder=JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(book)
    }

    func brewBookHistory(for account:UUID) async throws -> [BrewBookHistory] {
        let user=try await identity(account)
        let history:[BrewBookHistory] = try await client.from("coffee_brew_history").select("revision,contents,saved_at")
            .eq("owner_id",value:user.uuidString.lowercased()).order("revision",ascending:false).execute().value
        _ = try await identity(account)
        return history
    }

    /// Persist the request ID, revision and exact encoded JSON before calling;
    /// retry with those same bytes, not a freshly encoded Set or changing draft.
    func saveBrewBook(requestID: UUID, revision: Int, encodedBook: Data, account: UUID) async throws -> BrewBookWrite {
        _ = try await identity(account)
        let frozen=try JSONDecoder().decode(AnyJSON.self,from:encodedBook)
        let result:BrewBookWrite = try await client.rpc("save_coffee_brew_book",
            params:BrewBookSave(p_request:requestID,p_revision:revision,p_contents:frozen)).execute().value
        _ = try await identity(account)
        return result
    }

    func checkInDays(for account: UUID) async throws -> [CheckInDay] {
        let user = try await identity(account)
        return try await client.from("coffee_checkins").select("checkin_day,reward")
            .eq("owner_id", value: user.uuidString.lowercased())
            .order("checkin_day", ascending: false).execute().value
    }

    func checkIn(account: UUID) async throws -> CheckIn {
        _ = try await identity(account)
        let result: CheckIn = try await client.rpc("check_in_coffee").execute().value
        _ = try await identity(account)
        return result
    }

    func collectibles(for account: UUID) async throws -> [Collectible] {
        let user = try await identity(account)
        return try await client.from("coffee_collectibles").select("collectible_id,quantity")
            .eq("owner_id", value: user.uuidString.lowercased()).execute().value
    }

    func progress(for account: UUID) async throws -> Progress {
        let user = try await identity(account)
        return try await client.from("coffee_progress").select("experience")
            .eq("owner_id", value: user.uuidString.lowercased()).single().execute().value
    }

    /// Save and reuse the order ID when retrying an interrupted purchase.
    func collect(item: String, quantity: Int, orderID: UUID, account: UUID) async throws -> Int {
        _ = try await identity(account)
        let balance: Int = try await client.rpc("collect_coffee_item",
            params: CollectionOrder(order_id: orderID, item: item, item_quantity: quantity)).execute().value
        _ = try await identity(account)
        return balance
    }

    /// The order ID must be saved locally before this call and reused for retries.
    /// It is also supplied to StoreKit as appAccountToken for this purchase.
    func createPurchaseOrder(id: UUID, productID: String, account: UUID) async throws {
        let user = try await identity(account)
        let expected = PurchaseOrder(id: id, owner_id: user, product_id: productID)
        func matchingOrder() async throws -> Bool {
            let orders: [PurchaseOrder] = try await client.from("coffee_purchase_orders")
                .select("id,owner_id,product_id").eq("id", value: id.uuidString.lowercased()).execute().value
            guard let order = orders.first else { return false }
            guard orders.count == 1, order.owner_id == user, order.product_id == productID else {
                throw ConnectionError.actionUnavailable
            }
            return true
        }
        if try await matchingOrder() {
            _ = try await identity(account)
            return
        }
        do {
            try await client.from("coffee_purchase_orders").insert(expected).execute()
        } catch {
            // An interrupted response may follow a successful insert.
            guard (try? await matchingOrder()) == true else { throw error }
        }
        _ = try await identity(account)
    }

    /// Finish the StoreKit transaction only after this returns and the caller
    /// has safely persisted the resulting server balance and order state.
    func verifyPurchase(orderID: UUID, signedTransaction: String, account: UUID) async throws -> Int {
        _ = try await identity(account)
        let result: PurchaseSettlement = try await client.functions.invoke("verify-apple-purchase",
            options: FunctionInvokeOptions(body: PurchaseVerification(order_id: orderID, signed_transaction: signedTransaction)))
        _ = try await identity(account)
        return result.balance
    }

    func unlockRecipe(_ recipe: String, account: UUID) async throws -> Int {
        _ = try await identity(account)
        return try await client.rpc("unlock_coffee_recipe", params: Unlock(recipe: recipe)).execute().value
    }

    func submitMoment(id: UUID, caption: String, path: String, kind: String, account: UUID) async throws -> Int {
        _ = try await identity(account)
        return try await client.rpc("submit_coffee_moment", params: Submission(moment_id: id, caption: caption, media_path: path, media_kind: kind)).execute().value
    }

    func uploadMedia(file: URL, objectID: UUID, contentType: String, account: UUID) async throws -> String {
        let user = try await identity(account)
        let suffix = file.pathExtension.lowercased()
        let safeSuffix = suffix.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) } ? suffix : ""
        let name = objectID.uuidString.lowercased() + (safeSuffix.isEmpty ? "" : "." + safeSuffix)
        let path = user.uuidString.lowercased() + "/" + name
        do {
            try await client.storage.from("coffee-media").upload(path, fileURL: file, options: FileOptions(contentType: contentType))
        } catch {
            // A lost response may follow a successful upload. Reuse it only if
            // its bytes match the saved local draft, never just its filename.
            guard let remote=try? await client.storage.from("coffee-media").download(path: path),
                  let local=try? Data(contentsOf:file,options:.mappedIfSafe),
                  remote.count==local.count, SHA256.hash(data:remote)==SHA256.hash(data:local) else {throw error}
        }
        _ = try await identity(account)
        return path
    }

    func mediaURL(path: String, account: UUID) async throws -> URL {
        _ = try await identity(account)
        let url=try await client.storage.from("coffee-media").createSignedURL(path: path, expiresIn: 60)
        _ = try await identity(account)
        return url
    }
}
