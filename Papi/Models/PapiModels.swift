import Foundation

struct Person: Identifiable, Hashable {
    let id: String
    let name: String
    let portrait: String
    let bio: String
}
struct CoffeePost: Identifiable, Codable, Hashable {
    var id: String
    var authorID: String
    var media: String
    var isVideo: Bool = false
    var caption: String
    var category: String
    var createdAt: Date = Date()
    var isLocal: Bool = false
}
struct LocalComment: Identifiable, Codable {
    var id = UUID().uuidString
    var postID: String
    var text: String
    var createdAt = Date()
}
struct ReportDraft: Identifiable, Codable {
    var id = UUID().uuidString
    var subjectID: String
    var reason: String
    var createdAt = Date()
}
struct Gift: Identifiable, Hashable {
    let id: String
    let name: String
    let asset: String
    let cost: Int
}
struct Room: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let image: String
    let hostID: String
}
struct LocalGiftEvent: Identifiable, Codable {
    var id = UUID().uuidString
    var giftID: String
    var quantity: Int
    var context: String
    var createdAt = Date()
}
struct WalletEntry: Identifiable, Codable {
    var id: String
    var delta: Int
    var reason: String
    var createdAt = Date()
}
struct LocalProfile: Codable {
    var id = UUID()
    var name = "Coffee friend"
    var bio = "All good things start with coffee."
    var avatar = "brandMark"
    var cover = "coffee00"
    var photos: [String] = []
}
struct JournalDraft: Codable {
    var text = ""
    var media: String? = nil
    var isVideo = false
}
struct GuestState: Codable {
    var version = 1
    var profile = LocalProfile()
    var signedIn = false
    var sawOnboarding = false
    var acceptedPolicyVersion: String? = nil
    var language = PapiStrings.preferredLanguage
    var notificationPreference = false
    var follows: Set<String> = []
    var blocked: Set<String> = []
    var likes: Set<String> = []
    var bookmarks: Set<String> = []
    var localPosts: [CoffeePost] = []
    var comments: [LocalComment] = []
    var reports: [ReportDraft] = []
    var postDraft = JournalDraft()
    var chatDrafts: [String: String] = [:]
    var chatAttachments: [String: String] = [:]
    var voiceDrafts: [String: String] = [:]
    var roomDrafts: [String: String] = [:]
    var recentRooms: [String] = []
    var coins = 0
    var inventory: [String: Int] = [:]
    var displayedGift: String? = nil
    var giftHistory: [LocalGiftEvent] = []
    var checkinDays: Set<String> = []
    var experience = 0
    var wallet: [WalletEntry] = []
    var creditedTransactions: Set<String> = []
    var revokedTransactions: Set<String> = []
    var purchaseIntents: [String: UUID] = [:]
    // Ownership tombstones survive account deletion. They never grant the new guest ownership.
    var retiredGuestIDs: Set<UUID> = []
    var historicalTransactionIDs: Set<String> = []
    var pendingMediaDeletion: Set<UUID> = []
}

extension Person {
    static let previews: [Person] = (0..<8).map { i in
        Person(id: "preview-member-\(i)", name: ["Mia","Luna","Avery","Sam","Alex","Noah","Quinn","Charlie"][i],
               portrait: String(format:"person%02d",i), bio: "Coffee, conversation, and a slower kind of day.")
    }
    static func find(_ id: String) -> Person? { previews.first { $0.id == id } }
}
extension Gift {
    static let all: [Gift] = [
        .init(id: "love", name: "Sending love", asset: "giftLove", cost: 50),
        .init(id: "peach", name: "Peach", asset: "giftPeach", cost: 50),
        .init(id: "umbrella", name: "Sweet brew", asset: "giftUmbrella", cost: 50),
        .init(id: "cake", name: "Three wishes", asset: "giftCake", cost: 50),
        .init(id: "bird", name: "Little bird", asset: "giftBird", cost: 100),
        .init(id: "headphones", name: "Coffee beats", asset: "giftHeadphones", cost: 100),
        .init(id: "car", name: "Dream ride", asset: "giftCar", cost: 100),
        .init(id: "crown", name: "Café royalty", asset: "giftCrown", cost: 100)
    ]
}
extension Room {
    static let previews: [Room] = [
        .init(id: "room-chat", title: "Slow mornings", category: "Chat", image: "coffee08", hostID: "preview-member-0"),
        .init(id: "room-learn", title: "The brewing table", category: "Learn", image: "coffee09", hostID: "preview-member-1"),
        .init(id: "room-match", title: "Meet over coffee", category: "Match", image: "coffee04", hostID: "preview-member-2"),
        .init(id: "room-vibe", title: "Evening espresso", category: "Vibe", image: "coffee16", hostID: "preview-member-3"),
        .init(id: "room-breeze", title: "Window seat", category: "Breeze", image: "coffee13", hostID: "preview-member-4"),
        .init(id: "room-dream", title: "Coffee daydreams", category: "Dream", image: "coffee00", hostID: "preview-member-5")
    ]
}
extension CoffeePost {
    static let editorial: [CoffeePost] = {
        let captions = ["A little pause, a perfect pour.", "A table for two, and time to stay.", "Small rituals make a beautiful morning.", "The window seat is always my favorite.", "A warm cup and a fresh beginning.", "Making time for the good things."]
        let images = Array(0..<18) + [30]
        let photos = images.enumerated().map { offset, index in
            CoffeePost(id: "editorial-photo-\(index)", authorID: "papi-editorial", media: String(format:"coffee%02d",index),
                       caption: captions[offset % captions.count], category: ["Pour Over", "Latte Art", "Café Life"][offset % 3], createdAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(offset)*3600))
        }
        let videos = (0..<21).map { i in
            CoffeePost(id: "editorial-video-\(i)", authorID: "papi-editorial", media: String(format:"coffeeVideo%02d",i), isVideo: true,
                       caption: "A moment from the supplied collection.", category: "Community films", createdAt: Date(timeIntervalSince1970:1_790_000_000 + Double(i)*3600))
        }
        return Array(photos.prefix(4)) + videos + Array(photos.dropFirst(4))
    }()
}
