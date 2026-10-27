-- Draft only. Enable with the revocation worker only after concurrent join,
-- block, expiry and LiveKit token revocation have been verified.
create table papi_private.voice_members (
  owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,
  topic_id text not null references public.coffee_voice_topics(id),
  session_id uuid not null unique,
  status text not null default 'active' check (status in ('active','closing')),
  heartbeat_at timestamptz not null default now()
);
create index voice_members_topic_idx on papi_private.voice_members(topic_id);
alter table papi_private.voice_members enable row level security;
revoke all on papi_private.voice_members from public,anon,authenticated;

create table papi_private.voice_revocations (
  session_id uuid primary key,
  owner_id uuid not null,
  topic_id text not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index voice_revocations_pending_idx on papi_private.voice_revocations(created_at,session_id) where completed_at is null;
alter table papi_private.voice_revocations enable row level security;
revoke all on papi_private.voice_revocations from public,anon,authenticated;

create function papi_private.lock_voice_membership() returns void
language sql volatile security definer set search_path = '' as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('papi-voice-membership',0));
$$;
revoke all on function papi_private.lock_voice_membership() from public,anon,authenticated;

create function papi_private.queue_voice_revocation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.status='active' and (tg_op='DELETE' or new.status='closing') then
    insert into papi_private.voice_revocations(session_id,owner_id,topic_id)
      values(old.session_id,old.owner_id,old.topic_id) on conflict(session_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function papi_private.queue_voice_revocation() from public,anon,authenticated;
create trigger voice_member_closing after update of status on papi_private.voice_members
  for each row execute function papi_private.queue_voice_revocation();
create trigger voice_member_deleted after delete on papi_private.voice_members
  for each row execute function papi_private.queue_voice_revocation();

-- All app-originated blocks and voice joins take this lock first, preventing a
-- join from observing a block transaction halfway through.
create or replace function papi_private.set_coffee_block(p_member uuid,p_enabled boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_member is null or p_member=actor or p_enabled is null then raise exception 'Invalid block'; end if;
  perform papi_private.lock_voice_membership();
  perform papi_private.lock_social_pair(actor,p_member);
  if p_enabled then
    insert into public.coffee_blocks(blocker_id,blocked_id) values(actor,p_member) on conflict do nothing;
    update papi_private.voice_members other set status='closing'
      where other.owner_id=p_member and other.status='active'
        and exists(select 1 from papi_private.voice_members mine where mine.owner_id=actor and mine.topic_id=other.topic_id);
  else
    delete from public.coffee_blocks where blocker_id=actor and blocked_id=p_member;
  end if;
  return true;
end;
$$;

create function papi_private.enter_coffee_voice(p_topic text,p_session uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); existing papi_private.voice_members%rowtype;
begin
  if actor is null or p_session is null or p_topic is null then raise exception 'Voice room unavailable'; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing' where status='active' and heartbeat_at<now()-interval '45 seconds';
  if not exists(select 1 from public.coffee_voice_topics t where t.id=p_topic and t.enabled) then raise exception 'Voice room unavailable'; end if;
  if exists(select 1 from papi_private.voice_revocations q where q.session_id=p_session) then raise exception 'Voice session ended'; end if;
  if exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.completed_at is null) then raise exception 'Previous voice session is closing'; end if;
  select * into existing from papi_private.voice_members where owner_id=actor;
  if found then
    if existing.session_id=p_session and existing.topic_id=p_topic and existing.status='active' then
      update papi_private.voice_members set heartbeat_at=now() where owner_id=actor;
      return true;
    end if;
    raise exception 'Previous voice session is closing';
  end if;
  if exists(select 1 from papi_private.voice_members m join public.coffee_blocks b
      on (b.blocker_id=actor and b.blocked_id=m.owner_id) or (b.blocker_id=m.owner_id and b.blocked_id=actor)
      where m.topic_id=p_topic) then raise exception 'Voice room unavailable'; end if;
  if (select count(*) from papi_private.voice_members where topic_id=p_topic)>=20 then raise exception 'Voice room is full'; end if;
  insert into papi_private.voice_members(owner_id,topic_id,session_id) values(actor,p_topic,p_session);
  return true;
end;
$$;
revoke all on function papi_private.enter_coffee_voice(text,uuid) from public,anon;
grant execute on function papi_private.enter_coffee_voice(text,uuid) to authenticated;
create function public.enter_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.enter_coffee_voice(p_topic,p_session); $$;
revoke all on function public.enter_coffee_voice(text,uuid) from public,anon;
grant execute on function public.enter_coffee_voice(text,uuid) to authenticated;

create function papi_private.heartbeat_coffee_voice(p_topic text,p_session uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_session is null or p_topic is null then return false; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing' where status='active' and heartbeat_at<now()-interval '45 seconds';
  update papi_private.voice_members set heartbeat_at=now()
    where owner_id=actor and topic_id=p_topic and session_id=p_session and status='active';
  return found;
end;
$$;
revoke all on function papi_private.heartbeat_coffee_voice(text,uuid) from public,anon;
grant execute on function papi_private.heartbeat_coffee_voice(text,uuid) to authenticated;
create function public.heartbeat_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.heartbeat_coffee_voice(p_topic,p_session); $$;
revoke all on function public.heartbeat_coffee_voice(text,uuid) from public,anon;
grant execute on function public.heartbeat_coffee_voice(text,uuid) to authenticated;

create function papi_private.leave_coffee_voice(p_topic text,p_session uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_session is null or p_topic is null then return false; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing'
    where owner_id=actor and topic_id=p_topic and session_id=p_session and status='active';
  if found then return true; end if;
  if exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.topic_id=p_topic and q.session_id=p_session) then return true; end if;
  if exists(select 1 from papi_private.voice_members m where m.owner_id=actor) or
     exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.completed_at is null) or
     not exists(select 1 from public.coffee_voice_topics t where t.id=p_topic) then return false; end if;
  -- A tombstone prevents a delayed enter request from resurrecting this session.
  insert into papi_private.voice_revocations(session_id,owner_id,topic_id) values(p_session,actor,p_topic)
    on conflict(session_id) do nothing;
  return exists(select 1 from papi_private.voice_revocations q where q.session_id=p_session and q.owner_id=actor and q.topic_id=p_topic);
end;
$$;
revoke all on function papi_private.leave_coffee_voice(text,uuid) from public,anon;
grant execute on function papi_private.leave_coffee_voice(text,uuid) to authenticated;
create function public.leave_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.leave_coffee_voice(p_topic,p_session); $$;
revoke all on function public.leave_coffee_voice(text,uuid) from public,anon;
grant execute on function public.leave_coffee_voice(text,uuid) to authenticated;

create function papi_private.can_join_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from papi_private.voice_members m join public.coffee_voice_topics t on t.id=m.topic_id
    where m.owner_id=(select auth.uid()) and m.topic_id=p_topic and m.session_id=p_session
      and m.status='active' and m.heartbeat_at>=now()-interval '45 seconds' and t.enabled);
$$;
revoke all on function papi_private.can_join_coffee_voice(text,uuid) from public,anon;
grant execute on function papi_private.can_join_coffee_voice(text,uuid) to authenticated;
create function public.can_join_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.can_join_coffee_voice(p_topic,p_session); $$;
revoke all on function public.can_join_coffee_voice(text,uuid) from public,anon;
grant execute on function public.can_join_coffee_voice(text,uuid) to authenticated;

create function papi_private.pending_voice_revocations()
returns table(session_id uuid,owner_id uuid,topic_id text) language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Service authorization required'; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing' where status='active' and heartbeat_at<now()-interval '45 seconds';
  return query select q.session_id,q.owner_id,q.topic_id from papi_private.voice_revocations q
    where q.completed_at is null order by q.created_at,q.session_id limit 20;
end;
$$;
revoke all on function papi_private.pending_voice_revocations() from public,anon,authenticated;
grant execute on function papi_private.pending_voice_revocations() to service_role;
create function public.pending_voice_revocations() returns table(session_id uuid,owner_id uuid,topic_id text)
language sql security invoker set search_path = '' as $$ select * from papi_private.pending_voice_revocations(); $$;
revoke all on function public.pending_voice_revocations() from public,anon,authenticated;
grant execute on function public.pending_voice_revocations() to service_role;

create function papi_private.complete_voice_revocation(p_session uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_session is null then raise exception 'Service authorization required'; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_revocations set completed_at=coalesce(completed_at,now()) where session_id=p_session;
  if not found then return false; end if;
  delete from papi_private.voice_members where session_id=p_session and status='closing';
  return true;
end;
$$;
revoke all on function papi_private.complete_voice_revocation(uuid) from public,anon,authenticated;
grant execute on function papi_private.complete_voice_revocation(uuid) to service_role;
create function public.complete_voice_revocation(p_session uuid) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.complete_voice_revocation(p_session); $$;
revoke all on function public.complete_voice_revocation(uuid) from public,anon,authenticated;
grant execute on function public.complete_voice_revocation(uuid) to service_role;
