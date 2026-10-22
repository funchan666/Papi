import SwiftUI
import PhotosUI
import AVFoundation

struct HomeView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    var body:some View {
        PapiScreen {
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment:.leading,spacing:18) {
                        HStack(alignment:.center) {
                            VStack(alignment:.leading,spacing:5) {
                                PapiText("Coffee Community").font(.system(size:27,weight:.heavy,design:.serif)).italic().minimumScaleFactor(0.85)
                                PapiText("Discover & share coffee moments").font(.system(.caption,design:.serif)).foregroundStyle(Color.mutedCoffee)
                            }
                            Spacer(minLength:4)
                            PapiIconButton(asset:"plus",label:"Create a post") {router.sheet = .compose}
                        }
                        HStack(spacing:10) {
                            Button {router.go(.cafes)} label:{Image("exploreBanner").resizable().scaledToFit()}
                            Button {router.go(.beans)} label:{Image("beansBanner").resizable().scaledToFit()}
                        }.buttonStyle(.plain)
                        HStack(spacing:7) {
                            Image("coffeeUpdates").resizable().scaledToFit().frame(width:22,height:26)
                            PapiText("Coffee Updates").font(.headline)
                            Spacer()
                            PapiText("Curated previews").font(.caption2).foregroundStyle(Color.mutedCoffee)
                        }
                        let width=min(1200,geo.size.width)
                        let count=max(2,Int(width/180))
                        let tileWidth=max(44,(width-32-CGFloat(count-1)*12)/CGFloat(count))
                        HStack(alignment:.top,spacing:12) {
                            ForEach(0..<count,id:\.self) { column in
                                LazyVStack(spacing:14) {
                                    ForEach(Array(store.visiblePosts.enumerated()).filter{$0.offset%count==column},id:\.element.id) { index,post in
                                        PostTile(post:post,height:tileWidth*(index%3==1 ? 1.42:1.18))
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
struct PostTile:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    let post:CoffeePost
    var height:CGFloat=220
    var body:some View {
        VStack(spacing:0) {
            Button {router.go(.post(post.id))} label:{
                ZStack(alignment:.topTrailing) {
                    PapiImage(name:post.media).frame(height:height).frame(maxWidth:.infinity).clipped()
                    if post.isVideo {PapiText("Video").font(.caption.bold()).padding(7).background(Color.coffee.opacity(0.85),in:Capsule()).foregroundStyle(.white).padding(8)}
                }
            }.buttonStyle(.plain)
            HStack(spacing:1) {
                PapiText(post.category).font(.caption2.weight(.medium)).lineLimit(1).padding(.horizontal,8).padding(.vertical,5).background(Color.coffee,in:Capsule()).foregroundStyle(.white)
                Spacer(minLength:0)
                Button {store.toggleLike(post.id)} label:{Image("like").resizable().scaledToFit().frame(width:27,height:27).opacity(store.state.likes.contains(post.id) ? 1:0.48).frame(width:44,height:44)}.papiAccessibilityLabel(store.state.likes.contains(post.id) ? "Unlike":"Like")
                Button {router.go(.post(post.id))} label:{Image("comment").resizable().scaledToFit().frame(width:27,height:27).frame(width:44,height:44)}.papiAccessibilityLabel("Open comments")
            }.padding(.horizontal,7).background(Color.peach.opacity(0.55))
        }.clipShape(RoundedRectangle(cornerRadius:18)).buttonStyle(.plain)
    }
}
struct PostDetailView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @Environment(\.dismiss) private var dismiss
    let postID:String
    @State private var comment=""
    @State private var confirmDelete=false
    var body:some View {
        PapiScreen {
            if let post=store.post(postID),!store.state.blocked.contains(post.authorID) {
                VStack(spacing:0) {
                    PapiHeader("Coffee moment") {
                        PapiIconButton(asset:"more",label:"Post options") {
                            if post.isLocal {confirmDelete=true} else {router.sheet = .report("post:"+postID)}
                        }
                    }
                    ScrollView {
                        VStack(alignment:.leading,spacing:18) {
                            if post.isVideo {CoffeePlayerView(media:post.media).frame(height:380)}
                            else {Button {router.go(.photo(post.media))} label:{PapiImage(name:post.media).frame(height:350).clipped()}.buttonStyle(.plain)}
                            VStack(alignment:.leading,spacing:12) {
                                HStack {
                                    Avatar(name:post.isLocal ? store.state.profile.avatar:"brandMark",size:44)
                                    VStack(alignment:.leading,spacing:3) {
                                        PapiText(post.isLocal ? store.state.profile.name:"Papi coffee journal").font(.headline)
                                        PapiText(post.isLocal ? "Saved on this device":"Curated content preview").font(.caption).foregroundStyle(Color.mutedCoffee)
                                    }
                                    Spacer()
                                }
                                PapiText(verbatim:post.caption).font(.body)
                                HStack(spacing:18) {
                                    Button {store.toggleLike(post.id)} label:{HStack {Image("like").resizable().scaledToFit().frame(width:24,height:24).opacity(store.state.likes.contains(post.id) ? 1:0.5);PapiText(store.state.likes.contains(post.id) ? "1":"0")}}
                                    HStack {Image("comment").resizable().scaledToFit().frame(width:24,height:24);PapiText("\(store.state.comments.filter{$0.postID==postID}.count)")}
                                    Button {store.toggleBookmark(post.id)} label:{Image("star").resizable().scaledToFit().frame(width:25,height:25).opacity(store.state.bookmarks.contains(post.id) ? 1:0.4)}.papiAccessibilityLabel("Save coffee moment")
                                    Spacer()
                                }.buttonStyle(.plain).font(.caption)
                            }.padding(16).background(Color.peach.opacity(0.25),in:RoundedRectangle(cornerRadius:20)).padding(.horizontal,16)
                            PapiText("My local notes").font(.headline).padding(.horizontal,20)
                            let comments=store.state.comments.filter{$0.postID==postID}
                            if comments.isEmpty {PapiText("Keep a tasting note or thought about this moment.").font(.subheadline).foregroundStyle(Color.mutedCoffee).padding(.horizontal,20)}
                            ForEach(comments) { note in
                                HStack(alignment:.top,spacing:10) {
                                    Avatar(name:store.state.profile.avatar,size:34)
                                    VStack(alignment:.leading,spacing:4) {PapiText(verbatim:note.text);Text(note.createdAt,style:.date).font(.caption2).foregroundStyle(Color.mutedCoffee)}
                                    Spacer()
                                    PapiIconButton(asset:"trash",label:"Delete note",size:19) {_ = store.commit{$0.comments.removeAll{$0.id==note.id}}}
                                }.padding(14).background(Color.white,in:RoundedRectangle(cornerRadius:15)).padding(.horizontal,16)
                            }
                        }.padding(.bottom,20).frame(maxWidth:760).frame(maxWidth:.infinity)
                    }
                    HStack {
                        PapiInput("Tell your opinion…",text:$comment,axis:.vertical).lineLimit(1...4).foregroundStyle(.white).tint(.white).padding(.leading,18)
                        PapiTextButton("SAVE") {if store.addComment(postID:postID,text:comment) {comment=""}}.font(.caption.bold()).padding(12).background(Color.cream,in:Capsule()).disabled(comment.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }.padding(6).background(Color.coffee,in:Capsule()).padding(.horizontal,16).padding(.vertical,10)
                }.overlay {
                    if confirmDelete {PapiDialog(title:"Delete this local post?",message:"The post will be removed from this guest's journal. Coins already used are not refunded.",confirm:"Delete post",cancel:"Keep post",action:{store.deletePost(postID);confirmDelete=false;dismiss()},dismiss:{confirmDelete=false})}
                }
            } else {VStack {PapiHeader("Coffee moment");PapiEmpty(title:"This content is unavailable");Spacer()}}
        }
    }
}
struct ComposeView:View {
    @EnvironmentObject private var store:PapiStore
    @Environment(\.dismiss) private var dismiss
    @State private var item:PhotosPickerItem?
    @State private var importing=false
    @State private var camera=false
    @State private var movieCamera=false
    @State private var confirm=false
    private var caption:Binding<String> {Binding(get:{store.state.postDraft.text},set:{newValue in _ = store.commit{$0.postDraft.text=String(newValue.prefix(2000))}})}
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("A coffee moment")
                ScrollView {
                    VStack(spacing:18) {
                        if let media=store.state.postDraft.media {
                            if store.state.postDraft.isVideo {CoffeePlayerView(media:media).frame(height:260)}
                            else {PapiImage(name:media).frame(height:260).clipped().clipShape(RoundedRectangle(cornerRadius:18))}
                        }
                        PhotosPicker(selection:$item,matching:.any(of:[.images,.videos]),photoLibrary:.shared()) {
                            VStack(spacing:12) {
                                Image("uploadImage").resizable().scaledToFit().frame(width:65,height:65)
                                PapiText(importing ? "Importing…":(store.state.postDraft.media==nil ? "Add pictures or videos…":"Choose a different photo or video")).font(.subheadline)
                            }.frame(maxWidth:.infinity,minHeight:150).background(Color.white,in:RoundedRectangle(cornerRadius:20))
                        }.buttonStyle(.plain).disabled(importing)
                        HStack {
                            PapiTextButton("Take photo"){openCamera(movie:false)}
                            Spacer()
                            PapiTextButton("Record video"){openCamera(movie:true)}
                        }.font(.subheadline.weight(.medium))
                        PapiInput("Say something about your coffee…",text:caption,axis:.vertical).lineLimit(4...10).padding(18).background(Color.white,in:RoundedRectangle(cornerRadius:20))
                        HStack {PapiText("Saved only on this device");Spacer();PapiText("\(store.state.postDraft.text.count)/2000")}.font(.caption).foregroundStyle(Color.mutedCoffee)
                        HStack {PapiText("Save a post for");CoinLabel(value:10);PapiText("coins")}.font(.subheadline).padding(.top,20)
                        PapiTextButton("Save to my journal") {confirm=true}.buttonStyle(PapiButtonStyle()).disabled(importing || store.state.postDraft.media==nil)
                        PapiText("Your draft is kept if you leave this page. Nothing is uploaded to a public feed.").font(.caption).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                    }.padding(20).frame(maxWidth:620).frame(maxWidth:.infinity)
                }.scrollDismissesKeyboard(.interactively)
            }.overlay {
                if confirm {PapiDialog(title:"Save this coffee moment?",message:"10 coins will be used once the post is saved to your local journal.",confirm:"Save · 10 coins",cancel:"Keep editing",action:{confirm=false;if store.publish(){dismiss();store.inform("Saved to your journal","Your coffee moment is available on this device.")}},dismiss:{confirm=false})}
            }
        }.onChange(of:item) {_,value in if let value {Task {await importItem(value)}}}
        .fullScreenCover(isPresented:$camera) {
            CameraPicker(movie:movieCamera) {result in
                camera=false
                guard let result else{return}
                do {let output=try result.get(); let name:String;let video:Bool
                    switch output {
                    case .photo(let data):name=try MediaFiles.saveImage(data,guest:store.state.profile.id);video=false
                    case .movie(let url):name=try MediaFiles.saveMovie(url,guest:store.state.profile.id);video=true
                    }
                    _ = store.commit{$0.postDraft.media=name;$0.postDraft.isVideo=video}
                } catch {store.inform("Could not import media",error.localizedDescription)}
            }.ignoresSafeArea()
        }
    }
    private func openCamera(movie:Bool) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {store.inform("Camera unavailable","Choose an existing photo or video instead.");return}
        movieCamera=movie;camera=true
    }
    @MainActor private func importItem(_ selection:PhotosPickerItem) async {
        guard !importing else{return};importing=true;defer {importing=false}
        let owner=store.state.profile.id
        do {
            let name:String;let video=selection.supportedContentTypes.contains{$0.conforms(to:.movie)}
            if video {
                guard let file=try await selection.loadTransferable(type:ImportedMovie.self) else {throw MediaFiles.MediaError.invalid}
                defer {try? FileManager.default.removeItem(at:file.url)}
                guard store.state.signedIn,store.state.profile.id==owner else{return}
                name=try MediaFiles.saveMovie(file.url,guest:owner)
            } else {
                guard let data=try await selection.loadTransferable(type:Data.self) else {throw MediaFiles.MediaError.invalid}
                guard store.state.signedIn,store.state.profile.id==owner else{return}
                name=try MediaFiles.saveImage(data,guest:owner)
            }
            guard store.state.signedIn,store.state.profile.id==owner else{return}
            _ = store.commit{$0.postDraft.media=name;$0.postDraft.isVideo=video}
        } catch {store.inform("Could not import media",error.localizedDescription)}
    }
}
struct PhotoDetailView:View {
    var name:String
    @EnvironmentObject private var store:PapiStore
    @State private var selection=0
    @State private var started=false
    private var photos:[String] {
        let album=store.state.profile.photos
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
