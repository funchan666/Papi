import Foundation
import Supabase
import CryptoKit
import Security

private struct CoffeeKeychainStorage: AuthLocalStorage {
    private let service: String
    private let storage: KeychainLocalStorage

    init(service: String = "supabase.gotrue.swift") {
        self.service = service
        storage = KeychainLocalStorage(service: service)
    }

    func store(key: String, value: Data) throws {
        try storage.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        guard let data = result as? Data else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode)) }
        return data
    }

    func remove(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

private final class CoffeeNoRedirects:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(nil)
    }
}

/// Owns the network identity independently of the device's existing archive ID.
actor CoffeeCloud {
    static let shared = CoffeeCloud()
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://cquoffowtjnxmgaxavym.supabase.co")!,
        supabaseKey: "sb_publishable_srmPaTaw81JT37tSvfmCww_vqBh73A5",
        options: SupabaseClientOptions(auth: .init(storage: CoffeeKeychainStorage()))
    )
    private let sessionKey = "sb-cquoffowtjnxmgaxavym-auth-token"
    private let emailVerificationKey = "papi-email-verification-session"
    private let deletionStorage = CoffeeKeychainStorage(service:"Papi.DeletionReceipt.v1")
    private let emailVerificationStorage = CoffeeKeychainStorage(service:"Papi.EmailVerification.v1")
    private let emailVerifier = SupabaseClient(
        supabaseURL: URL(string:"https://cquoffowtjnxmgaxavym.supabase.co")!,
        supabaseKey: "sb_publishable_srmPaTaw81JT37tSvfmCww_vqBh73A5",
        options: SupabaseClientOptions(auth:.init(storage:CoffeeKeychainStorage(service:"Papi.EmailVerification.v1"),
                                                  storageKey:"papi-email-verification-session",autoRefreshToken:false))
    )

    struct Profile: Codable {
        let id: UUID
        let display_name: String
        let biography: String
        let avatar_path: String?
        let cover_path: String?
        let revision: Int?
    }
    private struct ProfileCreate: Encodable {
        let id: UUID
        let display_name: String
        let biography: String
    }
    struct ProfileImage:Decodable,Identifiable {
        let id:UUID
        let owner_id:UUID
        let kind:String
        let media_path:String
        let moderation_status:String
        let created_at:String
    }
    struct ProfileImageSummary:Decodable {
        let owner_id:UUID
        let avatar_path:String?
        let cover_path:String?
    }
    struct VoiceTopic:Decodable,Identifiable {
        let id:String
        let title:String
        let category:String
        let sort_order:Int
    }
    struct VoiceMessage:Decodable,Identifiable {
        let id:UUID
        let sender_id:UUID
        let body:String
        let created_at:String
    }
    struct VoiceGift:Decodable,Identifiable {
        let id:UUID
        let sender_id:UUID
        let gift_id:String
        let quantity:Int
        let created_at:String
    }
    struct VoiceGiftResult:Decodable {let status:String;let balance:Int}

    struct Follow: Codable {
        let follower_id: UUID
        let followed_id: UUID
    }
    struct Message: Codable, Identifiable {
        let id: UUID
        let sender_id: UUID
        let recipient_id: UUID
        let body: String
        let kind: String
        let media_path: String?
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
    struct FeedMoment:Decodable,Identifiable {
        let id:UUID
        let author_id:UUID
        let caption:String
        let media_path:String
        let media_kind:String
        let moderation_status:String
        let created_at:String
        let like_count:Int
        let comment_count:Int
        let liked:Bool
        let bookmarked:Bool
    }
    struct Comment: Codable, Identifiable {
        let id: UUID
        let post_id: UUID
        let author_id: UUID
        let body: String
        let moderation_status: String
        let created_at: String?
    }
    struct EditorialSummary:Decodable {
        let content_id:String
        let like_count:Int
        let comment_count:Int
        let liked:Bool
    }
    struct EditorialReportedPost:Decodable {let content_id:String}
    struct EditorialComment:Decodable,Identifiable {
        let id:UUID
        let content_id:String
        let author_id:UUID
        let body:String
        let moderation_status:String
        let created_at:String
    }
    private struct EditorialKeys:Encodable {let p_keys:[String]}
    private struct EditorialKey:Encodable {let p_key:String}
    private struct EditorialLike:Encodable {let p_key:String;let p_enabled:Bool}
    private struct EditorialCommentSend:Encodable {let p_key:String;let p_id:UUID;let p_body:String}
    private struct EditorialCommentID:Encodable {let p_id:UUID}
    private struct EditorialReport:Encodable {
        let p_id:UUID;let p_key:String;let p_comment:UUID?;let p_reason:String
        enum CodingKeys:String,CodingKey {case p_id,p_key,p_comment,p_reason}
        func encode(to encoder:Encoder) throws {
            var container=encoder.container(keyedBy:CodingKeys.self)
            try container.encode(p_id,forKey:.p_id);try container.encode(p_key,forKey:.p_key)
            if let p_comment {try container.encode(p_comment,forKey:.p_comment)} else {try container.encodeNil(forKey:.p_comment)}
            try container.encode(p_reason,forKey:.p_reason)
        }
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
        let transaction_id: String
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
    struct CallSession:Decodable,Identifiable {
        let id:UUID
        let caller_id:UUID
        let recipient_id:UUID
        let status:String
        let created_at:String
        let expires_at:String
    }
    struct CallToken:Decodable {let server_url:String;let participant_token:String}
    private func validLiveKitEndpoint(_ value:String)->Bool {
        guard let url=URLComponents(string:value) else{return false}
        return url.scheme=="wss" && url.host=="papi-umze01cq.livekit.cloud" &&
            url.user==nil && url.password==nil && url.port==nil &&
            (url.path.isEmpty || url.path=="/") && url.query==nil && url.fragment==nil
    }
    private struct DeletionBody:Encodable {let receipt:String}
    private struct DeletionResult:Decodable {let status:String}
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
    private struct MessageAttachment: Encodable {let p_id:UUID;let p_recipient:UUID;let p_kind:String}
    private struct ConversationCursor:Encodable {let p_peer:UUID;let p_before_time:String?;let p_before_id:UUID?}
    private struct CommentCursor:Encodable {let p_post:UUID;let p_before_time:String?;let p_before_id:UUID?}
    private struct ImageCursor:Encodable {let p_owner:UUID;let p_before_time:String?;let p_before_id:UUID?}
    private struct PairAction: Encodable { let p_member: UUID; let p_enabled: Bool }
    private struct ProfilePatch: Encodable { let display_name: String; let biography: String }
    private struct FeedCursor: Encodable { let p_before_time:String?;let p_before_id:UUID?;let p_target:UUID? }
    private struct ShelfCursor: Encodable { let p_author:UUID?;let p_saved:Bool;let p_before_time:String?;let p_before_id:UUID? }
    private struct ProfileMembers:Encodable {let p_members:[UUID]}
    private struct ProfileImageSubmit:Encodable {let p_id:UUID;let p_kind:String}
    private struct ProfileImageID:Encodable {let p_id:UUID}
    private struct CallRequest:Encodable {let p_id:UUID;let p_recipient:UUID}
    private struct CallAnswer:Encodable {let p_id:UUID;let p_accept:Bool}
    private struct CallID:Encodable {let p_id:UUID}
    private struct CallTokenRequest:Encodable {let call_id:UUID}
    private struct VoiceSession:Encodable {let p_topic:String;let p_session:UUID}
    private struct VoiceTokenRequest:Encodable {let topic_id:String;let session_id:UUID}
    private struct VoiceMessageRequest:Encodable {let p_topic:String;let p_session:UUID;let p_id:UUID;let p_body:String}
    private struct VoiceGiftRequest:Encodable {let p_topic:String;let p_session:UUID;let p_order:UUID;let p_gift:String;let p_quantity:Int;let p_cancel:Bool}
    enum VoiceOperation {case enter,heartbeat,leave,canJoin}
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
        guard try CoffeeKeychainStorage().retrieve(key: sessionKey) == nil,
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
            guard try CoffeeKeychainStorage().retrieve(key: sessionKey) == nil else {
                throw ConnectionError.sessionNotSaved
            }
            session = try await client.auth.signInAnonymously()
            guard client.auth.currentSession?.user.id == session.user.id else {
                throw ConnectionError.sessionNotSaved
            }
        }
        guard let stored = try CoffeeKeychainStorage().retrieve(key: sessionKey),
              let persisted = try? JSONDecoder().decode(Session.self, from: stored),
              persisted.user.id == session.user.id else { throw ConnectionError.sessionNotSaved }
        let userID = session.user.id
        if let expectedID, expectedID != userID { throw ConnectionError.wrongAccount }

        let profiles: [Profile] = try await client.from("coffee_profiles")
            .select("id,display_name,biography,avatar_path,cover_path,revision")
            .eq("id", value: userID.uuidString.lowercased()).execute().value
        if profiles.isEmpty {
            guard expectedID == nil else { throw ConnectionError.profileUnavailable }
            let name = passport.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = ProfileCreate(id: userID, display_name: String((name.isEmpty ? "My coffee corner" : name).prefix(80)),
                                        biography: String(passport.bio.prefix(2000)))
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

    // Email verification uses a separate Keychain session so an OTP can never
    // replace the guest account before its identity has been checked.
    func beginEmailLink(_ email:String,account:UUID) async throws {
        _ = try await identity(account)
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==nil else {throw ConnectionError.unboundSession}
        let current=try await client.auth.user()
        guard current.id==account,current.isAnonymous else {throw ConnectionError.actionUnavailable}
        let updated=try await client.auth.update(user:UserAttributes(email:email))
        guard updated.id==account else {throw ConnectionError.wrongAccount}
        _ = try await identity(account)
    }

    func verifyEmailLink(_ email:String,code:String,account:UUID) async throws {
        _ = try await identity(account)
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==nil else {throw ConnectionError.unboundSession}
        let response=try await emailVerifier.auth.verifyOTP(email:email,token:code,type:.emailChange)
        guard let session=response.session,session.user.id==account,!session.user.isAnonymous,
              session.user.emailConfirmedAt != nil,session.user.email?.lowercased()==email.lowercased() else {
            try? emailVerificationStorage.remove(key:emailVerificationKey)
            throw ConnectionError.wrongAccount
        }
        let data=try JSONEncoder().encode(session)
        try emailVerificationStorage.store(key:emailVerificationKey,value:data)
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==data else {throw ConnectionError.sessionNotSaved}
        _ = try await resumeEmailLink(account:account)
    }

    func resumeEmailLink(account:UUID) async throws -> Bool {
        guard let data=try emailVerificationStorage.retrieve(key:emailVerificationKey) else{return false}
        let saved=try JSONDecoder().decode(Session.self,from:data)
        guard saved.user.id==account,!saved.user.isAnonymous,saved.user.emailConfirmedAt != nil else {throw ConnectionError.wrongAccount}
        if let current=client.auth.currentSession,current.user.id != account {throw ConnectionError.wrongAccount}
        let adopted=try await client.auth.setSession(accessToken:saved.accessToken,refreshToken:saved.refreshToken)
        guard adopted.user.id==account,let stored=try CoffeeKeychainStorage().retrieve(key:sessionKey),
              let persisted=try? JSONDecoder().decode(Session.self,from:stored),persisted.user.id==account,
              persisted.refreshToken==adopted.refreshToken else {throw ConnectionError.sessionNotSaved}
        try emailVerificationStorage.remove(key:emailVerificationKey)
        return true
    }

    func requestEmailRecovery(_ email:String) async throws {
        try requireFreshBootstrap()
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==nil else {throw ConnectionError.unboundSession}
        try await emailVerifier.auth.signInWithOTP(email:email,shouldCreateUser:false)
    }

    func verifyEmailRecovery(_ email:String,code:String) async throws -> UUID {
        try requireFreshBootstrap()
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==nil else {throw ConnectionError.unboundSession}
        let response=try await emailVerifier.auth.verifyOTP(email:email,token:code,type:.email)
        guard let session=response.session,!session.user.isAnonymous,session.user.emailConfirmedAt != nil,
              session.user.email?.lowercased()==email.lowercased() else {
            try? emailVerificationStorage.remove(key:emailVerificationKey)
            throw ConnectionError.wrongAccount
        }
        let data=try JSONEncoder().encode(session)
        try emailVerificationStorage.store(key:emailVerificationKey,value:data)
        guard try emailVerificationStorage.retrieve(key:emailVerificationKey)==data else {throw ConnectionError.sessionNotSaved}
        return session.user.id
    }

    func pendingEmailRecoveryAccount() throws -> UUID? {
        guard let data=try emailVerificationStorage.retrieve(key:emailVerificationKey) else{return nil}
        let saved=try JSONDecoder().decode(Session.self,from:data)
        guard !saved.user.isAnonymous,saved.user.emailConfirmedAt != nil else {throw ConnectionError.actionUnavailable}
        return saved.user.id
    }

    func finishEmailRecovery(account:UUID) async throws {
        if let stored=try CoffeeKeychainStorage().retrieve(key:sessionKey) {
            let saved=try JSONDecoder().decode(Session.self,from:stored)
            guard saved.user.id==account,client.auth.currentSession?.user.id==account else {throw ConnectionError.wrongAccount}
            _ = try await identity(account)
            if let recoveryData=try emailVerificationStorage.retrieve(key:emailVerificationKey) {
                let recovery=try JSONDecoder().decode(Session.self,from:recoveryData)
                guard recovery.user.id==account else {throw ConnectionError.wrongAccount}
                try emailVerificationStorage.remove(key:emailVerificationKey)
            }
            return
        }
        guard client.auth.currentSession==nil,try await resumeEmailLink(account:account) else {throw ConnectionError.missingSession}
    }

    private func deletionKey(_ account:UUID)->String {"receipt-"+account.uuidString.lowercased()}
    func prepareDeletionReceipt(account:UUID) async throws {
        let key=deletionKey(account)
        if let existing=try deletionStorage.retrieve(key:key) {
            guard let value=String(data:existing,encoding:.utf8),value.utf8.count==64,
                  value.utf8.allSatisfy({(48...57).contains($0) || (97...102).contains($0)}) else {throw ConnectionError.sessionNotSaved}
            return
        }
        _ = try await identity(account)
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else {throw ConnectionError.sessionNotSaved}
        let receipt=bytes.map{String(format:"%02x",$0)}.joined()
        let data=Data(receipt.utf8)
        try deletionStorage.store(key:key,value:data)
        guard try deletionStorage.retrieve(key:key)==data else {throw ConnectionError.sessionNotSaved}
    }
    func requestAccountDeletion(account:UUID) async throws -> Bool {
        guard let data=try deletionStorage.retrieve(key:deletionKey(account)),let receipt=String(data:data,encoding:.utf8),receipt.count==64 else {throw ConnectionError.sessionNotSaved}
        var request=URLRequest(url:URL(string:"https://cquoffowtjnxmgaxavym.supabase.co/functions/v1/delete-coffee-account")!)
        request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("sb_publishable_srmPaTaw81JT37tSvfmCww_vqBh73A5",forHTTPHeaderField:"apikey")
        if let current=client.auth.currentSession {
            guard current.user.id==account else {throw ConnectionError.wrongAccount}
            if let session=try? await client.auth.session {
                guard session.user.id==account else {throw ConnectionError.wrongAccount}
                request.setValue("Bearer "+session.accessToken,forHTTPHeaderField:"Authorization")
            }
        }
        request.httpBody=try JSONEncoder().encode(DeletionBody(receipt:receipt))
        let config=URLSessionConfiguration.ephemeral;config.urlCache=nil;config.httpCookieStorage=nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData;config.timeoutIntervalForRequest=30
        let session=URLSession(configuration:config,delegate:CoffeeNoRedirects(),delegateQueue:nil)
        defer{session.invalidateAndCancel()}
        let (body,response)=try await session.data(for:request)
        guard let response=response as? HTTPURLResponse,response.url?.scheme=="https",
              response.url?.host=="cquoffowtjnxmgaxavym.supabase.co",body.count<=2048,[200,202].contains(response.statusCode),
              let result=try? JSONDecoder().decode(DeletionResult.self,from:body),["complete","pending"].contains(result.status) else {throw ConnectionError.actionUnavailable}
        return result.status=="complete"
    }
    func clearDeletedSession(account:UUID) async throws {
        let storage=CoffeeKeychainStorage()
        if let data=try storage.retrieve(key:sessionKey) {
            let saved=try JSONDecoder().decode(Session.self,from:data)
            guard saved.user.id==account else {throw ConnectionError.wrongAccount}
            do {try await client.auth.signOut(scope:.local)} catch {
                if try storage.retrieve(key:sessionKey) != nil {throw error}
            }
        }
        guard try storage.retrieve(key:sessionKey)==nil else {throw ConnectionError.sessionNotSaved}
    }
    func forgetDeletionReceipt(account:UUID) throws {try deletionStorage.remove(key:deletionKey(account))}

    func profiles(for account: UUID) async throws -> [Profile] {
        _ = try await identity(account)
        return try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path,revision").execute().value
    }
    func profiles(ids:[UUID],account:UUID) async throws -> [Profile] {
        _ = try await identity(account)
        guard !ids.isEmpty else{return []}
        let result:[Profile] = try await client.from("coffee_profiles").select("id,display_name,biography,avatar_path,cover_path,revision")
            .in("id",values:ids).execute().value
        _ = try await identity(account)
        return result
    }
    func voiceTopics(account:UUID) async throws -> [VoiceTopic] {
        _ = try await identity(account)
        let topics:[VoiceTopic] = try await client.from("coffee_voice_topics").select("id,title,category,sort_order").order("sort_order",ascending:true).execute().value
        _ = try await identity(account)
        return topics
    }

    func voiceSession(topic:String,id:UUID,account:UUID,operation:VoiceOperation) async throws -> Bool {
        _ = try await identity(account)
        let rpc:String
        switch operation {
        case .enter:rpc="enter_coffee_voice"
        case .heartbeat:rpc="heartbeat_coffee_voice"
        case .leave:rpc="leave_coffee_voice"
        case .canJoin:rpc="can_join_coffee_voice"
        }
        let result:Bool = try await client.rpc(rpc,params:VoiceSession(p_topic:topic,p_session:id)).execute().value
        _ = try await identity(account)
        return result
    }
    func voiceMessages(topic:String,session:UUID,account:UUID) async throws -> [VoiceMessage] {
        _ = try await identity(account)
        let rows:[VoiceMessage] = try await client.rpc("coffee_voice_messages",params:VoiceSession(p_topic:topic,p_session:session)).execute().value
        _ = try await identity(account)
        return rows
    }
    func sendVoiceMessage(topic:String,session:UUID,id:UUID,body:String,account:UUID) async throws {
        _ = try await identity(account)
        let result:UUID = try await client.rpc("send_coffee_voice_message",params:VoiceMessageRequest(p_topic:topic,p_session:session,p_id:id,p_body:body)).execute().value
        guard result==id else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }
    func voiceGifts(topic:String,session:UUID,account:UUID) async throws -> [VoiceGift] {
        _ = try await identity(account)
        let rows:[VoiceGift] = try await client.rpc("coffee_voice_gifts",params:VoiceSession(p_topic:topic,p_session:session)).execute().value
        _ = try await identity(account)
        return rows
    }
    func sendVoiceGift(_ pending:PendingCloudRoomGift,cancel:Bool,account:UUID) async throws -> VoiceGiftResult {
        _ = try await identity(account)
        let request=VoiceGiftRequest(p_topic:pending.topic,p_session:pending.sessionID,p_order:pending.id,p_gift:pending.giftID,p_quantity:pending.quantity,p_cancel:cancel)
        let rows:[VoiceGiftResult] = try await client.rpc("send_coffee_voice_gift",params:request).execute().value
        guard rows.count==1,["settled","cancelled","insufficient"].contains(rows[0].status) else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
        return rows[0]
    }
    func voiceToken(topic:String,id:UUID,account:UUID) async throws -> CallToken {
        _ = try await identity(account)
        let result:CallToken = try await client.functions.invoke("livekit-voice-token",options:FunctionInvokeOptions(body:VoiceTokenRequest(topic_id:topic,session_id:id)))
        guard validLiveKitEndpoint(result.server_url),!result.participant_token.isEmpty else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
        return result
    }

    func profileImageSummaries(_ members:[UUID],account:UUID) async throws -> [ProfileImageSummary] {
        _ = try await identity(account)
        guard !members.isEmpty else{return []}
        let result:[ProfileImageSummary] = try await client.rpc("coffee_profile_image_summary",params:ProfileMembers(p_members:members)).execute().value
        _ = try await identity(account)
        return result
    }

    func profileImages(owner:UUID,account:UUID,before:ProfileImage?=nil) async throws -> [ProfileImage] {
        _ = try await identity(account)
        let cursor=ImageCursor(p_owner:owner,p_before_time:before?.created_at,p_before_id:before?.id)
        let result:[ProfileImage] = try await client.rpc("coffee_profile_image_page",params:cursor).execute().value
        _ = try await identity(account)
        return result
    }
    func profileImage(_ id:UUID,account:UUID) async throws -> ProfileImage? {
        _ = try await identity(account)
        let rows:[ProfileImage] = try await client.from("coffee_profile_images").select().eq("id",value:id.uuidString.lowercased()).limit(1).execute().value
        _ = try await identity(account)
        return rows.first
    }

    func submitProfileImage(id:UUID,kind:String,account:UUID) async throws {
        _ = try await identity(account)
        let result:Bool = try await client.rpc("submit_coffee_profile_image",params:ProfileImageSubmit(p_id:id,p_kind:kind)).execute().value
        guard result else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func deleteProfileImage(id:UUID,account:UUID) async throws {
        let user=try await identity(account)
        let path:String = try await client.rpc("remove_coffee_profile_image",params:ProfileImageID(p_id:id)).execute().value
        let expected=user.uuidString.lowercased()+"/profile-"+id.uuidString.lowercased()+".jpg"
        guard path==expected else {throw ConnectionError.actionUnavailable}
        _ = try await client.storage.from("coffee-media").remove(paths:[path])
        let remains:Bool = try await client.rpc("removed_profile_media_exists",params:ProfileImageID(p_id:id)).execute().value
        guard !remains else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
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

    func recentMoments(for account:UUID,before:FeedMoment?=nil,target:UUID?=nil) async throws -> [FeedMoment] {
        _ = try await identity(account)
        let cursor=FeedCursor(p_before_time:before?.created_at,p_before_id:before?.id,p_target:target)
        let moments:[FeedMoment] = try await client.rpc("recent_coffee_moments",params:cursor).execute().value
        _ = try await identity(account)
        return moments
    }

    func momentShelf(for account:UUID,author:UUID?,saved:Bool,before:FeedMoment?=nil) async throws -> [FeedMoment] {
        _ = try await identity(account)
        let cursor=ShelfCursor(p_author:author,p_saved:saved,p_before_time:before?.created_at,p_before_id:before?.id)
        let moments:[FeedMoment] = try await client.rpc("coffee_moment_shelf",params:cursor).execute().value
        _ = try await identity(account)
        return moments
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

    func comments(for moment: UUID, account: UUID,before:Comment?=nil) async throws -> [Comment] {
        _ = try await identity(account)
        if before != nil && before?.created_at==nil {throw ConnectionError.actionUnavailable}
        let cursor=CommentCursor(p_post:moment,p_before_time:before?.created_at,p_before_id:before?.id)
        let result:[Comment] = try await client.rpc("coffee_comment_page",params:cursor).execute().value
        _ = try await identity(account)
        return result
    }

    func editorialSummary(_ keys:[String],account:UUID) async throws -> [EditorialSummary] {
        _ = try await identity(account)
        let rows:[EditorialSummary] = try await client.rpc("coffee_editorial_summary",params:EditorialKeys(p_keys:keys)).execute().value
        _ = try await identity(account);return rows
    }
    func editorialReportedPosts(account:UUID) async throws -> [EditorialReportedPost] {
        _ = try await identity(account)
        let rows:[EditorialReportedPost] = try await client.rpc("coffee_editorial_reported_posts").execute().value
        _ = try await identity(account);return rows
    }
    func setEditorialLike(_ key:String,enabled:Bool,account:UUID) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("set_coffee_editorial_like",params:EditorialLike(p_key:key,p_enabled:enabled)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable};_ = try await identity(account)
    }
    func editorialComments(_ key:String,account:UUID) async throws -> [EditorialComment] {
        _ = try await identity(account)
        let rows:[EditorialComment] = try await client.rpc("coffee_editorial_comments",params:EditorialKey(p_key:key)).execute().value
        _ = try await identity(account);return rows
    }
    func sendEditorialComment(_ key:String,id:UUID,body:String,account:UUID) async throws {
        _ = try await identity(account)
        let saved:UUID = try await client.rpc("send_coffee_editorial_comment",params:EditorialCommentSend(p_key:key,p_id:id,p_body:body)).execute().value
        guard saved==id else {throw ConnectionError.actionUnavailable};_ = try await identity(account)
    }
    func deleteEditorialComment(_ id:UUID,account:UUID) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("delete_coffee_editorial_comment",params:EditorialCommentID(p_id:id)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable};_ = try await identity(account)
    }
    func reportEditorial(_ key:String,comment:UUID?,reason:String,id:UUID,account:UUID) async throws {
        _ = try await identity(account)
        let saved:UUID = try await client.rpc("report_coffee_editorial",params:EditorialReport(p_id:id,p_key:key,p_comment:comment,p_reason:reason)).execute().value
        guard saved==id else {throw ConnectionError.actionUnavailable};_ = try await identity(account)
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

    func callSessions(account:UUID) async throws -> [CallSession] {
        _ = try await identity(account)
        let rows:[CallSession] = try await client.from("coffee_calls").select().order("created_at",ascending:false).limit(100).execute().value
        _ = try await identity(account)
        return rows
    }

    func requestCall(id:UUID,recipient:UUID,account:UUID) async throws -> UUID {
        _ = try await identity(account)
        let result:UUID = try await client.rpc("request_coffee_call",params:CallRequest(p_id:id,p_recipient:recipient)).execute().value
        _ = try await identity(account)
        return result
    }

    func answerCall(id:UUID,accept:Bool,account:UUID) async throws -> Bool {
        _ = try await identity(account)
        let result:Bool = try await client.rpc("answer_coffee_call",params:CallAnswer(p_id:id,p_accept:accept)).execute().value
        _ = try await identity(account)
        return result
    }

    func endCall(id:UUID,account:UUID) async throws {
        _ = try await identity(account)
        let result:Bool = try await client.rpc("end_coffee_call",params:CallID(p_id:id)).execute().value
        guard result else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func callToken(id:UUID,account:UUID) async throws -> CallToken {
        _ = try await identity(account)
        let result:CallToken = try await client.functions.invoke("livekit-call-token",options:FunctionInvokeOptions(body:CallTokenRequest(call_id:id)))
        guard validLiveKitEndpoint(result.server_url),!result.participant_token.isEmpty else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
        return result
    }

    func canJoinCall(id:UUID,account:UUID) async throws -> Bool {
        _ = try await identity(account)
        let allowed:Bool = try await client.rpc("can_join_coffee_call",params:CallID(p_id:id)).execute().value
        _ = try await identity(account)
        return allowed
    }

    func messages(for account: UUID) async throws -> [Message] {
        _ = try await identity(account)
        let result:[Message] = try await client.rpc("coffee_message_inbox").execute().value
        _ = try await identity(account)
        return result
    }

    func conversation(for peer:UUID,account:UUID,before:Message?=nil) async throws -> [Message] {
        _ = try await identity(account)
        let cursor=ConversationCursor(p_peer:peer,p_before_time:before?.created_at,p_before_id:before?.id)
        let messages:[Message] = try await client.rpc("coffee_conversation_page",params:cursor).execute().value
        _ = try await identity(account)
        return messages
    }

    func sendMessage(_ body: String, to recipient: UUID, account: UUID, messageID: UUID) async throws {
        _ = try await identity(account)
        let sent:Bool = try await client.rpc("send_coffee_message",params:MessageSend(p_id:messageID,p_recipient:recipient,p_body:body)).execute().value
        guard sent else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }
    func sendAttachment(_ kind:String,to recipient:UUID,account:UUID,messageID:UUID) async throws {
        _ = try await identity(account)
        let saved:Bool = try await client.rpc("send_coffee_attachment",params:MessageAttachment(p_id:messageID,p_recipient:recipient,p_kind:kind)).execute().value
        guard saved else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
    }

    func sendComment(_ body: String, on moment: UUID, account: UUID, commentID: UUID) async throws {
        let user = try await identity(account)
        struct Draft: Encodable { let id: UUID; let post_id: UUID; let author_id: UUID; let body: String }
        do {try await client.from("coffee_comments").insert(Draft(id: commentID, post_id: moment, author_id: user, body: body)).execute()}
        catch {
            let rows:[Comment] = try await client.from("coffee_comments").select().eq("id",value:commentID.uuidString.lowercased()).execute().value
            guard rows.count==1,let saved=rows.first,saved.author_id==user,saved.post_id==moment,saved.body==body else {throw error}
        }
        _ = try await identity(account)
    }

    func comment(_ id:UUID,account:UUID) async throws -> Comment? {
        _ = try await identity(account)
        let rows:[Comment] = try await client.from("coffee_comments").select().eq("id",value:id.uuidString.lowercased()).limit(1).execute().value
        _ = try await identity(account)
        return rows.first
    }

    func deleteComment(_ id:UUID,account:UUID) async throws {
        let user=try await identity(account)
        try await client.from("coffee_comments").delete().eq("id",value:id.uuidString.lowercased()).eq("author_id",value:user.uuidString.lowercased()).execute()
        let remaining:[Comment] = try await client.from("coffee_comments").select().eq("id",value:id.uuidString.lowercased()).execute().value
        guard remaining.isEmpty else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
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
        if enabled {
            do {try await client.from(table).insert(Reaction(moment_id: moment, member_id: user)).execute()}
            catch {
                let rows:[Reaction] = try await client.from(table).select("moment_id,member_id").eq("member_id",value:user.uuidString.lowercased()).eq("moment_id",value:moment.uuidString.lowercased()).execute().value
                guard rows.count==1 else {throw error}
            }
        }
        else {
            try await client.from(table).delete().eq("member_id", value: user.uuidString.lowercased())
                .eq("moment_id", value: moment.uuidString.lowercased()).execute()
        }
        let rows:[Reaction] = try await client.from(table).select("moment_id,member_id").eq("member_id",value:user.uuidString.lowercased()).eq("moment_id",value:moment.uuidString.lowercased()).execute().value
        guard (rows.count==1)==enabled else {throw ConnectionError.actionUnavailable}
        _ = try await identity(account)
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
    func verifyPurchase(orderID: UUID, transactionID: String, account: UUID) async throws -> Int {
        _ = try await identity(account)
        let result: PurchaseSettlement = try await client.functions.invoke("verify-apple-purchase",
            options: FunctionInvokeOptions(body: PurchaseVerification(order_id: orderID, transaction_id: transactionID)))
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

    func uploadMedia(file: URL, objectID: UUID, contentType: String, account: UUID, profileImage:Bool = false, messageAttachment:Bool = false) async throws -> String {
        let user = try await identity(account)
        let suffix = file.pathExtension.lowercased()
        let safeSuffix = suffix.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) } ? suffix : ""
        if profileImage && (safeSuffix != "jpg" || contentType != "image/jpeg") {throw ConnectionError.actionUnavailable}
        if messageAttachment && !((safeSuffix=="jpg" && contentType=="image/jpeg") || (safeSuffix=="m4a" && contentType=="audio/mp4")) {throw ConnectionError.actionUnavailable}
        guard !(profileImage && messageAttachment) else {throw ConnectionError.actionUnavailable}
        let name = (profileImage ? "profile-":(messageAttachment ? "message-":"")) + objectID.uuidString.lowercased() + (safeSuffix.isEmpty ? "" : "." + safeSuffix)
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

    func mediaURL(path: String, account: UUID, expiresIn:Int = 60) async throws -> URL {
        _ = try await identity(account)
        guard (1...300).contains(expiresIn) else {throw ConnectionError.actionUnavailable}
        let url=try await client.storage.from("coffee-media").createSignedURL(path: path, expiresIn: expiresIn)
        _ = try await identity(account)
        return url
    }
}
