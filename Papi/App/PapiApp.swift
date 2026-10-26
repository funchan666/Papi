import SwiftUI

@main struct PapiApp:App {
    @StateObject private var store=CoffeeHouse()
    @StateObject private var commerce=AppleCoinCounter()
    @StateObject private var router=CoffeeNavigation()
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            PapiDeviceContainer {
                Group {
                    if store.state.signedIn { PapiRootView() }
                    else { FirstCupWelcomeView() }
                }.papiNotices()
            }
            .environmentObject(store).environmentObject(commerce).environmentObject(router)
            .environment(\.locale,Locale(identifier:store.state.language))
            .environment(\.layoutDirection,store.state.language == "ar" ? .rightToLeft:.leftToRight)
            .font(CoffeeType.face(.body)).tint(.coffee).preferredColorScheme(.light)
            .task {commerce.start(store:store);store.presentWelcomeIfNeeded()}
            .onChange(of:scenePhase) { _,phase in if phase == .active {store.presentWelcomeIfNeeded();Task {await commerce.recover()}} }
            .onChange(of:store.state.signedIn) { _,signedIn in
                router.resetForAccountChange()
                if signedIn {Task {await commerce.recover()}}
            }
            .onChange(of:store.storageAvailable) {_,available in if available {Task {await commerce.recover()}}}
            .onChange(of:store.accountAction) {_,action in if action==nil {Task {await commerce.recover()}}}
        }
    }
}
enum CoffeeDestination:Hashable {
    case room(String),post(String),person(String),chat(String),beans,cafes,settings,editProfile,wallet,backpack,level,relationships(Int),blacklist,language,legal(String),notifications,photo(String),gifts(String),reviewQueue,tables,brewRecipe(String),brewArchive,brewCup(UUID),cuppingFlight,cupChoice(Int)
}
enum CoffeePresentation:Identifiable {
    case compose,checkin,report(SafetyTarget),safety(SafetyTarget),more(String),gifts(String)
    var id:String {
        switch self {
        case .compose:return "compose"
        case .checkin:return "checkin"
        case .report(let target):return "report-"+target.id
        case .safety(let target):return "safety-"+target.id
        case .more(let id):return "more-"+id
        case .gifts(let id):return "gifts-"+id
        }
    }
}
@MainActor final class CoffeeNavigation:ObservableObject {
    @Published var path:[CoffeeDestination]=[]
    @Published var sheet:CoffeePresentation?
    @Published private var modalPresentations:Set<UUID> = []
    private var rootSheetVisible=false
    private var routeAfterSheet:CoffeeDestination?
    var hasBlockingModal:Bool {!modalPresentations.isEmpty}
    func beginModal(_ id:UUID) {modalPresentations.insert(id)}
    func endModal(_ id:UUID) {modalPresentations.remove(id)}
    func go(_ route:CoffeeDestination) {if path.last != route {path.append(route)}}
    func goAfterClosingSheet(_ route:CoffeeDestination) {
        guard routeAfterSheet==nil else{return}
        if sheet != nil || rootSheetVisible {routeAfterSheet=route;sheet=nil}
        else {go(route)}
    }
    func rootSheetDidAppear() {rootSheetVisible=true}
    func rootSheetDidDismiss() {
        rootSheetVisible=false
        let next=routeAfterSheet;routeAfterSheet=nil
        if let next {go(next)}
    }
    func resetForAccountChange() {routeAfterSheet=nil;rootSheetVisible=false;path=[];sheet=nil}
    func openWallet() {goAfterClosingSheet(.wallet)}
    func removeHiddenDestinations(using store:CoffeeHouse) {
        if let index=path.firstIndex(where:{route in
            switch route {
            case .post(let id):return store.post(id)==nil
            case .person(let id),.chat(let id):return store.isUserHidden(id)
            case .room(let id):return CoffeeTable.previews.first(where:{$0.id==id}).map{!store.isRoomVisible($0)} ?? true
            default:return false
            }
        }) {path=Array(path.prefix(index))}
    }
}
struct PapiRootView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        NavigationStack(path:$router.path) {
            PapiTabShell().navigationDestination(for:CoffeeDestination.self) { route in destination(route) }
                .toolbar(.hidden,for:.navigationBar)
        }
        .sheet(item:$router.sheet,onDismiss:{router.rootSheetDidDismiss()}) { sheet in
            PapiDeviceContainer {
                NavigationStack { sheetContent(sheet).papiNotices() }
            }.onAppear{router.rootSheetDidAppear()}.presentationBackground {PapiBackground()}.presentationDragIndicator(.hidden).interactiveDismissDisabled(router.hasBlockingModal)
        }
        .onChange(of:store.visibilityKeys){_,_ in router.removeHiddenDestinations(using:store)}
    }
    @ViewBuilder private func destination(_ route:CoffeeDestination)->some View {
        switch route {
        case .room(let id):
            if let room=CoffeeTable.previews.first(where:{$0.id==id}),store.isRoomVisible(room) {CoffeeTableView(room:room)}
            else {PapiScreen {VStack(spacing:0){PapiHeader("Coffee tables");ScrollView {PapiEmpty(title:"This content is unavailable")}}}}
        case .post(let id):CoffeeMomentView(momentID:id)
        case .person(let id):
            if id==store.state.passport.id.uuidString {VStack(spacing:0){PapiHeader("Profile").background(Color.cream).papiContainerMargins();MyCoffeePassportView()}.background {PapiBackground()}}
            else {MemberPassportView(memberID:id)}
        case .chat(let id):CoffeeConversationView(memberID:id)
        case .beans:BeanVarietyShelf()
        case .cafes:CafeInspirationView()
        case .settings:CoffeePreferencesView()
        case .editProfile:EditCoffeePassportView()
        case .wallet:CoinReserveView()
        case .backpack:CoffeeCollectionView()
        case .level:CoffeeJourneyView()
        case .relationships(let tab):RelationshipsView(initialTab:tab)
        case .blacklist:BlacklistView()
        case .language:LanguageView()
        case .legal(let type):LegalView(type:type)
        case .notifications:CoffeeDeskView()
        case .photo(let name):PhotoDetailView(name:name)
        case .gifts(let context):CollectibleCounterView(context:context)
        case .reviewQueue:ReviewQueueView()
        case .tables:VStack(spacing:0){PapiHeader("Coffee tables").papiContainerMargins();CoffeeTablesView()}.background {PapiBackground()}
        case .brewRecipe(let id):BrewRecipeView(recipeID:id)
        case .brewArchive:BrewArchiveView()
        case .brewCup(let id):CupTastingView(cupID:id)
        case .cuppingFlight:CuppingFlightView()
        case .cupChoice(let slot):BrewCupPicker(slot:slot)
        }
    }
    @ViewBuilder private func sheetContent(_ sheet:CoffeePresentation)->some View {
        switch sheet {
        case .compose:CoffeeMomentComposer()
        case .checkin:DailyRitualView()
        case .report(let target):ReportView(target:target)
        case .safety(let target):SafetyMenuView(target:target)
        case .more(let id):SafetyMenuView(target:.user(id))
        case .gifts(let id):CollectibleCounterView(context:id)
        }
    }
}
struct PapiTabShell:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.layoutDirection) private var direction
    var body:some View {
        #if PAPI_DUO_SDK
        if #available(iOS 27.1,*) {DuoTabShell()}
        else {shell(side:nil)}
        #else
        shell(side:nil)
        #endif
    }
    func shell(side:HorizontalEdge?)->some View {
        PapiShellLayout(side:side) {
            ZStack {
                // Keep all tab roots mounted to preserve scroll positions and loaded state.
                CoffeeJournalView().opacity(store.selectedTab==0 ? 1:0).allowsHitTesting(store.selectedTab==0).accessibilityHidden(store.selectedTab != 0)
                BrewBenchView().opacity(store.selectedTab==1 ? 1:0).allowsHitTesting(store.selectedTab==1).accessibilityHidden(store.selectedTab != 1)
                CorrespondenceInbox().opacity(store.selectedTab==2 ? 1:0).allowsHitTesting(store.selectedTab==2).accessibilityHidden(store.selectedTab != 2)
                MyCoffeePassportView().opacity(store.selectedTab==3 ? 1:0).allowsHitTesting(store.selectedTab==3).accessibilityHidden(store.selectedTab != 3)
            }
            tabBar(vertical:side != nil)
        }.background(Color.cream)
    }
    private func tabBar(vertical:Bool)->some View {
        Group {
            if vertical {ScrollView(.vertical,showsIndicators:false){tabItems(vertical:true)}}
            else {tabItems(vertical:false)}
        }.frame(maxHeight:vertical ? .infinity:nil)
            .background {
                UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24).fill(Color.coffee)
                    .ignoresSafeArea(.container,edges:vertical ? .all:.bottom)
            }.disabled(router.hasBlockingModal).accessibilityHidden(router.hasBlockingModal)
    }
    private func tabItems(vertical:Bool)->some View {
        let layout=vertical ? AnyLayout(VStackLayout(spacing:20)):AnyLayout(HStackLayout(spacing:0))
        return layout {
            ForEach(0..<4) { index in
                let asset=["home","voice","messages","me"][index]
                Button {store.selectedTab=index} label:{
                    VStack(spacing:5) {
                        Image(index==1 ? "brewDripper":asset+(store.selectedTab==index ? "On":"Off")).resizable().scaledToFit().frame(width:30,height:30).opacity(store.selectedTab==index ? 1:0.65)
                        PapiText(store.text(["Home","Brew bench","Messages","Me"][index])).font(CoffeeType.face(.caption2)).fixedSize(horizontal:false,vertical:true).multilineTextAlignment(.center).foregroundStyle(store.selectedTab==index ? Color.cream:Color.cream.opacity(0.68))
                    }.frame(maxWidth:.infinity,minHeight:52).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(store.selectedTab==index ? .isSelected:[]).papiAvoidReserved()
            }
        }.padding(.horizontal,10).padding(.vertical,12)
    }

}
#if PAPI_DUO_SDK
@available(iOS 27.1,*) private struct DuoTabShell:View {
    @Environment(\.toolbarVerticalEdge) private var edge
    var body:some View {PapiTabShell().shell(side:edge)}
}
#endif
struct NoticeModifier:ViewModifier {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    func body(content:Content)->some View {
        content.disabled(store.notice != nil || store.accountAction != nil).accessibilityHidden(store.notice != nil || store.accountAction != nil).overlay {
            if let notice=store.notice {
                Group {
                    if notice.kind == .welcome {WelcomeCoinsView(close:{if store.notice?.id==notice.id {store.acknowledgeWelcome()}})}
                    else if notice.kind == .insufficient {
                        PapiDialog(title:notice.title,message:notice.message,confirm:"Recharge",cancel:"Later",action:{
                            guard store.notice?.id==notice.id else{return}
                            store.notice=nil;router.openWallet()
                        },dismiss:{closeNotice(notice.id)})
                    }
                    else if notice.kind == .information {PapiDialog(title:notice.title,message:notice.message,action:{closeNotice(notice.id)},dismiss:{closeNotice(notice.id)})}
                    else {CoffeeReceiptView(notice:notice,close:{closeNotice(notice.id)})}
                }.id(notice.id)
            }
            if let action=store.accountAction {AccountProgressView(action:action)}
        }
    }
    private func closeNotice(_ id:UUID) {if store.notice?.id==id {store.notice=nil}}
}
extension View {func papiNotices()->some View {modifier(NoticeModifier())}}
