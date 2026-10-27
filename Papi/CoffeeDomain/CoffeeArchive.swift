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
    // Each new checkout token can settle only one Apple transaction.
    var transactionID: String? = nil
}
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
    static var previews:[CoffeeMember] {portraits+CoffeeCollection.additionalPeople}
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
            let id="editorial-photo-\(index)"
            return CoffeeMoment(id:id,authorID:CollectionConversation.entry(id)?.contributorID ?? CoffeeMember.editorial.id,media:CoffeeArtwork.photoNames[index] ?? "emptyCup",caption:captions[index] ?? "A coffee moment from the Papi journal.",category:"Café journal",createdAt:Date(timeIntervalSince1970:1_790_000_000+Double(index)*3600))
        }
        let filmNotes:[Int:String] = [
            0:"A little ghost appears in the milk foam, one careful pour at a time.",
            1:"A steady milk stream opens into a rosetta in a dark cup.",
            2:"A portrait pause between café visits, from the Papi collection.",
            3:"A window-side journey, watching the afternoon pass outside.",
            4:"Espresso meets ice and milk in a clear glass.",
            5:"A bar-counter iced coffee, assembled from the first ice cube to the final stir.",
            6:"Two cups and a blue saucer frame a milk-pouring practice.",
            7:"Caramel trails line the glass before coffee and milk meet.",
            8:"A heart takes shape as the pitcher drops close to the surface.",
            9:"Orange peel joins the moka-pot ritual for a bright aromatic detail.",
            10:"An evening in the city, with company for the walk between stops.",
            11:"A tulip pattern builds from a few controlled milk pours.",
            12:"A city walk past familiar façades before the next coffee stop.",
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
            let id="editorial-video-\(index)"
            return CoffeeMoment(id:id,authorID:CollectionConversation.entry(id)?.contributorID ?? CoffeeMember.editorial.id,media:reference,isVideo:true,caption:caption,category:[2,3,10,12].contains(index) ? "Between cafés":"Coffee films",createdAt:Date(timeIntervalSince1970:1_790_000_000+Double(index)*3600))
        }
        return Array(photographs.prefix(4))+films+Array(photographs.dropFirst(4))
    }()
}

/// Fixed conversation samples for the supplied collection, never messages or relationship records.
struct CollectionConversation {
    let momentID:String
    let contributorIndex:Int
    let appreciationCount:Int
    let cupNotes:[String]
    var contributorID:String {CoffeeMember.portraits[contributorIndex].id}
    static func entry(_ momentID:String)->Self? {entries.first{$0.momentID==momentID}}
    static let entries:[CollectionConversation] = [
        .init(momentID:"editorial-photo-0",contributorIndex:0,appreciationCount:9,cupNotes:["That little cookie beside the cup is a lovely detail.","I'd pick the window seat for this one."]),
        .init(momentID:"editorial-photo-1",contributorIndex:4,appreciationCount:14,cupNotes:["Coffee first, then a slow breakfast. A good order of things."]),
        .init(momentID:"editorial-photo-2",contributorIndex:2,appreciationCount:6,cupNotes:["I like how the light comes through the americano."]),
        .init(momentID:"editorial-photo-3",contributorIndex:6,appreciationCount:17,cupNotes:["The canal reflection makes this feel so still.","Two cups and nowhere to rush."]),
        .init(momentID:"editorial-photo-4",contributorIndex:1,appreciationCount:8,cupNotes:["That croissant looks like it needs a second napkin."]),
        .init(momentID:"editorial-photo-5",contributorIndex:7,appreciationCount:12,cupNotes:["Round tables always seem to make a café feel friendlier."]),
        .init(momentID:"editorial-photo-6",contributorIndex:3,appreciationCount:5,cupNotes:["The pastry layers caught my eye before the foam did.","A little contrast between crisp and creamy."]),
        .init(momentID:"editorial-photo-7",contributorIndex:5,appreciationCount:11,cupNotes:["A cold brew for the walk home sounds right."]),
        .init(momentID:"editorial-photo-8",contributorIndex:0,appreciationCount:7,cupNotes:["I'd stay outside until that patch of sun moved."]),
        .init(momentID:"editorial-photo-9",contributorIndex:1,appreciationCount:16,cupNotes:["Everything within reach of the grinder. A tidy little setup.","The cups make the counter feel lived in."]),
        .init(momentID:"editorial-photo-10",contributorIndex:4,appreciationCount:4,cupNotes:["Just enough morning light for one quiet cup."]),
        .init(momentID:"editorial-photo-11",contributorIndex:5,appreciationCount:10,cupNotes:["Those iced lattes won't stay cold for long in that sun."]),
        .init(momentID:"editorial-photo-12",contributorIndex:7,appreciationCount:13,cupNotes:["I always pause before stirring the milk through.","The marble pattern changes with every pour."]),
        .init(momentID:"editorial-photo-13",contributorIndex:2,appreciationCount:6,cupNotes:["Breakfast in a courtyard feels like a small holiday."]),
        .init(momentID:"editorial-photo-14",contributorIndex:3,appreciationCount:15,cupNotes:["A cookie with a milk drink is a pairing I keep coming back to."]),
        .init(momentID:"editorial-photo-15",contributorIndex:6,appreciationCount:8,cupNotes:["That glass roof would make a rainy coffee break interesting too.","So many soft reflections in this corner."]),
        .init(momentID:"editorial-photo-16",contributorIndex:7,appreciationCount:12,cupNotes:["Dates bring their own sweetness to a small strong coffee."]),
        .init(momentID:"editorial-photo-17",contributorIndex:4,appreciationCount:5,cupNotes:["The rose chairs are a good reason to take the long way home."]),
        .init(momentID:"editorial-photo-30",contributorIndex:2,appreciationCount:9,cupNotes:["A quick street-side espresso, then back to the day.","Small cup, good pause."]),
        .init(momentID:"editorial-video-0",contributorIndex:0,appreciationCount:18,cupNotes:["The tiny ghost only appears at the very end.","That last pour takes a steady hand."]),
        .init(momentID:"editorial-video-1",contributorIndex:1,appreciationCount:11,cupNotes:["The rosetta opens so neatly when the pitcher comes closer."]),
        .init(momentID:"editorial-video-2",contributorIndex:4,appreciationCount:5,cupNotes:["A little pause before the next stop."]),
        .init(momentID:"editorial-video-3",contributorIndex:2,appreciationCount:8,cupNotes:["The view from a window can be part of the coffee break too."]),
        .init(momentID:"editorial-video-4",contributorIndex:5,appreciationCount:7,cupNotes:["I could watch espresso slipping between ice cubes for a while."]),
        .init(momentID:"editorial-video-5",contributorIndex:3,appreciationCount:13,cupNotes:["The ice goes in first and everything else follows.","I like seeing the whole glass come together."]),
        .init(momentID:"editorial-video-6",contributorIndex:6,appreciationCount:6,cupNotes:["That blue saucer makes the milk pour stand out."]),
        .init(momentID:"editorial-video-7",contributorIndex:4,appreciationCount:15,cupNotes:["The caramel trails stay visible until the first stir."]),
        .init(momentID:"editorial-video-8",contributorIndex:0,appreciationCount:19,cupNotes:["A small drop at the end gives the heart its point.","Getting the pitcher low seems to make all the difference."]),
        .init(momentID:"editorial-video-9",contributorIndex:2,appreciationCount:8,cupNotes:["Orange peel with a moka pot is an aroma combination I'd remember."]),
        .init(momentID:"editorial-video-10",contributorIndex:6,appreciationCount:4,cupNotes:["City evenings have their own pace."]),
        .init(momentID:"editorial-video-11",contributorIndex:1,appreciationCount:14,cupNotes:["One little layer at a time, then the tulip comes through."]),
        .init(momentID:"editorial-video-12",contributorIndex:3,appreciationCount:7,cupNotes:["I tend to notice the buildings on the way to a café."]),
        .init(momentID:"editorial-video-13",contributorIndex:3,appreciationCount:5,cupNotes:["That first espresso of the morning deserves a clean cup.","A short extraction, a long pause afterward."]),
        .init(momentID:"editorial-video-14",contributorIndex:4,appreciationCount:10,cupNotes:["The caramel disappears slowly around the spoon."]),
        .init(momentID:"editorial-video-15",contributorIndex:5,appreciationCount:16,cupNotes:["Citrus over ice makes this feel like an afternoon cup."]),
        .init(momentID:"editorial-video-16",contributorIndex:6,appreciationCount:12,cupNotes:["The rosetta fills almost the whole cappuccino.","The edges of the leaves stay so clear."]),
        .init(momentID:"editorial-video-17",contributorIndex:7,appreciationCount:6,cupNotes:["The spiral dessert catches a little coffee in every fold."]),
        .init(momentID:"editorial-video-18",contributorIndex:3,appreciationCount:17,cupNotes:["From grinder to cup is my favourite part of the routine."]),
        .init(momentID:"editorial-video-19",contributorIndex:5,appreciationCount:9,cupNotes:["The layers don't last long, but they're worth a look.","I'd stir this just before the first sip."]),
        .init(momentID:"editorial-video-20",contributorIndex:2,appreciationCount:7,cupNotes:["Pouring straight over ice makes the glass wake up."])
    ]
}
extension TastingReply {
    static let collectionSamples:[TastingReply] = CollectionConversation.entries.flatMap {entry -> [TastingReply] in
        guard let post=CoffeeMoment.editorial.first(where:{$0.id==entry.momentID}) else{return []}
        return entry.cupNotes.enumerated().map {offset,note in
            TastingReply(id:"collection-\(entry.momentID)-reply-\(offset)",momentID:entry.momentID,text:note,createdAt:post.createdAt.addingTimeInterval(Double(offset+1)*420),authorID:CoffeeMember.portraits[(entry.contributorIndex+offset+1)%CoffeeMember.portraits.count].id)
        }
    }
}
