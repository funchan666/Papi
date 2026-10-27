import Foundation

@MainActor extension CoffeeHouse {
    var community:CorrespondenceLedger {state.community ?? CorrespondenceLedger()}
    var hiddenKeys:Set<String> {
        community.hiddenTargets.union(state.communityReports.compactMap{$0.target?.id ?? SafetyTarget.legacy($0.contentReference)?.id})
    }
    var visibilityKeys:[String] {(hiddenKeys.union(state.blockedMembers.map{"blocked:"+$0})).sorted()}
    func person(_ id:String)->CoffeeMember? {
        if id==state.passport.id.uuidString {return .init(id:id,name:state.passport.name,portrait:state.passport.portraitReference,bio:state.passport.bio)}
        return CoffeeMember.find(id) ?? community.rememberedPeople[id]
    }
    func isUserHidden(_ id:String)->Bool {state.blockedMembers.contains(id) || hiddenKeys.contains(SafetyTarget.user(id).id)}
    func isTargetVisible(_ target:SafetyTarget)->Bool {
        !hiddenKeys.contains(target.id) && (target.authorID.map{!isUserHidden($0)} ?? true)
    }
    func isPostVisible(_ value:CoffeeMoment)->Bool {
        let approved = !value.isOwnMoment || value.moderation == .approved
        // Keep previous coffee-desk blocks effective after collection portraits were assigned.
        if !value.isOwnMoment,CollectionConversation.entry(value.id) != nil,isUserHidden(CoffeeMember.editorial.id) {return false}
        return approved && isTargetVisible(.post(value))
    }
    var visiblePosts:[CoffeeMoment] {(state.ownMoments+CoffeeMoment.editorial).filter{isPostVisible($0)}}
    func post(_ id:String)->CoffeeMoment? {visiblePosts.first{$0.id==id}}
    func appreciationCount(for post:CoffeeMoment)->Int {
        let sample=post.isOwnMoment ? 0:(CollectionConversation.entry(post.id)?.appreciationCount ?? 0)
        return sample+(state.appreciatedMoments.contains(post.id) ? 1:0)
    }
    var tastingNotes:[TastingReply] {TastingReply.collectionSamples+state.tastingReplies}
    func visibleComments(_ momentID:String)->[TastingReply] {
        guard post(momentID) != nil else{return []}
        return tastingNotes.filter{$0.momentID==momentID && isTargetVisible(.comment($0,owner:state.passport.id.uuidString))}.sorted{$0.createdAt<$1.createdAt}
    }
    func isRoomVisible(_ room:CoffeeTable)->Bool {isTargetVisible(.init(kind:.room,contentReference:room.id,authorID:room.hostMemberID))}
    func isMutual(_ id:String)->Bool {
        guard !isUserHidden(id),state.followedMembers.contains(id),let consent=community.relationships[id] else{return false}
        return consent.correspondentID==id && consent.passportID==state.passport.id && consent.followsCurrentGuest && !consent.confirmationID.isEmpty
    }
    func isFriend(_ id:String)->Bool {isMutual(id) && community.relationships[id]?.friendshipAccepted == true}
    var followers:[CoffeeMember] {community.relationships.keys.sorted().compactMap {id -> CoffeeMember? in
        guard !isUserHidden(id),let consent=community.relationships[id],consent.passportID==state.passport.id,
              consent.correspondentID==id,consent.followsCurrentGuest,!consent.confirmationID.isEmpty else{return nil}
        return person(id)
    }}
    var friends:[CoffeeMember] {community.relationships.keys.sorted().filter{isFriend($0)}.compactMap{person($0)}}
    @discardableResult func requireMutual(_ id:String)->Bool {
        guard state.signedIn,!isUserHidden(id),person(id) != nil else {inform("Profile unavailable","This profile is unavailable or hidden. Your saved conversation stays on this device.");return false}
        guard isMutual(id) else {
            inform("Follow each other first","Both people must choose to follow each other before sending messages or starting a video call. Your draft has been kept.");return false
        }
        return true
    }
    func requestFriendship(_ id:String) {
        guard !isUserHidden(id),id != state.passport.id.uuidString,person(id) != nil else{return}
        if isFriend(id) {return}
        if commit({value in
            var data=value.community ?? CorrespondenceLedger()
            if data.friendshipRequests[id]==nil {data.friendshipRequests[id] = .init(correspondentID:id)}
            value.community=data
        }) {inform("Friend request saved","The request is saved on this device. No community service is connected, so it has not been sent or accepted. Nobody has been added as a friend.")}
    }
    func cancelFriendshipRequest(_ id:String) {
        _ = commit {value in
            var data=value.community ?? CorrespondenceLedger();data.friendshipRequests.removeValue(forKey:id);value.community=data
        }
    }
    @discardableResult func report(_ target:SafetyTarget,reason:String)->Bool {
        guard !reason.isEmpty else{return false}
        let comment=target.kind == .comment ? tastingNotes.first{$0.id==target.contentReference}:nil
        let excerpt=comment?.text ?? (target.kind == .post ? (state.ownMoments+CoffeeMoment.editorial).first{$0.id==target.contentReference}?.caption:nil)
        let saved=commit {value in
            if !value.communityReports.contains(where:{($0.target?.id ?? SafetyTarget.legacy($0.contentReference)?.id)==target.id}) {value.communityReports.append(.init(contentReference:target.id,reason:reason,target:target,parentID:comment?.momentID,excerpt:excerpt.map{String($0.prefix(500))}))}
            var data=value.community ?? CorrespondenceLedger()
            data.hiddenTargets.insert(target.id)
            value.community=data
        }
        if saved {
            leaveHiddenRoom()
            notice = .init(title:"Report saved",message:"This item is hidden from your lists and your report is kept in your coffee book. Community review is not connected, so the report has not been delivered to a team.",kind:.safety)
        }
        return saved
    }
    @discardableResult func block(_ id:String)->Bool {
        guard id != state.passport.id.uuidString else{return false}
        let passport=person(id)
        let saved=commit {value in
            value.blockedMembers.insert(id);value.followedMembers.remove(id)
            var data=value.community ?? CorrespondenceLedger()
            if let passport {data.rememberedPeople[id]=passport}
            data.relationships.removeValue(forKey:id)
            data.friendshipRequests.removeValue(forKey:id)
            value.community=data
        }
        if saved {
            leaveHiddenRoom()
            notice = .init(title:"User blocked",message:"This person's moments, replies, coffee tables and conversations are hidden from your lists. Manage blocked people in Settings.",kind:.safety)
        }
        return saved
    }
    @discardableResult func hide(_ target:SafetyTarget)->Bool {
        if target.kind == .user {return block(target.contentReference)}
        if commit({value in
            var data=value.community ?? CorrespondenceLedger();data.hiddenTargets.insert(target.id);value.community=data
        }) {leaveHiddenRoom();notice = .init(title:"Content hidden",message:"This item is hidden from your lists and will stay hidden after you reopen Papi.",kind:.safety);return true}
        return false
    }
    func unblock(_ id:String) {
        if commit({$0.blockedMembers.remove(id)}) {notice = .init(title:"User unblocked",message:"The block has been removed. Previously reported items remain hidden, and following or friendship is never restored automatically.",kind:.safety)}
    }
    private func leaveHiddenRoom() {
        if let id=activeRoomID,let room=CoffeeTable.previews.first(where:{$0.id==id}),!isRoomVisible(room) {activeRoomID=nil;roomMicRequested=false}
    }
    var conversationPeople:[CoffeeMember] {
        let ids=Set(community.messages.map(\.correspondentID)).union(state.letterDrafts.keys).union(state.letterPhotos.keys).union(state.letterVoiceNotes.keys)
        return ids.sorted().compactMap{person($0)}.filter{!isUserHidden($0.id) && (hasChatDraft($0.id) || !messages(with:$0.id).isEmpty)}
    }
    func messages(with id:String)->[CoffeeLetter] {
        guard !isUserHidden(id) else{return []}
        return community.messages.filter{message in
            message.correspondentID==id && !isUserHidden(message.authorID) && isTargetVisible(.init(kind:.message,contentReference:message.id,authorID:message.authorID))
        }.sorted{$0.createdAt<$1.createdAt}
    }
    @discardableResult func sendChat(to id:String,text:String)->Bool {
        guard requireMutual(id) else{return false}
        let clean=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard clean.count<=2000 else {inform("Note is too long","Keep your note under 2,000 characters. Your text has been kept.");return false}
        guard validateCommunityText(clean) else{return false}
        let photo=state.letterPhotos[id],voice=state.letterVoiceNotes[id]
        guard !clean.isEmpty || photo != nil || voice != nil else{return false}
        if [photo,voice].compactMap({$0}).contains(where:{CoffeeMedia.url($0)==nil}) {
            inform("Could not import media","Choose an existing photo or video instead.");return false
        }
        let saved=commit {value in
            var data=value.community ?? CorrespondenceLedger()
            let owner=value.passport.id.uuidString
            if !clean.isEmpty {data.messages.append(.init(correspondentID:id,authorID:owner,kind:.text,value:clean))}
            if let photo {data.messages.append(.init(correspondentID:id,authorID:owner,kind:.photo,value:photo))}
            if let voice {data.messages.append(.init(correspondentID:id,authorID:owner,kind:.voice,value:voice))}
            value.community=data;value.letterDrafts.removeValue(forKey:id);value.letterPhotos.removeValue(forKey:id);value.letterVoiceNotes.removeValue(forKey:id)
        }
        if saved {inform("Saved to outbox","Your message is saved locally, not delivered. A connected messaging service is required to send it to another person.")}
        return saved
    }
}
