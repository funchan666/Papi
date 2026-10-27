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
    var fallback:String? = nil
    @State private var poster:UIImage?
    @State private var posterName:String?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        GeometryReader {proxy in
            Group {
                if let image = CoffeeMedia.image(name) ?? (posterName==name ? poster:nil) {
                    Image(uiImage:image).resizable().aspectRatio(contentMode:fit ? .fit : .fill)
                        .frame(width:proxy.size.width,height:proxy.size.height).clipped()
                } else if let fallback {
                    Image(fallback).resizable().scaledToFill()
                        .frame(width:proxy.size.width,height:proxy.size.height).clipped()
                } else {
                    Image("emptyCup").resizable().scaledToFit().padding(8)
                        .frame(width:proxy.size.width,height:proxy.size.height).background(Color.cream)
                }
            }
        }.task(id:name+(scenePhase == .active ? "|active":"|inactive")) {
            guard scenePhase == .active else{return}
            let source=name
            if posterName != source {poster=nil;posterName=nil}
            let result=await CoffeeMedia.preparePoster(source)
            guard !Task.isCancelled else{return}
            posterName=source;poster=result
        }
    }
}
struct PapiArtworkFill:View {
    var asset:String
    var body: some View {
        GeometryReader { proxy in
            Image(asset).resizable().scaledToFill()
                .frame(width:proxy.size.width,height:proxy.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct PapiArtworkFit:View {
    var asset:String
    var body:some View {
        GeometryReader {proxy in
            Image(asset).resizable().scaledToFit()
                .frame(width:proxy.size.width,height:proxy.size.height)
        }.accessibilityHidden(true)
    }
}
struct PapiBackground: View {
    var asset = "pageBackground"
    var body:some View {PapiArtworkFill(asset:asset).ignoresSafeArea()}
}
struct PapiButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var light = false
    var wide = false
    var cornerRadius:CGFloat = 26
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(CoffeeType.face(.body,weight:.semibold))
            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
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
    @Environment(\.papiBounds) private var bounds
    @ScaledMetric(relativeTo:.headline) private var titleLineHeight:CGFloat=24
    var title: String
    var back = true
    var backAction:(()->Void)?
    var titleAction:(()->Void)?
    @ViewBuilder var trailing: () -> Trailing
    init(_ title: String, back: Bool = true, backAction:(()->Void)?=nil, titleAction:(()->Void)?=nil, @ViewBuilder trailing:@escaping ()->Trailing) { self.title=title;self.back=back;self.backAction=backAction;self.titleAction=titleAction;self.trailing=trailing }
    var body: some View {
        PapiCenteredHeaderLayout {
            ZStack(alignment:.leading) {
                Color.clear.frame(width:44,height:44).accessibilityHidden(true)
                if back {PapiIconButton(asset:"back",label:"Back") {if let backAction {backAction()} else {dismiss()}}}
            }.fixedSize(horizontal:true,vertical:false)
            Group {
                if let titleAction {PapiTextButton(title,action:titleAction)} else {PapiText(title)}
            }.font(CoffeeType.face(.headline)).lineLimit(bounds.height>0 && bounds.height<titleLineHeight*6 ? 1:2).fixedSize(horizontal:false,vertical:true)
                .frame(maxWidth:.infinity).multilineTextAlignment(.center)
            ZStack(alignment:.trailing) {
                Color.clear.frame(width:44,height:44).accessibilityHidden(true)
                trailing()
            }.fixedSize(horizontal:true,vertical:false)
        }.foregroundStyle(Color.coffee).padding(.horizontal,8).padding(.vertical,4).papiAvoidReserved()
    }
}
private struct PapiCenteredHeaderLayout:Layout {
    private func measure(_ width:CGFloat,_ subviews:Subviews)->(CGSize,CGSize,CGSize,Bool) {
        let leading=subviews[0].sizeThatFits(.unspecified)
        let trailing=subviews[2].sizeThatFits(.unspecified)
        let side=max(leading.width,trailing.width)
        let stacked=width<side*2+60
        let titleWidth=stacked ? width:max(0,width-side*2-16)
        let title=subviews[1].sizeThatFits(ProposedViewSize(width:titleWidth,height:nil))
        return (leading,title,trailing,stacked)
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        guard subviews.count==3 else{return .zero}
        let ideal=subviews.reduce(CGFloat(16)) {$0+$1.sizeThatFits(.unspecified).width}
        let width=max(0,proposal.width.flatMap{$0.isFinite ? $0:nil} ?? ideal)
        let (leading,title,trailing,stacked)=measure(width,subviews)
        let actionsHeight=max(leading.height,trailing.height)
        return CGSize(width:width,height:stacked ? actionsHeight+4+title.height:max(actionsHeight,title.height))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        guard subviews.count==3 else{return}
        let (leading,title,trailing,stacked)=measure(bounds.width,subviews)
        let actionsHeight=max(leading.height,trailing.height)
        let actionsY=stacked ? bounds.minY+actionsHeight/2:bounds.midY
        subviews[0].place(at:CGPoint(x:bounds.minX,y:actionsY),anchor:.leading,proposal:ProposedViewSize(leading))
        subviews[2].place(at:CGPoint(x:bounds.maxX,y:actionsY),anchor:.trailing,proposal:ProposedViewSize(trailing))
        let titleY=stacked ? bounds.minY+actionsHeight+4+title.height/2:bounds.midY
        subviews[1].place(at:CGPoint(x:bounds.midX,y:titleY),anchor:.center,proposal:ProposedViewSize(title))
    }
}
extension PapiHeader where Trailing == EmptyView {
    init(_ title:String,back:Bool=true,backAction:(()->Void)?=nil) { self.init(title,back:back,backAction:backAction) { EmptyView() } }
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
struct CoffeeSectionIntro:View {
    let artwork:String
    let title:String
    let detail:String
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.papiBounds) private var bounds
    var body:some View {
        let layout=typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<360) ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(spacing:12))
        layout {
            VStack(alignment:.leading,spacing:6) {
                PapiText(title).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText(detail).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading)
            PapiArtworkFit(asset:artwork).frame(width:94,height:94)
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.cream.opacity(0.96),in:RoundedRectangle(cornerRadius:22))
    }
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
/// For stateless actions only; text inputs use the identity-preserving composer layout below.
struct PapiActionGroup<Content:View>:View {
    @ViewBuilder var content:()->Content
    var body:some View {
        ViewThatFits(in:.horizontal) {
            HStack(spacing:12,content:content).fixedSize(horizontal:true,vertical:false)
            VStack(spacing:12,content:content).frame(maxWidth:.infinity)
        }.frame(maxWidth:.infinity)
    }
}
struct PapiInputBar<Field:View,Actions:View>:View {
    @ScaledMetric(relativeTo:.body) private var inputWidth:CGFloat=140
    @ScaledMetric(relativeTo:.body) private var lineHeight:CGFloat=24
    @Environment(\.papiBounds) private var bounds
    var background:Color = .coffee
    @ViewBuilder var field:()->Field
    @ViewBuilder var actions:()->Actions
    var body:some View {
        let compact=bounds.height>0 && bounds.height<lineHeight*10
        PapiComposerLayout(minimumInputWidth:compact ? 60:inputWidth) {
            field().frame(maxWidth:.infinity)
            actions()
        }.environment(\.papiComposerLines,compact ? 1:3)
            .padding(10).background {background.ignoresSafeArea(.container,edges:.bottom)}.papiAvoidReserved()
    }
}
private struct CoffeeModalHeightKey:PreferenceKey {
    static var defaultValue:CGFloat=0
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=max(value,nextValue())}
}
struct CoffeeModal<Content:View>:View {
    var maximumWidth:CGFloat=360
    var maximumHeight:CGFloat=460
    var shade:Color=Color.black.opacity(0.48)
    var artwork:String?=nil
    @ViewBuilder var content:()->Content
    @Environment(\.papiRegions) private var regions
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var contentHeight:CGFloat=0
    @State private var presentationID=UUID()
    var body:some View {
        GeometryReader {proxy in
            let origin=proxy.frame(in:.named("PapiContainer")).origin
            let rect=PapiRegionGeometry.largestArea(in:CGRect(origin:.zero,size:proxy.size),excluding:regions.map{$0.offsetBy(dx:-origin.x,dy:-origin.y)})
            let width=max(0,min(maximumWidth,rect.width-24))
            let height=max(0,min(maximumHeight,rect.height-24))
            ZStack {
                shade.ignoresSafeArea().onTapGesture{}
                ScrollView {
                    content().padding(width<280 ? 16:26).frame(maxWidth:.infinity)
                        .background {GeometryReader {geometry in Color.clear.preference(key:CoffeeModalHeightKey.self,value:geometry.size.height)}}
                        .background {
                            if let artwork {PapiArtworkFill(asset:artwork)} else {Color.cream}
                        }
                }.frame(width:width,height:min(height,contentHeight>0 ? contentHeight:height))
                    .clipShape(RoundedRectangle(cornerRadius:24))
                    .shadow(color:Color.coffee.opacity(0.22),radius:18,x:0,y:10).position(x:rect.midX,y:rect.midY)
            }.foregroundStyle(Color.coffee)
        }.onPreferenceChange(CoffeeModalHeightKey.self){if abs(contentHeight-$0)>0.5 {contentHeight=$0}}
            .onAppear {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                router.beginModal(presentationID)
            }.onDisappear {router.endModal(presentationID)}
            .accessibilityAddTraits(.isModal)
    }
}
struct PapiDialog: View {
    var title:String
    var message:String
    var confirm="OK"
    var cancel:String? = nil
    var action:()->Void
    var dismiss:()->Void
    @State private var resolving=false
    var body:some View {
        CoffeeModal(maximumWidth:370,maximumHeight:560,shade:Color.coffee.opacity(0.62)) {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.center,spacing:12) {
                    PapiText(title).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                        .frame(maxWidth:.infinity,alignment:.leading)
                    PapiArtworkFit(asset:"dialogCoffeeArt").frame(width:72,height:72)
                }
                PapiText(message).font(CoffeeType.face(.body)).foregroundStyle(Color.mutedCoffee)
                    .fixedSize(horizontal:false,vertical:true)
                VStack(spacing:8) {
                    PapiTextButton(confirm){resolve(action)}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:15)).disabled(resolving)
                    if let cancel {PapiTextButton(cancel){resolve(dismiss)}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:15)).disabled(resolving)}
                }.padding(.top,2)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func resolve(_ choice:()->Void) {
        guard !resolving else{return}
        resolving=true;choice()
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
