import SwiftUI

struct BeanVarietyShelf:View {
    @State private var selected:Int?
    let names=["Arabica","Robusta","Geisha","Bourbon","Pacamara","SL28"]
    let assets=["beanArabica","beanRobusta","beanGeisha","beanBourbon","beanPacamara","beanSL28"]
    let notes=["Often enjoyed for a nuanced cup. Try recording the aroma, sweetness and finish of your own brew.","A fuller-bodied coffee often used in blends. Compare different brew ratios in your journal.","Take time with the aroma and let the cup cool before adding your tasting notes.","Compare roast levels and note how sweetness changes in your cup.","Explore your brewing recipe and note the texture and finish.","Keep track of grind size and water temperature as you explore each cup."]
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Coffee beans")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    PapiText("Explore Coffee Bean Varieties").font(CoffeeType.face(.headline))
                    PapiText("Learn flavors, origins & brewing tips").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:14){ForEach(0..<6){i in Button{selected=i} label:{Image(assets[i]).resizable().scaledToFit()}.buttonStyle(.plain).papiAccessibilityLabel(names[i])}}
                    PapiText("Every roast and harvest is different. Use these cards as a starting point for your own tasting journal.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
            }
        }.overlay {if let selected {PapiDialog(title:names[selected],message:notes[selected],action:{self.selected=nil},dismiss:{self.selected=nil})}}}
    }
}
