import SwiftUI
import PhotosUI

struct ProfileView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var collection=0
    var body:some View {
        PapiScreen {
            ScrollView {
                VStack(spacing:15) {
                    ZStack(alignment:.top) {
                        PapiImage(name:store.state.profile.cover).frame(height:260).clipped()
                        HStack {
                            Image("profileTitle").resizable().scaledToFit().frame(width:145,height:55)
                            Spacer()
                            PapiIconButton(asset:"edit",label:"Edit profile"){router.go(.editProfile)}
                            PapiIconButton(asset:"settings",label:store.text("Settings")){router.go(.settings)}
                        }.padding(18)
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Avatar(name:store.state.profile.avatar,size:66)
                            VStack(alignment:.leading,spacing:5) {PapiText(verbatim:store.state.profile.name).font(.title3.bold());PapiText("@"+String(store.state.profile.id.uuidString.prefix(10)).lowercased()).font(.caption).foregroundStyle(Color.mutedCoffee)}
                            Spacer()
                            if let id=store.state.displayedGift,let gift=Gift.all.first(where:{$0.id==id}) {Image(gift.asset).resizable().scaledToFit().frame(width:55,height:55).papiAccessibilityLabel(gift.name)}
                        }
                        PapiText(verbatim:store.state.profile.bio).font(.subheadline)
                        PapiText("#CoffeeLover  #BeanHunter  #CoffeeChat").font(.caption).foregroundStyle(Color.mutedCoffee)
                    }.padding(18).background(Color.cream.opacity(0.95),in:RoundedRectangle(cornerRadius:24)).padding(.horizontal,16).padding(.top,-42)
                    HStack(spacing:0) {
                        countButton(store.state.follows.count,"Following")
                        countButton(0,"Follower")
                        countButton(0,"Friends")
                    }.padding(.vertical,16).background(Color.coffee,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18)
                    HStack(spacing:12) {
                        Button {router.go(.wallet)} label:{Image("walletBanner").resizable().scaledToFit()}.papiAccessibilityLabel("My wallet")
                        Button {router.go(.level)} label:{Image("levelBanner").resizable().scaledToFit()}.papiAccessibilityLabel("My level")
                    }.buttonStyle(.plain).padding(.horizontal,18)
                    VStack(spacing:0) {
                        PapiRow(asset:"blocked",title:"Blacklist"){router.go(.blacklist)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"calendar",title:store.text("Check in")){router.sheet = .checkin}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"bag",title:"My backpack"){router.go(.backpack)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"globe",title:store.text("Language")){router.go(.language)}
                    }.background(Color.white,in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,18)
                    HStack {
                        ForEach(0..<3) {i in PapiTextButton(["Posts","Photo album","Saved"][i]){collection=i}.font(.subheadline.weight(.semibold)).padding(.vertical,10).frame(maxWidth:.infinity).background(collection==i ? Color.butter:Color.clear,in:Capsule())}
                    }.buttonStyle(.plain).padding(.horizontal,16)
                    if collection==1 {
                        if store.state.profile.photos.isEmpty {PapiEmpty(title:"No album photos yet",detail:"Add a photo from Edit Profile.")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                            ForEach(store.state.profile.photos,id:\.self) {name in Button{router.go(.photo(name))} label:{PapiImage(name:name).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)}
                        }.padding(.horizontal,18)
                    } else {
                        let posts=collection==0 ? store.state.localPosts:store.visiblePosts.filter{store.state.bookmarks.contains($0.id)}
                        if posts.isEmpty {PapiEmpty(title:collection==0 ? "Your coffee journal is waiting":"No saved moments",detail:collection==0 ? "Use the plus button on Home to save your first local post.":"Save a moment from its detail page to find it here.")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:12) {ForEach(posts){post in PostTile(post:post,height:210)}}.padding(.horizontal,18)
                    }
                }.padding(.bottom,24).frame(maxWidth:820).frame(maxWidth:.infinity)
            }
        }
    }
    private func countButton(_ count:Int,_ title:String)->some View {
        Button {router.go(.relationships(["Following","Follower","Friends"].firstIndex(of:title) ?? 0))} label:{VStack(spacing:4){PapiText("\(count)").font(.headline);PapiText(title).font(.caption)}}.buttonStyle(.plain).frame(maxWidth:.infinity).foregroundStyle(Color.cream)
    }
}
struct EditProfileView:View {
    @EnvironmentObject private var store:PapiStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile=LocalProfile()
    @State private var initialized=false
    @State private var picker:PhotosPickerItem?
    @State private var target="cover"
    @State private var showPicker=false
    @State private var importing=false
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Edit Profile")
                ScrollView {
                    VStack(spacing:18) {
                        PapiImage(name:profile.cover).frame(height:210).clipped().clipShape(RoundedRectangle(cornerRadius:20))
                        HStack {pickButton("Change background",kind:"cover");Spacer();pickButton("Change avatar",kind:"avatar")}
                        HStack {Avatar(name:profile.avatar,size:64);PapiText("Your local profile").font(.headline);Spacer()}
                        VStack(alignment:.leading,spacing:8) {
                            PapiText("Name").font(.caption.weight(.semibold));PapiTextField(prompt:"Please enter the name…",text:$profile.name)
                            PapiText("About you").font(.caption.weight(.semibold));PapiTextField(prompt:"All good things start with coffee.",text:$profile.bio)
                        }
                        HStack {PapiText("Photo album").font(.headline);Spacer();pickButton("Add photo",kind:"album")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:95),spacing:10)],spacing:10) {
                            ForEach(profile.photos,id:\.self) {name in
                                ZStack(alignment:.topTrailing){PapiImage(name:name).frame(height:120).clipped().clipShape(RoundedRectangle(cornerRadius:12));PapiIconButton(asset:"close",label:"Remove album photo",size:24){profile.photos.removeAll{$0==name}}}
                            }
                        }
                        if importing {PapiText("Importing photo…").font(.caption)}
                        PapiTextButton(store.text("Save")) {
                            let name=profile.name.trimmingCharacters(in:.whitespacesAndNewlines)
                            guard !name.isEmpty,name.count<=40,profile.bio.count<=300 else {store.inform("Check your profile","Use a name of 1–40 characters and a bio under 300 characters.");return}
                            guard profile.id==store.state.profile.id else {store.inform("Guest changed","Reopen this page to edit the current guest.");return}
                            profile.name=name
                            if store.commit({$0.profile=profile}) {dismiss()}
                        }.buttonStyle(PapiButtonStyle()).disabled(importing)
                        PapiText("Changes are saved only when you tap Save.").font(.caption).foregroundStyle(Color.mutedCoffee)
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }.photosPicker(isPresented:$showPicker,selection:$picker,matching:.images)
            .onAppear{if !initialized {profile=store.state.profile;initialized=true}}
            .onChange(of:picker){_,item in if let item {let destination=target;Task {await importPhoto(item,destination:destination)}}}
    }
    private func pickButton(_ label:String,kind:String)->some View {
        Button {target=kind;picker=nil;showPicker=true} label:{PapiText(label).font(.subheadline.weight(.medium)).padding(.vertical,8)}.buttonStyle(.plain).disabled(importing)
    }
    @MainActor private func importPhoto(_ item:PhotosPickerItem,destination:String) async {
        importing=true;defer{importing=false}
        do {
            guard let data=try await item.loadTransferable(type:Data.self) else {throw MediaFiles.MediaError.invalid}
            guard store.state.signedIn,store.state.profile.id==profile.id else{return}
            let name=try MediaFiles.saveImage(data,guest:profile.id)
            switch destination {case "avatar":profile.avatar=name;case "album":profile.photos.append(name);default:profile.cover=name}
        } catch {store.inform("Could not import photo",error.localizedDescription)}
    }
}
struct RelationshipsView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var selected:Int
    init(initialTab:Int=0) {_selected=State(initialValue:initialTab)}
    var body:some View {
        PapiScreen {VStack(spacing:12){
            PapiHeader("Connections")
            HStack {ForEach(0..<3){i in PapiTextButton(["Following","Follower","Friends"][i]){selected=i}.padding(10).frame(maxWidth:.infinity).background(selected==i ? Color.butter:.clear,in:Capsule())}}.buttonStyle(.plain).padding(.horizontal,16)
            ScrollView {
                if selected==0 {
                    let people=Person.previews.filter{store.state.follows.contains($0.id) && !store.state.blocked.contains($0.id)}
                    if people.isEmpty {PapiEmpty(title:"No following yet",detail:"Follow a preview profile to keep it in your local list.")}
                    ForEach(people){person in
                        HStack {Button {router.go(.person(person.id))} label:{HStack {Avatar(name:person.portrait);PapiText(verbatim:person.name)}}.buttonStyle(.plain);Spacer();PapiIconButton(asset:"comment",label:"Open chat"){router.go(.chat(person.id))}}.padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:14)).padding(.horizontal,16)
                    }
                } else {PapiEmpty(title:selected==1 ? "No followers":"No mutual connections",detail:"Preview profiles do not automatically follow you. Real connections require a connected community service.")}
            }
        }}
    }
}
struct BlacklistView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    var body:some View {
        PapiScreen {VStack {
            PapiHeader("Blacklist")
            ScrollView {
                if store.state.blocked.isEmpty {PapiEmpty(title:"Your blacklist is empty")}
                ForEach(store.state.blocked.sorted(),id:\.self){id in
                    let person=Person.find(id)
                    HStack {Avatar(name:person?.portrait ?? "brandMark");PapiText(person?.name ?? "Hidden profile");Spacer();PapiIconButton(asset:"trash",label:"Unblock"){store.unblock(id)}}.padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:15)).padding(.horizontal,18).padding(.bottom,8)
                }
            }
        }}
    }
}
struct SettingsView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @EnvironmentObject private var commerce:PapiCommerce
    @State private var confirmation:String?
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Settings"))
                ScrollView {
                    VStack(spacing:12) {
                        row("Blacklist",.blacklist);row(store.text("Privacy Policy"),.legal("privacy"));row(store.text("User Agreement"),.legal("terms"))
                        PapiRow(title:"Delete local guest"){confirmation="delete"}.background(Color.white,in:RoundedRectangle(cornerRadius:14))
                        PapiRow(title:store.text("Log Out")){confirmation="logout"}.background(Color.white,in:RoundedRectangle(cornerRadius:14))
                        row(store.text("Language"),.language)
                        PapiRow(title:"Notifications",subtitle:store.state.notificationPreference ? "Local preference: on":"Local preference: off") {
                            if store.commit({$0.notificationPreference.toggle()}) {store.inform("Preference saved","No push notification service is connected. This preference is stored for this guest only.")}
                        }.background(Color.white,in:RoundedRectangle(cornerRadius:14))
                        PapiPanel {
                            VStack(alignment:.leading,spacing:10) {
                                PapiText("Local guest").font(.headline)
                                PapiText("Your profile, journal, coins and gift collection stay on this device. Preview profiles cannot send messages, join audio or receive gifts. No account is created on a server.").font(.subheadline)
                                PapiText("Papi 1.0 · Original coffee-community design").font(.caption).foregroundStyle(Color.mutedCoffee)
                            }
                        }
                        if !store.storageAvailable {PapiTextButton("Retry local storage"){store.reload()}.buttonStyle(PapiButtonStyle())}
                    }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
                }
            }.overlay {
                if let confirmation {
                    PapiDialog(title:confirmation=="delete" ? "Delete this local guest?":"Log out?",
                               message:confirmation=="delete" ? "This removes your local profile, posts, media, coins and gifts. Purchase identifiers are retained only to protect ownership and prevent duplicate delivery. This cannot be undone.":"Your local data stays on this device. One-tap login will reopen the same guest.",
                               confirm:confirmation=="delete" ? "Delete local data":"Log out",cancel:"Cancel",action:{
                        self.confirmation=nil
                        if commerce.busy || commerce.unresolved {store.inform("Purchase recovery active","Resolve the purchase before changing this local guest.");return}
                        if confirmation=="delete" {store.deleteGuest()} else {store.logout()}
                    },dismiss:{self.confirmation=nil})
                }
            }
        }
    }
    private func row(_ title:String,_ route:PapiRoute)->some View {PapiRow(title:title){router.go(route)}.background(Color.white,in:RoundedRectangle(cornerRadius:14))}
}
struct LanguageView:View {
    @EnvironmentObject private var store:PapiStore
    @State private var pending:String?
    var body:some View {
        PapiScreen {VStack(spacing:14) {
            PapiHeader(store.text("Language"))
            ScrollView {
                VStack(spacing:12) {
                    ForEach(PapiStrings.languages,id:\.id) {language in
                        Button {pending=language.id} label:{HStack {PapiText(language.name);Spacer();if store.state.language==language.id {Image("check").resizable().scaledToFit().frame(width:18,height:18)}}.padding(19).frame(maxWidth:.infinity).background(store.state.language==language.id ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)
                    }
                    PapiText("App controls follow your selected language. Your writing and original artwork keep their original language.").font(.caption).foregroundStyle(Color.mutedCoffee).padding(.vertical,14)
                }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
            }
        }.overlay {
            if let pending {PapiDialog(title:"Change language?",message:"Your drafts and current guest will stay the same.",confirm:"Confirm",cancel:"Cancel",action:{_ = store.commit{$0.language=pending};self.pending=nil},dismiss:{self.pending=nil})}
        }}
    }
}
struct LegalView:View {
    var type:String
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader(type=="privacy" ? "Privacy Policy":"User Agreement")
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    PapiText("Papi · Local edition").font(.title2.bold())
                    PapiText("Updated 21 October 2026").font(.caption).foregroundStyle(Color.mutedCoffee)
                    if type=="privacy" {
                        section("Your data stays with you","Papi creates a guest identifier on this device. Profile details, follows, local notes, check-ins, wallet records, drafts and gift collections are kept in device-protected storage. Selected photos and videos are copied to the app's private media folder.")
                        section("Photos, camera and microphone","Papi accesses a photo or video when you choose it in Apple's picker. Camera or microphone access is requested only for a feature you explicitly start. Preview voice rooms do not connect to live audio.")
                        section("No community server","This edition does not upload posts, send chat messages, submit reports to a moderation team or transmit gifts. Supplied content and member profiles are previews. No advertising or analytics SDK is included.")
                        section("Purchases","Purchases are disabled until products are configured. If enabled in a future configuration, Apple handles payment and Papi stores transaction identifiers and the original guest token for delivery and recovery. Papi does not receive your payment card details.")
                        section("Deletion and local storage","Log out keeps your data. Delete local guest removes the local profile and its media. Minimal guest and transaction ownership records remain to prevent a future guest from claiming old purchases. Data does not sync to other devices; the app cannot recover local media lost on uninstall.")
                        section("Support","A public support contact has not been configured for this development edition. This document must be reviewed and a valid support channel supplied before public distribution.")
                    } else {
                        section("One-tap local access","By continuing, you create or reopen a local guest in Papi. This is not server authentication and does not create an online community account.")
                        section("Your coffee journal","You may select your own photos and videos, write notes, follow preview profiles, and save local posts. Only use media you are entitled to use. No content is publicly published by this edition.")
                        section("Coins and gifts","Daily check-ins provide local coins. Saving a post costs 10 coins. Collecting gifts uses the displayed coin amount and adds items to your local backpack. Gift previews are not remote transfers and spend no coins. Collected gifts can be displayed on your profile.")
                        section("Respectful content","Do not use the app to create or distribute abusive, exploitative, hateful or unlawful content. Block and report controls are available; reports are local records until a real moderation channel is connected.")
                        section("Availability and data","Preview rooms and people do not represent online availability. Remote chat and live voice are not active. Local guest data is device-bound, and deleting a guest removes its usable balance and collection.")
                        section("Development edition","Purchase products, real-time services and a public support contact still require configuration before this app is distributed as an online service.")
                    }
                }.padding(24).frame(maxWidth:700).frame(maxWidth:.infinity,alignment:.leading)
            }
        }}
    }
    private func section(_ title:String,_ body:String)->some View {VStack(alignment:.leading,spacing:8){PapiText(title).font(.headline);PapiText(body).font(.body).lineSpacing(4)}}
}
