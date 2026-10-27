import SwiftUI

struct CafeInspirationView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.layoutDirection) private var direction
    @State private var selected:Int?
    @State private var savedOnly=false
    private let names=["The home coffee corner","Under the glass roof","A rose-coloured terrace","The courtyard table"]
    private let subtitles=["Tools within reach, room for a careful pour","Natural light across a busy coffee bar","Outdoor tables and a quieter evening cup","Coffee and pastry in the open air"]
    private let images=["home-espresso-corner","glasshouse-cafe","rose-front-cafe","courtyard-brunch"]
    private var visibleScenes:[Int] {images.indices.filter{!savedOnly || isSaved($0)}}

    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Explore coffee scenes")
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        PapiText("Coffee inspiration").font(CoffeeType.display(.title2,weight:.bold))
                        HStack(spacing:6) {
                            filterButton("All",isSelected:!savedOnly){savedOnly=false}
                            filterButton("Saved",isSelected:savedOnly){savedOnly=true}
                        }.padding(5).background(Color.cream,in:RoundedRectangle(cornerRadius:18))
                        if visibleScenes.isEmpty {
                            PapiEmpty(title:"No saved scenes yet",detail:"Save a coffee scene to find it here.")
                        } else {
                            ForEach(visibleScenes,id:\.self) {index in sceneCard(index)}
                        }
                    }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
                }
            }.overlay {if let selected {cafeDetail(selected)}}
        }
    }
    private func filterButton(_ title:String,isSelected:Bool,action:@escaping ()->Void)->some View {
        Button(action:action) {
            PapiText(title).font(CoffeeType.face(.subheadline,weight:.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44)
                .background(isSelected ? Color.butter:Color.clear,in:RoundedRectangle(cornerRadius:14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected:[])
    }
    private func sceneCard(_ index:Int)->some View {
        Button {selected=index} label:{
            VStack(alignment:.leading,spacing:0) {
                PapiImage(name:images[index]).frame(height:170).accessibilityHidden(true)
                HStack(alignment:.center,spacing:12) {
                    VStack(alignment:.leading,spacing:6) {
                        PapiText(names[index]).font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                        PapiText(subtitles[index]).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if isSaved(index) {
                        Image("check").resizable().scaledToFit().frame(width:20,height:20).papiAccessibilityLabel("Saved")
                    } else {
                        Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12).accessibilityHidden(true)
                    }
                }.padding(16)
            }.frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:20))
                .clipShape(RoundedRectangle(cornerRadius:20)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func cafeDetail(_ index:Int)->some View {
        CoffeeModal(maximumWidth:360,maximumHeight:620,shade:Color.coffee.opacity(0.56),artwork:nil) {
            VStack(alignment:.leading,spacing:14) {
                PapiImage(name:images[index]).frame(height:170).clipShape(RoundedRectangle(cornerRadius:18)).accessibilityHidden(true)
                PapiText("Coffee inspiration").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee)
                PapiText(names[index]).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText(subtitles[index]).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                PapiTextButton(isSaved(index) ? "Remove from saved":"Save scene"){toggleSaved(index)}
                    .buttonStyle(PapiButtonStyle(light:isSaved(index),wide:true,cornerRadius:15))
                Button {selected=nil} label: {
                    PapiText("Close").font(CoffeeType.face(.subheadline,weight:.semibold))
                        .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func isSaved(_ index:Int)->Bool {store.state.savedCoffeeScenes?.contains(images[index]) == true}
    private func toggleSaved(_ index:Int) {
        let reference=images[index]
        _ = store.commit {state in
            var saved=state.savedCoffeeScenes ?? []
            if !saved.insert(reference).inserted {saved.remove(reference)}
            state.savedCoffeeScenes=saved
        }
    }
}
