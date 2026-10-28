import Foundation

@MainActor extension CoffeeHouse {
    var visiblePassport:CoffeePassport {
        var passport=state.passport
        if let account=state.cloudAccountID {
            passport.avatar=profileImageReference(cloudImageSummaries[account]?.avatar_path,owner:account) ?? "emptyCup"
            passport.cover=profileImageReference(cloudImageSummaries[account]?.cover_path,owner:account) ?? "corner-latte"
            if let profile=cloudProfiles?.first(where:{$0.id==account}) {
                passport.name=profile.display_name;passport.bio=profile.biography
            } else {passport.name=text("Profile unavailable");passport.bio=""}
        }
        return passport
    }
    func profileImageReference(_ path:String?,owner:UUID)->String? {
        guard let path,path.lowercased().hasPrefix(owner.uuidString.lowercased()+"/profile-"),
              path.split(separator:"/").count==2,!path.contains(".."),path.lowercased().hasSuffix(".jpg") else{return nil}
        return "cloud/"+path
    }
    var community:CorrespondenceLedger {state.community ?? CorrespondenceLedger()}
    var hiddenKeys:Set<String> {
        community.hiddenTargets.union(state.communityReports.compactMap{$0.target?.id ?? SafetyTarget.legacy($0.contentReference)?.id})
    }
    var visibilityKeys:[String] {
        (hiddenKeys.union(state.blockedMembers.map{"blocked:"+$0}).union(cloudBlocks.map{"blocked:"+$0.blocked_id.uuidString})
            .union(cloudReports.map{"reported:"+$0.subject_kind+":"+$0.subject_id.uuidString})).sorted()
    }
    var followingIDs:Set<String> {
        guard let account=state.cloudAccountID else {return state.followedMembers}
        return Set(cloudFollows.filter{$0.follower_id==account}.map{$0.followed_id.uuidString})
    }
    var blockedIDs:Set<String> {
        guard let account=state.cloudAccountID else {return state.blockedMembers}
        return Set(cloudBlocks.filter{$0.blocker_id==account}.map{$0.blocked_id.uuidString}).union(state.blockedMembers.filter{UUID(uuidString:$0)==nil})
    }
    func isFollowing(_ id:String)->Bool {
        guard usesCloudWallet else {return state.followedMembers.contains(id)}
        guard let account=state.cloudAccountID,let member=UUID(uuidString:id) else {return false}
        return cloudFollows.contains{$0.follower_id==account && $0.followed_id==member}
    }
    var communityPeople:[CoffeeMember] {
        guard usesCloudWallet else {return CoffeeMember.previews}
        guard let account=state.cloudAccountID else {return []}
        return (cloudProfiles ?? []).filter{$0.id != account}.map {
            CoffeeMember(id:$0.id.uuidString,name:$0.display_name,portrait:profileImageReference(cloudImageSummaries[$0.id]?.avatar_path,owner:$0.id) ?? "emptyCup",bio:$0.biography)
        }
    }
    func person(_ id:String)->CoffeeMember? {
        if id==state.passport.id.uuidString {let passport=visiblePassport;return .init(id:id,name:passport.name,portrait:passport.portraitReference,bio:passport.bio)}
        if let member=UUID(uuidString:id),usesCloudWallet {
            if member==state.cloudAccountID {let passport=visiblePassport;return .init(id:id,name:passport.name,portrait:passport.portraitReference,bio:passport.bio)}
            if let profile=cloudProfiles?.first(where:{$0.id==member}) {
                return .init(id:profile.id.uuidString,name:profile.display_name,portrait:profileImageReference(cloudImageSummaries[profile.id]?.avatar_path,owner:profile.id) ?? "emptyCup",bio:profile.biography)
            }
            return nil
        }
        return CoffeeMember.find(id) ?? community.rememberedPeople[id]
    }
    func isUserHidden(_ id:String)->Bool {
        if let member=UUID(uuidString:id),let account=state.cloudAccountID,
           cloudBlocks.contains(where:{$0.blocker_id==account && $0.blocked_id==member}) {return true}
        if let member=UUID(uuidString:id),cloudReports.contains(where:{$0.subject_kind=="profile" && $0.subject_id==member}) {return true}
        return state.blockedMembers.contains(id) || hiddenKeys.contains(SafetyTarget.user(id).id)
    }
    func isTargetVisible(_ target:SafetyTarget)->Bool {
        let kind=target.kind == .user ? "profile":target.kind.rawValue
        if let id=UUID(uuidString:target.contentReference),cloudReports.contains(where:{$0.subject_kind==kind && $0.subject_id==id}) {return false}
        return !hiddenKeys.contains(target.id) && (target.authorID.map{!isUserHidden($0)} ?? true)
    }
    func isPostVisible(_ value:CoffeeMoment)->Bool {
        let approved = !value.isOwnMoment || value.moderation == .approved
        if editorialReportedPosts.contains(value.id) {return false}
        // Keep previous coffee-desk blocks effective after collection portraits were assigned.
        if !value.isOwnMoment,CollectionConversation.entry(value.id) != nil,isUserHidden(CoffeeMember.editorial.id) {return false}
        return approved && isTargetVisible(.post(value))
    }
    var visiblePosts:[CoffeeMoment] {
        guard state.cloudAccountID != nil else {return (state.ownMoments+CoffeeMoment.editorial).filter{isPostVisible($0)}}
        return visibleCloudMoments(cloudFeed ?? [])
    }
    var visibleCollectionPosts:[CoffeeMoment] {
        guard !usesCloudWallet || editorialReportsReady else{return []}
        return CoffeeMoment.editorial.filter{isPostVisible($0)}
    }
    func visibleCloudMoments(_ items:[CoffeeCloud.FeedMoment])->[CoffeeMoment] {
        guard let account=state.cloudAccountID else{return []}
        return items.compactMap {item -> CoffeeMoment? in
            guard item.moderation_status=="approved",["photo","video"].contains(item.media_kind),
                  item.media_path.lowercased().hasPrefix(item.author_id.uuidString.lowercased()+"/"),
                  item.media_path.split(separator:"/").count==2,!item.media_path.contains(".."),
                  let date=cloudDate(item.created_at) else{return nil}
            return CoffeeMoment(id:item.id.uuidString,authorID:item.author_id.uuidString,media:"cloud/"+item.media_path,
                isVideo:item.media_kind=="video",caption:item.caption,category:"Coffee moment",createdAt:date,
                isOwnMoment:item.author_id==account,moderation:.approved)
        }.filter{isPostVisible($0)}
    }
    func cloudDate(_ value:String)->Date? {
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        return formatter.date(from:value) ?? ISO8601DateFormatter().date(from:value)
    }
    func activeCloudCall(with peer:UUID)->CoffeeCloud.CallSession? {
        guard let account=state.cloudAccountID else{return nil}
        return cloudCalls?.first {call in
            ((call.caller_id==account && call.recipient_id==peer) || (call.caller_id==peer && call.recipient_id==account)) &&
            ["pending","accepted"].contains(call.status) && (cloudDate(call.expires_at) ?? .distantPast)>Date()
        }
    }
    var incomingCloudCalls:[CoffeeCloud.CallSession] {
        guard let account=state.cloudAccountID else{return []}
        return (cloudCalls ?? []).filter{$0.recipient_id==account && $0.status=="pending" && (cloudDate($0.expires_at) ?? .distantPast)>Date()}
    }
    func cloudFeedItem(_ id:String)->CoffeeCloud.FeedMoment? {
        if let item=(cloudFeed ?? []).first(where:{$0.id.uuidString==id}) {return item}
        for shelf in cloudShelves.values {if let item=shelf.first(where:{$0.id.uuidString==id}) {return item}}
        return nil
    }
    func post(_ id:String)->CoffeeMoment? {
        if let found=visiblePosts.first(where:{$0.id==id}) {return found}
        if usesCloudWallet,let found=visibleCollectionPosts.first(where:{$0.id==id}) {return found}
        guard let item=cloudFeedItem(id) else{return nil}
        return visibleCloudMoments([item]).first
    }
    func cloudShelfPosts(author:UUID?,saved:Bool)->[CoffeeMoment] {
        let items=cloudShelves[cloudShelfKey(author:author,saved:saved)] ?? []
        return visibleCloudMoments(saved ? items.filter(\.bookmarked):items)
    }
    func isVisibleCloudVideo(_ media:String)->Bool {
        let items=(cloudFeed ?? []) + cloudShelves.values.flatMap{$0}
        return visibleCloudMoments(items).contains{$0.media==media && $0.isVideo}
    }
    func appreciationCount(for post:CoffeeMoment)->Int {
        if usesCloudWallet {return cloudFeedItem(post.id)?.like_count ?? 0}
        let sample=post.isOwnMoment ? 0:(CollectionConversation.entry(post.id)?.appreciationCount ?? 0)
        return sample+(state.appreciatedMoments.contains(post.id) ? 1:0)
    }
    var tastingNotes:[TastingReply] {TastingReply.collectionSamples+state.tastingReplies}
    func visibleComments(_ momentID:String)->[TastingReply] {
        guard post(momentID) != nil else{return []}
        if usesCloudWallet,let id=UUID(uuidString:momentID) {
            return (cloudComments[id] ?? []).compactMap {comment in
                guard let stamp=comment.created_at,let date=cloudDate(stamp) else{return nil}
                let reply=TastingReply(id:comment.id.uuidString,momentID:momentID,text:comment.body,createdAt:date,authorID:comment.author_id.uuidString)
                return isTargetVisible(.comment(reply,owner:state.passport.id.uuidString)) ? reply:nil
            }.sorted{$0.createdAt<$1.createdAt}
        }
        return tastingNotes.filter{$0.momentID==momentID && isTargetVisible(.comment($0,owner:state.passport.id.uuidString))}.sorted{$0.createdAt<$1.createdAt}
    }
    func isRoomVisible(_ room:CoffeeTable)->Bool {isTargetVisible(.init(kind:.room,contentReference:room.id,authorID:room.hostMemberID))}
    func isMutual(_ id:String)->Bool {
        if let account=state.cloudAccountID,let member=UUID(uuidString:id) {
            return !isUserHidden(id) && cloudFollows.contains{$0.follower_id==account && $0.followed_id==member}
                && cloudFollows.contains{$0.follower_id==member && $0.followed_id==account}
        }
        guard !isUserHidden(id),state.followedMembers.contains(id),let consent=community.relationships[id] else{return false}
        return consent.correspondentID==id && consent.passportID==state.passport.id && consent.followsCurrentGuest && !consent.confirmationID.isEmpty
    }
    func isFriend(_ id:String)->Bool {
        if let account=state.cloudAccountID,let member=UUID(uuidString:id) {
            return isMutual(id) && cloudFriendships.contains{$0.status=="accepted" && (($0.requester_id==account && $0.recipient_id==member) || ($0.requester_id==member && $0.recipient_id==account))}
        }
        return isMutual(id) && community.relationships[id]?.friendshipAccepted == true
    }
    func outgoingFriendship(to id:String)->CoffeeCloud.Friendship? {
        guard let account=state.cloudAccountID,let member=UUID(uuidString:id) else {return nil}
        return cloudFriendships.first{$0.requester_id==account && $0.recipient_id==member && $0.status=="pending"}
    }
    func incomingFriendship(from id:String)->CoffeeCloud.Friendship? {
        guard let account=state.cloudAccountID,let member=UUID(uuidString:id) else {return nil}
        return cloudFriendships.first{$0.requester_id==member && $0.recipient_id==account && $0.status=="pending"}
    }
    var incomingFriendships:[CoffeeCloud.Friendship] {
        guard let account=state.cloudAccountID else {return []}
        return cloudFriendships.filter{$0.recipient_id==account && $0.status=="pending"}
    }
    var followers:[CoffeeMember] {
        if let account=state.cloudAccountID {
            return cloudFollows.filter{$0.followed_id==account}.compactMap{person($0.follower_id.uuidString)}.filter{!isUserHidden($0.id)}
        }
        return community.relationships.keys.sorted().compactMap {id -> CoffeeMember? in
        guard !isUserHidden(id),let consent=community.relationships[id],consent.passportID==state.passport.id,
              consent.correspondentID==id,consent.followsCurrentGuest,!consent.confirmationID.isEmpty else{return nil}
        return person(id)
    }}
    var friends:[CoffeeMember] {
        if usesCloudWallet {return communityPeople.filter{isFriend($0.id)}}
        return community.relationships.keys.sorted().filter{isFriend($0)}.compactMap{person($0)}
    }
    @discardableResult func requireMutual(_ id:String)->Bool {
        guard state.signedIn,!isUserHidden(id),person(id) != nil else {inform("Profile unavailable","This profile is unavailable or hidden. Your conversation is still saved.");return false}
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
        }) {inform("Friend request saved","Your request has not been sent or accepted. No friend has been added.")}
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
        if let account=state.cloudAccountID {
            let ids=Set(cloudMessages.map{($0.sender_id==account ? $0.recipient_id:$0.sender_id).uuidString})
                .union(state.letterDrafts.keys).union(state.letterPhotos.keys).union(state.letterVoiceNotes.keys)
            return ids.sorted().compactMap{person($0)}.filter{!isUserHidden($0.id) && (hasChatDraft($0.id) || !messages(with:$0.id).isEmpty)}
        }
        let ids=Set(community.messages.map(\.correspondentID)).union(state.letterDrafts.keys).union(state.letterPhotos.keys).union(state.letterVoiceNotes.keys)
        return ids.sorted().compactMap{person($0)}.filter{!isUserHidden($0.id) && (hasChatDraft($0.id) || !messages(with:$0.id).isEmpty)}
    }
    func messages(with id:String)->[CoffeeLetter] {
        guard !isUserHidden(id) else{return []}
        if let account=state.cloudAccountID,let peer=UUID(uuidString:id) {
            return (cloudConversations[peer] ?? cloudMessages).compactMap {message in
                guard (message.sender_id==account && message.recipient_id==peer) || (message.sender_id==peer && message.recipient_id==account) else {return nil}
                let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
                let date=formatter.date(from:message.created_at) ?? ISO8601DateFormatter().date(from:message.created_at)
                guard let date,isTargetVisible(.init(kind:.message,contentReference:message.id.uuidString,authorID:message.sender_id.uuidString)) else {return nil}
                let kind:CoffeeLetter.Kind
                let value:String
                switch message.kind {
                case "text":kind = .text;value=message.body
                case "photo","voice":
                    let suffix=message.kind=="photo" ? ".jpg":".m4a"
                    let expected=message.sender_id.uuidString.lowercased()+"/message-"+message.id.uuidString.lowercased()+suffix
                    guard let path=message.media_path,path.lowercased()==expected else{return nil}
                    kind=message.kind=="photo" ? .photo:.voice;value="cloud/"+path
                default:return nil
                }
                return CoffeeLetter(id:message.id.uuidString,correspondentID:id,
                    authorID:message.sender_id==account ? state.passport.id.uuidString:message.sender_id.uuidString,
                    kind:kind,value:value,createdAt:date,delivery:message.sender_id==account ? .sent:.received)
            }.sorted{$0.createdAt<$1.createdAt}
        }
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
        if saved {inform("Saved to outbox","Your message was saved but not delivered. Messaging is unavailable.")}
        return saved
    }
}
