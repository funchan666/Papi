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
struct CoffeeCollectible: Identifiable, Hashable {
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
}
enum CoffeeEconomy {
    static let welcomeCoins = 800
    static func postCost(isVideo: Bool) -> Int { isVideo ? 80 : 40 }
}
struct CoffeePassport: Codable {
    var id = UUID()
    var name = "My coffee corner"
    var bio = "Keeping the cups I want to brew again."
    var avatar = "brandMark"
    var cover = "corner-latte"
    var photos: [String] = []
}
struct MomentDraft: Codable {
    var text = ""
    var media: String? = nil
    var isVideo = false
}
struct CoffeeArchive: Codable {
    var version = 1
    var passport = CoffeePassport()
    var signedIn = false
    var sawOnboarding = false
    var acceptedPolicyVersion: String? = nil
    var language = PapiStrings.preferredLanguage
    var notificationPreference = false
    var followedMembers: Set<String> = []
    var blockedMembers: Set<String> = []
    var appreciatedMoments: Set<String> = []
    var keptMoments: Set<String> = []
    var ownMoments: [CoffeeMoment] = []
    var tastingReplies: [TastingReply] = []
    var communityReports: [CommunityReport] = []
    var momentDraft = MomentDraft()
    var letterDrafts: [String: String] = [:]
    var letterPhotos: [String: String] = [:]
    var letterVoiceNotes: [String: String] = [:]
    var tableNotes: [String: String] = [:]
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
        case signedIn = "signedIn"
        case sawOnboarding = "sawOnboarding"
        case acceptedPolicyVersion = "acceptedPolicyVersion"
        case language = "language"
        case notificationPreference = "notificationPreference"
        case followedMembers = "follows"
        case blockedMembers = "blocked"
        case appreciatedMoments = "likes"
        case keptMoments = "bookmarks"
        case ownMoments = "localPosts"
        case tastingReplies = "comments"
        case communityReports = "reports"
        case momentDraft = "postDraft"
        case letterDrafts = "chatDrafts"
        case letterPhotos = "chatAttachments"
        case letterVoiceNotes = "voiceDrafts"
        case tableNotes = "roomDrafts"
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
}

extension CoffeeMember {
    static let portraits:[CoffeeMember] = (0..<8).map {index in
        let names=["Clara Voss","Jun Park","Kai Moreno","Theo Ellis","Elise Reed","Mateo Silva","Ren Aoki","Dae Han"]
        let notes=["A portrait for those who take the window seat and leave time for a pour-over.","A coffee portrait inspired by ceramic drippers and tidy brewing notes.","A portrait for a thermos, a trail and a cup worth stopping for.","A coffee portrait inspired by dark chocolate notes and short espresso breaks.","A portrait for unhurried café reading and a second cup.","A coffee portrait inspired by bright iced brews after a morning outside.","A portrait for small roasteries, new beans and handwritten recipes.","A coffee portrait inspired by quiet counters and the first cup of the day."]
        return .init(id:"preview-member-\(index)",name:names[index],portrait:CoffeeArtwork.portraits[index],bio:notes[index])
    }
    // Legacy identifiers remain stable for existing follows, blocks and reports.
    static var previews:[CoffeeMember] {portraits}
    static let editorial=CoffeeMember(id:"papi-editorial",name:"The Papi coffee desk",portrait:"brandMark",bio:"Coffee scenes, brewing details and small rituals selected for the Papi journal.")
    static func find(_ id:String)->CoffeeMember? {id==editorial.id ? editorial:portraits.first{$0.id==id}}
    var handle:String {
        if id==Self.editorial.id {return "papi.coffee.desk"}
        let handles=["clara.pourover","jun.ceramics","kai.trailcoffee","theo.espresso","elise.readsandbrews","mateo.icedcoffee","ren.roastnotes","dae.firstcup"]
        if let index=Self.portraits.firstIndex(where:{$0.id==id}) {return handles[index]}
        return "coffee.reader"
    }
}
extension CoffeeCollectible {
    static let all: [CoffeeCollectible] = [
        .init(id: "love", name: "Sending love", asset: "giftLove", cost: 80),
        .init(id: "peach", name: "Peach", asset: "giftPeach", cost: 120),
        .init(id: "umbrella", name: "Sweet brew", asset: "giftUmbrella", cost: 180),
        .init(id: "cake", name: "Three wishes", asset: "giftCake", cost: 260),
        .init(id: "bird", name: "Little bird", asset: "giftBird", cost: 360),
        .init(id: "headphones", name: "Coffee beats", asset: "giftHeadphones", cost: 520),
        .init(id: "car", name: "Dream ride", asset: "giftCar", cost: 900),
        .init(id: "crown", name: "Café royalty", asset: "giftCrown", cost: 1400)
    ]
}
extension CoffeeTable {
    static let previews: [CoffeeTable] = [
        .init(id: "room-chat", title: "Slow mornings", category: "Coffee rituals", image: "garden-coffee-seat", hostMemberID: "preview-member-0"),
        .init(id: "room-learn", title: "The brewing table", category: "Brew notes", image: "home-espresso-corner", hostMemberID: "preview-member-1"),
        .init(id: "room-match", title: "Recipes over coffee", category: "Pour over", image: "croissant-table", hostMemberID: "preview-member-2"),
        .init(id: "room-vibe", title: "Evening espresso", category: "Roast notes", image: "coffee-and-dates", hostMemberID: "preview-member-3"),
        .init(id: "room-breeze", title: "Window seat", category: "Café reading", image: "courtyard-brunch", hostMemberID: "preview-member-4"),
        .init(id: "room-dream", title: "Coffee daydreams", category: "Slow coffee", image: "corner-latte", hostMemberID: "preview-member-5")
    ]
}
extension CoffeeMoment {
    static let editorial:[CoffeeMoment] = {
        let captions: [Int:String] = [
            0:"A window-side latte, with room to set the cup down and stay awhile.",
            1:"Coffee and a pastry on a breakfast tray: a reason to slow the morning.",
            2:"An americano catches the light at a quiet window table.",
            3:"Two cups on a canal-side table, with the afternoon reflected in the water.",
            4:"A croissant and a small latte share the same patch of morning light.",
            5:"A round café table keeps the cups close and the conversation easy.",
            6:"Pastry layers and latte foam: a small study in texture.",
            7:"Cold brew in hand, ready for the walk between one place and the next.",
            8:"A café garden seat makes an ordinary coffee break feel a little longer.",
            9:"An espresso corner keeps grinder, brewer and favourite cups within reach.",
            10:"The sun reaches the cup before the first sip.",
            11:"Two iced coffees on a wooden table, slowly losing their frost.",
            12:"Milk meets coffee in soft marbled layers beside a warm cup.",
            13:"A courtyard table brings breakfast out into the open air.",
            14:"A cookie, a milk drink and a little pause at the table.",
            15:"Light through the glass roof falls across an afternoon café.",
            16:"Coffee and dates: a simple pairing to taste slowly.",
            17:"Rose-coloured chairs gather outside a café terrace as the light fades.",
            30:"A street-side espresso, carried into the rest of the day."
        ]
        let photographs=(Array(0..<18)+[30]).map {index in
            CoffeeMoment(id:"editorial-photo-\(index)",authorID:"papi-editorial",media:CoffeeArtwork.photoNames[index] ?? "emptyCup",caption:captions[index] ?? "A coffee moment from the Papi journal.",category:"Café journal",createdAt:Date(timeIntervalSince1970:1_790_000_000+Double(index)*3600))
        }
        let filmNotes:[Int:String] = [
            0:"A little ghost appears in the milk foam, one careful pour at a time.",
            1:"A steady milk stream opens into a rosetta in a dark cup.",
            4:"Espresso meets ice and milk in a clear glass.",
            5:"A bar-counter iced coffee, assembled from the first ice cube to the final stir.",
            6:"Two cups and a blue saucer frame a milk-pouring practice.",
            7:"Caramel trails line the glass before coffee and milk meet.",
            8:"A heart takes shape as the pitcher drops close to the surface.",
            9:"Orange peel joins the moka-pot ritual for a bright aromatic detail.",
            11:"A tulip pattern builds from a few controlled milk pours.",
            13:"An empty cup becomes the first espresso of the morning.",
            14:"A spoon carries caramel through an iced latte.",
            15:"A citrus iced coffee comes together over a glass of ice.",
            16:"A rosetta unfolds on the surface of a cappuccino.",
            17:"A spiral dessert meets a slow ribbon of coffee.",
            18:"From freshly ground beans to a short espresso extraction.",
            19:"Coffee, ice and milk turn into a small layered ritual.",
            20:"Fresh coffee falls over ice before the milk is stirred in.",
        ]
        let films=CoffeeArtwork.filmNames.keys.sorted().compactMap {index -> CoffeeMoment? in
            guard let reference=CoffeeArtwork.filmNames[index],let caption=filmNotes[index] else{return nil}
            return CoffeeMoment(id:"editorial-video-\(index)",authorID:"papi-editorial",media:reference,isVideo:true,caption:caption,category:"Coffee films",createdAt:Date(timeIntervalSince1970:1_790_000_000+Double(index)*3600))
        }
        return Array(photographs.prefix(4))+films+Array(photographs.dropFirst(4))
    }()
}
