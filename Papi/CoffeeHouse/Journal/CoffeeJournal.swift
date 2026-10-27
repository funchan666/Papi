import SwiftUI
import PhotosUI
import AVFoundation

struct CoffeeJournalView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.caption) private var portraitNameLineHeight:CGFloat=18
    var body:some View {
        PapiScreen {
            GeometryReader { geo in
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
                            Button {router.go(.cafes)} label:{Image("exploreBanner").resizable().scaledToFit()}
                            Button {router.go(.beans)} label:{Image("beansBanner").resizable().scaledToFit()}
                        }.buttonStyle(.plain)
                        let portraits=CoffeeMember.previews.filter{!store.isUserHidden($0.id)}
                        if !portraits.isEmpty {
                            HStack {
                                PapiText("Around the coffee table").font(CoffeeType.face(.headline))
                                Spacer()
                                PapiText("Collection portraits").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
                            }
                            ScrollView(.horizontal) {
                                LazyHStack(alignment:.top,spacing:14) {
                                    ForEach(portraits) {person in
                                        Button {router.go(.person(person.id))} label:{
                                            VStack(spacing:8) {
                                                Avatar(name:person.portrait,size:typeSize.isAccessibilitySize ? 88:70)
                                                PapiText(verbatim:person.name).font(CoffeeType.face(.caption)).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                                            }.frame(width:typeSize.isAccessibilitySize ? 150:96)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.vertical,4)
                            }.scrollIndicators(.hidden).frame(height:(typeSize.isAccessibilitySize ? 88:70)+16+portraitNameLineHeight*2)
                        }
                        Button {router.openWallet()} label:{
                            HStack {PapiText("Coffee reserve").font(CoffeeType.face(.subheadline,weight:.semibold));Spacer();CoinLabel(value:store.state.coinBalance);PapiText("Recharge").font(CoffeeType.face(.caption,weight:.bold))}
                                .padding(14).background(Color.butter,in:RoundedRectangle(cornerRadius:16))
                        }.buttonStyle(.plain)
                        HStack(spacing:7) {
                            Image("coffeeUpdates").resizable().scaledToFit().frame(width:22,height:26)
                            PapiText("Coffee Updates").font(CoffeeType.face(.headline))
                            Spacer()
                            PapiText("Collection preview").font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
                        }
                        let width=min(1200,geo.size.width)
                        let count=typeSize.isAccessibilitySize ? 1:max(1,Int((width-20)/180))
                        let tileWidth=max(44,(width-32-CGFloat(count-1)*12)/CGFloat(count))
                        HStack(alignment:.top,spacing:12) {
                            ForEach(0..<count,id:\.self) { column in
                                LazyVStack(spacing:14) {
                                    ForEach(Array(store.visiblePosts.enumerated()).filter{$0.offset%count==column},id:\.element.id) { index,post in
                                        CoffeeMomentTile(post:post,height:tileWidth*(index%3==1 ? 1.42:1.18))
                                    }
                                }.frame(maxWidth:.infinity)
                            }
                        }
                    }.padding(.horizontal,16).padding(.top,12).padding(.bottom,20).frame(maxWidth:1200).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }
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
                    PapiImage(name:post.media).frame(height:height).frame(maxWidth:.infinity).clipped()
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
            Button {store.toggleLike(post.id)} label:{
                HStack(spacing:4) {
                    Image("like").resizable().scaledToFit().frame(width:22,height:22).opacity(store.state.appreciatedMoments.contains(post.id) ? 1:0.48)
                    Text(store.appreciationCount(for:post),format:.number).monospacedDigit().fixedSize()
                }.frame(minWidth:44,minHeight:44)
            }.papiAccessibilityLabel(store.state.appreciatedMoments.contains(post.id) ? "Unlike":"Like")
                .accessibilityValue(Text(store.appreciationCount(for:post),format:.number))
            Button(action:openComments) {
                HStack(spacing:4) {
                    Image("comment").resizable().scaledToFit().frame(width:22,height:22)
                    Text(store.visibleComments(post.id).count,format:.number).monospacedDigit().fixedSize()
                }.frame(minWidth:44,minHeight:44)
            }.papiAccessibilityLabel("Open comments").accessibilityValue(Text(store.visibleComments(post.id).count,format:.number))
            if showsBookmark {
                PapiIconButton(asset:"star",label:"Save coffee moment",size:24){store.toggleBookmark(post.id)}.opacity(store.state.keptMoments.contains(post.id) ? 1:0.45)
            }
            Spacer(minLength:0)
        }.font(CoffeeType.face(.caption,weight:.semibold)).foregroundStyle(Color.coffee).buttonStyle(.plain)
    }
}
struct CoffeeMomentView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    let momentID:String
    @State private var comment=""
    @State private var confirmDelete=false
    var body:some View {
        PapiScreen {
            if let post=store.post(momentID) {
                VStack(spacing:0) {
                    PapiHeader("Coffee moment") {
                        PapiIconButton(asset:"more",label:"Post options") {
                            if post.isOwnMoment {confirmDelete=true} else {router.sheet = .safety(.post(post))}
                        }
                    }
                    ScrollViewReader {reader in
                        ScrollView {
                            VStack(alignment:.leading,spacing:18) {
                                if post.isVideo {CoffeePlayerView(media:post.media).frame(height:380)}
                                else {Button {router.go(.photo(post.media))} label:{PapiImage(name:post.media).frame(height:350).clipped()}.buttonStyle(.plain)}
                                VStack(alignment:.leading,spacing:12) {
                                    HStack {
                                        PapiUserLink(userID:post.authorID,size:44,showsName:false)
                                        VStack(alignment:.leading,spacing:3) {
                                            Button {router.go(.person(post.authorID))} label:{PapiText(verbatim:store.person(post.authorID)?.name ?? "Papi coffee journal").font(CoffeeType.face(.headline))}.buttonStyle(.plain)
                                            PapiText(post.isOwnMoment ? "Saved on this device":"Collection preview").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                        }
                                        Spacer()
                                    }
                                    PapiText(verbatim:post.caption).font(CoffeeType.face(.body))
                                    CoffeeMomentReactions(post:post,showsBookmark:true,openComments:{withAnimation{reader.scrollTo("cup-notes",anchor:.top)}})
                                }.padding(16).background(Color.peach.opacity(0.25),in:RoundedRectangle(cornerRadius:20)).padding(.horizontal,16)
                                PapiText("Cup notes").font(CoffeeType.face(.headline)).padding(.horizontal,20).id("cup-notes")
                                let tastingReplies=store.visibleComments(momentID)
                                if tastingReplies.isEmpty {PapiText("Keep a tasting note or thought about this moment.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).padding(.horizontal,20)}
                                ForEach(tastingReplies) { note in
                                    HStack(alignment:.top,spacing:10) {
                                        PapiUserLink(userID:note.authorID ?? store.state.passport.id.uuidString,size:34,showsName:false)
                                        VStack(alignment:.leading,spacing:4) {
                                            Button {router.go(.person(note.authorID ?? store.state.passport.id.uuidString))} label:{PapiText(verbatim:store.person(note.authorID ?? store.state.passport.id.uuidString)?.name ?? "My coffee corner").font(CoffeeType.face(.caption,weight:.bold))}.buttonStyle(.plain)
                                            PapiText(verbatim:note.text);Text(note.createdAt,style:.date).font(CoffeeType.face(.caption2)).foregroundStyle(Color.mutedCoffee)
                                        }
                                        Spacer()
                                        PapiIconButton(asset:"more",label:"Comment options",size:19) {router.sheet = .safety(.comment(note,owner:store.state.passport.id.uuidString))}
                                        if note.authorID==nil || note.authorID==store.state.passport.id.uuidString {PapiIconButton(asset:"trash",label:"Delete note",size:19) {_ = store.commit{$0.tastingReplies.removeAll{$0.id==note.id}}}}
                                    }.padding(14).background(Color.white,in:RoundedRectangle(cornerRadius:15)).padding(.horizontal,16)
                                }
                            }.padding(.bottom,20).frame(maxWidth:760).frame(maxWidth:.infinity)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge:.bottom,spacing:0) {
                            PapiInputBar {
                                PapiInput("Tell your opinion…",text:$comment,axis:.vertical).lineLimit(1...3).foregroundStyle(.white).tint(.white).padding(12).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:18))
                            } actions: {
                                PapiTextButton("SAVE") {if store.addComment(momentID:momentID,text:comment) {comment=""}}.font(CoffeeType.face(.caption,weight:.bold)).padding(12).frame(minHeight:44).background(Color.cream,in:Capsule()).disabled(comment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }.overlay {
                    if confirmDelete {PapiDialog(title:"Remove this coffee moment?",message:"This moment will be removed from your coffee book. Coins already used are not refunded.",confirm:"Delete post",cancel:"Keep post",action:{store.deletePost(momentID);confirmDelete=false;dismiss()},dismiss:{confirmDelete=false})}
                }
            } else {VStack(spacing:0){PapiHeader("Coffee moment");ScrollView {PapiEmpty(title:"This content is unavailable")}}}
        }
    }
}
struct CoffeeMomentComposer:View {
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @State private var item:PhotosPickerItem?
    @State private var importing=false
    @State private var camera=false
    @State private var movieCamera=false
    @State private var confirm=false
    private var caption:Binding<String> {Binding(get:{store.state.momentDraft.text},set:{newValue in _ = store.commit{$0.momentDraft.text=String(newValue.prefix(2000))}})}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("A coffee moment")
                ScrollView {
                    VStack(spacing:18) {
                        if let media=store.state.momentDraft.media {
                            if store.state.momentDraft.isVideo {CoffeePlayerView(media:media).frame(height:260)}
                            else {PapiImage(name:media).frame(height:260).clipped().clipShape(RoundedRectangle(cornerRadius:18))}
                        }
                        PhotosPicker(selection:$item,matching:.any(of:[.images,.videos]),photoLibrary:.shared()) {
                            VStack(spacing:12) {
                                Image("uploadImage").resizable().scaledToFit().frame(width:65,height:65)
                                PapiText(importing ? "Importing…":(store.state.momentDraft.media==nil ? "Add pictures or videos…":"Choose a different photo or video")).font(CoffeeType.face(.subheadline))
                            }.frame(maxWidth:.infinity,minHeight:150).background(Color.white,in:RoundedRectangle(cornerRadius:20))
                        }.buttonStyle(.plain).disabled(importing)
                        HStack {
                            PapiTextButton("Take photo"){openCamera(movie:false)}
                            Spacer()
                            PapiTextButton("Record video"){openCamera(movie:true)}
                        }.font(CoffeeType.face(.subheadline,weight:.medium)).disabled(importing)
                        PapiInput("Say something about your coffee…",text:caption,axis:.vertical).lineLimit(4...10).padding(18).background(Color.white,in:RoundedRectangle(cornerRadius:20))
                        HStack {PapiText("Saved only on this device");Spacer();PapiText("\(store.state.momentDraft.text.count)/2000")}.font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        HStack {PapiText("Save a post for");CoinLabel(value:CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo));PapiText("coins")}.font(CoffeeType.face(.subheadline)).padding(.top,20)
                        PapiTextButton("Submit for review") {confirm=true}.buttonStyle(PapiButtonStyle(wide:true)).disabled(importing || store.state.momentDraft.media==nil)
                        PapiText("Posts stay private until approved. No moderation server is connected yet; pending posts are never approved automatically.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.overlay {
                if confirm {PapiDialog(title:"Submit for review?",message:"\(CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo)) coins are used when this post is saved to your private review queue. It appears in the feed only after approval.",confirm:"Submit · \(CoffeeEconomy.postCost(isVideo:store.state.momentDraft.isVideo)) coins",cancel:"Keep editing",action:{confirm=false;if store.publish(){dismiss();store.notice = .init(title:"Post saved for review",message:"Your post is saved privately in the review queue. It will appear only after approval. No moderation server is connected yet.",kind:.review)}},dismiss:{confirm=false})}
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
