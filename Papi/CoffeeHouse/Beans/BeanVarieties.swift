import SwiftUI

struct BeanVarietyShelf:View {
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected:Int?
    private let names=["Arabica","Robusta","Geisha","Bourbon","Pacamara","SL28"]
    private let assets=["beanArabica","beanRobusta","beanGeisha","beanBourbon","beanPacamara","beanSL28"]
    private let notes=["Often enjoyed for a nuanced cup. Try recording the aroma, sweetness and finish of your own brew.","A fuller-bodied coffee often used in blends. Compare different brew ratios in your journal.","Take time with the aroma and let the cup cool before adding your tasting notes.","Compare roast levels and note how sweetness changes in your cup.","Explore your brewing recipe and note the texture and finish.","Keep track of grind size and water temperature as you explore each cup."]
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
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:columnCount),spacing:14) {
                            ForEach(names.indices,id:\.self) {index in
                                Button {selected=index} label:{
                                    VStack(alignment:.leading,spacing:8) {
                                        Image(assets[index]).resizable().scaledToFit().frame(maxWidth:.infinity).accessibilityHidden(true)
                                        HStack {
                                            PapiText("Read notes").font(CoffeeType.face(.caption,weight:.semibold))
                                            Spacer(minLength:0)
                                            Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12).accessibilityHidden(true)
                                        }.padding(.horizontal,6).padding(.bottom,4)
                                    }.padding(8).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:20)).contentShape(Rectangle())
                                }.buttonStyle(.plain).papiAccessibilityLabel(names[index])
                            }
                        }
                    }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
                    }
                }
            }.overlay {if let selected {beanDetail(selected)}}
        }
    }
    private func beanDetail(_ index:Int)->some View {
        CoffeeModal(maximumWidth:370,maximumHeight:610,shade:Color.coffee.opacity(0.55),artwork:nil) {
            VStack(alignment:.leading,spacing:16) {
                HStack(spacing:12) {
                    VStack(alignment:.leading,spacing:5) {
                        PapiText("Coffee bean guide").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee)
                        PapiText("Tasting notes").font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    PapiArtworkFit(asset:"beanGuideArt").frame(width:72,height:72)
                }
                Image(assets[index]).resizable().scaledToFit().frame(maxWidth:.infinity).frame(height:160).papiAccessibilityLabel(names[index])
                PapiText(notes[index]).font(CoffeeType.face(.body)).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                PapiTextButton("Close"){selected=nil}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16))
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
}
