import SwiftUI

struct BeanVarietyShelf:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected:String?
    private var guides:[CoffeeCloud.ReferenceGuide] {
        (store.cloudReferenceGuides ?? []).filter{$0.kind=="bean"}
    }
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Coffee beans")
                GeometryReader {geometry in
                    let contentWidth=max(0,min(850,geometry.size.width)-40)
                    let columnCount=typeSize.isAccessibilitySize || contentWidth<330 ? 1:min(4,max(1,Int((contentWidth+12)/162)))
                    ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        HStack(alignment:.center,spacing:12) {
                            VStack(alignment:.leading,spacing:8) {
                                PapiText("Coffee bean guide").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee)
                                PapiText("Explore Coffee Bean Varieties").font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                PapiText("Every roast and harvest is different. Use these cards as a starting point for your own tasting journal.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            PapiArtworkFit(asset:"beanGuideArt").frame(width:96,height:96)
                        }.padding(18).background(Color.cream.opacity(0.96),in:RoundedRectangle(cornerRadius:22))
                        if store.usesCloudWallet && store.cloudReferenceGuides == nil {
                            PapiTextButton("Retry"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                        }
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:columnCount),spacing:14) {
                            ForEach(guides) {guide in
                                Button {selected=guide.id} label:{
                                    VStack(alignment:.leading,spacing:8) {
                                        Image(guide.asset).resizable().scaledToFit().frame(maxWidth:.infinity).accessibilityHidden(true)
                                        HStack {
                                            PapiText("Read notes").font(CoffeeType.face(.caption,weight:.semibold))
                                            Spacer(minLength:0)
                                            Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12).accessibilityHidden(true)
                                        }.padding(.horizontal,6).padding(.bottom,4)
                                    }.padding(8).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:20)).contentShape(Rectangle())
                                }.buttonStyle(.plain).papiAccessibilityLabel(guide.title)
                            }
                        }
                    }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
                    }
                }
            }.overlay {if let selected,let guide=guides.first(where:{$0.id==selected}) {beanDetail(guide)}}
        }
    }
    private func beanDetail(_ guide:CoffeeCloud.ReferenceGuide)->some View {
        CoffeeModal(maximumWidth:370,maximumHeight:610,shade:Color.coffee.opacity(0.55),artwork:nil) {
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:5) {
                        PapiText("Coffee bean guide").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee)
                        PapiText("Tasting notes").font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    PapiArtworkFit(asset:"beanGuideArt").frame(width:72,height:72)
                }
                Image(guide.asset).resizable().scaledToFit().frame(maxWidth:.infinity).frame(height:160).papiAccessibilityLabel(guide.title)
                PapiText(guide.detail).font(CoffeeType.face(.body)).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                PapiTextButton("Close"){selected=nil}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16))
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
