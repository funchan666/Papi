import SwiftUI
import PhotosUI

struct MyCoffeePassportView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var collection=0
    var body:some View {
        PapiScreen {
            ScrollView {
                VStack(spacing:15) {
                    ZStack(alignment:.top) {
                        PapiImage(name:store.state.passport.cover).frame(height:260).clipped()
                        HStack {
                            Image("profileTitle").resizable().scaledToFit().frame(maxWidth:145).frame(height:55)
                            Spacer()
                            PapiIconButton(asset:"edit",label:"Edit profile"){router.go(.editProfile)}.background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:12))
                            PapiIconButton(asset:"settings",label:store.text("Settings")){router.go(.settings)}.background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:12))
                        }.padding(18).papiAvoidReserved()
                    }
                    VStack(alignment:.leading,spacing:12) {
                        HStack {
                            Avatar(name:store.state.passport.avatar,size:66)
                            VStack(alignment:.leading,spacing:5) {PapiText(verbatim:store.state.passport.name).font(CoffeeType.face(.title3,weight:.bold));PapiText("Your coffee passport").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                            Spacer()
                            if let id=store.state.displayedGift,let gift=CoffeeCollectible.all.first(where:{$0.id==id}) {Image(gift.asset).resizable().scaledToFit().frame(width:55,height:55).papiAccessibilityLabel(gift.name)}
                        }
                        PapiText(verbatim:store.state.passport.bio).font(CoffeeType.face(.subheadline))
                        PapiText("\(store.brewBook.cups.count) cups in your book").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    }.padding(18).background(Color.cream.opacity(0.95),in:RoundedRectangle(cornerRadius:24)).padding(.horizontal,16).padding(.top,-42)
                    HStack(spacing:0) {
                        countButton(store.state.followedMembers.filter{!store.isUserHidden($0)}.count,"Following")
                        countButton(store.followers.count,"Follower")
                        countButton(store.friends.count,"Friends")
                    }.padding(.vertical,16).background(Color.coffee,in:RoundedRectangle(cornerRadius:12)).padding(.horizontal,18)
                    HStack(spacing:12) {
                        Button {router.go(.wallet)} label:{Image("walletBanner").resizable().scaledToFit()}.papiAccessibilityLabel("My wallet")
                        Button {router.go(.level)} label:{Image("levelBanner").resizable().scaledToFit()}.papiAccessibilityLabel("My level")
                    }.buttonStyle(.plain).padding(.horizontal,18)
                    VStack(spacing:0) {
                        PapiRow(asset:"brewDripper",title:"My brew book"){router.go(.brewArchive)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"voiceOn",title:"Coffee tables"){router.go(.tables)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"blocked",title:"Blacklist"){router.go(.blacklist)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"calendar",title:store.text("Check in")){router.sheet = .checkin}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"bag",title:"My backpack"){router.go(.backpack)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"globe",title:store.text("Language")){router.go(.language)}
                        Divider().padding(.leading,52)
                        PapiRow(asset:"coffeeUpdates",title:"My submissions"){router.go(.reviewQueue)}
                    }.background(Color.white,in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,18)
                    HStack {
                        ForEach(0..<3) {i in PapiTextButton(["Posts","Photo album","Saved"][i]){collection=i}.font(CoffeeType.face(.subheadline,weight:.semibold)).padding(.vertical,10).frame(maxWidth:.infinity).background(collection==i ? Color.butter:Color.clear,in:Capsule())}
                    }.buttonStyle(.plain).padding(.horizontal,16)
                    if collection==1 {
                        if store.state.passport.photos.isEmpty {PapiEmpty(title:"No album photos yet",detail:"Add a photo from Edit Profile.")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                            ForEach(store.state.passport.photos,id:\.self) {name in Button{router.go(.photo(name))} label:{PapiImage(name:name).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)}
                        }.padding(.horizontal,18)
                    } else {
                        let posts=collection==0 ? store.visiblePosts.filter{$0.authorID==store.state.passport.id.uuidString}:store.visiblePosts.filter{store.state.keptMoments.contains($0.id)}
                        if posts.isEmpty {PapiEmpty(title:collection==0 ? "Your coffee journal is waiting":"No saved moments",detail:collection==0 ? "Use the plus button on Home to keep your first coffee moment.":"Save a moment from its detail page to find it here.")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:12) {ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}}.padding(.horizontal,18)
                    }
                }.padding(.bottom,24).frame(maxWidth:820).frame(maxWidth:.infinity)
            }
        }
    }
    private func countButton(_ count:Int,_ title:String)->some View {
        Button {router.go(.relationships(["Following","Follower","Friends"].firstIndex(of:title) ?? 0))} label:{VStack(spacing:4){PapiText("\(count)").font(CoffeeType.face(.headline));PapiText(title).font(CoffeeType.face(.caption))}}.buttonStyle(.plain).frame(maxWidth:.infinity).foregroundStyle(Color.cream)
    }
}
struct EditCoffeePassportView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @State private var passport=CoffeePassport()
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
                        PapiImage(name:passport.cover).frame(height:210).clipped().clipShape(RoundedRectangle(cornerRadius:20))
                        PapiActionGroup {pickButton("Change background",kind:"cover");pickButton("Change avatar",kind:"avatar")}
                        HStack {Avatar(name:passport.avatar,size:64);PapiText("Your coffee passport").font(CoffeeType.face(.headline));Spacer()}
                        VStack(alignment:.leading,spacing:8) {
                            PapiText("Name").font(CoffeeType.face(.caption,weight:.semibold));PapiTextField(prompt:"Please enter the name…",text:$passport.name)
                            PapiText("About you").font(CoffeeType.face(.caption,weight:.semibold));PapiTextField(prompt:"Keeping the cups I want to brew again.",text:$passport.bio)
                        }
                        HStack {PapiText("Photo album").font(CoffeeType.face(.headline));Spacer();pickButton("Add photo",kind:"album")}
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:95),spacing:10)],spacing:10) {
                            ForEach(passport.photos,id:\.self) {name in
                                ZStack(alignment:.topTrailing){PapiImage(name:name).frame(height:120).clipped().clipShape(RoundedRectangle(cornerRadius:12));PapiIconButton(asset:"close",label:"Remove album photo",size:24){passport.photos.removeAll{$0==name}}}
                            }
                        }
                        if importing {PapiText("Importing photo…").font(CoffeeType.face(.caption))}
                        PapiTextButton(store.text("Save")) {
                            let name=passport.name.trimmingCharacters(in:.whitespacesAndNewlines)
                            guard !name.isEmpty,name.count<=40,passport.bio.count<=300 else {store.inform("Check your profile","Use a name of 1–40 characters and a bio under 300 characters.");return}
                            guard store.validateCommunityText(name+" "+passport.bio) else{return}
                            guard passport.id==store.state.passport.id else {store.inform("Account changed","Reopen this page to edit the current coffee account.");return}
                            passport.name=name
                            if store.commit({$0.passport=passport}) {dismiss()}
                        }.buttonStyle(PapiButtonStyle()).disabled(importing)
                        PapiText("Tap Save to keep these changes.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }.photosPicker(isPresented:$showPicker,selection:$picker,matching:.images)
            .onAppear{if !initialized {passport=store.state.passport;initialized=true}}
            .onChange(of:picker){_,item in if let item {let destination=target;Task {await importPhoto(item,destination:destination)}}}
    }
    private func pickButton(_ label:String,kind:String)->some View {
        Button {target=kind;picker=nil;showPicker=true} label:{PapiText(label).font(CoffeeType.face(.subheadline,weight:.medium)).padding(.vertical,8).frame(minHeight:44)}.buttonStyle(.plain).disabled(importing)
    }
    @MainActor private func importPhoto(_ item:PhotosPickerItem,destination:String) async {
        importing=true;defer{importing=false}
        do {
            guard let data=try await item.loadTransferable(type:Data.self) else {throw CoffeeMedia.MediaError.invalid}
            guard store.state.signedIn,store.state.passport.id==passport.id else{return}
            let name=try CoffeeMedia.saveImage(data,guest:passport.id)
            switch destination {case "avatar":passport.avatar=name;case "album":passport.photos.append(name);default:passport.cover=name}
        } catch {store.inform("Could not import photo",error.localizedDescription)}
    }
}
struct RelationshipsView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @State private var selected:Int
    init(initialTab:Int=0) {_selected=State(initialValue:initialTab)}
    var body:some View {
        PapiScreen {VStack(spacing:12){
            PapiHeader("Connections")
            HStack {ForEach(0..<3){i in PapiTextButton(["Following","Follower","Friends"][i]){selected=i}.padding(10).frame(maxWidth:.infinity).background(selected==i ? Color.butter:.clear,in:Capsule())}}.buttonStyle(.plain).padding(.horizontal,16)
            ScrollView {
                    let following=store.state.followedMembers.sorted().compactMap{store.person($0)}.filter{!store.isUserHidden($0.id)}
                    let people=selected==0 ? following:(selected==1 ? store.followers:store.friends)
                    if people.isEmpty {PapiEmpty(title:selected==0 ? "No following yet":(selected==1 ? "No followers":"No mutual connections"),detail:"No relationships are created automatically. Friendship needs the other person's acceptance.")}
                    ForEach(people){person in
                        HStack {Button {router.go(.person(person.id))} label:{HStack {Avatar(name:person.portrait);PapiText(verbatim:person.name)}}.buttonStyle(.plain);Spacer();PapiIconButton(asset:"comment",label:"Open chat"){router.go(.chat(person.id))}}.padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:14)).padding(.horizontal,16)
                    }
            }
        }}
    }
}
struct BlacklistView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {VStack {
            PapiHeader("Blacklist")
            ScrollView {
                if store.state.blockedMembers.isEmpty {PapiEmpty(title:"Your blacklist is empty")}
                ForEach(store.state.blockedMembers.sorted(),id:\.self){id in
                    let person=store.person(id)
                    HStack {Avatar(name:person?.portrait ?? "brandMark");PapiText(verbatim:person?.name ?? "Hidden profile");Spacer();PapiTextButton("Unblock"){store.unblock(id)}.font(CoffeeType.face(.caption,weight:.bold)).padding(10).frame(minHeight:44).background(Color.butter,in:Capsule())}.padding(16).background(Color.white,in:RoundedRectangle(cornerRadius:15)).padding(.horizontal,18).padding(.bottom,8)
                }
            }
        }}
    }
}
struct CoffeePreferencesView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @EnvironmentObject private var commerce:AppleCoinCounter
    @State private var confirmation:String?
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(store.text("Settings"))
                ScrollView {
                    VStack(spacing:12) {
                        row("Blacklist",.blacklist);row(store.text("Privacy Policy"),.legal("privacy"));row(store.text("User Agreement"),.legal("terms"))
                        row("Community Guidelines",.legal("community"))
                        PapiRow(title:"Delete account"){confirmation="delete"}.background(Color.white,in:RoundedRectangle(cornerRadius:14))
                        PapiRow(title:store.text("Log Out")){confirmation="logout"}.background(Color.white,in:RoundedRectangle(cornerRadius:14))
                        row(store.text("Language"),.language)
                        PapiPanel {
                            VStack(alignment:.leading,spacing:10) {
                                PapiText("Your coffee account").font(CoffeeType.face(.headline))
                                PapiText("Your coffee account, brew book and balance are stored on this device. Community sharing is not connected. Collection portraits are not available chat contacts.").font(CoffeeType.face(.subheadline))
                                PapiText("Papi 1.0 · Brew, taste, remember").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }
                        }
                        if !store.storageAvailable {PapiTextButton("Retry local storage"){store.reload()}.buttonStyle(PapiButtonStyle())}
                    }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
                }
            }.overlay {
                if let confirmation {
                    PapiDialog(title:confirmation=="delete" ? "Delete this coffee account?":"Log out?",
                               message:confirmation=="delete" ? "This removes your passport, brew book, recipes, moments, media, coins and keepsakes. Purchase ownership records are retained to prevent duplicate delivery. This cannot be undone.":"Your coffee book stays on this device. One-tap login reopens this account.",
                               confirm:confirmation=="delete" ? "Delete local data":"Log out",cancel:"Cancel",action:{
                        self.confirmation=nil
                        if commerce.busy || commerce.unresolved {store.inform("Purchase recovery active","Resolve the purchase before changing this local guest.");return}
                        Task {await store.performAccountAction(confirmation=="delete" ? .delete:.logout)}
                    },dismiss:{self.confirmation=nil})
                }
            }
        }
    }
    private func row(_ title:String,_ route:CoffeeDestination)->some View {PapiRow(title:title){router.go(route)}.background(Color.white,in:RoundedRectangle(cornerRadius:14))}
}
struct LanguageView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @State private var pending:String?
    var body:some View {
        PapiScreen {VStack(spacing:14) {
            PapiHeader(store.text("Language"))
            ScrollView {
                VStack(spacing:12) {
                    ForEach(PapiStrings.languages,id:\.id) {language in
                        Button {pending=language.id} label:{HStack {PapiText(language.name);Spacer();if store.state.language==language.id {Image("check").resizable().scaledToFit().frame(width:18,height:18)}}.padding(19).frame(maxWidth:.infinity).background(store.state.language==language.id ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)
                    }
                    PapiText("App controls follow your selected language. Your writing and original artwork keep their original language.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).padding(.vertical,14)
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
            PapiHeader(type=="privacy" ? "Privacy Policy":(type=="community" ? "Community Guidelines":"User Agreement"))
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    PapiText("Papi · Your coffee book").font(CoffeeType.face(.title2,weight:.bold))
                    PapiText("Updated 22 October 2026").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    if type=="privacy" {
                        section("Your data stays with you","Papi creates a guest identifier on this device. Profile details, message history, follows, local notes, reports, review submissions, check-ins, wallet records, drafts and gift collections are kept in device-protected storage. Selected photos and videos are copied to the app's private media folder.")
                        section("Photos, camera and microphone","Papi accesses a photo or video when you choose it in Apple's picker. Camera or microphone access is requested only for a feature you explicitly start. Preview voice rooms do not connect to live audio.")
                        section("No community server","This edition does not upload posts, send chat messages, submit reports to a moderation team or transmit gifts. Supplied content and member profiles are previews. No advertising or analytics SDK is included.")
                        section("Purchases","Apple handles payments through its own confirmation sheet. Papi stores transaction identifiers, the original local owner and the coin amount for delivery and recovery. Product details are requested only when you tap Buy. Papi does not receive your payment card details.")
                        section("Deletion and local storage","Log out keeps your data. Delete local guest removes the local profile and its media. Minimal guest and transaction ownership records remain to prevent a future guest from claiming old purchases. Data does not sync to other devices; the app cannot recover local media lost on uninstall.")
                        section("Support","A public support contact has not been configured for this development edition. This document must be reviewed and a valid support channel supplied before public distribution.")
                    } else if type=="terms" {
                        section("Your coffee account","Continuing opens your coffee passport on this device. It does not create an online community account.")
                        section("Your coffee journal","You may select your own photos and videos, write notes, follow preview profiles, and save local posts. Only use media you are entitled to use. No content is publicly published by this edition.")
                        section("Coins and gifts","A new local guest receives 800 welcome coins once. Daily check-ins also provide coins. Saving a photo submission costs 40 coins; a video submission costs 80. This saves a private review entry and does not buy approval or public visibility. Optional backpack gifts cost the displayed amount. Gift previews and displaying owned gifts are free. Chat, photos in chat, voice messages and video calls never cost coins.")
                        section("Brewing and tasting","The morning cone and quiet immersion recipes are included. Optional recipes unlock once for 120, 180 or 240 coins, as shown before confirmation. Reusing recipes, brew records and two-cup tastings are free. Unlocked recipes and notes belong to this device account and are removed when it is deleted. Recipe timings are guidance, and tasting scores are your own impressions.")
                        section("Respectful content","Do not use the app to create or distribute abusive, exploitative, hateful or unlawful content. Block and report controls are available; reports are local records until a real moderation channel is connected.")
                        section("Chat and review","Both people must choose to follow each other before messaging or video-call actions. Friendship requires the other person's acceptance. New posts remain private until approved. This local edition stores messages and submissions on your device without remote delivery or automatic approval.")
                        section("Availability and data","Preview rooms and people do not represent online availability. Remote chat and live voice are not active. Local guest data is device-bound, and deleting a guest removes its usable balance and collection.")
                        section("Community connections","Purchases require products configured for this app in App Store Connect. The Apple sheet provides the final local price. Real-time community services and a public support contact still need configuration before online distribution. Coins stay with this device's guest and cannot be transferred or redeemed for cash.")
                    } else {
                        section("A welcoming coffee table","Share coffee rituals, café discoveries and thoughtful conversation. Respect different cultures, preferences and brewing experience. Do not harass, threaten, bully, discriminate against or shame another person.")
                        section("Keep the community safe","Pornography, sexual exploitation, child endangerment, hateful content, graphic violence, illegal activity and threats are prohibited. Do not publish another person's private information or intimate media without consent.")
                        section("Real consent, real connections","Chat messages and video-call actions require mutual following. Friendship requires the other person's acceptance. Do not impersonate someone, create fake relationships or use Papi for random or anonymous chat. You may withdraw a follow at any time.")
                        section("Share only what is yours","Post only photos, videos, audio and text you have the right to share. Get permission from identifiable people. Avoid scams, spam, misleading promotions and dangerous advice. Never pressure someone to send money or gifts.")
                        section("Review before visibility","New posts remain private until approved. In this local edition, submissions wait on your device until a moderation service is connected. There is no automatic approval or fabricated moderator response.")
                        section("Report and control your space","Use the safety menu on a profile, post, comment, message or room. Choose a report reason and confirm. Saved reports hide the item immediately on this device. Blocking a user hides their profile, posts, comments, rooms and chats. Manage blocks in Settings; unblocking never restores follows or friendship automatically.")
                        section("Camera and microphone consent","Camera preview starts only after you choose it and grant camera and microphone access. This local edition does not connect a call or send your camera or microphone to another person. Stop preview or leave the page to stop capture.")
                        section("Moderation and support","A live community must provide content filtering, timely handling of reports and a published way to contact its operator. These services and a public support contact are not connected in this local edition. Local hiding is not a substitute for server moderation; online sharing stays unavailable until those services are ready.")
                    }
                }.padding(24).frame(maxWidth:700).frame(maxWidth:.infinity,alignment:.leading)
            }
        }}
    }
    private func section(_ title:String,_ body:String)->some View {VStack(alignment:.leading,spacing:8){PapiText(title).font(CoffeeType.face(.headline));PapiText(body).font(CoffeeType.face(.body)).lineSpacing(4)}}
}
