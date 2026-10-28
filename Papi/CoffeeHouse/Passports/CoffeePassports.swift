import SwiftUI
import PhotosUI
import WebKit

struct MyCoffeePassportView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var collection=0
    var body:some View {
        PapiScreen {
            GeometryReader {container in
                let topInset=container.safeAreaInsets.top
                let coverHeight=min(320,max(220,container.size.width*0.56))
                ScrollView {
                    VStack(spacing:0) {
                        ZStack(alignment:.top) {
                            PapiImage(name:store.visiblePassport.cover)
                                .frame(width:container.size.width,height:coverHeight+topInset).clipped()
                            HStack {
                                Image("profileTitle").resizable().scaledToFit().frame(maxWidth:145).frame(height:55)
                                Spacer()
                                PapiIconButton(asset:"edit",label:"Edit profile"){router.go(.editProfile)}.background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:12))
                                PapiIconButton(asset:"settings",label:store.text("Settings")){router.go(.settings)}.background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:12))
                            }.padding(18).padding(.top,topInset).frame(maxWidth:820).papiAvoidReserved()
                        }.frame(height:coverHeight+topInset)
                        VStack(spacing:16) {
                            VStack(alignment:.leading,spacing:14) {
                                HStack(alignment:.center,spacing:12) {
                                    Button {router.go(.editProfile)} label:{Avatar(name:store.visiblePassport.portraitReference,size:72)}
                                        .buttonStyle(.plain).papiAccessibilityLabel("Change avatar")
                                    VStack(alignment:.leading,spacing:5) {
                                        PapiText(verbatim:store.visiblePassport.name).font(CoffeeType.face(.title3,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                        PapiText("Your coffee passport").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    if let id=store.state.displayedGift,(store.collectedItems[id] ?? 0)>0,let gift=CoffeeCollectible.all.first(where:{$0.id==id}) {Image(gift.asset).resizable().scaledToFit().frame(width:44,height:44).papiAccessibilityLabel(gift.name)}
                                }
                                PapiText(verbatim:store.visiblePassport.bio).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                                PapiText("\(store.brewBook.cups.count) cups in your book").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }.padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Color.cream,in:RoundedRectangle(cornerRadius:24)).padding(.top,-28)
                            if store.usesCloudWallet && store.cloudProfiles==nil {
                                PapiTextButton("Retry members"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                            } else {HStack(spacing:0) {
                                countButton(store.followingIDs.filter{!store.isUserHidden($0)}.count,"Following")
                                countButton(store.followers.count,"Follower")
                                countButton(store.friends.count,"Friends")
                            }.padding(.vertical,14).background(Color.coffee,in:RoundedRectangle(cornerRadius:18))}
                            HStack(spacing:12) {
                                Button {router.go(.wallet)} label:{Image("walletBanner").resizable().scaledToFit().frame(maxWidth:.infinity)}.papiAccessibilityLabel("My wallet")
                                Button {router.go(.level)} label:{Image("levelBanner").resizable().scaledToFit().frame(maxWidth:.infinity)}.papiAccessibilityLabel("My level")
                            }.buttonStyle(.plain)
                            VStack(alignment:.leading,spacing:10) {
                                PapiText("Your coffee spaces").font(CoffeeType.face(.headline)).padding(.horizontal,4)
                                VStack(spacing:0) {
                                    PapiRow(asset:"brewDripper",title:"Brew bench"){router.go(.brewBench)}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"brewDripper",title:"My brew book"){router.go(.brewArchive)}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"voiceOn",title:"Coffee tables"){router.go(.tables)}
                                }.background(Color.white.opacity(0.94),in:RoundedRectangle(cornerRadius:18))
                                PapiText("Your account").font(CoffeeType.face(.headline)).padding(.horizontal,4).padding(.top,6)
                                VStack(spacing:0) {
                                    PapiRow(asset:"calendar",title:store.text("Check in")){router.sheet = .checkin}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"bag",title:"My backpack"){router.go(.backpack)}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"coffeeUpdates",title:"My submissions"){router.go(.reviewQueue)}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"blocked",title:"Blacklist"){router.go(.blacklist)}
                                    Divider().padding(.leading,52)
                                    PapiRow(asset:"globe",title:store.text("Language")){router.go(.language)}
                                }.background(Color.white.opacity(0.94),in:RoundedRectangle(cornerRadius:18))
                            }
                            let shelfLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:4)):AnyLayout(HStackLayout(spacing:4))
                            shelfLayout {
                                ForEach(0..<3) {i in
                                    Button {collection=i} label:{
                                        PapiText(["Posts","Photo album","Saved"][i]).font(CoffeeType.face(.subheadline,weight:.semibold))
                                            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                                            .padding(.vertical,10).frame(maxWidth:.infinity,minHeight:44)
                                            .background(collection==i ? Color.butter:Color.clear,in:Capsule()).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityAddTraits(collection==i ? .isSelected:[])
                                }
                            }
                            if collection==1 {
                                let photos:[String] = {
                                    guard let account=store.state.cloudAccountID else {return store.state.passport.photos}
                                    return (store.cloudProfileImages[account] ?? []).filter{$0.kind=="album" && $0.moderation_status=="approved"}.compactMap{store.profileImageReference($0.media_path,owner:account)}
                                }()
                                if store.usesCloudWallet,let account=store.state.cloudAccountID,store.cloudProfileImages[account]==nil {PapiTextButton("Retry"){Task {await store.refreshCloudProfileImages(owner:account)}}.disabled(store.cloudProfileMediaBusy)}
                                else if photos.isEmpty {PapiEmpty(title:"No album photos yet",detail:"Add a photo from Edit Profile.")}
                                LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {
                                    ForEach(photos,id:\.self) {name in Button{router.go(.photo(name))} label:{PapiImage(name:name).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)}
                                }
                                if let account=store.state.cloudAccountID,store.cloudProfileImagesHasMore[account]==true {PapiTextButton("Load more photos"){Task {await store.loadMoreCloudProfileImages(owner:account)}}.disabled(store.cloudProfileMediaBusy)}
                            } else if let account=store.state.cloudAccountID {
                                let saved=collection==2
                                let author:UUID?=saved ? nil:account
                                let key=store.cloudShelfKey(author:author,saved:saved)
                                let posts=store.cloudShelfPosts(author:author,saved:saved)
                                if store.cloudShelves[key]==nil {
                                    PapiText(store.cloudShelfBusy.contains(key) ? "Loading moments…":"Moments unavailable")
                                    PapiTextButton("Retry"){Task {await store.loadCloudShelf(author:author,saved:saved)}}.disabled(store.cloudShelfBusy.contains(key))
                                } else if posts.isEmpty {PapiEmpty(title:saved ? "No saved moments":"Your coffee journal is waiting",detail:saved ? "Save a moment from its detail page to find it here.":"Use the plus button on Home to keep your first coffee moment.")}
                                LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:12) {ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}}
                                if store.cloudShelfHasMore[key]==true {PapiTextButton("Load more"){Task {await store.loadCloudShelf(author:author,saved:saved,more:true)}}.disabled(store.cloudShelfBusy.contains(key))}
                            } else {
                                let posts=collection==0 ? store.visiblePosts.filter{$0.authorID==store.state.passport.id.uuidString}:store.visiblePosts.filter{store.state.keptMoments.contains($0.id)}
                                if posts.isEmpty {PapiEmpty(title:collection==0 ? "Your coffee journal is waiting":"No saved moments",detail:collection==0 ? "Use the plus button on Home to keep your first coffee moment.":"Save a moment from its detail page to find it here.")}
                                LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:12) {ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}}
                            }
                        }.padding(.horizontal,18).padding(.bottom,24).frame(maxWidth:820).frame(maxWidth:.infinity)
                    }
                }
                // Extend the photo and scroll surface; measured top padding keeps controls below system cutouts.
                .ignoresSafeArea(.container,edges:.top)
                .contentMargins(.top,0,for:.scrollContent)
                .frame(width:container.size.width,height:container.size.height+topInset)
                .clipped().offset(y:-topInset)
            }
        }.task(id:store.state.cloudAccountID) {if store.usesCloudWallet {if let account=store.state.cloudAccountID {await store.refreshCloudProfileImages(owner:account)};if store.cloudFeed==nil {await store.refreshCloudFeed()}}}
            .task(id:"\(store.state.cloudAccountID?.uuidString ?? "none")|\(collection)") {
                guard let account=store.state.cloudAccountID,collection != 1 else{return}
                let saved=collection==2
                await store.loadCloudShelf(author:saved ? nil:account,saved:saved)
            }
    }
    private func countButton(_ count:Int,_ title:String)->some View {
        Button {router.go(.relationships(["Following","Follower","Friends"].firstIndex(of:title) ?? 0))} label:{
            VStack(spacing:4){PapiText("\(count)").font(CoffeeType.face(.headline));PapiText(title).font(CoffeeType.face(.caption)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)}
                .frame(maxWidth:.infinity,minHeight:48).contentShape(Rectangle())
        }.buttonStyle(.plain).frame(maxWidth:.infinity).foregroundStyle(Color.cream)
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
    @State private var waitingForProfile=false
    @State private var removingImage:UUID?
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Edit Profile")
                ScrollView {
                    VStack(spacing:18) {
                        CoffeeSectionIntro(artwork:"passportBrewArt",title:"Your coffee passport",detail:"Tap Save to keep these changes.")
                        PapiImage(name:passport.cover).frame(height:210).clipped().clipShape(RoundedRectangle(cornerRadius:20))
                        PapiActionGroup {pickButton("Change background",kind:"cover");pickButton("Change avatar",kind:"avatar")}
                        if store.usesCloudWallet {PapiText("Selected photos are submitted for review. Save profile text separately.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                        HStack {Avatar(name:passport.portraitReference,size:64);PapiText("Your coffee passport").font(CoffeeType.face(.headline));Spacer()}
                        VStack(alignment:.leading,spacing:8) {
                            PapiText("Name").font(CoffeeType.face(.caption,weight:.semibold));PapiTextField(prompt:"Please enter the name…",text:$passport.name).disabled(store.cloudSocialBusy || store.state.pendingCloudProfile != nil)
                            PapiText("About you").font(CoffeeType.face(.caption,weight:.semibold));PapiTextField(prompt:"Keeping the cups I want to brew again.",text:$passport.bio).disabled(store.cloudSocialBusy || store.state.pendingCloudProfile != nil)
                        }.disabled(waitingForProfile).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:20))
                        if waitingForProfile {PapiTextButton("Retry members"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)}
                        HStack {PapiText("Photo album").font(CoffeeType.face(.headline));Spacer();pickButton("Add photo",kind:"album")}
                        if !store.usesCloudWallet {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:95),spacing:10)],spacing:10) {
                            ForEach(passport.photos,id:\.self) {name in
                                ZStack(alignment:.topTrailing){PapiImage(name:name).frame(height:120).clipped().clipShape(RoundedRectangle(cornerRadius:12));PapiIconButton(asset:"close",label:"Remove album photo",size:24){passport.photos.removeAll{$0==name}}}
                            }
                        }
                        } else if let account=store.state.cloudAccountID {
                            if let pending=store.state.pendingCloudProfileImage {PapiTextButton("Retry photo upload"){Task {_ = await store.submitCloudProfileImage(reference:pending.reference,kind:pending.kind)}}.disabled(store.cloudProfileMediaBusy)}
                            if let pending=store.state.pendingCloudProfileImageRemoval {PapiTextButton("Retry photo removal"){Task {await store.removeCloudProfileImage(pending.id)}}.disabled(store.cloudProfileMediaBusy)}
                            if let images=store.cloudProfileImages[account] {
                                ForEach(images) {item in
                                    HStack(spacing:12) {
                                        if let reference=store.profileImageReference(item.media_path,owner:account) {PapiImage(name:reference).frame(width:64,height:64).clipShape(RoundedRectangle(cornerRadius:12))}
                                        VStack(alignment:.leading,spacing:5) {
                                            PapiText(item.kind=="avatar" ? "Avatar":(item.kind=="cover" ? "Background":"Photo album"))
                                            PapiText(item.moderation_status=="approved" ? "Approved":(item.moderation_status=="rejected" ? "Not approved":"Under review")).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        PapiIconButton(asset:"trash",label:"Remove photo",size:20){removingImage=item.id}.disabled(store.cloudProfileMediaBusy || store.state.pendingCloudProfileImageRemoval != nil)
                                    }.padding(12).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:16))
                                }
                                if store.cloudProfileImagesHasMore[account]==true {PapiTextButton("Load more photos"){Task {await store.loadMoreCloudProfileImages(owner:account)}}.disabled(store.cloudProfileMediaBusy)}
                            } else {PapiTextButton("Retry photos"){Task {await store.refreshCloudProfileImages(owner:account)}}.disabled(store.cloudProfileMediaBusy)}
                        }
                        if importing {PapiText("Importing photo…").font(CoffeeType.face(.caption))}
                        PapiTextButton(store.text("Save")) {
                            let name=passport.name.trimmingCharacters(in:.whitespacesAndNewlines)
                            guard !name.isEmpty,name.count<=40,passport.bio.count<=300 else {store.inform("Check your profile","Use a name of 1–40 characters and a bio under 300 characters.");return}
                            guard store.validateCommunityText(name+" "+passport.bio) else{return}
                            guard passport.id==store.state.passport.id else {store.inform("Account changed","Reopen this page to edit the current coffee account.");return}
                            passport.name=name
                            passport.avatar=passport.portraitReference
                            if store.usesCloudWallet {
                                let bio=passport.bio
                                Task {if await store.saveCloudProfile(name:name,biography:bio){dismiss()}}
                            } else if store.commit({$0.passport=passport}) {dismiss()}
                        }.buttonStyle(PapiButtonStyle()).disabled(importing || store.cloudSocialBusy || waitingForProfile)
                        PapiText("Tap Save to keep these changes.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }.overlay {
            if let removingImage {PapiDialog(title:"Remove this photo?",message:"The online photo will be removed. The original file stays on this device.",confirm:"Remove photo",cancel:"Cancel",action:{self.removingImage=nil;Task {await store.removeCloudProfileImage(removingImage)}},dismiss:{self.removingImage=nil})}
        }.photosPicker(isPresented:$showPicker,selection:$picker,matching:.images)
            .task(id:store.state.cloudAccountID) {if let account=store.state.cloudAccountID {await store.refreshCloudProfileImages(owner:account)}}
            .onAppear{if !initialized {passport=store.visiblePassport;waitingForProfile=store.usesCloudWallet && store.cloudProfiles?.contains(where:{$0.id==store.state.cloudAccountID}) != true && store.state.pendingCloudProfile==nil;if let pending=store.state.pendingCloudProfile {passport.name=pending.name;passport.bio=pending.biography};initialized=true}}
            .onChange(of:store.cloudProfiles?.first(where:{$0.id==store.state.cloudAccountID})?.revision) {_,_ in
                if waitingForProfile,store.cloudProfiles?.contains(where:{$0.id==store.state.cloudAccountID}) == true {passport=store.visiblePassport;waitingForProfile=false}
            }
            .onChange(of:picker){_,item in if let item {let destination=target;Task {await importPhoto(item,destination:destination)}}}
    }
    private func pickButton(_ label:String,kind:String)->some View {
        Button {target=kind;picker=nil;showPicker=true} label:{PapiText(label).font(CoffeeType.face(.subheadline,weight:.medium)).padding(.vertical,8).frame(minHeight:44)}.buttonStyle(.plain).disabled(importing || waitingForProfile || store.cloudProfileMediaBusy || (store.usesCloudWallet && store.state.pendingCloudProfileImage != nil))
    }
    @MainActor private func importPhoto(_ item:PhotosPickerItem,destination:String) async {
        importing=true;defer{importing=false}
        do {
            guard let data=try await item.loadTransferable(type:Data.self) else {throw CoffeeMedia.MediaError.invalid}
            guard store.state.signedIn,store.state.passport.id==passport.id else{return}
            let name=try CoffeeMedia.saveImage(data,guest:passport.id)
            if store.usesCloudWallet {
                if destination=="avatar" {passport.avatar=name} else if destination=="cover" {passport.cover=name}
                _ = await store.submitCloudProfileImage(reference:name,kind:destination)
            } else {switch destination {case "avatar":passport.avatar=name;case "album":passport.photos.append(name);default:passport.cover=name}}
        } catch {store.inform("Could not import photo",error.localizedDescription)}
    }
}
struct RelationshipsView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected:Int
    init(initialTab:Int=0) {_selected=State(initialValue:initialTab)}
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Connections")
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    CoffeeSectionIntro(artwork:"coffeePostArt",title:"Connections",detail:"No relationships are created automatically. Friendship needs the other person's acceptance.")
                    let filterLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:5)):AnyLayout(HStackLayout(spacing:5))
                    filterLayout {
                        ForEach(0..<3){i in
                            Button {selected=i} label:{PapiText(["Following","Follower","Friends"][i]).font(CoffeeType.face(.subheadline,weight:.semibold)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44).background(selected==i ? Color.butter:Color.clear,in:RoundedRectangle(cornerRadius:14)).contentShape(Rectangle())}
                                .buttonStyle(.plain).accessibilityAddTraits(selected==i ? .isSelected:[])
                        }
                    }.padding(5).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:18))
                    let following=store.followingIDs.sorted().compactMap{store.person($0)}.filter{!store.isUserHidden($0.id)}
                    let people=selected==0 ? following:(selected==1 ? store.followers:store.friends)
                    if selected==2 && store.usesCloudWallet && !store.incomingFriendships.isEmpty {
                        PapiText("Friend requests").font(CoffeeType.face(.headline))
                        ForEach(store.incomingFriendships) {request in
                            if let person=store.person(request.requester_id.uuidString) {
                                VStack(alignment:.leading,spacing:10) {
                                    PapiUserLink(userID:person.id)
                                    HStack {
                                        PapiTextButton("Accept"){Task {await store.answerCloudFriendship(request.id,accepted:true)}}.disabled(store.cloudSocialBusy)
                                        PapiTextButton("Decline"){Task {await store.answerCloudFriendship(request.id,accepted:false)}}.disabled(store.cloudSocialBusy)
                                    }
                                }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.92),in:RoundedRectangle(cornerRadius:18))
                            }
                        }
                    }
                    if store.usesCloudWallet && store.cloudProfiles==nil {
                        PapiTextButton("Retry members"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                    } else if people.isEmpty {PapiEmpty(title:selected==0 ? "No following yet":(selected==1 ? "No followers":"No mutual connections"))}
                    ForEach(people){person in
                        HStack(spacing:12) {PapiUserLink(userID:person.id);Spacer(minLength:0);PapiIconButton(asset:"comment",label:"Open chat"){router.go(.chat(person.id))}}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.92),in:RoundedRectangle(cornerRadius:18))
                    }
                }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
            }
        }}
    }
}
struct BlacklistView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("Blacklist")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    CoffeeSectionIntro(artwork:"passportCareArt",title:"Blacklist",detail:"Manage the people you have blocked.")
                    if store.usesCloudWallet && store.cloudProfiles==nil {PapiTextButton("Retry members"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)}
                    else if store.blockedIDs.isEmpty {PapiEmpty(title:"Your blacklist is empty")}
                    ForEach(store.blockedIDs.sorted(),id:\.self){id in
                        let person=store.person(id)
                        HStack(spacing:12) {
                            Avatar(name:person?.portrait ?? "brandMark")
                            PapiText(verbatim:person?.name ?? "Hidden profile").font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                            PapiTextButton("Unblock"){if store.usesCloudWallet,let member=UUID(uuidString:id) {Task {_ = await store.changeCloudBlock(member,enabled:false)}} else {store.unblock(id)}}.font(CoffeeType.face(.caption,weight:.bold)).padding(10).frame(minHeight:44).background(Color.butter,in:Capsule()).disabled(store.cloudSocialBusy)
                        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.94),in:RoundedRectangle(cornerRadius:18))
                    }
                }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
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
                    VStack(alignment:.leading,spacing:20) {
                        CoffeeSectionIntro(artwork:"settingsCoffeeArt",title:"Your coffee account",detail:"Papi 1.0 · Brew, taste, remember")
                        preferenceSection("Community & privacy") {
                            if let pending=store.state.pendingCloudReport {PapiRow(title:"Finish pending report"){router.sheet = .report(pending.target)}}
                            if store.state.pendingCloudMessage != nil {PapiRow(title:"Finish pending message"){Task {await store.retryPendingCloudMessage()}}}
                            if let pending=store.state.pendingCloudAttachment {PapiRow(title:"Finish pending attachment"){Task {_ = await store.sendCloudAttachment(to:pending.recipientID.uuidString,reference:pending.reference,kind:pending.kind)}}.disabled(store.cloudSocialBusy)}
                            if store.liveCallsEnabled,let pending=store.state.pendingCloudCall {PapiRow(title:"Retry call request"){Task {_ = await store.requestCloudCall(pending.recipientID)}}.disabled(store.cloudCallsBusy)}
                            if store.liveCallsEnabled,let pending=store.state.pendingCloudCallEnd {PapiRow(title:"Finish ending call"){Task {await store.endCloudCall(pending.id)}}.disabled(store.cloudCallsBusy)}
                            if store.state.pendingCloudVoice != nil {PapiRow(title:"Finish voice session"){Task {await store.finishCloudVoice()}}.disabled(store.cloudVoiceBusy)}
                            if let pending=store.state.pendingCloudRoomGift {PapiRow(title:"Cancel pending gift"){Task {_ = await store.cloudRoomGift(gift:nil,quantity:pending.quantity,topic:pending.topic,session:pending.sessionID,cancel:true)}}.disabled(store.cloudWalletBusy)}
                            if let pending=store.state.pendingCloudFriendship {PapiRow(title:"Finish friend request"){Task {await store.requestCloudFriendship(pending.recipientID)}}}
                            if store.state.pendingCloudProfile != nil {PapiRow(title:"Finish profile changes"){router.go(.editProfile)}}
                            if let pending=store.state.pendingCloudProfileImage {PapiRow(title:"Retry photo upload"){Task {_ = await store.submitCloudProfileImage(reference:pending.reference,kind:pending.kind)}}.disabled(store.cloudProfileMediaBusy)}
                            if let pending=store.state.pendingCloudProfileImageRemoval {PapiRow(title:"Retry photo removal"){Task {await store.removeCloudProfileImage(pending.id)}}.disabled(store.cloudProfileMediaBusy)}
                            if let pending=store.state.pendingCloudComment {
                                PapiRow(title:"Finish pending comment"){Task {_ = await store.submitCloudComment(moment:pending.momentID,text:pending.body)}}.disabled(store.cloudCommentsBusy)
                                PapiRow(title:"Discard pending comment"){confirmation="discardComment"}.disabled(store.cloudCommentsBusy)
                            }
                            if let pending=store.state.pendingCloudEditorialComment {
                                PapiRow(title:"Finish pending comment"){Task {_ = await store.sendEditorialComment(pending.momentID,text:pending.body)}}.disabled(store.editorialBusy)
                            }
                            row("Blacklist",.blacklist)
                            row("Community Guidelines",.legal("community"))
                            row("Privacy Policy",.legal("privacy"))
                            row("User Agreement",.legal("terms"))
                        }
                        preferenceSection("Preferences") {
                            row("Language",.language)
                        }
                        preferenceSection("Account") {
                            if store.usesCloudWallet && store.emailLinkEnabled {PapiRow(title:"Link email"){router.go(.linkEmail)}}
                            if !store.usesCloudWallet && store.emailLinkEnabled {PapiRow(title:"Recover account"){router.go(.recoverEmail)}}
                            if store.state.deletedCloudAccountID != nil {PapiRow(title:"Create a new online account"){confirmation="newOnline"}}
                            PapiRow(title:"Log Out"){confirmation="logout"}
                            PapiRow(title:"Delete account"){confirmation="delete"}
                        }
                        PapiText(store.usesCloudWallet ? "Your coffee book and balance use this account. Account recovery and some community features are still unavailable." : "Your coffee book and balance do not sync between devices. Community sharing and messaging are unavailable.")
                            .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        if !store.storageAvailable {PapiTextButton("Retry"){store.reload()}.buttonStyle(PapiButtonStyle())}
                    }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
                }
            }.overlay {
                if let confirmation {
                    PapiDialog(title:confirmation=="discardComment" ? "Discard pending comment?":(confirmation=="newOnline" ? "Create a new online account?":(confirmation=="delete" ? "Delete this coffee account?":"Log out?")),
                               message:confirmation=="discardComment" ? "This clears the pending retry on this device. If the server already accepted the comment, it may still appear after review.":(confirmation=="newOnline" ? "Your saved device data stays here. The new online account has a separate balance and requires you to review the policies again.":(confirmation=="delete" ? (store.usesCloudWallet ? "This removes your online profile, content and balance. Your existing device data stays on this device. Purchase ownership records are retained to prevent duplicate delivery. This cannot be undone.":"This removes your passport, brew book, recipes, moments, media, coins and keepsakes. Purchase ownership records are retained to prevent duplicate delivery. This cannot be undone."):"Your coffee book will be here when you return.")),
                               confirm:confirmation=="discardComment" ? "Discard":(confirmation=="newOnline" ? "Continue":(confirmation=="delete" ? "Delete account":"Log out")),cancel:"Cancel",action:{
                        self.confirmation=nil
                        if confirmation=="discardComment" {_ = store.commit{$0.pendingCloudComment=nil};return}
                        if commerce.busy || commerce.unresolved {store.inform("Purchase recovery active","Resolve the purchase before changing accounts.");return}
                        if confirmation=="newOnline" {Task {await store.prepareNewCloudAccount()};return}
                        Task {await store.performAccountAction(confirmation=="delete" ? .delete:.logout)}
                    },dismiss:{self.confirmation=nil})
                }
            }
        }
    }
    private func row(_ title:String,_ route:CoffeeDestination)->some View {PapiRow(title:title){router.go(route)}}
    private func preferenceSection<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:8) {
            PapiText(title).font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(Color.mutedCoffee).padding(.horizontal,4)
            VStack(spacing:2) {content()}.background(Color.white.opacity(0.94),in:RoundedRectangle(cornerRadius:20))
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct CoffeeEmailLinkView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @State private var email=""
    @State private var code=""
    @State private var sent=false
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Link email")
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        CoffeeSectionIntro(artwork:"settingsCoffeeArt",title:"Keep your coffee account",detail:"Verify an email for this guest account. Your current coffee book stays on this device.")
                        PapiText("Email address").font(CoffeeType.face(.caption,weight:.semibold))
                        PapiInput("Email address",text:$email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().padding(15)
                            .background(Color.white,in:RoundedRectangle(cornerRadius:15)).disabled(store.emailLinkBusy || sent)
                        PapiTextButton("Send verification code") {Task {if await store.requestEmailLink(email) {sent=true}}}
                            .buttonStyle(PapiButtonStyle()).disabled(store.emailLinkBusy || email.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        if sent {
                            PapiText("Verification code").font(CoffeeType.face(.caption,weight:.semibold))
                            PapiInput("Verification code",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                                .padding(15).background(Color.white,in:RoundedRectangle(cornerRadius:15)).disabled(store.emailLinkBusy)
                            PapiTextButton("Verify email") {Task {if await store.verifyEmailLink(email,code:code) {code="";sent=false}}}
                                .buttonStyle(PapiButtonStyle()).disabled(store.emailLinkBusy || code.isEmpty)
                            PapiTextButton("Use another email") {sent=false;code=""}.disabled(store.emailLinkBusy)
                        }
                        PapiText("Account recovery on another device is not available yet. Keep this device and its saved data.")
                            .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PapiTextButton("Retry saved verification") {Task {await store.resumeEmailLink()}}.disabled(store.emailLinkBusy)
                    }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
        }.task {await store.resumeEmailLink()}
    }
}
struct CoffeeEmailRecoveryView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @State private var email=""
    @State private var code=""
    @State private var sent=false
    @State private var confirm=false
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Recover account")
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        CoffeeSectionIntro(artwork:"settingsCoffeeArt",title:"Open your online account",detail:"Enter the email previously verified for your account.")
                        PapiText("Email address").font(CoffeeType.face(.caption,weight:.semibold))
                        PapiInput("Email address",text:$email).keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().padding(15)
                            .background(Color.white,in:RoundedRectangle(cornerRadius:15)).disabled(store.emailLinkBusy || sent)
                        PapiTextButton("Send verification code") {Task {if await store.requestEmailRecovery(email) {sent=true}}}
                            .buttonStyle(PapiButtonStyle()).disabled(store.emailLinkBusy || email.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                        if sent {
                            PapiText("Verification code").font(CoffeeType.face(.caption,weight:.semibold))
                            PapiInput("Verification code",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                                .padding(15).background(Color.white,in:RoundedRectangle(cornerRadius:15)).disabled(store.emailLinkBusy)
                            PapiTextButton("Recover account") {confirm=true}.buttonStyle(PapiButtonStyle()).disabled(store.emailLinkBusy || code.isEmpty)
                            PapiTextButton("Use another email") {sent=false;code=""}.disabled(store.emailLinkBusy)
                        }
                        PapiText("Device data stays saved here. Online and device data are not merged automatically.")
                            .font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PapiTextButton("Retry saved recovery") {Task {if await store.resumeEmailRecovery() {dismiss()}}}.disabled(store.emailLinkBusy)
                    }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.overlay {
                if confirm {PapiDialog(title:"Open online account?",message:"Your existing device data stays saved here. Online and device data will not be merged automatically.",confirm:"Continue",cancel:"Cancel",action:{confirm=false;Task {if await store.verifyEmailRecovery(email,code:code) {code="";dismiss()}}},dismiss:{confirm=false})}
            }
        }
    }
}
struct LanguageView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @State private var pending:String?
    var body:some View {
        PapiScreen {VStack(spacing:14) {
            PapiHeader(store.text("Language"))
            ScrollView {
                VStack(spacing:12) {
                    CoffeeSectionIntro(artwork:"passportCareArt",title:"Language",detail:"App controls follow your selected language. Your writing and original artwork keep their original language.")
                    ForEach(PapiStrings.languages,id:\.id) {language in
                        Button {pending=language.id} label:{HStack {PapiText(language.name);Spacer();if store.state.language==language.id {Image("check").resizable().scaledToFit().frame(width:18,height:18)}}.padding(19).frame(maxWidth:.infinity).background(store.state.language==language.id ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:13))}.buttonStyle(.plain)
                    }
                }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
            }
        }.overlay {
            if let pending {PapiDialog(title:"Change language?",message:"Your drafts and current guest will stay the same.",confirm:"Confirm",cancel:"Cancel",action:{_ = store.commit{$0.language=pending};self.pending=nil},dismiss:{self.pending=nil})}
        }}
    }
}
struct CoffeePolicyDocument:Decodable,Identifiable {
    let id:String
    let title:String
    let subtitle:String
    let updated:String
    let publishedURL:String
    var url:URL? {
        guard let url=URL(string:publishedURL),url.scheme=="https",url.host=="cquoffowtjnxmgaxavym.supabase.co",
              (id=="terms" && url.path=="/storage/v1/object/public/papi-policies/terms-online-v1.pdf") ||
              (id=="privacy" && url.path=="/storage/v1/object/public/papi-policies/privacy-online-v1.pdf"),
              url.query==nil,url.fragment==nil,url.user==nil,url.password==nil,url.port==nil else{return nil}
        return url
    }
}
enum CoffeePolicyLibrary {
    private struct Book:Decodable {let version:String;let documents:[CoffeePolicyDocument]}
    private static let book:Book? = {
        guard let url=Bundle.main.url(forResource:"PapiPolicies",withExtension:"json",subdirectory:"Localization"),let data=try? Data(contentsOf:url) else{return nil}
        return try? JSONDecoder().decode(Book.self,from:data)
    }()
    static var version:String {book?.version ?? "2026-10-27"}
    static func document(_ id:String)->CoffeePolicyDocument? {book?.documents.first{$0.id==id}}
}
struct LegalView:View {
    var type:String
    var body:some View {
        if type=="community" {CoffeeCommunityGuidelinesView()}
        else if let document=CoffeePolicyLibrary.document(type) {PublishedCoffeePolicyView(document:document).id(document.id)}
        else {PapiScreen {VStack(spacing:0){PapiHeader("Policy");PapiEmpty(title:"Policy unavailable",detail:"Please reopen this page to try again.");Spacer()}}}
    }
}
private struct PublishedCoffeePolicyView:View {
    let document:CoffeePolicyDocument
    @Environment(\.openURL) private var openURL
    @State private var loading=true
    @State private var unavailable=false
    @State private var reloadID=UUID()
    @Environment(\.papiRegions) private var reservedRegions
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader(document.id=="privacy" ? "Privacy Policy":"User Agreement")
                GeometryReader {proxy in
                    let frame=proxy.frame(in:.named("PapiContainer"))
                    let regions=reservedRegions.map{$0.offsetBy(dx:-frame.minX,dy:-frame.minY)}
                    let readingArea=PapiRegionGeometry.largestArea(in:CGRect(origin:.zero,size:proxy.size),excluding:regions)
                    readingContent.frame(width:readingArea.width,height:readingArea.height).position(x:readingArea.midX,y:readingArea.midY)
                }
                if let url=document.url {
                    PapiTextButton("Open in browser") {openURL(url)}
                        .font(CoffeeType.face(.caption,weight:.semibold)).frame(maxWidth:.infinity,minHeight:44).background(Color.cream).papiAvoidReserved()
                }
            }
        }
    }
    @ViewBuilder private var readingContent:some View {
        if let url=document.url {
            ZStack {
                CoffeePolicyWebPage(url:url,loading:$loading,unavailable:$unavailable,openExternal:{openURL($0)}).id(reloadID)
                    .opacity(unavailable ? 0:1).accessibilityHidden(unavailable)
                if loading || unavailable {
                    ScrollView {
                        VStack(spacing:16) {
                            Image("brandMark").resizable().scaledToFit().frame(width:54,height:54).accessibilityHidden(true)
                            PapiText(unavailable ? "Online policy unavailable":"Opening the policy…").font(CoffeeType.face(.headline)).multilineTextAlignment(.center)
                            if unavailable {
                                PapiText("Please check your connection and try again.").font(CoffeeType.face(.subheadline)).multilineTextAlignment(.center)
                                PapiTextButton("Retry") {loading=true;unavailable=false;reloadID=UUID()}.buttonStyle(PapiButtonStyle())
                            }
                        }.padding(24).frame(maxWidth:520).frame(maxWidth:.infinity)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).background {PapiBackground()}
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
        } else {PapiEmpty(title:"Policy unavailable",detail:"Please reopen this page to try again.")}
    }
}
private struct CoffeePolicyWebPage:UIViewRepresentable {
    let url:URL
    @Binding var loading:Bool
    @Binding var unavailable:Bool
    let openExternal:(URL)->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIView(context:Context)->WKWebView {
        let configuration=WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript=false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically=false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view=WKWebView(frame:.zero,configuration:configuration)
        view.navigationDelegate=context.coordinator
        view.isOpaque=false;view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.load(URLRequest(url:url,cachePolicy:.useProtocolCachePolicy,timeoutInterval:20))
        return view
    }
    func updateUIView(_ view:WKWebView,context:Context) {context.coordinator.owner=self}
    static func dismantleUIView(_ view:WKWebView,coordinator:Coordinator) {view.navigationDelegate=nil;view.stopLoading()}
    final class Coordinator:NSObject,WKNavigationDelegate {
        var owner:CoffeePolicyWebPage
        init(_ owner:CoffeePolicyWebPage) {self.owner=owner}
        func webView(_ webView:WKWebView,didStartProvisionalNavigation navigation:WKNavigation!) {owner.loading=true;owner.unavailable=false}
        func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {owner.loading=false}
        func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) {failed(error)}
        func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) {failed(error)}
        func webViewWebContentProcessDidTerminate(_ webView:WKWebView) {owner.loading=false;owner.unavailable=true}
        private func failed(_ error:Error) {
            guard (error as NSError).code != NSURLErrorCancelled else{return}
            owner.loading=false;owner.unavailable=true
        }
        func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
            guard let url=action.request.url else {decisionHandler(.cancel);return}
            if url.absoluteString.lowercased()=="mailto:papi_service2026@outlook.com",action.navigationType == .linkActivated {
                decisionHandler(.cancel);owner.openExternal(url);return
            }
            guard url.scheme=="https" else {decisionHandler(.cancel);return}
            if action.targetFrame?.isMainFrame==false {decisionHandler(.allow);return}
            if url.host==owner.url.host,url.path==owner.url.path {decisionHandler(.allow);return}
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated {owner.openExternal(url)}
        }
        func webView(_ webView:WKWebView,decidePolicyFor response:WKNavigationResponse,decisionHandler:@escaping(WKNavigationResponsePolicy)->Void) {
            if response.isForMainFrame,let http=response.response as? HTTPURLResponse,!(200...299).contains(http.statusCode) {
                owner.loading=false;owner.unavailable=true;decisionHandler(.cancel)
            } else {decisionHandler(.allow)}
        }
    }
}
private struct CoffeeCommunityGuidelinesView:View {
    var body:some View {
        PapiScreen {VStack(spacing:0) {
            PapiHeader("Community Guidelines")
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    PapiText("Papi · Your coffee book").font(CoffeeType.face(.title2,weight:.bold))
                    PapiText("Updated 26 October 2026").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                    section("A welcoming coffee table","Share coffee rituals, café discoveries and thoughtful conversation. Respect different cultures, preferences and brewing experience. Do not harass, threaten, bully, discriminate against or shame another person.")
                    section("Keep the community safe","Pornography, sexual exploitation, child endangerment, hateful content, graphic violence, illegal activity and threats are prohibited. Do not publish another person's private information or intimate media without consent.")
                    section("Real consent, real connections","Chat messages and video-call actions require mutual following. Friendship requires the other person's acceptance. Do not impersonate someone, create fake relationships or use Papi for random or anonymous chat. You may withdraw a follow at any time.")
                    section("Share only what is yours","Post only photos, videos, audio and text you have the right to share. Get permission from identifiable people. Avoid scams, spam, misleading promotions and dangerous advice. Never pressure someone to send money or gifts.")
                    section("Review before visibility","New posts remain private until approved. In this local edition, submissions wait on your device until a moderation service is connected. There is no automatic approval or fabricated moderator response.")
                    section("Report and control your space","Use the safety menu on a profile, post, comment, message or room. Choose a report reason and confirm. Saved reports hide the item immediately on this device. Blocking a user hides their profile, posts, comments, rooms and chats. Manage blocks in Settings; unblocking never restores follows or friendship automatically.")
                    section("Camera and microphone consent","Camera preview starts only after you choose it and grant camera and microphone access. This local edition does not connect a call or send your camera or microphone to another person. Stop preview or leave the page to stop capture.")
                    section("Moderation and support","A live community must provide content filtering, timely handling of reports and a published way to contact its operator. These services and a public support contact are not connected in this local edition. Local hiding is not a substitute for server moderation; online sharing stays unavailable until those services are ready.")
                }.padding(24).frame(maxWidth:700).frame(maxWidth:.infinity,alignment:.leading)
            }
        }}
    }
    private func section(_ title:String,_ body:String)->some View {VStack(alignment:.leading,spacing:8){PapiText(title).font(CoffeeType.face(.headline));PapiText(body).font(CoffeeType.face(.body)).lineSpacing(4)}}
}
