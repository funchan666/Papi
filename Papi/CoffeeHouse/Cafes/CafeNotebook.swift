import SwiftUI

struct CafeInspirationView:View {
    @State private var selected:Int?
    let names=["The home coffee corner","Under the glass roof","A rose-coloured terrace","The courtyard table"]
    let subtitles=["Tools within reach, room for a careful pour","Natural light across a busy coffee bar","Outdoor tables and a quieter evening cup","Coffee and pastry in the open air"]
    let images=["home-espresso-corner","glasshouse-cafe","rose-front-cafe","courtyard-brunch"]
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Explore cafés")
            ScrollView {
                VStack(spacing:22) {
                    PreviewLabel(text:"Café notebook · Concepts")
                    ForEach(0..<4){i in
                        Button{selected=i} label:{
                            HStack(spacing:13) {
                                ZStack(alignment:.topLeading){PapiImage(name:images[i]).frame(width:90,height:95).clipped().clipShape(RoundedRectangle(cornerRadius:14));if i<3 {Image("hot").resizable().scaledToFit().frame(width:55,height:33).offset(x:-4,y:-15)}}
                                VStack(alignment:.leading,spacing:7){PapiText(names[i]).font(CoffeeType.face(.headline));PapiText(subtitles[i]).font(CoffeeType.face(.caption));PapiText("Coffee inspiration").font(CoffeeType.face(.caption2)).opacity(0.8)}
                                Spacer(minLength:0)
                            }.padding(12).background(Color.coffee,in:RoundedRectangle(cornerRadius:20)).foregroundStyle(Color.cream)
                        }.buttonStyle(.plain)
                    }
                    PapiText("These café concepts are prompts for your notebook, not verified venues. Locations, reservations and opening hours are not provided.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
            }
        }.overlay{if let selected {PapiDialog(title:names[selected],message:subtitles[selected]+". This is an inspiration card. A real café directory has not been connected.",action:{self.selected=nil},dismiss:{self.selected=nil})}}}
    }
}
