import SwiftUI

@main struct PapiApp:App {
    @StateObject private var store=PapiStore()
    @StateObject private var commerce=PapiCommerce()
    @StateObject private var router=PapiRouter()
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            PapiDeviceContainer {
                Group {
                    if store.state.signedIn { PapiRootView() }
                    else { WelcomeView() }
                }.papiNotices()
            }
            .environmentObject(store).environmentObject(commerce).environmentObject(router)
            .environment(\.locale,Locale(identifier:store.state.language))
            .environment(\.layoutDirection,store.state.language == "ar" ? .rightToLeft:.leftToRight)
            .tint(.coffee).preferredColorScheme(.light)
            .task {commerce.start(store:store)}
            .onChange(of:scenePhase) { _,phase in if phase == .active {Task {await commerce.recover()}} }
            .onChange(of:store.state.signedIn) { _,_ in router.path=[];router.sheet=nil }
        }
    }
}
enum PapiRoute:Hashable {
    case room(String),post(String),person(String),chat(String),beans,cafes,settings,editProfile,wallet,backpack,level,relationships(Int),blacklist,language,legal(String),notifications,photo(String),gifts(String)
}
enum PapiSheet:Identifiable {
    case compose,checkin,report(String),more(String),gifts(String)
    var id:String {
        switch self {
        case .compose:return "compose"
        case .checkin:return "checkin"
        case .report(let id):return "report-"+id
        case .more(let id):return "more-"+id
        case .gifts(let id):return "gifts-"+id
        }
    }
}
@MainActor final class PapiRouter:ObservableObject {
    @Published var path:[PapiRoute]=[]
    @Published var sheet:PapiSheet?
    func go(_ route:PapiRoute) {path.append(route)}
}
struct PapiRootView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    var body:some View {
        NavigationStack(path:$router.path) {
            PapiTabShell().navigationDestination(for:PapiRoute.self) { route in destination(route) }
                .toolbar(.hidden,for:.navigationBar)
        }
        .sheet(item:$router.sheet) { sheet in
            PapiDeviceContainer {
                NavigationStack { sheetContent(sheet).papiNotices() }
            }.presentationDragIndicator(.hidden)
        }

    }
    @ViewBuilder private func destination(_ route:PapiRoute)->some View {
        switch route {
        case .room(let id):
            if let room=Room.previews.first(where:{$0.id==id}) {RoomDetailView(room:room)}
        case .post(let id):PostDetailView(postID:id)
        case .person(let id):PersonView(personID:id)
        case .chat(let id):ChatView(personID:id)
        case .beans:BeansView()
        case .cafes:CafesView()
        case .settings:SettingsView()
        case .editProfile:EditProfileView()
        case .wallet:WalletView()
        case .backpack:BackpackView()
        case .level:LevelView()
        case .relationships(let tab):RelationshipsView(initialTab:tab)
        case .blacklist:BlacklistView()
        case .language:LanguageView()
        case .legal(let type):LegalView(type:type)
        case .notifications:NotificationView()
        case .photo(let name):PhotoDetailView(name:name)
        case .gifts(let context):GiftShopView(context:context)
        }
    }
    @ViewBuilder private func sheetContent(_ sheet:PapiSheet)->some View {
        switch sheet {
        case .compose:ComposeView()
        case .checkin:CheckinView()
        case .report(let id):ReportView(subjectID:id)
        case .more(let id):MemberActionsView(personID:id)
        case .gifts(let id):GiftShopView(context:id)
        }
    }
}
struct PapiTabShell:View {
    @EnvironmentObject private var store:PapiStore
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
                HomeView().opacity(store.selectedTab==0 ? 1:0).allowsHitTesting(store.selectedTab==0).accessibilityHidden(store.selectedTab != 0)
                RoomsView().opacity(store.selectedTab==1 ? 1:0).allowsHitTesting(store.selectedTab==1).accessibilityHidden(store.selectedTab != 1)
                MessagesView().opacity(store.selectedTab==2 ? 1:0).allowsHitTesting(store.selectedTab==2).accessibilityHidden(store.selectedTab != 2)
                ProfileView().opacity(store.selectedTab==3 ? 1:0).allowsHitTesting(store.selectedTab==3).accessibilityHidden(store.selectedTab != 3)
            }.clipped()
            tabBar(vertical:side != nil)
        }.background(Color.cream)
    }
    private func tabBar(vertical:Bool)->some View {
        let layout=vertical ? AnyLayout(VStackLayout(spacing:20)):AnyLayout(HStackLayout(spacing:0))
        return layout {
            ForEach(0..<4) { index in
                let asset=["home","voice","messages","me"][index]
                Button {store.selectedTab=index} label:{
                    VStack(spacing:5) {
                        Image(asset+(store.selectedTab==index ? "On":"Off")).resizable().scaledToFit().frame(width:30,height:30)
                        PapiText(store.text(["Home","Voice","Messages","Me"][index])).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(store.selectedTab==index ? Color.cream:Color.cream.opacity(0.68))
                    }.frame(maxWidth:.infinity,minHeight:52).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(store.selectedTab==index ? .isSelected:[]).papiAvoidReserved()
            }
        }.padding(.horizontal,10).padding(.vertical,12).frame(maxHeight:vertical ? .infinity:nil)
            .background(Color.coffee,in:UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24))
    }
}
#if PAPI_DUO_SDK
@available(iOS 27.1,*) private struct DuoTabShell:View {
    @Environment(\.toolbarVerticalEdge) private var edge
    var body:some View {PapiTabShell().shell(side:edge)}
}
#endif
struct NoticeModifier:ViewModifier {
    @EnvironmentObject private var store:PapiStore
    func body(content:Content)->some View {
        content.disabled(store.notice != nil).accessibilityHidden(store.notice != nil).overlay {
            if let notice=store.notice {
                PapiDialog(title:notice.title,message:notice.message,action:{store.notice=nil},dismiss:{store.notice=nil})
            }
        }
    }
}
extension View {func papiNotices()->some View {modifier(NoticeModifier())}}
