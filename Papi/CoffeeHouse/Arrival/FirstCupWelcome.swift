import SwiftUI

struct FirstCupWelcomeView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var page=0
    @State private var legal:String?
    var body:some View {
        ZStack {
            if !store.state.sawOnboarding {
                TabView(selection:$page) {
                    ForEach(0..<3) { index in
                        PapiBackground(asset:["onboardingPour","onboardingChill","onboardingRoast"][index]).tag(index)
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never)).ignoresSafeArea(.container)
                VStack {
                    HStack {Spacer();PapiTextButton(store.text("Skip")) {finishIntro()}.font(CoffeeType.face(.subheadline,weight:.bold)).padding(12).background(Color.cream.opacity(0.9),in:Capsule())}.padding(20)
                    Spacer()
                    HStack {
                        PapiText("\(page+1) / 3").font(CoffeeType.face(.subheadline,weight:.bold)).foregroundStyle(.white).padding(12).background(Color.coffee.opacity(0.7),in:Capsule())
                        Spacer()
                        Button {
                            if page<2 {withAnimation(.easeInOut(duration:0.2)){page+=1}} else {finishIntro()}
                        } label:{Image("onboardNext").resizable().scaledToFit().frame(width:72,height:44)}.papiAccessibilityLabel(store.text("Next"))
                    }.padding(24).papiAvoidReserved()
                }
            } else {
                PapiBackground(asset:"welcomeBackground")
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing:0) {
                            HStack {
                                PapiIconButton(asset:"back",label:"Back") {_ = store.commit{$0.sawOnboarding=false}}
                                Spacer()
                                PapiText("Papi").font(CoffeeType.display(size:23,weight:.bold))
                            }.foregroundStyle(Color.coffee).padding(.horizontal,16).frame(minHeight:52).papiAvoidReserved()
                            Color.clear.frame(height:max(120,proxy.size.height*0.72-52))
                            PapiTextButton(store.text("Log in")) {store.login()}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:12)).frame(maxWidth:.infinity)
                                .disabled(!store.storageAvailable).padding(.horizontal,16)
                            PapiText("Your recipes, coffee moments and tasting notes, kept together.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).padding(.top,10).padding(.horizontal,20).multilineTextAlignment(.center)
                            if !store.storageAvailable {PapiTextButton("Retry local storage"){store.reload()}.buttonStyle(PapiButtonStyle(light:true))}
                            Spacer(minLength:30)
                            VStack(spacing:4) {
                                PapiText(store.text("By continuing, you agree to our")).font(CoffeeType.face(.caption))
                                PapiActionGroup {
                                    PapiTextButton(store.text("User Agreement")){legal="terms"}.frame(minHeight:44)
                                    PapiTextButton(store.text("Privacy Policy")){legal="privacy"}.frame(minHeight:44)
                                }.font(CoffeeType.face(.caption,weight:.medium))
                            }.foregroundStyle(Color.mutedCoffee).padding(.bottom,20)
                        }.frame(maxWidth:520).frame(minHeight:proxy.size.height).frame(maxWidth:.infinity)
                    }
                }
            }
        }.safeAreaInset(edge:.bottom) {
            if !store.storageAvailable && !store.state.sawOnboarding {PapiTextButton("Retry local storage"){store.reload()}.buttonStyle(PapiButtonStyle(light:true,wide:true)).padding(16).background(Color.cream)}
        }.sheet(isPresented:Binding(get:{legal != nil},set:{if !$0 {legal=nil}})) {
            PapiDeviceContainer {NavigationStack {LegalView(type:legal ?? "privacy")}}
                .presentationBackground {PapiBackground()}.presentationDragIndicator(.hidden).interactiveDismissDisabled(router.hasBlockingModal)
        }
    }
    private func finishIntro(){_ = store.commit{$0.sawOnboarding=true}}
}
