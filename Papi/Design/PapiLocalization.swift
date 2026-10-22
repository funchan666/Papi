import SwiftUI

extension PapiStore {
    func text(_ key:String)->String {PapiStrings.text(key,language:state.language)}
}
enum PapiStrings {
    static let languages:[(id:String,name:String)]=[("en","English"),("es","Español"),("th","ภาษาไทย"),("ar","العربية"),("vi","Tiếng Việt"),("ko","한국어")]
    static var preferredLanguage:String {
        Locale.preferredLanguages.map{String($0.prefix(2))}.first{code in languages.contains{$0.id==code}} ?? "en"
    }
    private static let entries:[String:[String:String]] = {
        guard let url=Bundle.main.url(forResource:"PapiTranslations",withExtension:"json",subdirectory:"Localization"),
              let data=try? Data(contentsOf:url),let values=try? JSONDecoder().decode([String:[String:String]].self,from:data) else{return [:]}
        return values
    }()
    private struct Pattern {
        let key:String
        let expression:NSRegularExpression
        let count:Int
    }
    private static let patterns:[Pattern] = entries.keys.filter{$0.contains("{0}")}.sorted{$0.count>$1.count}.compactMap {key in
        var expression=NSRegularExpression.escapedPattern(for:key)
        var count=0
        while key.contains("{\(count)}") {
            expression=expression.replacingOccurrences(of:NSRegularExpression.escapedPattern(for:"{\(count)}"),with:"(.+?)")
            count+=1
        }
        guard let regex=try? NSRegularExpression(pattern:"^"+expression+"$") else{return nil}
        return Pattern(key:key,expression:regex,count:count)
    }
    static func text(_ key:String,language:String)->String {
        let language=String(language.prefix(2))
        guard language != "en" else{return key}
        if let translation=entries[key]?[language] {return translation}
        for pattern in patterns {
            guard let match=pattern.expression.firstMatch(in:key,range:NSRange(key.startIndex...,in:key)),
                  var translation=entries[pattern.key]?[language] else{continue}
            for index in 0..<pattern.count {
                guard let range=Range(match.range(at:index+1),in:key) else{continue}
                let value=String(key[range])
                translation=translation.replacingOccurrences(of:"{\(index)}",with:entries[value]?[language] ?? value)
            }
            return translation
        }
        return key
    }
}
/// Localizes application copy at render time; user-authored text opts into verbatim.
struct PapiText:View {
    @Environment(\.locale) private var locale
    private let value:String
    private let translates:Bool
    init(_ value:String) {self.value=value;translates=true}
    init(verbatim value:String) {self.value=value;translates=false}
    var body:some View {Text(verbatim:translates ? PapiStrings.text(value,language:locale.identifier):value)}
}
struct PapiTextButton:View {
    @Environment(\.locale) private var locale
    private let title:String
    private let action:()->Void
    init(_ title:String,action:@escaping ()->Void) {self.title=title;self.action=action}
    var body:some View {Button(action:action){Text(verbatim:PapiStrings.text(title,language:locale.identifier))}}
}
struct PapiInput:View {
    @Environment(\.locale) private var locale
    private let prompt:String
    @Binding private var text:String
    private let axis:Axis
    init(_ prompt:String,text:Binding<String>,axis:Axis = .horizontal) {self.prompt=prompt;self._text=text;self.axis=axis}
    var body:some View {TextField(PapiStrings.text(prompt,language:locale.identifier),text:$text,axis:axis)}
}
private struct PapiAccessibleLabel:ViewModifier {
    @Environment(\.locale) private var locale
    let value:String
    func body(content:Content)->some View {content.accessibilityLabel(Text(verbatim:PapiStrings.text(value,language:locale.identifier)))}
}
extension View {
    func papiAccessibilityLabel(_ value:String)->some View {modifier(PapiAccessibleLabel(value:value))}
}
