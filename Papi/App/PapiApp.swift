import SwiftUI
import UIKit
import UserNotifications
import Network

private final class PapiProbeRedirects:NSObject,URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {completionHandler(nil)}
}

@MainActor final class PapiNetworkCoordinator {
    static let shared=PapiNetworkCoordinator()
    private let monitor=NWPathMonitor()
    private let queue=DispatchQueue(label:"papi.network.path")
    private let redirects=PapiProbeRedirects()
    private var started=false
    private var active=true
    private var ready=false
    private var generation=0
    private var currentProbe:Task<Bool,Never>?
    private var retryTask:Task<Void,Never>?
    private var retryIndex=0
    private var lastStatus:NWPath.Status?
    private let session:URLSession = {
        let configuration=URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity=true
        configuration.timeoutIntervalForRequest=12
        configuration.timeoutIntervalForResource=15
        return URLSession(configuration:configuration)
    }()
    func start() {
        guard !started else{return}
        started=true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else{return}
                if self.lastStatus == nil {
                    self.lastStatus=path.status
                    if path.status != .satisfied {self.invalidate()}
                    else if self.active && self.currentProbe == nil {Task { _ = await self.probe() }}
                    return
                }
                guard self.lastStatus != path.status else{return}
                self.lastStatus=path.status
                self.invalidate()
                if path.status == .satisfied,self.active {Task { _ = await self.probe() }}
            }
        }
        monitor.start(queue:queue)
        Task {_ = await probe()}
    }
    func setActive(_ value:Bool) {
        guard value != active else{return}
        active=value;invalidate()
        if value {Task {_ = await probe()}}
    }
    private func invalidate() {
        generation += 1;ready=false;currentProbe?.cancel();currentProbe=nil
        retryTask?.cancel();retryTask=nil;retryIndex=0
    }
    func markFailed() {invalidate();scheduleRetry()}
    private func scheduleRetry() {
        guard active,retryTask==nil else{return}
        let delays=[2,4,8,16,30]
        let delay=delays[min(retryIndex,delays.count-1)]
        retryIndex=min(retryIndex+1,delays.count-1)
        let attempt=generation
        retryTask=Task { [weak self] in
            do {try await Task.sleep(for:.seconds(delay))} catch {return}
            guard let self,self.generation==attempt,self.active else{return}
            self.retryTask=nil
            _ = await self.probe()
        }
    }
    func probe() async -> Bool {
        guard active else{return false}
        if ready {return true}
        if let currentProbe {return await currentProbe.value}
        let attempt=generation
        let task=Task { [session,redirects] in
            var request=URLRequest(url:URL(string:"https://cquoffowtjnxmgaxavym.supabase.co/")!)
            request.httpMethod="HEAD"
            do {let (_,response)=try await session.data(for:request,delegate:redirects);return response is HTTPURLResponse}
            catch {return false}
        }
        currentProbe=task
        let result=await task.value
        guard attempt==generation else{return false}
        currentProbe=nil;ready=result
        if result {retryTask?.cancel();retryTask=nil;retryIndex=0} else {scheduleRetry()}
        return result
    }
}

@MainActor final class PapiPushCoordinator {
    static let shared=PapiPushCoordinator()
    private(set) var token:String?
    private(set) var registrationFailed=false
    private var requestingPermission=false
    func registered(_ data:Data) {
        token=data.map {String(format:"%02x",$0)}.joined()
        registrationFailed=false
    }
    func failed() {token=nil;registrationFailed=true}
    func requestPermissionIfNeeded() async {
        guard !requestingPermission,UIApplication.shared.applicationState == .active else{return}
        requestingPermission=true;defer{requestingPermission=false}
        let center=UNUserNotificationCenter.current()
        let settings=await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined,UIApplication.shared.applicationState == .active else{return}
        _ = try? await center.requestAuthorization(options:[.alert,.sound,.badge])
    }
}

final class PapiApplicationDelegate:NSObject,UIApplicationDelegate {
    func application(_ application:UIApplication,didFinishLaunchingWithOptions launchOptions:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {
        application.registerForRemoteNotifications()
        return true
    }
    func application(_ application:UIApplication,didRegisterForRemoteNotificationsWithDeviceToken deviceToken:Data) {
        PapiPushCoordinator.shared.registered(deviceToken)
    }
    func application(_ application:UIApplication,didFailToRegisterForRemoteNotificationsWithError error:Error) {
        PapiPushCoordinator.shared.failed()
    }
}

@main struct PapiApp:App {
    @UIApplicationDelegateAdaptor(PapiApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store=CoffeeHouse()
    @StateObject private var commerce=AppleCoinCounter()
    @StateObject private var router=CoffeeNavigation()
    @State private var showingLaunch=true
    @State private var deferredOnlinePolicy=false
    @Environment(\.scenePhase) private var scenePhase
    var body:some Scene {
        WindowGroup {
            PapiDeviceContainer {
                Group {
                    if store.state.pendingCloudDeletionID != nil {CoffeeCloudDeletionPendingView()}
                    else if store.onlinePolicyRenewalRequired && !deferredOnlinePolicy {CoffeeOnlinePolicyRenewalView {deferredOnlinePolicy=true}}
                    else if store.cloudConnectionRequired {CoffeeCloudConnectionPendingView()}
                    else if store.state.signedIn { PapiRootView() }
                    else { FirstCupWelcomeView() }
                }.papiNotices()
                    .disabled(showingLaunch).accessibilityHidden(showingLaunch)
                    .overlay {if showingLaunch {PapiLaunchLoadingView()}}
            }
            .environmentObject(store).environmentObject(commerce).environmentObject(router)
            .environment(\.locale,Locale(identifier:store.state.language))
            .environment(\.layoutDirection,store.state.language == "ar" ? .rightToLeft:.leftToRight)
            .font(CoffeeType.face(.body)).tint(.coffee).preferredColorScheme(.light)
            .task {
                guard showingLaunch else{return}
                do {try await Task.sleep(for:.milliseconds(700))} catch {return}
                showingLaunch=false
            }
            .task {PapiNetworkCoordinator.shared.start();commerce.start(store:store);guard store.state.pendingCloudDeletionID==nil else{return};store.presentWelcomeIfNeeded();await store.refreshCloudWallet();await store.syncCloudBrewBook();await store.refreshCloudSocial()}
            .task {if scenePhase == .active && store.state.signedIn {await PapiPushCoordinator.shared.requestPermissionIfNeeded()}}
            .onChange(of:scenePhase) { _,phase in PapiNetworkCoordinator.shared.setActive(phase != .background);if phase == .active && store.state.pendingCloudDeletionID==nil {store.presentWelcomeIfNeeded();if store.state.signedIn {Task {await PapiPushCoordinator.shared.requestPermissionIfNeeded()}};Task {await commerce.recover();await store.refreshCloudWallet();await store.syncCloudBrewBook();await store.refreshCloudSocial()}} }
            .onChange(of:store.state.signedIn) { _,signedIn in
                router.resetForAccountChange()
                if signedIn {Task {await PapiPushCoordinator.shared.requestPermissionIfNeeded()};Task {await commerce.recover();await store.refreshCloudWallet();await store.syncCloudBrewBook();await store.refreshCloudSocial()}}
            }
            .onChange(of:store.state.cloudAccountID) {_,account in
                if account != nil {Task {await commerce.recover();await store.refreshCloudWallet();await store.syncCloudBrewBook();await store.refreshCloudSocial()}}
            }
            .onChange(of:store.state.deletedCloudAccountID) {old,new in
                if old != nil && new == nil {deferredOnlinePolicy=false}
            }
            .onChange(of:store.storageAvailable) {_,available in if available {Task {await commerce.recover()}}}
            .onChange(of:store.accountAction) {_,action in if action==nil {Task {await commerce.recover()}}}
        }
    }
}
enum CoffeeDestination:Hashable {
    case room(String),post(String),playPost(String),person(String),chat(String),liveCall(UUID),beans,cafes,settings,editProfile,linkEmail,recoverEmail,wallet,backpack,level,relationships(Int),blacklist,language,legal(String),notifications,photo(String),gifts(String),reviewQueue,tables,brewBench,brewRecipe(String),brewArchive,brewCup(UUID),cuppingFlight,cupChoice(Int)
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
            case .post(let id),.playPost(let id):return store.post(id)==nil
            case .person(let id),.chat(let id):return store.isUserHidden(id)
            case .room(let id):
                if store.usesCloudWallet {
                    guard let topics=store.cloudVoiceTopics else{return false}
                    guard let room=topics.first(where:{$0.id==id})?.room else{return true}
                    return !store.isRoomVisible(room)
                }
                return CoffeeTable.previews.first(where:{$0.id==id}).map{!store.isRoomVisible($0)} ?? true
            default:return false
            }
        }) {path=Array(path.prefix(index))}
    }
}
struct PapiRootView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        NavigationStack(path:$router.path) {
            PapiTabShell().navigationDestination(for:CoffeeDestination.self) { route in destination(route) }
                .toolbar(.hidden,for:.navigationBar)
        }
        .safeAreaInset(edge:.top,spacing:0) {
            if store.liveCallsEnabled,store.usesCloudWallet,!store.incomingCloudCalls.isEmpty,
               !(store.selectedTab==2 && router.path.isEmpty),router.sheet==nil,!router.hasBlockingModal {
                PapiPanel {
                    Button {
                        router.path=[];store.selectedTab=2
                    } label: {
                        HStack(spacing:12) {
                            Image("messagesOn").resizable().scaledToFit().frame(width:28,height:28).accessibilityHidden(true)
                            PapiText("Incoming video call").font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                            Spacer(minLength:0)
                        }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.frame(maxWidth:700).padding(.horizontal,16).padding(.bottom,6)
            }
        }
        .sheet(item:$router.sheet,onDismiss:{router.rootSheetDidDismiss()}) { sheet in
            PapiDeviceContainer {
                NavigationStack { sheetContent(sheet).papiNotices() }
            }.onAppear{router.rootSheetDidAppear()}.presentationBackground {PapiBackground()}.presentationDragIndicator(.hidden).interactiveDismissDisabled(router.hasBlockingModal)
        }
        .task(id:scenePhase) {
            guard store.liveCallsEnabled,scenePhase == .active else{return}
            while !Task.isCancelled {
                if store.usesCloudWallet,store.state.signedIn,store.state.pendingCloudDeletionID==nil {
                    await store.refreshCloudCalls()
                }
                do {try await Task.sleep(for:.seconds(10))} catch {break}
            }
        }
        .onChange(of:store.visibilityKeys){_,_ in router.removeHiddenDestinations(using:store)}
    }
    @ViewBuilder private func destination(_ route:CoffeeDestination)->some View {
        switch route {
        case .room(let id):
            if store.usesCloudWallet,store.liveVoiceEnabled,let account=store.state.cloudAccountID,
               let topic=store.cloudVoiceTopics?.first(where:{$0.id==id}),let room=topic.room {
                CoffeeLiveVoiceRoomView(topic:topic,cover:room.coverReference,account:account)
            }
            else if store.usesCloudWallet {PapiScreen {VStack(spacing:0){PapiHeader("Coffee tables");ScrollView {PapiEmpty(title:"Voice rooms unavailable")}}}}
            else if let room=CoffeeTable.previews.first(where:{$0.id==id}),store.isRoomVisible(room) {CoffeeTableView(room:room)}
            else {PapiScreen {VStack(spacing:0){PapiHeader("Coffee tables");ScrollView {PapiEmpty(title:"This content is unavailable")}}}}
        case .post(let id):CoffeeMomentView(momentID:id)
        case .playPost(let id):CoffeeMomentView(momentID:id,autoplay:true)
        case .person(let id):
            if id==store.state.passport.id.uuidString || id==store.state.cloudAccountID?.uuidString {VStack(spacing:0){PapiHeader("Profile").background(Color.cream).papiContainerMargins();MyCoffeePassportView()}.background {PapiBackground()}}
            else {MemberPassportView(memberID:id)}
        case .chat(let id):CoffeeConversationView(memberID:id)
        case .liveCall(let id):
            if store.liveCallsEnabled,let account=store.state.cloudAccountID {CoffeeLiveCallView(callID:id,accountID:account)}
            else {PapiScreen {PapiEmpty(title:"Call unavailable")}}
        case .beans:BeanVarietyShelf()
        case .cafes:CafeInspirationView()
        case .settings:CoffeePreferencesView()
        case .editProfile:EditCoffeePassportView()
        case .linkEmail:
            if store.emailLinkEnabled {CoffeeEmailLinkView()}
            else {PapiScreen {PapiEmpty(title:"Account recovery unavailable")}}
        case .recoverEmail:
            if store.emailLinkEnabled {CoffeeEmailRecoveryView()}
            else {PapiScreen {PapiEmpty(title:"Account recovery unavailable")}}
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
        case .brewBench:BrewBenchView()
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
            GeometryReader {viewport in
                ZStack {
                    // Keep all tab roots mounted to preserve scroll positions and loaded state.
                    CoffeeJournalView().opacity(store.selectedTab==0 ? 1:0).allowsHitTesting(store.selectedTab==0).accessibilityHidden(store.selectedTab != 0)
                    CoffeeTablesView().opacity(store.selectedTab==1 ? 1:0).allowsHitTesting(store.selectedTab==1).accessibilityHidden(store.selectedTab != 1)
                    CorrespondenceInbox().opacity(store.selectedTab==2 ? 1:0).allowsHitTesting(store.selectedTab==2).accessibilityHidden(store.selectedTab != 2)
                    MyCoffeePassportView().opacity(store.selectedTab==3 ? 1:0).allowsHitTesting(store.selectedTab==3).accessibilityHidden(store.selectedTab != 3)
                    CoffeeRatioStudioView().opacity(store.selectedTab==4 ? 1:0).allowsHitTesting(store.selectedTab==4).accessibilityHidden(store.selectedTab != 4)
                }.frame(width:viewport.size.width,height:viewport.size.height)
            }
            tabBar(vertical:side != nil)
        }.background {PapiBackground()}
    }
    private func tabBar(vertical:Bool)->some View {
        Group {
            if vertical {
                glassSurface(ScrollView(.vertical,showsIndicators:false){tabItems(vertical:true)}).frame(maxHeight:.infinity)
            } else {
                glassSurface(tabItems(vertical:false))
                    .padding(.horizontal,12).padding(.bottom,6)
            }
        }.disabled(router.hasBlockingModal).accessibilityHidden(router.hasBlockingModal)
    }
    @ViewBuilder private func glassSurface<Content:View>(_ content:Content)->some View {
        if reduceTransparency {
            content.background(Color.cream,in:Capsule())
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0,*) {
                GlassEffectContainer {
                    content.glassEffect(.regular,in:Capsule())
                }
            } else {
                content.background(.regularMaterial,in:Capsule())
            }
            #else
            content.background(.regularMaterial,in:Capsule())
            #endif
        }
    }
    private func tabItems(vertical:Bool)->some View {
        let layout=vertical ? AnyLayout(VStackLayout(spacing:20)):AnyLayout(HStackLayout(spacing:0))
        return layout {
            ForEach(0..<5) { index in
                let target=[0,1,4,2,3][index]
                let asset=["homeOn","voiceOn","brewRatioTab","messagesOn","meOn"][index]
                let selected=store.selectedTab==target
                Button {store.selectedTab=target} label:{
                    Image(asset).resizable().scaledToFit().frame(width:30,height:30).opacity(selected ? 1:0.68)
                        .frame(width:48,height:48).background(selected ? Color.coffee.opacity(0.12):Color.clear,in:Capsule())
                        .frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle())
                }.buttonStyle(.plain).papiAccessibilityLabel(["Home","Voice","Brew calculator","Messages","Me"][index])
                    .accessibilityAddTraits(selected ? .isSelected:[]).papiAvoidReserved()
            }
        }.padding(.horizontal,10).padding(.vertical,vertical ? 12:8)
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
        content.disabled(store.notice != nil || store.accountAction != nil || store.loginInProgress).accessibilityHidden(store.notice != nil || store.accountAction != nil || store.loginInProgress).overlay {
            if store.loginInProgress {FirstCupLoadingView()}
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
