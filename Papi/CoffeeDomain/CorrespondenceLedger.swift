import Foundation

enum SafetyKind:String,Codable {case user,post,comment,message,room}
struct SafetyTarget:Hashable,Identifiable,Codable {
    var kind:SafetyKind
    var contentReference:String
    var authorID:String?
    var id:String {kind.rawValue+":"+contentReference}
    static func user(_ id:String)->Self {.init(kind:.user,contentReference:id,authorID:id)}
    static func post(_ value:CoffeeMoment)->Self {.init(kind:.post,contentReference:value.id,authorID:value.authorID)}
    static func comment(_ value:TastingReply,owner:String)->Self {.init(kind:.comment,contentReference:value.id,authorID:value.authorID ?? owner)}
    static func legacy(_ key:String)->Self? {
        let parts=key.split(separator:":",maxSplits:1).map(String.init)
        guard parts.count==2,let kind=SafetyKind(rawValue:parts[0]=="person" ? "user":parts[0]) else{return nil}
        return .init(kind:kind,contentReference:parts[1],authorID:kind == .user ? parts[1]:nil)
    }
    enum CodingKeys:String,CodingKey {
        case kind = "kind"
        case contentReference = "subjectID"
        case authorID = "authorID"
    }
}
enum ModerationStatus:String,Codable {case awaitingSubmission,pendingReview,approved,rejected}
struct FollowingConsent:Codable {
    var correspondentID:String
    var passportID:UUID
    var followsCurrentGuest:Bool
    var friendshipAccepted:Bool
    // Only a real authenticated service acknowledgement may populate this record.
    var confirmationID:String
    enum CodingKeys:String,CodingKey {
        case correspondentID = "peerID"
        case passportID = "currentGuestID"
        case followsCurrentGuest = "followsCurrentGuest"
        case friendshipAccepted = "friendshipAccepted"
        case confirmationID = "confirmationID"
    }
}
struct CoffeeIntroduction:Codable {
    var correspondentID:String
    var requestedAt=Date()
    var acknowledgementID:String? // nil means saved locally, not delivered or accepted.
    enum CodingKeys:String,CodingKey {
        case correspondentID = "peerID"
        case requestedAt = "requestedAt"
        case acknowledgementID = "acknowledgementID"
    }
}
struct CoffeeLetter:Codable,Identifiable {
    enum Kind:String,Codable {case text,photo,voice}
    enum Delivery:String,Codable {case waitingForConnection,sent,received}
    var id=UUID().uuidString
    var correspondentID:String
    var authorID:String
    var kind:Kind
    var value:String
    var createdAt=Date()
    var delivery:Delivery = .waitingForConnection
    enum CodingKeys:String,CodingKey {
        case id = "id"
        case correspondentID = "peerID"
        case authorID = "authorID"
        case kind = "kind"
        case value = "value"
        case createdAt = "createdAt"
        case delivery = "delivery"
    }
}
struct CorrespondenceLedger:Codable {
    var hiddenTargets:Set<String> = []
    var relationships:[String:FollowingConsent] = [:]
    var friendshipRequests:[String:CoffeeIntroduction] = [:]
    var messages:[CoffeeLetter] = []
    var rememberedPeople:[String:CoffeeMember] = [:]
}
enum AccountTransition:String {case logout,delete}
