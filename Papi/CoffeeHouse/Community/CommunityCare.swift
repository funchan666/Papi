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
    @Environment(\.layoutDirection) private var direction
    @State private var reporting=false
    @State private var confirmBlock=false
    @State private var authorToBlock:String?
    var body:some View {
        Group {
            if reporting {ReportView(target:target,onBack:{reporting=false})}
            else {
                PapiScreen {
                    VStack(spacing:0) {
                        PapiHeader("Safety options")
                        ScrollView {
                            VStack(alignment:.leading,spacing:18) {
                                HStack(spacing:16) {
                                    VStack(alignment:.leading,spacing:8) {
                                        PapiText("Safety options").font(CoffeeType.display(.title2,weight:.bold))
                                        PapiText("Choose a report reason, or hide this item from your lists.").font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                    PapiArtworkFit(asset:"coffeeSafetyArt").frame(width:92,height:92)
                                }.padding(18).background(Color.cream.opacity(0.95),in:RoundedRectangle(cornerRadius:22))
                                if let author=target.authorID {
                                    PapiUserLink(userID:author,size:48).frame(maxWidth:.infinity,alignment:.leading)
                                }
                                safetyChoice("Report",detail:"Choose a reason",tint:Color.white) {reporting=true}
                                safetyChoice(target.kind == .user ? "Block user":"Hide content",detail:target.kind == .user ? "Their posts, comments, rooms and chats will be hidden. You can unblock them in Settings.":"This item will disappear from your lists.",tint:Color.butter.opacity(0.7)) {confirmBlock=true}
                                if target.kind != .user,let author=target.authorID,author != store.state.passport.id.uuidString {
                                    safetyChoice("Block author",detail:"Their posts, comments, rooms and chats will be hidden. You can unblock them in Settings.",tint:Color.white) {authorToBlock=author}
                                }
                            }.padding(20).frame(maxWidth:600).frame(maxWidth:.infinity)
                        }
                    }
                    .overlay {
                        if confirmBlock {
                            safetyConfirmation(title:target.kind == .user ? "Block this user?":"Hide this content?",message:target.kind == .user ? "Their posts, comments, rooms and chats will be hidden. You can unblock them in Settings.":"This item will disappear from your lists.",confirm:target.kind == .user ? "Block user":"Hide content",action:{confirmBlock=false;if target.kind == .user {blockUser(target.contentReference)} else if store.hide(target){dismiss()}},cancel:{confirmBlock=false})
                        }
                        if let authorToBlock {
                            safetyConfirmation(title:"Block this user?",message:"Their posts, comments, rooms and chats will be hidden. You can unblock them in Settings.",confirm:"Block user",action:{self.authorToBlock=nil;blockUser(authorToBlock)},cancel:{self.authorToBlock=nil})
                        }
                    }
                }
            }
        }
    }
    private func blockUser(_ id:String) {
        if store.usesCloudWallet {
            guard let member=UUID(uuidString:id) else {return}
            Task {if await store.changeCloudBlock(member,enabled:true){dismiss()}}
        } else if store.block(id) {dismiss()}
    }
    private func safetyChoice(_ title:String,detail:String,tint:Color,action:@escaping ()->Void)->some View {
        Button(action:action) {
            HStack(alignment:.center,spacing:12) {
                VStack(alignment:.leading,spacing:6) {
                    PapiText(title).font(CoffeeType.face(.headline))
                    PapiText(detail).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Image("chevron").resizable().scaledToFit().scaleEffect(x:direction == .rightToLeft ? -1:1,y:1).frame(width:14,height:14).accessibilityHidden(true)
            }.padding(17).frame(maxWidth:.infinity,minHeight:64,alignment:.leading).background(tint,in:RoundedRectangle(cornerRadius:18)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func safetyConfirmation(title:String,message:String,confirm:String,action:@escaping ()->Void,cancel:@escaping ()->Void)->some View {
        CoffeeModal(maximumWidth:370,maximumHeight:560,shade:Color.coffee.opacity(0.55),artwork:nil) {
            VStack(alignment:.leading,spacing:16) {
                PapiArtworkFit(asset:"coffeeSafetyArt").frame(width:86,height:86)
                PapiText(title).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText(message).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                PapiTextButton(confirm,action:action).buttonStyle(PapiButtonStyle(wide:true,cornerRadius:15))
                PapiTextButton("Cancel",action:cancel).buttonStyle(PapiButtonStyle(light:true,wide:true,cornerRadius:15))
            }.frame(maxWidth:.infinity,alignment:.leading)
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
            VStack(spacing:0) {
                PapiHeader("Report Type",backAction:onBack)
                ScrollView {
                    VStack(alignment:.leading,spacing:14) {
                        HStack(spacing:14) {
                            VStack(alignment:.leading,spacing:6) {
                                PapiText("Choose a reason").font(CoffeeType.display(.title2,weight:.bold))
                                PapiText(store.usesCloudWallet ? "The report will be sent for review and the item will be hidden.":"The item will be hidden after saving. Reports are not sent for review.").font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee).fixedSize(horizontal:false,vertical:true)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            PapiArtworkFit(asset:"coffeeSafetyArt").frame(width:80,height:80)
                        }.padding(18).background(Color.cream.opacity(0.95),in:RoundedRectangle(cornerRadius:22))
                        ForEach(reasons,id:\.self) {item in
                            Button {reason=item} label:{
                                HStack(spacing:12) {PapiText(item).font(CoffeeType.face(.subheadline,weight:.medium)).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true);Spacer(minLength:0);if reason==item {Image("check").resizable().scaledToFit().frame(width:20,height:20).accessibilityHidden(true)}}
                                    .padding(16).frame(maxWidth:.infinity,minHeight:52,alignment:.leading).background(reason==item ? Color.butter:Color.white.opacity(0.9),in:RoundedRectangle(cornerRadius:16))
                            }.buttonStyle(.plain).disabled(store.state.pendingCloudReport != nil).accessibilityAddTraits(reason==item ? .isSelected:[])
                        }
                        PapiTextButton("Report") {if let reason {if store.usesCloudWallet {Task {if await store.submitCloudReport(target,reason:reason){dismiss()}}} else if store.report(target,reason:reason){dismiss()}}}
                            .buttonStyle(PapiButtonStyle(wide:true,cornerRadius:16)).disabled(reason==nil || store.cloudSocialBusy || (store.usesCloudWallet && UUID(uuidString:target.contentReference)==nil))
                    }.padding(20).frame(maxWidth:600).frame(maxWidth:.infinity)
                }
            }
        }.onAppear {if let pending=store.state.pendingCloudReport,pending.target.id==target.id {reason=pending.reason}}
    }
}
struct CoffeeReceiptView:View {
    let notice:CoffeeReceipt
    var close:()->Void
    var body:some View {
        CoffeeModal(maximumWidth:370,maximumHeight:570,shade:Color.coffee.opacity(0.62),artwork:nil) {
            VStack(alignment:.leading,spacing:18) {
                HStack(alignment:.center) {
                    Image(notice.kind == .safety ? "coffeeSafetyArt":(notice.kind == .review ? "coffeeUpdates":"brandMark")).resizable().scaledToFit().frame(width:notice.kind == .safety ? 82:58,height:notice.kind == .safety ? 82:58)
                    Spacer()
                    PapiText("Papi").font(CoffeeType.display(size:25,weight:.bold)).italic()
                }
                Divider().overlay(Color.coffee.opacity(0.25))
                PapiText(notice.title).font(CoffeeType.display(.title2,weight:.bold)).fixedSize(horizontal:false,vertical:true)
                PapiText(notice.message).font(CoffeeType.face(.subheadline)).foregroundStyle(Color.mutedCoffee).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                if notice.kind == .review {
                    status("Saved privately",asset:"check")
                    status("Awaiting moderation connection",asset:"coffeeUpdates")
                    PapiText("Visible only after approval").font(CoffeeType.face(.caption,weight:.bold)).padding(13).frame(maxWidth:.infinity,alignment:.leading).background(Color.butter,in:RoundedRectangle(cornerRadius:12))
                } else if notice.kind == .safety {status("Saved",asset:"check")}
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
                    VStack(alignment:.leading,spacing:16) {
                        CoffeeSectionIntro(artwork:"momentComposeArt",title:"My submissions",detail:store.usesCloudWallet ? "Posts remain private until reviewed and approved.":"Posts stay private until approved. No moderation server is connected yet; pending posts are never approved automatically.")
                        if store.usesCloudWallet {
                            if let pending=store.state.pendingCloudPostDeletion {
                                PapiText("A post removal is waiting for confirmation.").font(CoffeeType.face(.caption))
                                PapiTextButton("Retry removal"){Task {await store.deleteCloudSubmission(pending.postID)}}.disabled(store.cloudSubmissionsBusy)
                            }
                            if let submissions=store.cloudSubmissions {
                                if submissions.isEmpty {PapiEmpty(title:"No submissions yet")}
                                ForEach(submissions) {post in
                                    PapiPanel {VStack(alignment:.leading,spacing:12) {
                                        HStack {Image("coffeeUpdates").resizable().scaledToFit().frame(width:24,height:28);PapiText(cloudStatus(post.moderation_status)).font(CoffeeType.face(.headline));Spacer()}
                                        HStack(alignment:.top,spacing:12) {
                                            if post.media_kind=="photo" {PrivateSubmissionPhoto(path:post.media_path).frame(width:72,height:72).clipShape(RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)}
                                            PapiText(verbatim:post.caption).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                                        }
                                        PapiTextButton("Delete post"){removing=post.id.uuidString}.font(CoffeeType.face(.caption,weight:.bold)).disabled(store.cloudSubmissionsBusy || store.state.pendingCloudPostDeletion != nil)
                                    }}
                                }
                            } else {
                                PapiText(store.cloudSubmissionsBusy ? "Loading submissions…":"Submissions unavailable")
                                PapiTextButton("Retry"){Task {await store.refreshCloudSubmissions()}}.disabled(store.cloudSubmissionsBusy)
                            }
                        } else {
                        if store.state.ownMoments.isEmpty {PapiEmpty(title:"No submissions yet")}
                        ForEach(store.state.ownMoments) {post in
                            PapiPanel {VStack(alignment:.leading,spacing:12) {
                                HStack {Image("coffeeUpdates").resizable().scaledToFit().frame(width:24,height:28);PapiText(status(post)).font(CoffeeType.face(.headline));Spacer()}
                                HStack(alignment:.top,spacing:12) {
                                    PapiImage(name:post.media).frame(width:72,height:72).clipShape(RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)
                                    VStack(alignment:.leading,spacing:6) {
                                        PapiText(verbatim:post.caption).lineLimit(3)
                                        Text(post.createdAt,style:.date).font(CoffeeType.face(.caption)).foregroundStyle(Color.mutedCoffee)
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                }
                                PapiTextButton("Delete post"){removing=post.id}.font(CoffeeType.face(.caption,weight:.bold))
                            }}
                        }
                        }
                    }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
                }
            }.overlay {
                if let removing {PapiDialog(title:"Remove this coffee moment?",message:"This moment will be removed from your coffee book. Coins already used are not refunded.",confirm:"Delete post",cancel:"Cancel",action:{self.removing=nil;if store.usesCloudWallet {if let id=UUID(uuidString:removing) {Task {await store.deleteCloudSubmission(id)}}} else {store.deletePost(removing)}},dismiss:{self.removing=nil})}
            }
        }.task {if store.usesCloudWallet {await store.refreshCloudSubmissions()}}
    }
    private func cloudStatus(_ value:String)->String {
        switch value {case "pending":return "Under review";case "approved":return "Approved";case "rejected":return "Not approved";default:return "Status unavailable"}
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
