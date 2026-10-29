import SwiftUI

struct CoffeeTablesView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter=0
    private var rooms:[CoffeeTable] {
        let recent=store.cloudRecentRooms ?? []
        return (store.cloudVoiceTopics ?? []).compactMap(\.room).filter {room in
            store.isRoomVisible(room) && (filter==0 || recent.contains(room.id))
        }.sorted {a,b in
            if filter==1 {return (recent.firstIndex(of:a.id) ?? 99)<(recent.firstIndex(of:b.id) ?? 99)}
            return (store.cloudVoiceTopics?.first(where:{$0.id==a.id})?.sort_order ?? 0)<(store.cloudVoiceTopics?.first(where:{$0.id==b.id})?.sort_order ?? 0)
        }
    }
    var body:some View {
        PapiScreen {
            GeometryReader {geo in
                let topInset=geo.safeAreaInsets.top
                let bannerHeight=(typeSize.isAccessibilitySize ? 300:min(230,max(190,geo.size.width*0.48)))+topInset
                let contentWidth=max(0,min(1100,geo.size.width)-32)
                let columnCount=typeSize.isAccessibilitySize || contentWidth<330 ? 1:min(4,max(1,Int((contentWidth+12)/170)))
                ScrollView {
                    VStack(spacing:0) {
                        ZStack(alignment:.topLeading) {
                            Image("coffeeTableHeaderArt").resizable().scaledToFill()
                                .frame(width:geo.size.width,height:bannerHeight,alignment:.trailing).clipped()
                                .overlay(alignment:.top) {
                                    LinearGradient(colors:[Color.cream.opacity(0.8),Color.clear],startPoint:.top,endPoint:.bottom)
                                        .frame(height:topInset+30).allowsHitTesting(false)
                                }.accessibilityHidden(true)
                            VStack(alignment:.leading,spacing:7) {
                                PapiText("Coffee tables").font(CoffeeType.display(.title,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                PapiText("Around the coffee table").font(CoffeeType.face(.subheadline,weight:.medium)).fixedSize(horizontal:false,vertical:true)
                            }.foregroundStyle(Color.cream).shadow(color:Color.coffee.opacity(0.8),radius:4,y:2)
                                .frame(maxWidth:typeSize.isAccessibilitySize ? 340:240,alignment:.leading)
                                .padding(.horizontal,20).padding(.top,topInset+22).papiAvoidReserved()
                        }.frame(width:geo.size.width,height:bannerHeight)
                        VStack(alignment:.leading,spacing:16) {
                            let filterLayout=typeSize.isAccessibilitySize || contentWidth<300 ? AnyLayout(VStackLayout(spacing:4)):AnyLayout(HStackLayout(spacing:4))
                            filterLayout {
                                ForEach(0..<2,id:\.self) {i in
                                    Button {filter=i} label:{
                                        PapiText(["All","Recent"][i]).font(CoffeeType.face(.subheadline,weight:filter==i ? .bold:.medium)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                                            .frame(maxWidth:.infinity,minHeight:54)
                                            .background {if filter==i {Image("voiceActionPlate").resizable()}}
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).foregroundStyle(filter==i ? Color.coffee:Color.mutedCoffee).accessibilityAddTraits(filter==i ? .isSelected:[])
                                }
                            }.padding(.horizontal,4).padding(.vertical,2).background(Color.coffee.opacity(0.07),in:RoundedRectangle(cornerRadius:20)).papiAvoidReserved()
                            HStack(spacing:8) {
                                PapiArtworkFit(asset:"audioTableMark").frame(width:32,height:32)
                                PapiText(store.liveVoiceEnabled ? "Live voice rooms":"Coffee topics · Audio unavailable").font(CoffeeType.face(.caption)).fixedSize(horizontal:false,vertical:true)
                            }.foregroundStyle(Color.mutedCoffee).frame(maxWidth:.infinity,alignment:.leading)
                            if store.usesCloudWallet && store.cloudVoiceTopics==nil {PapiTextButton("Retry topics"){Task {await store.refreshCloudVoiceTopics()}}.disabled(store.cloudVoiceTopicsBusy)}
                            else if store.usesCloudWallet && filter==1 && store.cloudRecentRooms==nil {PapiTextButton("Retry recent rooms"){Task {await store.refreshCloudRecentRooms()}}.disabled(store.cloudRecentRoomsBusy)}
                            else if rooms.isEmpty {PapiEmpty(title:filter==1 ? "No recent rooms":"No topics available",detail:"Open a coffee topic to keep it here.")}
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:columnCount),spacing:14) {
                                ForEach(rooms) {room in
                                    roomCard(room)
                                }
                            }
                        }.padding(.horizontal,16).padding(.top,16).padding(.bottom,24).frame(maxWidth:1100).frame(maxWidth:.infinity)
                    }
                }.ignoresSafeArea(.container,edges:.top).contentMargins(.top,0,for:.scrollContent)
            }
        }.task(id:store.state.cloudAccountID) {if store.usesCloudWallet {filter=0;await store.refreshCloudVoiceTopics()}}
    }
    private func roomCard(_ room:CoffeeTable)->some View {
        VStack(alignment:.leading,spacing:0) {
            Button {if store.isRoomVisible(room) {router.go(.room(room.id))}} label:{
                ZStack(alignment:.bottomLeading) {
                    PapiImage(name:store.person(room.hostMemberID)?.portrait ?? room.image,fallback:room.image).frame(height:typeSize.isAccessibilitySize ? 290:245).clipped()
                        .overlay {LinearGradient(colors:[.clear,Color.coffee.opacity(0.3),Color.coffee.opacity(0.96)],startPoint:.center,endPoint:.bottom)}
                        .overlay(alignment:.topLeading) {
                            HStack(spacing:4) {
                                PapiArtworkFit(asset:"audioTableMark").frame(width:22,height:22)
                                PapiText(room.category).font(CoffeeType.face(.caption2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                            }.foregroundStyle(Color.coffee).padding(.horizontal,9).padding(.vertical,4).background(Color.cream.opacity(0.96),in:Capsule()).padding(10).padding(.trailing,54)
                        }
                    VStack(alignment:.leading,spacing:6) {
                        PapiText(room.title).font(CoffeeType.display(.headline,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                        PapiText(store.cloudVoiceTopics?.first(where:{$0.id==room.id})?.room_description ?? "").font(CoffeeType.face(.caption)).foregroundStyle(Color.cream.opacity(0.9)).fixedSize(horizontal:false,vertical:true)
                    }.foregroundStyle(Color.cream).padding(13).frame(maxWidth:.infinity,alignment:.leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(store.usesCloudWallet && !store.liveVoiceEnabled)
                .overlay(alignment:.topTrailing) {
                    PapiIconButton(asset:"more",label:"Safety options",size:20) {
                        router.sheet = .safety(.init(kind:.room,contentReference:room.id,authorID:nil))
                    }.background(Color.cream.opacity(0.95),in:Circle()).padding(6)
                }
        }.frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.95),in:RoundedRectangle(cornerRadius:20)).clipShape(RoundedRectangle(cornerRadius:20))
    }
}
struct MemberPassportView:View {
    let memberID:String
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedShelf:Int?

    var body:some View {
        PapiScreen {
            if let person=store.person(memberID),!store.isUserHidden(memberID) {
                GeometryReader {container in
                    let topInset=container.safeAreaInsets.top
                    let coverHeight=min(520,max(340,container.size.width*1.08))
                    let contentWidth=max(0,min(720,container.size.width)-40)
                    let posts: [CoffeeMoment] = {
                        if store.usesCloudWallet,let member=UUID(uuidString:person.id) {return store.cloudShelfPosts(author:member,saved:false)}
                        return (store.usesCloudWallet ? store.visibleCollectionPosts:store.visiblePosts).filter{$0.authorID==person.id}
                    }()
                    ScrollView {
                        VStack(spacing:0) {
                            portraitCover(person,width:container.size.width,height:coverHeight+topInset,topInset:topInset)
                            VStack(alignment:.leading,spacing:24) {
                                memberDetails(person,width:contentWidth)
                                if store.usesCloudWallet && UUID(uuidString:person.id) != nil {
                                    VStack(alignment:.leading,spacing:12) {
                                        if let member=UUID(uuidString:person.id) {
                                            let photos=(store.cloudProfileImages[member] ?? []).filter{$0.kind=="album" && $0.moderation_status=="approved"}.compactMap{store.profileImageReference($0.media_path,owner:member)}
                                            if !photos.isEmpty {
                                                PapiText("Photo album").font(CoffeeType.face(.headline))
                                                LazyVGrid(columns:[GridItem(.adaptive(minimum:145),spacing:12)],spacing:12) {ForEach(photos,id:\.self) {photo in Button {router.go(.photo(photo))} label:{PapiImage(name:photo).frame(height:180).clipped().clipShape(RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain)}}
                                            } else if store.cloudProfileImages[member]==nil {PapiTextButton("Retry photos"){Task {await store.refreshCloudProfileImages(owner:member)}}.disabled(store.cloudProfileMediaBusy)}
                                            if store.cloudProfileImagesHasMore[member]==true {PapiTextButton("Load more photos"){Task {await store.loadMoreCloudProfileImages(owner:member)}}.disabled(store.cloudProfileMediaBusy)}
                                        }
                                        if let member=UUID(uuidString:person.id) {
                                            let key=store.cloudShelfKey(author:member,saved:false)
                                            if store.cloudShelves[key]==nil {
                                                PapiText(store.cloudShelfBusy.contains(key) ? "Loading moments…":"Moments unavailable")
                                                PapiTextButton("Retry"){Task {await store.loadCloudShelf(author:member,saved:false)}}.disabled(store.cloudShelfBusy.contains(key))
                                            } else if posts.isEmpty {PapiEmpty(title:"No moments yet")}
                                            LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:14) {ForEach(posts){post in CoffeeMomentTile(post:post,height:210)}}
                                            if store.cloudShelfHasMore[key]==true {PapiTextButton("Load more"){Task {await store.loadCloudShelf(author:member,saved:false,more:true)}}.disabled(store.cloudShelfBusy.contains(key))}
                                        }
                                    }
                                } else {collectionShelf(person,posts:posts,width:contentWidth)}
                            }
                            .padding(.horizontal,20).padding(.top,-28).padding(.bottom,28)
                            .frame(maxWidth:720).frame(maxWidth:.infinity)
                        }
                    }
                    // Extend the portrait into the top inset; keep controls below the measured system area.
                    .ignoresSafeArea(.container,edges:.top)
                    .contentMargins(.top,0,for:.scrollContent)
                }
            } else {VStack(spacing:0){PapiHeader("Profile");ScrollView {PapiEmpty(title:"Profile unavailable")}}}
        }.task(id:memberID) {if store.usesCloudWallet {if store.cloudFeed==nil {await store.refreshCloudFeed()};if let member=UUID(uuidString:memberID) {await store.refreshCloudProfileImages(owner:member);await store.loadCloudShelf(author:member,saved:false)}}}
    }

    private func portraitCover(_ person:CoffeeMember,width:CGFloat,height:CGFloat,topInset:CGFloat)->some View {
        ZStack(alignment:.top) {
            PapiImage(name:person.portrait).frame(width:width,height:height).clipped()
            HStack {
                PapiIconButton(asset:"back",label:"Back"){dismiss()}
                    .background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:14))
                Spacer(minLength:16)
                PapiIconButton(asset:"more",label:"Member options"){router.sheet = .more(person.id)}
                    .background(Color.cream.opacity(0.94),in:RoundedRectangle(cornerRadius:14))
            }
            .padding(.horizontal,20).padding(.top,topInset+12)
            .frame(maxWidth:720).papiAvoidReserved()
        }.frame(width:width,height:height)
    }

    private func memberDetails(_ person:CoffeeMember,width:CGFloat)->some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top,spacing:14) {
                Avatar(name:person.portrait,size:76)
                VStack(alignment:.leading,spacing:6) {
                    PapiText(verbatim:person.name).font(CoffeeType.face(.title2,weight:.bold))
                        .fixedSize(horizontal:false,vertical:true)
                    if !store.usesCloudWallet || UUID(uuidString:person.id)==nil {
                        PapiText(verbatim:"@"+person.handle).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PreviewLabel()
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            PapiText(verbatim:store.usesCloudWallet && UUID(uuidString:person.id) != nil ? person.bio:store.text(person.bio)).font(CoffeeType.face(.subheadline)).lineSpacing(3)
                .fixedSize(horizontal:false,vertical:true)
            let actionLayout=typeSize.isAccessibilitySize || width<320 ? AnyLayout(VStackLayout(spacing:10)):AnyLayout(HStackLayout(spacing:12))
            actionLayout {
                PapiTextButton(store.isFollowing(person.id) ? "Following":"Follow"){store.follow(person.id)}
                    .buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(store.isUserHidden(person.id) || (store.usesCloudWallet && (store.cloudProfiles==nil || store.cloudSocialBusy || UUID(uuidString:person.id)==nil)))
                PapiTextButton("Chatting"){router.go(.chat(person.id))}
                    .buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:16))
            }
            if store.usesCloudWallet,let member=UUID(uuidString:person.id) {
                PapiRow(asset:"plus",title:store.isFriend(person.id) ? "Friends":(store.incomingFriendship(from:person.id) != nil ? "Respond to request":(store.outgoingFriendship(to:person.id) == nil ? "Request friendship":"Cancel friend request"))) {
                    if store.incomingFriendship(from:person.id) != nil {router.go(.relationships(2))}
                    else if let request=store.outgoingFriendship(to:person.id) {Task {await store.cancelCloudFriendship(request.id)}}
                    else {Task {await store.requestCloudFriendship(member)}}
                }.disabled(store.isFriend(person.id) || store.cloudSocialBusy).background(Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
            } else if person.id != CoffeeMember.editorial.id && !store.usesCloudWallet {
                PapiRow(asset:"plus",title:store.isFriend(person.id) ? "Friends":(store.community.friendshipRequests[person.id] == nil ? "Request friendship":"Cancel friend request")) {
                    if store.community.friendshipRequests[person.id] != nil {store.cancelFriendshipRequest(person.id)} else {store.requestFriendship(person.id)}
                }.disabled(store.isFriend(person.id)).background(Color.white.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
            }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.cream,in:RoundedRectangle(cornerRadius:26))
    }

    private func collectionShelf(_ person:CoffeeMember,posts:[CoffeeMoment],width:CGFloat)->some View {
        let activeShelf=selectedShelf ?? (posts.isEmpty ? 0:1)
        let shelfLayout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:6)):AnyLayout(HStackLayout(spacing:6))
        return VStack(alignment:.leading,spacing:16) {
            shelfLayout {
                shelfButton("Photo",count:person.portrait.isEmpty ? 0:1,index:0,selected:activeShelf)
                shelfButton("Posts",count:posts.count,index:1,selected:activeShelf)
            }.padding(6).background(Color.white.opacity(0.85),in:RoundedRectangle(cornerRadius:20))
            if activeShelf==0 {
                if !person.portrait.isEmpty {
                    Button {router.go(.photo(person.portrait))} label:{
                        PapiImage(name:person.portrait).frame(width:width,height:min(460,width*1.18))
                            .clipped().clipShape(RoundedRectangle(cornerRadius:22))
                    }.buttonStyle(.plain).papiAccessibilityLabel("Photo")
                }
            } else if posts.isEmpty {
                PapiEmpty(title:"No published posts",detail:"Explore coffee moments in the Papi collection.")
            } else {
                LazyVGrid(columns:typeSize.isAccessibilitySize ? [GridItem(.flexible())]:[GridItem(.adaptive(minimum:170),spacing:12)],spacing:14) {
                    ForEach(posts){post in
                        if store.usesCloudWallet,post.id.hasPrefix("editorial-") {CoffeeCollectionTile(post:post,height:210)}
                        else {CoffeeMomentTile(post:post,height:210)}
                    }
                }
            }
        }
    }

    private func shelfButton(_ title:String,count:Int,index:Int,selected:Int)->some View {
        Button {selectedShelf=index} label:{
            HStack(spacing:8) {
                PapiText(title).font(CoffeeType.face(.subheadline,weight:.semibold))
                PapiText(verbatim:String(count)).font(CoffeeType.face(.caption,weight:.semibold))
            }.padding(.horizontal,12).padding(.vertical,12).frame(maxWidth:.infinity,minHeight:46)
                .background(selected==index ? Color.butter:Color.clear,in:RoundedRectangle(cornerRadius:14))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected==index ? .isSelected:[])
    }
}
