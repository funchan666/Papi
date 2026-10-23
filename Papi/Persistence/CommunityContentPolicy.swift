import Foundation

/// A narrow pre-publication text screen. It complements the private review queue;
/// it cannot certify user images, video or future server-side moderation.
enum CommunityContentPolicy {
    private static let prohibitedSolicitations = [
        #"\b(?:buy|sell|selling)\s+(?:sex|nudes)\b"#,
        #"\b(?:child|underage)\s+(?:porn|nudes)\b"#,
        #"\b(?:kill|rape)\s+(?:you|them)\b"#,
        #"\b(?:escort service|sexual services|sex trafficking)\b"#,
        #"(?:出售裸照|未成年色情|性交易|杀了你|卖淫)"#,
        #"(?:venta de sexo|pornografía infantil|te voy a matar)"#,
        #"(?:ขายบริการทางเพศ|สื่อลามกเด็ก)"#,
        #"(?:بيع خدمات جنسية|استغلال الأطفال جنسيا)"#,
        #"(?:mua bán dâm|khiêu dâm trẻ em|tao sẽ giết mày)"#,
        #"(?:성매매 알선|아동 음란물|죽여버리겠다)"#
    ]
    static func permits(_ text:String)->Bool {
        let normalised=text.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of:"\u{200B}",with:"").replacingOccurrences(of:"\u{200D}",with:"")
            .folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
        return !prohibitedSolicitations.contains {pattern in
            let folded=pattern.folding(options:[.caseInsensitive,.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en_US_POSIX"))
            return normalised.range(of:folded,options:.regularExpression) != nil
        }
    }
}
@MainActor extension CoffeeHouse {
    func validateCommunityText(_ text:String)->Bool {
        guard CommunityContentPolicy.permits(text) else {
            inform("Keep the coffee table welcoming","Please revise wording that offers sexual services, exploits minors or threatens someone. Your draft is still here.")
            return false
        }
        return true
    }
}
