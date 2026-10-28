import SwiftUI
import PhotosUI
import AVFoundation

struct CoffeeJournalView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.caption) private var portraitNameLineHeight:CGFloat=18
    @State private var lastDismissedPortrait:String?
    var body:some View {
        PapiScreen {
            GeometryReader { geo in
                let viewportWidth=max(0,min(1200,geo.size.width))
                let contentWidth=max(0,viewportWidth-32)
                let bannerWidth=max(0,(contentWidth-10)/2)
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        HStack(alignment:.center) {
                            VStack(alignment:.leading,spacing:5) {
                                PapiText("Coffee Community").font(CoffeeType.display(size:27,weight:.heavy)).italic().minimumScaleFactor(0.85)
                                PapiText("Discover & share coffee moments").font(CoffeeType.display(.caption)).foregroundStyle(Color.mutedCoffee)
                            }
                            Spacer(minLength:4)
                            PapiIconButton(asset:"plus",label:"Create a post") {router.sheet = .compose}
                        }
                        HStack(spacing:10) {
                            Button {router.go(.cafes)} label:{Image("exploreBanner").resizable().scaledToFit().frame(width:bannerWidth)}
                            Button {router.go(.beans)} label:{Image("beansBanner").resizable().scaledToFit().frame(width:bannerWidth)}
                        }.buttonStyle(.plain)
                        let portraits=store.communityPeople.filter{!store.isUserHidden($0.id) && !(store.state.dismissedRecommendations?.contains($0.id) ?? false)}
                        if store.usesCloudWallet && store.cloudProfiles==nil {
                            PapiTextButton("Retry members"){Task {await store.refreshCloudSocial()}}.disabled(store.cloudSocialBusy)
                        }
                        if !portraits.isEmpty || lastDismissedPortrait != nil {
                            VStack(alignment:.leading,spacing:8) {
                                HStack(alignment:.firstTextBaseline,spacing:8) {
                                    PapiText("Around the coffee table").font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                                    Spacer(minLength:4)
                                    if let lastDismissedPortrait {
                                        PapiTextButton("Undo") {
                                            if store.commit({state in _ = state.dismissedRecommendations?.remove(lastDismissedPortrait)}) {self.lastDismissedPortrait=nil}
                                        }.font(CoffeeType.face(.caption,weight:.semibold)).frame(minHeight:44)
                                    } else {
                                        PapiText(store.usesCloudWallet ? "Coffee members":"Collection portraits").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
                                    }
                                }
                                if !portraits.isEmpty {ScrollView(.horizontal) {
                                    LazyHStack(alignment:.top,spacing:14) {
                                        ForEach(portraits) {person in
                                            VStack(spacing:6) {
                                                ZStack(alignment:.topTrailing) {
                                                    Button {router.go(.person(person.id))} label:{
                                                    Avatar(name:person.portrait,size:typeSize.isAccessibilitySize ? 88:70)
                                                        .frame(width:typeSize.isAccessibilitySize ? 150:96,height:(typeSize.isAccessibilitySize ? 88:70)+8)
                                                    }.buttonStyle(.plain).papiAccessibilityLabel(person.name)
                                                    Button {
                                                        if store.commit({state in
                                                            var dismissed=state.dismissedRecommendations ?? []
                                                            dismissed.insert(person.id)
                                                            state.dismissedRecommendations=dismissed
                                                        }) {lastDismissedPortrait=person.id}
                                                    } label:{
                                                        Image("dismissPortrait").resizable().scaledToFit().frame(width:30,height:30)
                                                            .frame(width:44,height:44,alignment:.topTrailing).contentShape(Rectangle())
                                                    }.buttonStyle(.plain).papiAccessibilityLabel("Remove recommendation for \(person.name)")
                                                }
                                                Button {router.go(.person(person.id))} label:{
                                                    PapiText(verbatim:person.name).font(CoffeeType.face(.caption)).multilineTextAlignment(.center)
                                                        .lineLimit(typeSize.isAccessibilitySize ? 2:1).minimumScaleFactor(0.85)
                                                }.buttonStyle(.plain)
                                            }.frame(width:typeSize.isAccessibilitySize ? 150:96)
                                        }
                                    }
                                    .padding(.vertical,4)
                                }.scrollIndicators(.hidden).frame(width:contentWidth,height:(typeSize.isAccessibilitySize ? 88:70)+22+portraitNameLineHeight*(typeSize.isAccessibilitySize ? 2:1)).clipped()}
                            }
                        }
                        Button {router.openWallet()} label:{
                            let walletLayout=typeSize.isAccessibilitySize || geo.size.width<330 ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)):AnyLayout(HStackLayout(spacing:10))
                            walletLayout {
                                PapiText("Coffee reserve").font(CoffeeType.face(.subheadline,weight:.semibold)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                                HStack(spacing:8) {
                                    CoffeeCurrentBalance()
                                    PapiText("Recharge").font(CoffeeType.face(.caption,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                                }
                            }.padding(.horizontal,16).padding(.vertical,13).frame(minHeight:52).background(Color.butter,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                        HStack(spacing:7) {
                            Image("coffeeUpdates").resizable().scaledToFit().frame(width:22,height:26)
                            PapiText("Coffee Updates").font(CoffeeType.face(.headline))
                            Spacer()
                            if !store.usesCloudWallet {PapiText("Coffee collection").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)}
                        }
                        if store.usesCloudWallet && store.cloudFeed==nil {
                            PapiText(store.cloudFeedBusy ? "Loading moments…":"Moments unavailable")
                            PapiTextButton("Retry"){Task {await store.refreshCloudFeed()}}.disabled(store.cloudFeedBusy)
                        }
                        let collectionIDs=Set(store.visibleCollectionPosts.map(\.id))
                        let posts=store.usesCloudWallet ? store.visiblePosts+store.visibleCollectionPosts:store.visiblePosts
                        if posts.isEmpty && (!store.usesCloudWallet || store.cloudFeed != nil) {
                            PapiText("No moments yet").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)
                        }
                        if store.usesCloudWallet && store.cloudFeedHasMore {PapiTextButton("Load more"){Task {await store.loadMoreCloudFeed()}}.disabled(store.cloudFeedBusy)}
                        let count=typeSize.isAccessibilitySize ? 1:max(1,Int((contentWidth+12)/182))
                        let tileWidth=max(0,(contentWidth-CGFloat(count-1)*12)/CGFloat(count))
                        HStack(alignment:.top,spacing:12) {
                            ForEach(0..<count,id:\.self) { column in
                                LazyVStack(spacing:14) {
                                    ForEach(Array(posts.enumerated()).filter{$0.offset%count==column},id:\.element.id) { index,post in
                                        if store.usesCloudWallet && collectionIDs.contains(post.id) {
                                            CoffeeCollectionTile(post:post,height:tileWidth*(index%3==1 ? 1.42:1.18)).frame(width:tileWidth).clipped()
                                        } else {
                                            CoffeeMomentTile(post:post,height:tileWidth*(index%3==1 ? 1.42:1.18)).frame(width:tileWidth).clipped()
                                        }
                                    }
                                }.frame(width:tileWidth)
                            }
                        }
                    }.frame(width:contentWidth,alignment:.leading).padding(.horizontal,16).padding(.top,12).padding(.bottom,20).frame(width:viewportWidth).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively).frame(width:geo.size.width,height:geo.size.height).clipped()
            }
        }.task(id:store.state.cloudAccountID) {if store.usesCloudWallet {await store.refreshCloudFeed()}}
    }
}
struct CoffeeCollectionTile:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    let post:CoffeeMoment
    let height:CGFloat
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            ZStack(alignment:.topTrailing) {
                Button {router.go(.post(post.id))} label:{
                    PapiImage(name:post.media).frame(height:height).frame(maxWidth:.infinity).clipped()
                }.buttonStyle(.plain)
                if post.isVideo {PapiText("Video").font(CoffeeType.face(.caption,weight:.bold)).padding(7).background(Color.coffee.opacity(0.85),in:Capsule()).foregroundStyle(.white).padding(.top,52).padding(.trailing,8)}
                PapiIconButton(asset:"more",label:"Post options",size:20){router.sheet = .safety(.post(post))}
                    .background(Color.cream.opacity(0.95),in:Circle()).padding(5)
            }
            VStack(alignment:.leading,spacing:3) {
                PapiText(post.category).font(CoffeeType.face(.caption2,weight:.medium)).foregroundStyle(Color.coffee)
                PapiUserLink(userID:post.authorID,size:26)
                CoffeeEditorialReactions(post:post,openComments:{router.go(.post(post.id))})
            }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,10).padding(.top,8).background(Color.peach.opacity(0.55))
        }.clipShape(RoundedRectangle(cornerRadius:18))
    }
}
struct CoffeeEditorialReactions:View {
    @EnvironmentObject private var store:CoffeeHouse
    let post:CoffeeMoment
    var openComments:()->Void
    var body:some View {
        if let summary=store.editorialSummaries[post.id] {
            HStack(spacing:12) {
                Button {Task {await store.changeEditorialLike(post.id)}} label:{
                    HStack(spacing:4) {Image("like").resizable().scaledToFit().frame(width:22,height:22).opacity(summary.liked ? 1:0.48);Text(summary.like_count,format:.number)}.frame(minWidth:44,minHeight:44)
                }.papiAccessibilityLabel(summary.liked ? "Unlike":"Like").disabled(store.editorialBusy || store.cloudFeedBusy)
                Button(action:openComments) {
                    HStack(spacing:4) {Image("comment").resizable().scaledToFit().frame(width:22,height:22);Text(summary.comment_count,format:.number)}.frame(minWidth:44,minHeight:44)
                }.papiAccessibilityLabel("Open comments")
                Spacer(minLength:0)
            }.font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.coffee).buttonStyle(.plain)
        }
    }
}
struct CoffeeMomentTile:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    let post:CoffeeMoment
    var height:CGFloat=220
    var body:some View {
        VStack(spacing:0) {
            Button {router.go(.post(post.id))} label:{
                ZStack(alignment:.topTrailing) {
                    if post.isVideo && post.media.hasPrefix("cloud/") {PapiImage(name:"emptyCup").frame(height:height).frame(maxWidth:.infinity).clipped()}
                    else {PapiImage(name:post.media).frame(height:height).frame(maxWidth:.infinity).clipped()}
                    if post.isVideo {PapiText("Video").font(CoffeeType.face(.caption,weight:.bold)).padding(7).background(Color.coffee.opacity(0.85),in:Capsule()).foregroundStyle(.white).padding(8)}
                }
            }.buttonStyle(.plain)
            HStack(spacing:4) {PapiUserLink(userID:post.authorID,size:32);Spacer(minLength:0);PapiIconButton(asset:"more",label:"Safety options",size:20){router.sheet = .safety(.post(post))}}
                .padding(.horizontal,9).padding(.vertical,5).background(Color.cream)
            VStack(alignment:.leading,spacing:0) {
                PapiText(post.category).font(CoffeeType.face(.caption2,weight:.medium)).fixedSize(horizontal:false,vertical:true).padding(.top,7)
                CoffeeMomentReactions(post:post,openComments:{router.go(.post(post.id))})
            }.padding(.horizontal,10).background(Color.peach.opacity(0.55))
        }.clipShape(RoundedRectangle(cornerRadius:18)).buttonStyle(.plain)
    }
}
struct CoffeeMomentReactions:View {
    @EnvironmentObject private var store:CoffeeHouse
    let post:CoffeeMoment
    var showsBookmark=false
    var openComments:()->Void
    var body:some View {
        HStack(spacing:12) {
            Button {if store.usesCloudWallet {if let id=UUID(uuidString:post.id),let item=store.cloudFeedItem(post.id) {Task {await store.changeCloudReaction(id,bookmarks:false,enabled:!item.liked)}}} else {store.toggleLike(post.id)}} label:{
                HStack(spacing:4) {
                    Image("like").resizable().scaledToFit().frame(width:22,height:22).opacity((store.usesCloudWallet ? (store.cloudFeedItem(post.id)?.liked ?? false):store.state.appreciatedMoments.contains(post.id)) ? 1:0.48)
                    Text(store.appreciationCount(for:post),format:.number).monospacedDigit().fixedSize()
                }.frame(minWidth:44,minHeight:44)
            }.disabled(store.usesCloudWallet && store.cloudFeedBusy).papiAccessibilityLabel((store.usesCloudWallet ? (store.cloudFeedItem(post.id)?.liked ?? false):store.state.appreciatedMoments.contains(post.id)) ? "Unlike":"Like")
                .accessibilityValue(Text(store.appreciationCount(for:post),format:.number))
            Button(action:openComments) {
                HStack(spacing:4) {
                    Image("comment").resizable().scaledToFit().frame(width:22,height:22)
                    Text(store.usesCloudWallet ? (store.cloudFeedItem(post.id)?.comment_count ?? 0):store.visibleComments(post.id).count,format:.number).monospacedDigit().fixedSize()
                }.frame(minWidth:44,minHeight:44)
            }.papiAccessibilityLabel("Open comments").accessibilityValue(Text(store.usesCloudWallet ? (store.cloudFeedItem(post.id)?.comment_count ?? 0):store.visibleComments(post.id).count,format:.number))
            if showsBookmark {
                PapiIconButton(asset:"star",label:"Save coffee moment",size:24){if store.usesCloudWallet {if let id=UUID(uuidString:post.id),let item=store.cloudFeedItem(post.id) {Task {await store.changeCloudReaction(id,bookmarks:true,enabled:!item.bookmarked)}}} else {store.toggleBookmark(post.id)}}.disabled(store.usesCloudWallet && store.cloudFeedBusy).opacity((store.usesCloudWallet ? (store.cloudFeedItem(post.id)?.bookmarked ?? false):store.state.keptMoments.contains(post.id)) ? 1:0.45)
            }
            Spacer(minLength:0)
        }.font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.coffee).buttonStyle(.plain)
    }
}
struct CoffeeMomentView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.papiBounds) private var bounds
    let momentID:String
    @State private var comment=""
    @State private var confirmDelete=false
    var body:some View {
        PapiScreen {
            if let post=store.post(momentID),store.usesCloudWallet,store.visibleCollectionPosts.contains(where:{$0.id==momentID}) {
                CoffeeCollectionDetail(post:post)
            } else if let post=store.post(momentID) {
                VStack(spacing:0) {
                    PapiHeader("Coffee moment") {
                        PapiIconButton(asset:"more",label:"Post options") {
                            if post.isOwnMoment {confirmDelete=true} else {router.sheet = .safety(.post(post))}
                        }
                    }
                    ScrollViewReader {reader in
                        ScrollView {
                            VStack(alignment:.leading,spacing:20) {
                                VStack(alignment:.leading,spacing:14) {
                                    HStack(spacing:12) {
                                        PapiUserLink(userID:post.authorID,size:46,showsName:false)
                                        VStack(alignment:.leading,spacing:3) {
                                            Button {router.go(.person(post.authorID))} label:{PapiText(verbatim:store.person(post.authorID)?.name ?? store.text("Coffee member")).font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)}.buttonStyle(.plain)
                                            PapiText(post.category).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                        }
                                        Spacer(minLength:0)
                                    }
                                    let mediaHeight=post.isVideo ? min(470,max(300,(bounds.width > 0 ? bounds.width:320)*1.02)):min(470,max(260,(bounds.width > 0 ? bounds.width:320)*0.95))
                                    if post.isVideo && post.media.hasPrefix("cloud/") {CloudMomentVideo(media:post.media).frame(height:mediaHeight)}
                                    else if post.isVideo {CoffeePlayerView(media:post.media).frame(height:mediaHeight)}
                                    else {
                                        Button {router.go(.photo(post.media))} label:{
                                            PapiImage(name:post.media).frame(height:mediaHeight).clipShape(RoundedRectangle(cornerRadius:18))
                                        }.buttonStyle(.plain).papiAccessibilityLabel("Open photo")
                                    }
                                    PapiText(verbatim:post.caption).font(CoffeeType.face(.body)).fixedSize(horizontal:false,vertical:true)
                                    CoffeeMomentReactions(post:post,showsBookmark:true,openComments:{withAnimation{reader.scrollTo("cup-notes",anchor:.top)}})
                                }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:24))
                                let tastingReplies=store.visibleComments(momentID)
                                HStack(alignment:.center,spacing:12) {
                                    PapiArtworkFit(asset:"momentNoteArt").frame(width:62,height:62)
                                    VStack(alignment:.leading,spacing:3) {
                                        PapiText("Cup notes").font(CoffeeType.display(.title3,weight:.bold))
                                        HStack(spacing:4) {
                                            Text(store.usesCloudWallet ? (store.cloudFeedItem(momentID)?.comment_count ?? 0):tastingReplies.count,format:.number).monospacedDigit()
                                            PapiText("Comments")
                                        }.font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                    }
                                    Spacer(minLength:0)
                                }.id("cup-notes")
                                if store.usesCloudWallet,let id=UUID(uuidString:momentID),store.cloudComments[id]==nil {
                                    PapiText(store.cloudCommentsBusy ? "Loading comments…":"Comments unavailable")
                                    PapiTextButton("Retry"){Task {await store.refreshCloudComments(id)}}.disabled(store.cloudCommentsBusy)
                                } else if tastingReplies.isEmpty {PapiText("Keep a tasting note or thought about this moment.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)}
                                if let id=UUID(uuidString:momentID),store.usesCloudWallet,store.cloudCommentsHasMore[id]==true {PapiTextButton("Load earlier comments"){Task {await store.loadEarlierCloudComments(id)}}.disabled(store.cloudCommentsBusy)}
                                ForEach(tastingReplies) { note in
                                    HStack(alignment:.top,spacing:10) {
                                        PapiUserLink(userID:note.authorID ?? store.state.passport.id.uuidString,size:38,showsName:false)
                                        VStack(alignment:.leading,spacing:6) {
                                            Button {router.go(.person(note.authorID ?? store.state.passport.id.uuidString))} label:{PapiText(verbatim:store.person(note.authorID ?? store.state.passport.id.uuidString)?.name ?? "My coffee corner").font(CoffeeType.face(.caption,weight:.bold))}.buttonStyle(.plain)
                                            PapiText(verbatim:note.text).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                                            if store.usesCloudWallet,let moment=UUID(uuidString:momentID),let noteID=UUID(uuidString:note.id),let value=store.cloudComments[moment]?.first(where:{$0.id==noteID}),value.moderation_status != "approved" {PapiText(value.moderation_status == "rejected" ? "Not approved":"Under review").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)}
                                            Text(note.createdAt,style:.date).font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
                                        }.frame(maxWidth:.infinity,alignment:.leading)
                                        PapiIconButton(asset:"more",label:"Comment options",size:19) {router.sheet = .safety(.comment(note,owner:store.state.passport.id.uuidString))}
                                        if note.authorID==nil || note.authorID==store.state.passport.id.uuidString || note.authorID==store.state.cloudAccountID?.uuidString {PapiIconButton(asset:"trash",label:"Delete note",size:19) {if store.usesCloudWallet {if let id=UUID(uuidString:note.id),let moment=UUID(uuidString:momentID) {Task {await store.deleteCloudComment(id,moment:moment)}}} else {_ = store.commit{$0.tastingReplies.removeAll{$0.id==note.id}}}}.disabled(store.cloudCommentsBusy)}
                                    }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.88),in:RoundedRectangle(cornerRadius:18))
                                }
                            }.padding(.horizontal,16).padding(.top,8).padding(.bottom,20).frame(maxWidth:760).frame(maxWidth:.infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge:.bottom,spacing:0) {
                            PapiInputBar(background:.cream) {
                                PapiInput("Tell your opinion…",text:$comment,axis:.vertical).lineLimit(1...3).foregroundStyle(Color.coffee).tint(Color.coffee).padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:18)).disabled(store.usesCloudWallet && store.state.pendingCloudComment != nil)
                            } actions: {
                                PapiTextButton("SAVE") {if store.usesCloudWallet {if let id=UUID(uuidString:momentID) {let body=comment;Task {if await store.submitCloudComment(moment:id,text:body),comment==body {comment=""}}}} else if store.addComment(momentID:momentID,text:comment) {comment=""}}.font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(.white).padding(12).frame(minHeight:44).background(Color.coffee,in:Capsule()).disabled(comment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.cloudCommentsBusy || (store.state.pendingCloudComment != nil && store.state.pendingCloudComment?.momentID.uuidString != momentID)).opacity(comment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0.45:1)
                            }
                        }
                    }
                }.overlay {
                    if confirmDelete {PapiDialog(title:"Remove this coffee moment?",message:"This moment will be removed from your coffee book. Coins already used are not refunded.",confirm:"Delete post",cancel:"Keep post",action:{confirmDelete=false;if store.usesCloudWallet {if let id=UUID(uuidString:momentID) {Task {if await store.deleteCloudSubmission(id) {await store.refreshCloudFeedItem(id);dismiss()}}}} else {store.deletePost(momentID);dismiss()}},dismiss:{confirmDelete=false})}
                }
            } else {VStack(spacing:0){PapiHeader("Coffee moment");ScrollView {PapiEmpty(title:"This content is unavailable")}}}
        }.task(id:momentID) {
            if store.usesCloudWallet,let id=UUID(uuidString:momentID) {
                if let pending=store.state.pendingCloudComment,pending.momentID==id {comment=pending.body}
                await store.refreshCloudComments(id)
            }
        }
    }
}
struct CoffeeCollectionDetail:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.papiBounds) private var bounds
    @State private var comment=""
    let post:CoffeeMoment
    var body:some View {
        VStack(spacing:0) {
            PapiHeader("Coffee moment") {PapiIconButton(asset:"more",label:"Post options") {router.sheet = .safety(.post(post))}}
            ScrollViewReader {reader in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        HStack(spacing:11) {
                            Button {router.go(.person(post.authorID))} label:{
                                HStack(spacing:11) {
                                    Avatar(name:store.person(post.authorID)?.portrait ?? "emptyCup",size:46)
                                    VStack(alignment:.leading,spacing:3) {
                                        PapiText(verbatim:store.person(post.authorID)?.name ?? "Coffee lover").font(CoffeeType.face(.headline))
                                        PapiText(post.category).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                    }
                                }.frame(minHeight:46).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Spacer(minLength:0)
                            if post.isVideo {PapiText("Video").font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.mutedCoffee)}
                        }.padding(.horizontal,4)
                        let mediaHeight=post.isVideo ? min(470,max(300,(bounds.width > 0 ? bounds.width:320)*1.02)):min(470,max(260,(bounds.width > 0 ? bounds.width:320)*0.95))
                        if post.isVideo {CoffeePlayerView(media:post.media).frame(height:mediaHeight)}
                        else {
                            Button {router.go(.photo(post.media))} label:{PapiImage(name:post.media).frame(height:mediaHeight).clipShape(RoundedRectangle(cornerRadius:20))}
                                .buttonStyle(.plain).papiAccessibilityLabel("Open photo")
                        }
                        VStack(alignment:.leading,spacing:12) {
                            PapiText(verbatim:post.caption).font(CoffeeType.face(.body)).fixedSize(horizontal:false,vertical:true)
                            if store.editorialSummaries[post.id] != nil {
                                CoffeeEditorialReactions(post:post,openComments:{withAnimation {reader.scrollTo("editorial-notes",anchor:.top)}})
                            } else {
                                PapiTextButton(store.editorialBusy ? "Loading comments…":"Retry") {Task {await store.refreshEditorial(post.id)}}.disabled(store.editorialBusy)
                            }
                        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:20))
                        HStack(spacing:12) {
                            PapiArtworkFit(asset:"momentNoteArt").frame(width:50,height:50)
                            VStack(alignment:.leading,spacing:3) {
                                PapiText("Cup notes").font(CoffeeType.display(.title3,weight:.bold))
                                PapiText("Comments").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                            }
                            Spacer()
                        }.id("editorial-notes")
                        if let notes=store.editorialComments[post.id] {
                            let visible=notes.filter {note in store.isTargetVisible(.init(kind:.editorialComment,contentReference:note.id.uuidString,authorID:note.author_id.uuidString,parentReference:post.id))}
                            if visible.isEmpty {PapiText("Keep a tasting note or thought about this moment.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee)}
                            ForEach(visible) {note in
                                HStack(alignment:.top,spacing:10) {
                                    PapiUserLink(userID:note.author_id.uuidString,size:38,showsName:false)
                                    VStack(alignment:.leading,spacing:5) {
                                        PapiText(verbatim:store.person(note.author_id.uuidString)?.name ?? "Coffee lover").font(CoffeeType.face(.caption,weight:.bold))
                                        PapiText(verbatim:note.body).font(CoffeeType.face(.subheadline)).fixedSize(horizontal:false,vertical:true)
                                        if note.moderation_status != "approved" {PapiText(note.moderation_status == "rejected" ? "Not approved":"Under review").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)}
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    if note.author_id==store.state.cloudAccountID {
                                        PapiIconButton(asset:"trash",label:"Delete note",size:19) {Task {await store.removeEditorialComment(note.id,key:post.id)}}.disabled(store.editorialBusy)
                                    } else {
                                        PapiIconButton(asset:"more",label:"Comment options",size:19) {router.sheet = .safety(.init(kind:.editorialComment,contentReference:note.id.uuidString,authorID:note.author_id.uuidString,parentReference:post.id))}
                                    }
                                }.padding(14).background(Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:18))
                            }
                        }
                    }.padding(.horizontal,16).padding(.top,8).padding(.bottom,20).frame(maxWidth:760).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge:.bottom,spacing:0) {
                    PapiInputBar(background:.cream) {
                        PapiInput("Tell your opinion…",text:$comment,axis:.vertical).lineLimit(1...3).foregroundStyle(Color.coffee).tint(Color.coffee).padding(12).background(Color.white,in:RoundedRectangle(cornerRadius:18)).disabled(store.state.pendingCloudEditorialComment != nil)
                    } actions: {
                        PapiTextButton("SAVE") {let body=comment;Task {if await store.sendEditorialComment(post.id,text:body),comment==body {comment=""}}}
                            .font(CoffeeType.face(.caption,weight:.bold)).foregroundStyle(.white).padding(12).frame(minHeight:44).background(Color.coffee,in:Capsule())
                            .disabled(comment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || store.editorialBusy || (store.state.pendingCloudEditorialComment != nil && store.state.pendingCloudEditorialComment?.momentID != post.id))
                    }
                }
            }
        }.task(id:post.id) {
            if let pending=store.state.pendingCloudEditorialComment,pending.momentID==post.id {comment=pending.body}
            await store.refreshEditorial(post.id)
        }
    }
}
struct CoffeeMomentComposer:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.papiBounds) private var bounds
    @Environment(\.layoutDirection) private var direction
    @State private var item:PhotosPickerItem?
    @State private var importing=false
    @State private var camera=false
    @State private var movieCamera=false
    @State private var confirm=false
    private var caption:Binding<String> {Binding(get:{store.state.momentDraft.text},set:{newValue in if store.state.pendingCloudMoment==nil {_ = store.commit{$0.momentDraft.text=String(newValue.prefix(2000))}}})}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("A coffee moment")
                ScrollView {
                    VStack(alignment:.leading,spacing:16) {
                        if let media=store.state.momentDraft.media {
                            if store.state.momentDraft.isVideo {CoffeePlayerView(media:media).frame(height:260)}
                            else {PapiImage(name:media).frame(height:260).clipped().clipShape(RoundedRectangle(cornerRadius:18))}
                        }
                        let hasDraftMedia=store.state.momentDraft.media != nil
                        PhotosPicker(selection:$item,matching:.any(of:[.images,.videos]),photoLibrary:.shared()) {
                            HStack(spacing:16) {
                                if !hasDraftMedia {
                                    PapiArtworkFit(asset:"momentComposeArt").frame(width:typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<330) ? 72:100,height:typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<330) ? 72:100)
                                }
                                VStack(alignment:.leading,spacing:6) {
                                    PapiText(importing ? "Importing…":(!hasDraftMedia ? "Add pictures or videos…":"Choose a different photo or video"))
                                        .font(CoffeeType.face(.headline)).fixedSize(horizontal:false,vertical:true)
                                    if !hasDraftMedia {
                                        PapiText("A coffee moment").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                    }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                                Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:12,height:12).accessibilityHidden(true)
                            }.padding(16).frame(maxWidth:.infinity,minHeight:70,alignment:.leading).background(Color.white.opacity(0.93),in:RoundedRectangle(cornerRadius:22)).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(importing || store.state.pendingCloudMoment != nil)
                        let cameraLayout=typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<330) ? AnyLayout(VStackLayout(spacing:10)):AnyLayout(HStackLayout(spacing:10))
                        cameraLayout {
                            PapiTextButton("Take photo"){openCamera(movie:false)}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:15))
                            PapiTextButton("Record video"){openCamera(movie:true)}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:15))
                        }.disabled(importing || store.state.pendingCloudMoment != nil)
                        VStack(alignment:.leading,spacing:10) {
                            PapiText("Your coffee note").font(CoffeeType.face(.headline))
                            PapiInput("Say something about your coffee…",text:caption,axis:.vertical).lineLimit(4...10).foregroundStyle(Color.coffee).tint(Color.coffee).padding(14).background(Color.cream,in:RoundedRectangle(cornerRadius:15)).disabled(store.state.pendingCloudMoment != nil)
                            HStack {PapiText("Draft");Spacer(minLength:8);PapiText("\(store.state.momentDraft.text.count)/2000").monospacedDigit()}.font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.white.opacity(0.93),in:RoundedRectangle(cornerRadius:22))
                        VStack(alignment:.leading,spacing:12) {
                            let costLayout=typeSize.isAccessibilitySize || (bounds.width>0 && bounds.width<330) ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)):AnyLayout(HStackLayout(spacing:6))
                            costLayout {
                                PapiText("Save a post for").frame(maxWidth:.infinity,alignment:.leading)
                                HStack(spacing:6) {CoinLabel(value:CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo));PapiText("coins")}
                            }.font(CoffeeType.face(.subheadline,weight:.semibold))
                            PapiText(store.usesCloudWallet ? "Posts remain private until reviewed and approved.":"Posts stay private until approved. No moderation server is connected yet; pending posts are never approved automatically.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                            if store.state.pendingCloudMoment != nil {PapiText("Retry the saved submission to confirm its result.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)}
                            PapiTextButton("Submit for review") {confirm=true}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(importing || store.state.momentDraft.media==nil || store.cloudWalletBusy || (store.usesCloudWallet && store.cloudWallet==nil))
                            if store.usesCloudWallet && store.cloudWallet==nil {PapiTextButton("Retry wallet"){Task {await store.refreshCloudWallet()}}.disabled(store.cloudWalletBusy)}
                        }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter.opacity(0.55),in:RoundedRectangle(cornerRadius:22))
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.overlay {
                if confirm {CoffeeModal(maximumWidth:370,maximumHeight:570,shade:Color.coffee.opacity(0.55),artwork:nil) {
                    VStack(alignment:.leading,spacing:15) {
                        PapiArtworkFit(asset:"momentComposeArt").frame(width:90,height:90)
                        PapiText("Submit for review?").font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                        PapiText("\(CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo)) coins are used when this post is saved to your private review queue. It appears in the feed only after approval.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PapiText(store.usesCloudWallet ? "Posts remain private until reviewed and approved.":"Posts stay private until approved. No moderation server is connected yet; pending posts are never approved automatically.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                        PapiTextButton("Submit · \(CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo)) coins") {confirm=false;if store.usesCloudWallet {Task {if await store.cloudSubmitMoment(){dismiss()}}} else if store.publish(){dismiss();store.notice = .init(title:"Post saved for review",message:"Your post is saved privately in the review queue. It will appear only after approval. No moderation server is connected yet.",kind:.review)}}.buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16))
                        PapiTextButton("Keep editing"){confirm=false}.buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:16))
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }}
            }
        }.onChange(of:item) {_,value in
            guard let value,!importing else{return}
            let owner=store.state.passport.id;importing=true
            Task {await importItem(value,owner:owner)}
        }
        .fullScreenCover(isPresented:$camera) {
            CameraPicker(movie:movieCamera) {result in
                camera=false
                guard let result else{return}
                do {let output=try result.get(); let name:String;let video:Bool
                    switch output {
                    case .photo(let data):name=try CoffeeMedia.saveImage(data,guest:store.state.passport.id);video=false
                    case .movie(let url):name=try CoffeeMedia.saveMovie(url,guest:store.state.passport.id);video=true
                    }
                    _ = store.commit{$0.momentDraft.media=name;$0.momentDraft.isVideo=video}
                } catch {store.inform("Could not import media",error.localizedDescription)}
            }.ignoresSafeArea()
        }
    }
    private func openCamera(movie:Bool) {
        guard !importing else{return}
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {store.inform("Camera unavailable","Choose an existing photo or video instead.");return}
        movieCamera=movie;camera=true
    }
    @MainActor private func importItem(_ selection:PhotosPickerItem,owner:UUID) async {
        defer {importing=false;item=nil}
        guard store.state.signedIn,store.state.passport.id==owner else{return}
        do {
            let name:String;let video=selection.supportedContentTypes.contains{$0.conforms(to:.movie)}
            if video {
                guard let file=try await selection.loadTransferable(type:ImportedMovie.self) else {throw CoffeeMedia.MediaError.invalid}
                defer {try? FileManager.default.removeItem(at:file.url)}
                guard store.state.signedIn,store.state.passport.id==owner else{return}
                name=try CoffeeMedia.saveMovie(file.url,guest:owner)
            } else {
                guard let data=try await selection.loadTransferable(type:Data.self) else {throw CoffeeMedia.MediaError.invalid}
                guard store.state.signedIn,store.state.passport.id==owner else{return}
                name=try CoffeeMedia.saveImage(data,guest:owner)
            }
            guard store.state.signedIn,store.state.passport.id==owner else{return}
            _ = store.commit{$0.momentDraft.media=name;$0.momentDraft.isVideo=video}
        } catch {store.inform("Could not import media",error.localizedDescription)}
    }
}
struct PhotoDetailView:View {
    var name:String
    @EnvironmentObject private var store:CoffeeHouse
    @State private var selection=0
    @State private var started=false
    private var photos:[String] {
        if name.hasPrefix("cloud/"),let account=store.state.cloudAccountID {
            let cloud=(store.cloudProfileImages[account] ?? []).filter{$0.kind=="album" && $0.moderation_status=="approved"}.compactMap{store.profileImageReference($0.media_path,owner:account)}
            if cloud.contains(name) {return cloud}
        }
        let album=store.state.passport.photos
        return album.contains(name) ? album:[name]
    }
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("Photo \(selection+1) / \(photos.count)")
                TabView(selection:$selection) {
                    ForEach(Array(photos.enumerated()),id:\.element) {index,photo in ZoomablePhoto(name:photo).tag(index)}
                }.tabViewStyle(.page(indexDisplayMode:.never))
            }
        }.onAppear{if !started{selection=photos.firstIndex(of:name) ?? 0;started=true}}
    }
}

private struct ZoomablePhoto:View {
    var name:String
    @State private var scale:CGFloat=1
    @GestureState private var gestureScale:CGFloat=1
    @State private var offset:CGSize = .zero
    @GestureState private var drag:CGSize = .zero
    var body:some View {
        GeometryReader {proxy in
            let zoom=min(4,max(1,scale*gestureScale))
            let position=limited(CGSize(width:offset.width+drag.width,height:offset.height+drag.height),zoom:zoom,size:proxy.size)
            PapiImage(name:name,fit:true).frame(width:proxy.size.width,height:proxy.size.height)
                .scaleEffect(zoom).offset(position)
                .gesture(MagnificationGesture().updating($gestureScale){value,state,_ in state=value}.onEnded{scale=min(4,max(1,scale*$0));offset=limited(offset,zoom:scale,size:proxy.size)})
                .simultaneousGesture(DragGesture().updating($drag){value,state,_ in state=value.translation}.onEnded{value in offset=limited(CGSize(width:offset.width+value.translation.width,height:offset.height+value.translation.height),zoom:scale,size:proxy.size)},including:scale>1 ? .all:.none)
                .onTapGesture(count:2){scale=scale>1 ? 1:2;offset = .zero}
                .onChange(of:proxy.size){_,size in offset=limited(offset,zoom:scale,size:size)}
        }.clipped().papiAccessibilityLabel("Photo. Double tap to zoom.")
    }
    private func limited(_ point:CGSize,zoom:CGFloat,size:CGSize)->CGSize {
        let x=max(0,size.width*(zoom-1)/2),y=max(0,size.height*(zoom-1)/2)
        return CGSize(width:min(x,max(-x,point.width)),height:min(y,max(-y,point.height)))
    }
}
