import SwiftUI

struct CafeInspirationView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.layoutDirection) private var direction
    @State private var selected:String?
    @State private var savedOnly=false
    private var guides:[CoffeeCloud.ReferenceGuide] {
        (store.cloudReferenceGuides ?? []).filter{$0.kind=="cafe"}
    }
    private var visibleScenes:[CoffeeCloud.ReferenceGuide] {guides.filter{!savedOnly || isSaved($0)}}

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
                        if store.usesCloudWallet && store.cloudReferenceGuides == nil {
                            PapiTextButton("Retry"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                        } else if savedOnly && store.usesCloudWallet && store.cloudSavedScenes == nil {
                            PapiTextButton(store.cloudSavedScenesBusy ? "Connecting…":"Retry") {Task {await store.refreshSavedScenes()}}
                                .disabled(store.cloudSavedScenesBusy)
                        } else if visibleScenes.isEmpty {
                            PapiEmpty(title:"No saved scenes yet",detail:"Save a coffee scene to find it here.")
                        } else {
                            ForEach(visibleScenes) {guide in sceneCard(guide)}
                        }
                    }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
                }
            }.overlay {if let selected,let guide=guides.first(where:{$0.id==selected}) {cafeDetail(guide)}}
        }.task(id:store.state.cloudAccountID) {if store.usesCloudWallet {await store.refreshSavedScenes()}}
    }
    private func filterButton(_ title:String,isSelected:Bool,action:@escaping ()->Void)->some View {
        Button(action:action) {
            PapiText(title).font(CoffeeType.face(.subheadline,weight:.semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44)
                .background(isSelected ? Color.butter:Color.clear,in:RoundedRectangle(cornerRadius:14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected:[])
    }
    private func sceneCard(_ guide:CoffeeCloud.ReferenceGuide)->some View {
        Button {selected=guide.id} label:{
            VStack(alignment:.leading,spacing:0) {
                PapiImage(name:guide.asset).frame(height:170).accessibilityHidden(true)
                HStack(alignment:.center,spacing:12) {
                    VStack(alignment:.leading,spacing:6) {
                        PapiText(guide.title).font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                        PapiText(guide.detail).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                    if isSaved(guide) {
                        Image("check").resizable().scaledToFit().frame(width:20,height:20).papiAccessibilityLabel("Saved")
                    } else {
                        Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12).accessibilityHidden(true)
                    }
                }.padding(16)
            }.frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:20))
                .clipShape(RoundedRectangle(cornerRadius:20)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func cafeDetail(_ guide:CoffeeCloud.ReferenceGuide)->some View {
        CoffeeModal(maximumWidth:360,maximumHeight:620,shade:Color.coffee.opacity(0.56),artwork:nil) {
            VStack(alignment:.leading,spacing:14) {
                PapiImage(name:guide.asset).frame(height:170).clipShape(RoundedRectangle(cornerRadius:18)).accessibilityHidden(true)
                PapiText("Coffee inspiration").font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee)
                PapiText(guide.title).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText(guide.detail).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                PapiTextButton(isSaved(guide) ? "Remove from saved":"Save scene"){toggleSaved(guide)}
                    .buttonStyle(PapiButtonStyle(light:isSaved(guide),wide:true,cornerRadius:15))
                    .disabled(store.usesCloudWallet && (store.cloudSavedScenes == nil || store.cloudSavedScenesBusy))
                if store.usesCloudWallet && store.cloudSavedScenes == nil {
                    PapiTextButton("Retry"){Task {await store.refreshSavedScenes()}}.disabled(store.cloudSavedScenesBusy)
                }
                Button {selected=nil} label: {
                    PapiText("Close").font(CoffeeType.face(.subheadline,weight:.semibold))
                        .frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func isSaved(_ guide:CoffeeCloud.ReferenceGuide)->Bool {
        store.usesCloudWallet ? store.cloudSavedScenes?.contains(guide.id) == true : store.state.savedCoffeeScenes?.contains(guide.asset) == true
    }
    private func toggleSaved(_ guide:CoffeeCloud.ReferenceGuide) {
        if store.usesCloudWallet {
            Task {await store.setSavedScene(guide.id,enabled:!isSaved(guide))};return
        }
        let reference=guide.asset
        _ = store.commit {state in
            var saved=state.savedCoffeeScenes ?? []
            if !saved.insert(reference).inserted {saved.remove(reference)}
            state.savedCoffeeScenes=saved
        }
    }
}
