import Foundation
import Supabase

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
        let created_at: String?
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
    private struct Report: Encodable {
        let id: UUID
        let reporter_id: UUID
        let subject_kind: String
        let subject_id: UUID
        let reason: String
    }
    private struct FriendRequest: Encodable {
        let id: UUID
        let requester_id: UUID
        let recipient_id: UUID
    }
    private struct Unlock: Encodable { let recipe: String }
    private struct Submission: Encodable {
        let moment_id: UUID
        let caption: String
        let media_path: String
        let media_kind: String
    }

    enum ConnectionError: LocalizedError {
        case missingSession, wrongAccount, profileUnavailable, sessionNotSaved, actionUnavailable, unboundSession
        var errorDescription: String? {
            switch self {
            case .missingSession: return "The saved guest session is unavailable. Your coffee book has not been changed."
            case .wrongAccount: return "The saved guest does not match this coffee book. Your data has not been changed."
            case .profileUnavailable: return "Your online profile is unavailable. Your coffee book has not been changed."
            case .sessionNotSaved: return "The guest session could not be saved securely. Please unlock the device and try again."
            case .actionUnavailable: return "This request is no longer available. Refresh and try again."
            case .unboundSession: return "A saved guest session needs review before it can be linked to this coffee book."
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
            .select("id,display_name,biography,avatar_path,cover_path")
            .eq("id", value: userID.uuidString.lowercased()).execute().value
        if profiles.isEmpty {
            guard expectedID == nil else { throw ConnectionError.profileUnavailable }
            let name = passport.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = Profile(id: userID, display_name: String((name.isEmpty ? "My coffee corner" : name).prefix(80)),
                                  biography: String(passport.bio.prefix(2000)), avatar_path: passport.avatar, cover_path: passport.cover)
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
        return try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path").execute().value
    }

    func moments(for account: UUID) async throws -> [Moment] {
        _ = try await identity(account)
        return try await client.from("coffee_posts").select().order("created_at", ascending: false).execute().value
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
        let user = try await identity(account)
        if enabled {
            try await client.from("coffee_follows").insert(Follow(follower_id: user, followed_id: member)).execute()
        } else {
            try await client.from("coffee_follows").delete().eq("follower_id", value: user.uuidString.lowercased())
                .eq("followed_id", value: member.uuidString.lowercased()).execute()
        }
    }

    func requestFriendship(_ member: UUID, account: UUID, requestID: UUID) async throws {
        let user = try await identity(account)
        try await client.from("coffee_friend_requests")
            .insert(FriendRequest(id: requestID, requester_id: user, recipient_id: member)).execute()
    }

    func friendshipRequests(for account: UUID) async throws -> [Friendship] {
        _ = try await identity(account)
        return try await client.from("coffee_friend_requests").select().order("created_at", ascending: false).execute().value
    }

    func respondToFriendship(_ requestID: UUID, accepted: Bool, account: UUID) async throws {
        let user = try await identity(account)
        let updated: [Friendship] = try await client.from("coffee_friend_requests").update(["status": accepted ? "accepted" : "declined"])
            .eq("id", value: requestID.uuidString.lowercased()).eq("recipient_id", value: user.uuidString.lowercased())
            .select().execute().value
        guard updated.count == 1 else { throw ConnectionError.actionUnavailable }
    }

    func messages(for account: UUID) async throws -> [Message] {
        _ = try await identity(account)
        return try await client.from("coffee_messages").select().order("created_at", ascending: true).execute().value
    }

    func sendMessage(_ body: String, to recipient: UUID, account: UUID, messageID: UUID) async throws {
        let user = try await identity(account)
        try await client.from("coffee_messages")
            .insert(Message(id: messageID, sender_id: user, recipient_id: recipient, body: body, created_at: nil)).execute()
    }

    func sendComment(_ body: String, on moment: UUID, account: UUID, commentID: UUID) async throws {
        let user = try await identity(account)
        struct Draft: Encodable { let id: UUID; let post_id: UUID; let author_id: UUID; let body: String }
        try await client.from("coffee_comments").insert(Draft(id: commentID, post_id: moment, author_id: user, body: body)).execute()
    }

    func report(_ kind: String, subject: UUID, reason: String, account: UUID, reportID: UUID) async throws {
        let user = try await identity(account)
        try await client.from("coffee_reports").insert(Report(id: reportID, reporter_id: user, subject_kind: kind, subject_id: subject, reason: reason)).execute()
    }

    func setBlock(_ member: UUID, account: UUID, enabled: Bool) async throws {
        let user = try await identity(account)
        if enabled { try await client.from("coffee_blocks").insert(Block(blocker_id: user, blocked_id: member)).execute() }
        else {
            try await client.from("coffee_blocks").delete().eq("blocker_id", value: user.uuidString.lowercased())
                .eq("blocked_id", value: member.uuidString.lowercased()).execute()
        }
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
        try await client.storage.from("coffee-media").upload(path, fileURL: file, options: FileOptions(contentType: contentType))
        return path
    }

    func mediaURL(path: String, account: UUID) async throws -> URL {
        _ = try await identity(account)
        return try await client.storage.from("coffee-media").createSignedURL(path: path, expiresIn: 60)
    }
}
