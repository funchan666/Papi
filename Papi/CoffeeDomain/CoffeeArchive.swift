import Foundation

struct CoffeeMember: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let portrait: String
    let bio: String
}
struct CoffeeMoment: Identifiable, Codable, Hashable {
    var id: String
    var authorID: String
    var media: String
    var isVideo: Bool = false
    var caption: String
    var category: String
    var createdAt: Date = Date()
    var isOwnMoment: Bool = false
    var moderation:ModerationStatus? = nil
    enum CodingKeys:String,CodingKey {
        case id = "id"
        case authorID = "authorID"
        case media = "media"
        case isVideo = "isVideo"
        case caption = "caption"
        case category = "category"
        case createdAt = "createdAt"
        case isOwnMoment = "isLocal"
        case moderation = "moderation"
    }
}
struct TastingReply: Identifiable, Codable {
    var id = UUID().uuidString
    var momentID: String
    var text: String
    var createdAt = Date()
    var authorID:String? = nil
    enum CodingKeys:String,CodingKey {
        case id = "id"
        case momentID = "postID"
        case text = "text"
        case createdAt = "createdAt"
        case authorID = "authorID"
    }
}
struct CommunityReport: Identifiable, Codable {
    var id = UUID().uuidString
    var contentReference: String
    var reason: String
    var createdAt = Date()
    var target:SafetyTarget? = nil
    var parentID:String? = nil
    var excerpt:String? = nil
    enum CodingKeys:String,CodingKey {
        case id = "id"
        case contentReference = "subjectID"
        case reason = "reason"
        case createdAt = "createdAt"
        case target = "target"
        case parentID = "parentID"
        case excerpt = "excerpt"
    }
}
struct CoffeeCollectible: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let asset: String
    let cost: Int
}
struct CoffeeTable: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let image: String
    let hostMemberID: String
    var coverReference:String {CoffeeMember.find(hostMemberID)?.portrait ?? image}
}
struct TableNoteEntry:Identifiable,Codable {
    var id=UUID().uuidString
    let text:String
    var createdAt=Date()
}
struct GiftPreview: Identifiable, Codable {
    var id = UUID().uuidString
    var giftID: String
    var quantity: Int
    var context: String
    var createdAt = Date()
}
struct CoinMovement: Identifiable, Codable {
    var id: String
    var delta: Int
    var reason: String
    var createdAt = Date()
}
struct WelcomeGrant: Codable {
    let coins: Int
    var acknowledged = false
    var createdAt = Date()
}
struct CoinPurchaseTerms: Codable {
    let token: UUID
    let owner: UUID
    let productID: String
    let coins: Int
    var createdAt = Date()
    // Each new checkout token can settle only one Apple transaction.
    var transactionID: String? = nil
    // A terminal StoreKit failure is retained for later server reconciliation.
    var failedAt: Date? = nil
    // Nil identifies older orders whose submission state is unknown.
    var paymentStarted: Bool? = nil
}
struct PendingCloudCollectible: Codable {
    let id: UUID
    let accountID: UUID
    let item: String
    let quantity: Int
}
struct PendingCloudRoomGift: Codable {
    let id:UUID
    let accountID:UUID
    let topic:String
    let sessionID:UUID
    let giftID:String
    let quantity:Int
}
struct PendingCloudMoment: Codable {
    let id: UUID
    let accountID: UUID
    let caption: String
    let media: String
    let isVideo: Bool
}
struct PendingCloudPostDeletion: Codable {
    let accountID: UUID
    let postID: UUID
}
struct PendingCloudBrewWrite: Codable {
    let id: UUID
    let accountID: UUID
    let revision: Int
    let generation: Int
    let encodedBook: Data
}
struct PendingCloudReport: Codable {
    let id: UUID
    let accountID: UUID
    let target: SafetyTarget
    let reason: String
}
struct PendingCloudMessage: Codable {
    let id: UUID
    let accountID: UUID
    let recipientID: UUID
    let body: String
}
struct PendingCloudFriendship: Codable {
    let id: UUID
    let accountID: UUID
    let recipientID: UUID
}
struct PendingCloudProfile: Codable {
    let accountID: UUID
    let name: String
    let biography: String
    let revision: Int
}
struct PendingCloudComment: Codable {
    let id:UUID
    let accountID:UUID
    let momentID:UUID
    let body:String
}
struct PendingCloudEditorialComment:Codable {
    let id:UUID
    let accountID:UUID
    let momentID:String
    let body:String
}
struct PendingCloudProfileImage:Codable {
    let id:UUID
    let accountID:UUID
    let reference:String
    let kind:String
}
struct PendingCloudProfileImageRemoval:Codable {
    let id:UUID
    let accountID:UUID
}
struct PendingCloudAttachment:Codable {
    let id:UUID
    let accountID:UUID
    let recipientID:UUID
    let reference:String
    let kind:String
}
struct PendingCloudCall:Codable {let id:UUID;let accountID:UUID;let recipientID:UUID}
struct PendingCloudCallEnd:Codable {let id:UUID;let accountID:UUID}
struct PendingCloudVoice:Codable {let id:UUID;let accountID:UUID;let topic:String;var closing:Bool}
enum CoffeeEconomy {
    static let welcomeCoins = 800
    static func postCost(isVideo: Bool) -> Int { isVideo ? 80 : 40 }
}
struct CoffeePassport: Codable {
    static let defaultPortrait = "portrait-caleb-stone"
    var id = UUID()
    var name = "My coffee corner"
    var bio = "Keeping the cups I want to brew again."
    var avatar = CoffeePassport.defaultPortrait
    var cover = "corner-latte"
    var photos: [String] = []
    // Existing guests with the original brand avatar receive the same photo default as new guests.
    var portraitReference:String {avatar.isEmpty || avatar=="brandMark" ? Self.defaultPortrait:avatar}
}
struct MomentDraft: Codable {
    var text = ""
    var media: String? = nil
    var isVideo = false
}
struct CoffeeArchive: Codable {
    var version = 1
    var passport = CoffeePassport()
    // Optional fields keep pre-cloud snapshots readable and prevent a lost
    // session from silently creating a different remote guest.
    var cloudAccountID: UUID? = nil
    var cloudBootstrapPending: Bool? = nil
    var pendingCloudRecoveryID: UUID? = nil
    var pendingCloudDeletionID: UUID? = nil
    var deletedCloudAccountID: UUID? = nil
    var pendingCloudCollectible: PendingCloudCollectible? = nil
    var pendingCloudRoomGift: PendingCloudRoomGift? = nil
    var pendingCloudMoment: PendingCloudMoment? = nil
    var pendingCloudPostDeletion: PendingCloudPostDeletion? = nil
    var cloudBrewRevision: Int? = nil
    var cloudBrewGeneration: Int? = nil
    var cloudBrewSyncedGeneration: Int? = nil
    var pendingCloudBrewWrite: PendingCloudBrewWrite? = nil
    // Retain interrupted writes from deleted online accounts without replaying them into a new one.
    var retiredCloudBrewWrites: [PendingCloudBrewWrite]? = nil
    var cloudBrewConflict: Bool? = nil
    var cloudBrewLocalBackups: [BrewNotebook]? = nil
    var pendingCloudReport: PendingCloudReport? = nil
    var pendingCloudMessage: PendingCloudMessage? = nil
    var pendingCloudFriendship: PendingCloudFriendship? = nil
    var pendingCloudProfile: PendingCloudProfile? = nil
    var pendingCloudComment: PendingCloudComment? = nil
    var pendingCloudEditorialComment:PendingCloudEditorialComment? = nil
    var pendingCloudProfileImage: PendingCloudProfileImage? = nil
    var pendingCloudProfileImageRemoval: PendingCloudProfileImageRemoval? = nil
    var pendingCloudAttachment: PendingCloudAttachment? = nil
    var pendingCloudCall: PendingCloudCall? = nil
    var pendingCloudCallEnd: PendingCloudCallEnd? = nil
    var pendingCloudVoice: PendingCloudVoice? = nil
    var signedIn = false
    var sawOnboarding = false
    var acceptedPolicyVersion: String? = nil
    var language = "en"
    // Missing in earlier snapshots, whose language could have been selected automatically.
    var languageDefaultRevision: Int? = 1
    var notificationPreference = false
    var followedMembers: Set<String> = []
    var blockedMembers: Set<String> = []
    var appreciatedMoments: Set<String> = []
    var keptMoments: Set<String> = []
    // Optional so older guest snapshots keep their existing data.
    var savedCoffeeScenes: Set<String>? = nil
    var dismissedRecommendations: Set<String>? = nil
    var ownMoments: [CoffeeMoment] = []
    var tastingReplies: [TastingReply] = []
    var communityReports: [CommunityReport] = []
    var momentDraft = MomentDraft()
    var letterDrafts: [String: String] = [:]
    var letterPhotos: [String: String] = [:]
    var letterVoiceNotes: [String: String] = [:]
    var tableNotes: [String: String] = [:]
    // Optional so existing account snapshots remain readable.
    var tableNoteHistory: [String:[TableNoteEntry]]? = nil
    var recentRooms: [String] = []
    var coinBalance = 0
    var collectiblesOwned: [String: Int] = [:]
    var displayedGift: String? = nil
    var giftHistory: [GiftPreview] = []
    var checkinDays: Set<String> = []
    var experience = 0
    var coinMovements: [CoinMovement] = []
    var creditedTransactions: Set<String> = []
    var revokedTransactions: Set<String> = []
    var purchaseIntents: [String: UUID] = [:]
    // Optional fields preserve snapshots created before the wallet upgrade.
    var coinPurchaseTerms: [CoinPurchaseTerms]? = nil
    var activePurchaseToken: UUID? = nil
    var welcomeGrant: WelcomeGrant? = nil
    var brewNotebook: BrewNotebook? = nil
    // Ownership tombstones survive account deletion. They never grant the new guest ownership.
    var retiredGuestIDs: Set<UUID> = []
    var historicalTransactionIDs: Set<String> = []
    var pendingMediaDeletion: Set<UUID> = []
    // Optional so pre-community snapshots decode without resetting identity or purchases.
    var community:CorrespondenceLedger? = nil
    enum CodingKeys:String,CodingKey {
        case version = "version"
        case passport = "profile"
        case cloudAccountID = "cloudAccountID"
        case cloudBootstrapPending = "cloudBootstrapPending"
        case pendingCloudRecoveryID = "pendingCloudRecoveryID"
        case pendingCloudDeletionID = "pendingCloudDeletionID"
        case deletedCloudAccountID = "deletedCloudAccountID"
        case pendingCloudCollectible = "pendingCloudCollectible"
        case pendingCloudRoomGift = "pendingCloudRoomGift"
        case pendingCloudMoment = "pendingCloudMoment"
        case pendingCloudPostDeletion = "pendingCloudPostDeletion"
        case cloudBrewRevision = "cloudBrewRevision"
        case cloudBrewGeneration = "cloudBrewGeneration"
        case cloudBrewSyncedGeneration = "cloudBrewSyncedGeneration"
        case pendingCloudBrewWrite = "pendingCloudBrewWrite"
        case retiredCloudBrewWrites = "retiredCloudBrewWrites"
        case cloudBrewConflict = "cloudBrewConflict"
        case cloudBrewLocalBackups = "cloudBrewLocalBackups"
        case pendingCloudReport = "pendingCloudReport"
        case pendingCloudMessage = "pendingCloudMessage"
        case pendingCloudFriendship = "pendingCloudFriendship"
        case pendingCloudProfile = "pendingCloudProfile"
        case pendingCloudComment = "pendingCloudComment"
        case pendingCloudEditorialComment = "pendingCloudEditorialComment"
        case pendingCloudProfileImage = "pendingCloudProfileImage"
        case pendingCloudProfileImageRemoval = "pendingCloudProfileImageRemoval"
        case pendingCloudAttachment = "pendingCloudAttachment"
        case pendingCloudCall = "pendingCloudCall"
        case pendingCloudCallEnd = "pendingCloudCallEnd"
        case pendingCloudVoice = "pendingCloudVoice"
        case signedIn = "signedIn"
        case sawOnboarding = "sawOnboarding"
        case acceptedPolicyVersion = "acceptedPolicyVersion"
        case language = "language"
        case languageDefaultRevision = "languageDefaultRevision"
        case notificationPreference = "notificationPreference"
        case followedMembers = "follows"
        case blockedMembers = "blocked"
        case appreciatedMoments = "likes"
        case keptMoments = "bookmarks"
        case savedCoffeeScenes = "savedCoffeeScenes"
        case dismissedRecommendations = "dismissedRecommendations"
        case ownMoments = "localPosts"
        case tastingReplies = "comments"
        case communityReports = "reports"
        case momentDraft = "postDraft"
        case letterDrafts = "chatDrafts"
        case letterPhotos = "chatAttachments"
        case letterVoiceNotes = "voiceDrafts"
        case tableNotes = "roomDrafts"
        case tableNoteHistory = "tableNoteHistory"
        case recentRooms = "recentRooms"
        case coinBalance = "coins"
        case collectiblesOwned = "inventory"
        case displayedGift = "displayedGift"
        case giftHistory = "giftHistory"
        case checkinDays = "checkinDays"
        case experience = "experience"
        case coinMovements = "wallet"
        case creditedTransactions = "creditedTransactions"
        case revokedTransactions = "revokedTransactions"
        case purchaseIntents = "purchaseIntents"
        case coinPurchaseTerms = "coinPurchaseTerms"
        case activePurchaseToken = "activePurchaseToken"
        case welcomeGrant = "welcomeGrant"
        case brewNotebook = "brewNotebook"
        case retiredGuestIDs = "retiredGuestIDs"
        case historicalTransactionIDs = "historicalTransactionIDs"
        case pendingMediaDeletion = "pendingMediaDeletion"
        case community = "community"
    }

    mutating func setBrewNotebook(_ book:BrewNotebook) {
        brewNotebook=book
        if cloudAccountID != nil {cloudBrewGeneration=(cloudBrewGeneration ?? 0)+1}
    }
}

extension CoffeeMember {
    // Stable IDs are retained for archived references; display data comes from the cloud.
    static var portraits:[CoffeeMember] {(0..<8).compactMap {index in CoffeeCollection.cloudPeople()?.first{$0.id=="preview-member-\(index)"}}}
    static var previews:[CoffeeMember] {CoffeeCollection.cloudPeople() ?? []}
    static let editorial=CoffeeMember(id:"papi-editorial",name:"The Papi coffee desk",portrait:"brandMark",bio:"Coffee scenes, brewing details and small rituals selected for the Papi journal.")
    static func find(_ id:String)->CoffeeMember? {id==editorial.id ? editorial:previews.first{$0.id==id}}
    var handle:String {
        if id==Self.editorial.id {return "papi.coffee.desk"}
        let handles=["clara.pourover","jun.ceramics","kai.trailcoffee","theo.espresso","elise.readsandbrews","mateo.icedcoffee","ren.roastnotes","dae.firstcup"]
        if let index=Self.portraits.firstIndex(where:{$0.id==id}) {return handles[index]}
        return name.lowercased().replacingOccurrences(of:" ",with:".")
    }
}
extension CoffeeCollectible {
    static var all:[CoffeeCollectible] {CoffeeCollection.cloudGifts() ?? []}
}
extension CoffeeMoment {
    static var editorial:[CoffeeMoment] {CoffeeCollection.cloudEditorial() ?? []}
}

/// Fixed conversation samples for the supplied collection, never messages or relationship records.
struct CollectionConversation {
    let momentID:String
    let contributorIndex:Int
    let appreciationCount:Int
    let cupNotes:[String]
    var contributorID:String {"preview-member-\(contributorIndex)"}
    static func entry(_ momentID:String)->Self? {entries.first{$0.momentID==momentID}}
    static var entries:[CollectionConversation] {CoffeeCollection.cloudConversations() ?? []}
}
extension TastingReply {
    static var collectionSamples:[TastingReply] {CollectionConversation.entries.flatMap {entry -> [TastingReply] in
        guard let post=CoffeeMoment.editorial.first(where:{$0.id==entry.momentID}) else{return []}
        return entry.cupNotes.enumerated().map {offset,note in
            TastingReply(id:"collection-\(entry.momentID)-reply-\(offset)",momentID:entry.momentID,text:note,createdAt:post.createdAt.addingTimeInterval(Double(offset+1)*420),authorID:"preview-member-\((entry.contributorIndex+offset+1)%8)")
        }
    }}
}
