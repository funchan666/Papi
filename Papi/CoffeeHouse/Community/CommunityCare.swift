import SwiftUI

/// Every avatar/name uses the same identity and the same profile destination.
struct PapiUserLink:View {
    var userID:String
    var size:CGFloat=44
    var showsName=true
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    var body:some View {
        if let person=store.person(userID),!store.isUserHidden(userID) {
            Button {router.goAfterClosingSheet(.person(userID))} label:{
                HStack(spacing:10) {
                    Avatar(name:person.portrait,size:size)
                    if showsName {PapiText(verbatim:person.name).font(size<=32 ? .caption:.headline).multilineTextAlignment(.leading).lineLimit(2)}
                }.frame(minHeight:max(44,size)).contentShape(Rectangle())
            }.buttonStyle(.plain).papiAccessibilityLabel(person.name)
        }
    }
}
struct SafetyMenuView:View {
    var target:SafetyTarget
    @EnvironmentObject private var store:CoffeeHouse
    @EnvironmentObject private var router:CoffeeNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var reporting=false
    @State private var confirmBlock=false
    var body:some View {
        Group {
            if reporting {ReportView(target:target,onBack:{reporting=false})}
            else {
                PapiScreen {
                    VStack(spacing:24) {
                        PapiHeader("Safety options")
                        ScrollView {
                            VStack(spacing:24) {
                                if let author=target.authorID {PapiUserLink(userID:author,size:64)}
                                PapiActionGroup {
                                    Button {reporting=true} label:{Image("report").resizable().scaledToFit().frame(width:100,height:100)}.papiAccessibilityLabel("Report")
                                    Button {confirmBlock=true} label:{Image("block").resizable().scaledToFit().frame(width:100,height:100)}.papiAccessibilityLabel(target.kind == .user ? "Block user":"Hide content")
                                }.buttonStyle(.plain)
                                PapiText("Choose a report reason, or hide this item from your lists.").font(CoffeeType.face(.subheadline)).multilineTextAlignment(.center)
                                if target.kind != .user,let author=target.authorID,author != store.state.passport.id.uuidString {
                                    PapiTextButton("Block author") {if store.block(author){dismiss()}}.buttonStyle(PapiButtonStyle(light:true))
                                }
                            }.padding(.bottom,20)
                        }
                    }.padding(22).frame(maxWidth:600).frame(maxWidth:.infinity)
                    .overlay {
                        if confirmBlock {
                            PapiDialog(title:target.kind == .user ? "Block this user?":"Hide this content?",message:target.kind == .user ? "Their posts, comments, rooms and chats will be hidden. You can unblock them in Settings.":"This item will disappear from your lists on this device.",confirm:target.kind == .user ? "Block user":"Hide content",cancel:"Cancel",action:{confirmBlock=false;if store.hide(target){dismiss()}},dismiss:{confirmBlock=false})
                        }
                    }
                }
            }
        }
    }
}
struct ReportView:View {
    var target:SafetyTarget
    var onBack:(()->Void)? = nil
    @EnvironmentObject private var store:CoffeeHouse
    @Environment(\.dismiss) private var dismiss
    @State private var reason:String?
    private let reasons=["Inappropriate content","Harassment or hate","Discrimination","Spam or misleading content","Privacy or safety concern"]
    var body:some View {
        PapiScreen {
            VStack(spacing:16) {
                PapiHeader("Report Type",backAction:onBack)
                ScrollView {
                    VStack(spacing:13) {
                        PapiText("Choose a reason").font(CoffeeType.face(.title3,weight:.bold))
                        ForEach(reasons,id:\.self) {item in
                            Button {reason=item} label:{
                                HStack {PapiText(item).multilineTextAlignment(.leading);Spacer();if reason==item {Image("check").resizable().scaledToFit().frame(width:18,height:18)}}
                                    .padding(17).frame(maxWidth:.infinity).background(reason==item ? Color.butter:Color.white,in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(.plain).accessibilityAddTraits(reason==item ? .isSelected:[])
                        }
                        PapiText("Your report stays on this device and the item will be hidden immediately after saving.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                        PapiTextButton("Report") {if let reason,store.report(target,reason:reason){dismiss()}}
                            .buttonStyle(PapiButtonStyle(wide:true)).disabled(reason==nil)
                    }.padding(22).frame(maxWidth:600).frame(maxWidth:.infinity)
                }
            }
        }
    }
}
struct CoffeeReceiptView:View {
    let notice:CoffeeReceipt
    var close:()->Void
    var body:some View {
        CoffeeModal(maximumWidth:370,maximumHeight:570,shade:Color.black.opacity(0.5)) {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.center) {
                    Image(notice.kind == .review ? "coffeeUpdates":"brandMark").resizable().scaledToFit().frame(width:58,height:58)
                    Spacer()
                    PapiText("Papi").font(CoffeeType.display(size:25,weight:.bold)).italic()
                }
                Divider().overlay(Color.coffee.opacity(0.25))
                PapiText(notice.title).font(CoffeeType.display(.title2,weight:.bold))
                PapiText(notice.message).font(CoffeeType.face(.subheadline)).lineSpacing(4)
                if notice.kind == .review {
                    status("Saved privately",asset:"check")
                    status("Awaiting moderation connection",asset:"coffeeUpdates")
                    PapiText("Visible only after approval").font(CoffeeType.face(.caption,weight:.bold)).padding(13).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter,in:RoundedRectangle(cornerRadius:12))
                } else if notice.kind == .safety {status("Saved on this device",asset:"check")}
                PapiTextButton("Got it",action:close).buttonStyle(PapiButtonStyle(wide:true,cornerRadius:12)).padding(.top,4)
            }
        }
    }
    private func status(_ title:String,asset:String)->some View {
        HStack(spacing:10) {Image(asset).resizable().scaledToFit().frame(width:22,height:22);PapiText(title).font(CoffeeType.face(.caption))}
    }
}
struct AccountProgressView:View {
    let action:AccountTransition
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate=false
    var body:some View {
        CoffeeModal(maximumWidth:350,maximumHeight:300,shade:Color.coffee.opacity(0.6)) {
            VStack(spacing:20) {
                Image("coffeeUpdates").resizable().scaledToFit().frame(width:54,height:64).rotationEffect(.degrees(animate && !reduceMotion ? 8:-8))
                PapiText(action == .delete ? "Closing your coffee account…":"Logging out…").font(CoffeeType.face(.headline)).multilineTextAlignment(.center)
            }
        }.onAppear{if !reduceMotion {withAnimation(.easeInOut(duration:0.6).repeatForever(autoreverses:true)){animate=true}}}
    }
}
struct ReviewQueueView:View {
    @EnvironmentObject private var store:CoffeeHouse
    @State private var removing:String?
    var body:some View {
        PapiScreen {
            VStack(spacing:0) {
                PapiHeader("My submissions")
                ScrollView {
                    VStack(spacing:16) {
                        PapiText("Posts stay private until approved. No moderation server is connected yet; pending posts are never approved automatically.").font(CoffeeType.face(.subheadline))
                        if store.state.ownMoments.isEmpty {PapiEmpty(title:"No submissions yet")}
                        ForEach(store.state.ownMoments) {post in
                            PapiPanel {VStack(alignment:.leading,spacing:12) {
                                HStack {Image("coffeeUpdates").resizable().scaledToFit().frame(width:24,height:28);PapiText(status(post)).font(CoffeeType.face(.headline));Spacer()}
                                PapiText(verbatim:post.caption).lineLimit(3)
                                Text(post.createdAt,style:.date).font(CoffeeType.face(.caption))
                                PapiTextButton("Delete post"){removing=post.id}.font(CoffeeType.face(.caption,weight:.bold))
                            }}
                        }
                    }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
                }
            }.overlay {
                if let removing {PapiDialog(title:"Remove this coffee moment?",message:"This moment will be removed from your coffee book. Coins already used are not refunded.",confirm:"Delete post",cancel:"Cancel",action:{store.deletePost(removing);self.removing=nil},dismiss:{self.removing=nil})}
            }
        }
    }
    private func status(_ post:CoffeeMoment)->String {
        switch post.moderation ?? .awaitingSubmission {
        case .awaitingSubmission:return "Awaiting moderation connection"
        case .pendingReview:return "Under review"
        case .approved:return "Approved"
        case .rejected:return "Not approved"
        }
    }
}
