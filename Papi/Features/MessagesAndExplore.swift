import SwiftUI
import PhotosUI

struct MessagesView:View {
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var confirmClear=false
    var body:some View {
        PapiScreen {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    HStack {
                        Image("chatTitle").resizable().scaledToFit().frame(width:110,height:58)
                        Spacer()
                        PapiIconButton(asset:"clean",label:"Clear chat drafts") {confirmClear=true}
                    }
                    ScrollView(.horizontal,showsIndicators:false) {
                        HStack(spacing:18) {
                            ForEach(Person.previews.filter{!store.state.blocked.contains($0.id)}) {person in
                                Button {router.go(.chat(person.id))} label:{VStack(spacing:7){Avatar(name:person.portrait,size:54);PapiText(verbatim:person.name).font(.caption);PapiText("Preview").font(.caption2).foregroundStyle(Color.mutedCoffee)}}.buttonStyle(.plain)
                            }
                        }
                    }
                    Button {router.go(.notifications)} label:{messageRow(asset:"interactionNotice",title:"Interactions",subtitle:"Your local activity and saved reports")}.buttonStyle(.plain)
                    Button {router.go(.notifications)} label:{messageRow(asset:"systemNotice",title:"Papi updates",subtitle:"A quieter place for your coffee moments")}.buttonStyle(.plain)
                    let drafted=Person.previews.filter{store.hasChatDraft($0.id) && !store.state.blocked.contains($0.id)}
                    if !drafted.isEmpty {
                        PapiText("Saved drafts").font(.headline)
                        ForEach(drafted) {person in
                            Button {router.go(.chat(person.id))} label:{HStack(spacing:12){Avatar(name:person.portrait);VStack(alignment:.leading,spacing:4){PapiText(verbatim:person.name).font(.headline);PapiText(verbatim:store.chatPreview(person.id)).font(.subheadline).lineLimit(1).foregroundStyle(Color.mutedCoffee)};Spacer();PapiText("Draft").font(.caption)}}.buttonStyle(.plain).padding(.vertical,8)
                        }
                    }
                    PapiText("Profiles above are previews. No unread messages or mutual follows are generated automatically.").font(.caption).foregroundStyle(Color.mutedCoffee).padding(.top,16)
                }.padding(20).frame(maxWidth:800).frame(maxWidth:.infinity)
            }
        }.overlay {
            if confirmClear {PapiDialog(title:"Clear chat drafts?",message:"Remove all saved chat text, photo attachments and voice drafts from your chats. Your profile and journal stay unchanged.",confirm:"Clear drafts",cancel:"Keep drafts",action:{confirmClear=false;store.clearChatDrafts()},dismiss:{confirmClear=false})}
        }
    }
    private func messageRow(asset:String,title:String,subtitle:String)->some View {
        HStack(spacing:13){Image(asset).resizable().scaledToFit().frame(width:48,height:48);VStack(alignment:.leading,spacing:6){PapiText(title).font(.headline);PapiText(subtitle).font(.subheadline).foregroundStyle(Color.mutedCoffee)};Spacer()}.padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading)
    }
}
struct ChatView:View {
    let personID:String
    @EnvironmentObject private var store:PapiStore
    @EnvironmentObject private var router:PapiRouter
    @State private var picker:PhotosPickerItem?
    @State private var showVoice=false
    @State private var importing=false
    private var draft:Binding<String> {Binding(get:{store.state.chatDrafts[personID] ?? ""},set:{new in _ = store.commit{$0.chatDrafts[personID]=String(new.prefix(2000))}})}
    var body:some View {
        PapiScreen {
            if let person=Person.find(personID) {
                VStack(spacing:0) {
                    PapiHeader(person.name) {PapiTextButton("Profile"){router.go(.person(personID))}.font(.caption.weight(.medium)).padding(9).background(Color.cream,in:Capsule())}
                    ScrollView {
                        VStack(spacing:20) {
                            Avatar(name:person.portrait,size:66)
                            PreviewLabel()
                            PapiText("Start with a coffee hello.").font(.system(.title3,design:.serif)).italic()
                            PapiText("Messages require mutual following. This preview profile is not connected to a messaging service.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(Color.mutedCoffee)
                            if let attachment=store.state.chatAttachments[personID] {
                                VStack(spacing:8) {
                                    PapiText("Local attachment · Not sent").font(.caption)
                                    PapiImage(name:attachment).frame(height:200).clipped().clipShape(RoundedRectangle(cornerRadius:16))
                                    PapiTextButton("Remove attachment"){_ = store.commit{$0.chatAttachments.removeValue(forKey:personID)}}.font(.caption)
                                }
                            }
                            if let voice=store.state.voiceDrafts[personID] {
                                LocalVoicePlayer(name:voice)
                                PapiTextButton("Remove voice draft"){_ = store.commit{$0.voiceDrafts.removeValue(forKey:personID)}}.font(.caption)
                            }
                            if importing {PapiText("Importing photo…").font(.caption)}
                        }.padding(30).frame(maxWidth:600).frame(maxWidth:.infinity)
                    }
                    HStack(spacing:5) {
                        PapiIconButton(asset:"mic",label:"Record local voice draft",size:34){showVoice=true}
                        PapiInput("Say Hi…",text:draft,axis:.vertical).lineLimit(1...4).padding(12).background(Color.cream,in:Capsule())
                        PapiIconButton(asset:"send",label:"Send message",size:24){store.sendChat(to:personID,text:draft.wrappedValue)}
                        PhotosPicker(selection:$picker,matching:.images) {Image("chatPhoto").resizable().scaledToFit().frame(width:34,height:34).frame(width:44,height:44)}.disabled(importing).papiAccessibilityLabel("Choose a local photo draft")
                    }.padding(10).background(Color.coffee)
                }
            } else {VStack{PapiHeader("Chat");PapiEmpty(title:"Profile unavailable");Spacer()}}
        }.onChange(of:picker){_,item in if let item {Task{await importPhoto(item)}}}
            .sheet(isPresented:$showVoice){PapiDeviceContainer {VoiceDraftView(personID:personID).papiNotices()}}
    }
    @MainActor private func importPhoto(_ item:PhotosPickerItem) async {
        importing=true;defer{importing=false};let owner=store.state.profile.id
        do {
            guard let data=try await item.loadTransferable(type:Data.self) else {throw MediaFiles.MediaError.invalid}
            guard store.state.profile.id==owner,store.state.signedIn else{return}
            let name=try MediaFiles.saveImage(data,guest:owner)
            guard store.state.profile.id==owner,store.state.signedIn else{return}
            _ = store.commit{$0.chatAttachments[personID]=name}
        } catch {store.inform("Could not import photo",error.localizedDescription)}
    }
}
struct NotificationView:View {
    @EnvironmentObject private var store:PapiStore
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Local activity")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    PapiPanel{VStack(alignment:.leading,spacing:8){PapiText("Welcome to Papi").font(.headline);PapiText("Your coffee journal, collection and drafts stay on this device. No system messages are fabricated for preview profiles.").font(.subheadline)}}
                    if !store.state.reports.isEmpty {PapiText("Saved report drafts").font(.headline)}
                    ForEach(store.state.reports.reversed()){report in PapiPanel{VStack(alignment:.leading,spacing:5){PapiText(report.reason).font(.headline);PapiText(report.subjectID).font(.caption);PapiText("Saved locally · Not submitted").font(.caption).foregroundStyle(Color.mutedCoffee)}}}
                }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
            }
        }}
    }
}
struct BeansView:View {
    @State private var selected:Int?
    let names=["Arabica","Robusta","Geisha","Bourbon","Pacamara","SL28"]
    let assets=["beanArabica","beanRobusta","beanGeisha","beanBourbon","beanPacamara","beanSL28"]
    let notes=["Often enjoyed for a nuanced cup. Try recording the aroma, sweetness and finish of your own brew.","A fuller-bodied coffee often used in blends. Compare different brew ratios in your journal.","Take time with the aroma and let the cup cool before adding your tasting notes.","Compare roast levels and note how sweetness changes in your cup.","Explore your brewing recipe and note the texture and finish.","Keep track of grind size and water temperature as you explore each cup."]
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Coffee beans")
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    PapiText("Explore Coffee Bean Varieties").font(.headline)
                    PapiText("Learn flavors, origins & brewing tips").font(.subheadline).foregroundStyle(Color.mutedCoffee)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:14){ForEach(0..<6){i in Button{selected=i} label:{Image(assets[i]).resizable().scaledToFit()}.buttonStyle(.plain).papiAccessibilityLabel(names[i])}}
                    PapiText("Every roast and harvest is different. Use these cards as a starting point for your own tasting journal.").font(.caption).foregroundStyle(Color.mutedCoffee)
                }.padding(20).frame(maxWidth:850).frame(maxWidth:.infinity)
            }
        }.overlay {if let selected {PapiDialog(title:names[selected],message:notes[selected],action:{self.selected=nil},dismiss:{self.selected=nil})}}}
    }
}
struct CafesView:View {
    @State private var selected:Int?
    let names=["Aura Bean","Hush Brew","Sunny Sip","Loom Coffee"]
    let subtitles=["Floral aroma & quiet leisure","Hidden spot for hand brew","Fruity signature & easy vibe","Cozy space for sharing"]
    let images=["coffee09","coffee15","coffee17","coffee13"]
    var body:some View {
        PapiScreen {VStack(spacing:0){
            PapiHeader("Explore cafés")
            ScrollView {
                VStack(spacing:22) {
                    PreviewLabel(text:"Café inspiration · Illustrative listings")
                    ForEach(0..<4){i in
                        Button{selected=i} label:{
                            HStack(spacing:13) {
                                ZStack(alignment:.topLeading){PapiImage(name:images[i]).frame(width:90,height:95).clipped().clipShape(RoundedRectangle(cornerRadius:14));if i<3 {Image("hot").resizable().scaledToFit().frame(width:55,height:33).offset(x:-4,y:-15)}}
                                VStack(alignment:.leading,spacing:7){PapiText(names[i]).font(.headline);PapiText(subtitles[i]).font(.caption);PapiText("Coffee inspiration").font(.caption2).opacity(0.8)}
                                Spacer(minLength:0)
                            }.padding(12).background(Color.coffee,in:RoundedRectangle(cornerRadius:20)).foregroundStyle(Color.cream)
                        }.buttonStyle(.plain)
                    }
                    PapiText("These are design-inspired café concepts, not verified business listings. No live locations, bookings or opening hours are provided.").font(.caption).foregroundStyle(Color.mutedCoffee).multilineTextAlignment(.center)
                }.padding(20).frame(maxWidth:700).frame(maxWidth:.infinity)
            }
        }.overlay{if let selected {PapiDialog(title:names[selected],message:subtitles[selected]+". This is an inspiration card. A real café directory has not been connected.",action:{self.selected=nil},dismiss:{self.selected=nil})}}}
    }
}
