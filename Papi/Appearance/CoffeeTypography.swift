import SwiftUI

/// Two bundled OFL families; unsupported scripts use the platform's installed glyph fallback.
/// Custom fonts scale with Dynamic Type and never make a network request.
enum CoffeeType {
    private static func pointSize(_ style:Font.TextStyle)->CGFloat {
        switch style {
        case .largeTitle:return 34
        case .title:return 28
        case .title2:return 22
        case .title3:return 20
        case .headline,.body:return 17
        case .callout:return 16
        case .subheadline:return 15
        case .footnote:return 13
        case .caption:return 12
        case .caption2:return 11
        @unknown default:return 17
        }
    }
    static func face(_ style:Font.TextStyle,weight:Font.Weight = .regular)->Font {
        let resolved=style == .headline && weight == .regular ? Font.Weight.semibold:weight
        let suffix=resolved == .bold || resolved == .heavy || resolved == .black ? "Bold":(resolved == .semibold || resolved == .medium ? "SemiBold":"Regular")
        return .custom("PapiCounter-"+suffix,size:pointSize(style),relativeTo:style)
    }
    static func display(_ style:Font.TextStyle,weight:Font.Weight = .regular,italic:Bool=false)->Font {
        display(size:pointSize(style),weight:weight,italic:italic,relativeTo:style)
    }
    static func display(size:CGFloat,weight:Font.Weight = .regular,italic:Bool=false,relativeTo:Font.TextStyle = .title)->Font {
        let suffix=italic ? "Italic":(weight == .regular ? "Regular":"SemiBold")
        return .custom("PapiEditorial-"+suffix,size:size,relativeTo:relativeTo)
    }
    static func counter(size:CGFloat,weight:Font.Weight = .regular)->Font {
        let suffix=weight == .regular ? "Regular":(weight == .medium || weight == .semibold ? "SemiBold":"Bold")
        return .custom("PapiCounter-"+suffix,size:size,relativeTo:.body)
    }
}
