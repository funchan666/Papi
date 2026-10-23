import SwiftUI
import UIKit

extension Color {
    static let coffee = Color(red:0.35,green:0.19,blue:0.14)
    static let cream = Color(red:0.992,green:0.969,blue:0.941)
    static let peach = Color(red:0.88,green:0.59,blue:0.48)
    static let butter = Color(red:1,green:0.91,blue:0.64)
    static let mutedCoffee = Color(red:0.47,green:0.36,blue:0.29)
}
struct PapiImage: View {
    var name: String
    var fit = false
    @State private var poster:UIImage?
    @State private var posterName:String?
    var body: some View {
        Group {
        if let image = CoffeeMedia.image(name) ?? (posterName==name ? poster:nil) {
            Image(uiImage:image).resizable().aspectRatio(contentMode:fit ? .fit : .fill)
        } else {
            Image("emptyCup").resizable().scaledToFit().padding(24).background(Color.cream)
        }
        }.task(id:name) {
            let source=name
            let result=await CoffeeMedia.preparePoster(source)
            guard !Task.isCancelled else{return}
            posterName=source;poster=result
        }
    }
}
struct PapiBackground: View {
    var asset = "pageBackground"
    var body: some View {
        GeometryReader { proxy in
            if asset == "welcomeBackground" || asset.hasPrefix("onboarding") {
                Color.cream
                Image(asset).resizable().scaledToFit().frame(width:proxy.size.width,height:proxy.size.height)
            } else {
                Image(asset).resizable().scaledToFill().frame(width:proxy.size.width,height:proxy.size.height).clipped()
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct PapiButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var light = false
    var wide = false
    var cornerRadius:CGFloat = 26
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(CoffeeType.face(.body,weight:.semibold))
            .foregroundStyle(light ? Color.coffee : .white)
            .padding(.horizontal,22).padding(.vertical,14).frame(maxWidth:wide ? .infinity:nil,minHeight:48)
            .background(light ? Color.butter : Color.coffee,in:RoundedRectangle(cornerRadius:cornerRadius))
            .opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.72 : 1))
    }
}
struct PapiIconButton: View {
    @Environment(\.layoutDirection) private var direction
    var asset: String
    var label: String
    var size: CGFloat = 27
    var action: () -> Void
    var body: some View {
        Button(action:action) { Image(asset).resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft && asset == "back" ? -1:1,y:1).frame(width:size,height:size).frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
            .buttonStyle(.plain).papiAccessibilityLabel(label).papiAvoidReserved()
    }
}
struct Avatar: View {
    var name: String
    var size: CGFloat = 48
    var body: some View {
        PapiImage(name:name).frame(width:size,height:size).clipShape(Circle())
            .overlay(Circle().stroke(Color.cream,lineWidth:1.5))
    }
}
struct PapiHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var back = true
    var titleAction:(()->Void)?
    @ViewBuilder var trailing: () -> Trailing
    init(_ title: String, back: Bool = true, titleAction:(()->Void)?=nil, @ViewBuilder trailing:@escaping ()->Trailing) { self.title=title;self.back=back;self.titleAction=titleAction;self.trailing=trailing }
    var body: some View {
        HStack(spacing:8) {
            if back { PapiIconButton(asset:"back",label:"Back") { dismiss() } }
            else { EmptyView() }
            Group {
                if let titleAction {PapiTextButton(title,action:titleAction)} else {PapiText(title)}
            }.font(CoffeeType.face(.headline)).frame(maxWidth:.infinity).multilineTextAlignment(.center)
            trailing().frame(minWidth:44,minHeight:44)
        }.foregroundStyle(Color.coffee).padding(.horizontal,8).padding(.vertical,4)
    }
}
extension PapiHeader where Trailing == EmptyView {
    init(_ title:String,back:Bool=true) { self.init(title,back:back) { EmptyView() } }
}
struct PapiEmpty: View {
    var title: String
    var detail: String = ""
    var body: some View {
        VStack(spacing:14) {
            Image("emptyCup").resizable().scaledToFit().frame(width:76,height:76)
            PapiText(title).font(CoffeeType.face(.headline)).foregroundStyle(Color.coffee)
            if !detail.isEmpty { PapiText(detail).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center).frame(maxWidth:340) }
        }.padding(30).frame(maxWidth:.infinity).frame(minHeight:220)
    }
}
struct PreviewLabel: View {
    var text = "Coffee portrait"
    var body: some View { PapiText(text).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).padding(.horizontal,10).padding(.vertical,5).background(Color.cream.opacity(0.9),in:Capsule()) }
}
struct CoinLabel: View {
    var value: Int
    var body: some View { HStack(spacing:5) { Image("coin").resizable().scaledToFit().frame(width:23,height:23);Text(value,format:.number).fontWeight(.semibold).monospacedDigit() } }
}
struct PapiPanel<Content:View>:View {
    @ViewBuilder var content:()->Content
    var body:some View { content().padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:20)) }
}
struct PapiRow: View {
    @Environment(\.layoutDirection) private var direction
    var asset: String?
    var title: String
    var subtitle: String? = nil
    var action: ()->Void
    var body: some View {
        Button(action:action) {
            HStack(spacing:14) {
                if let asset { Image(asset).resizable().scaledToFit().frame(width:25,height:25) }
                VStack(alignment:.leading,spacing:4) { PapiText(title).font(CoffeeType.face(.body));if let subtitle {PapiText(subtitle).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)} }
                Spacer(minLength:8)
                Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12)
            }.padding(.vertical,16).padding(.horizontal,14).frame(minHeight:58).foregroundStyle(Color.coffee).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
struct PapiTextField: View {
    var prompt: String
    @Binding var text: String
    var body:some View {
        PapiInput(prompt,text:$text,axis:.vertical).lineLimit(1...5).padding(15).background(Color.white,in:RoundedRectangle(cornerRadius:15)).foregroundStyle(Color.coffee)
    }
}
struct PapiDialog: View {
    var title: String
    var message: String
    var confirm = "OK"
    var cancel: String? = nil
    var action: ()->Void
    var dismiss: ()->Void
    @Environment(\.papiRegions) private var regions
    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in:.named("PapiContainer")).origin
            let localRegions = regions.map {$0.offsetBy(dx:-origin.x,dy:-origin.y)}
            let rect = PapiRegionGeometry.largestArea(in:CGRect(origin:.zero,size:proxy.size),excluding:localRegions)
            ZStack {
                Color.black.opacity(0.48).ignoresSafeArea().onTapGesture {}
                ScrollView {
                    VStack(spacing:20) {
                        PapiText(title).font(CoffeeType.face(.title3,weight:.bold)).multilineTextAlignment(.center)
                        PapiText(message).font(CoffeeType.face(.body)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        PapiTextButton(confirm,action:action).buttonStyle(PapiButtonStyle()).frame(maxWidth:.infinity)
                        if let cancel { PapiTextButton(cancel,action:dismiss).buttonStyle(PapiButtonStyle(light:true)) }
                    }.padding(30).frame(maxWidth:350)
                        .background { Image("dialogBackground").resizable() }
                }.frame(width:min(360,max(44,rect.width-24)),height:min(460,max(44,rect.height-24)))
                    .position(x:rect.midX,y:rect.midY)
            }.foregroundStyle(Color.coffee)
        }.accessibilityAddTraits(.isModal)
    }
}
struct PapiScreen<Content:View>: View {
    var background = "pageBackground"
    @ViewBuilder var content:()->Content
    var body:some View {
        // Only foreground content receives container margins; artwork extends to every screen edge.
        content().frame(maxWidth:.infinity,maxHeight:.infinity)
            .papiContainerMargins()
            .background {PapiBackground(asset:background)}
            .foregroundStyle(Color.coffee).toolbar(.hidden,for:.navigationBar)
            .background(SwipeBackBridge())
    }
}
