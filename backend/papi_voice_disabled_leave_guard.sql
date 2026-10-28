-- Avoid creating unknown-session cleanup jobs while voice is disabled.
create or replace function papi_private.leave_coffee_voice(p_topic text,p_session uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_session is null or p_topic is null then return false; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing'
    where owner_id=actor and topic_id=p_topic and session_id=p_session and status='active';
  if found then return true; end if;
  if exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.topic_id=p_topic and q.session_id=p_session) then return true; end if;
  -- When disabled, an unknown enter cannot start and needs no tombstone.
  if not coalesce((select enabled from papi_private.voice_runtime_config where singleton),false) then return false; end if;
  if exists(select 1 from papi_private.voice_members m where m.owner_id=actor) or
     exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.completed_at is null) or
     not exists(select 1 from public.coffee_voice_topics t where t.id=p_topic) then return false; end if;
  -- A tombstone prevents a delayed enter request from resurrecting this session.
  insert into papi_private.voice_revocations(session_id,owner_id,topic_id) values(p_session,actor,p_topic)
    on conflict(session_id) do nothing;
  return exists(select 1 from papi_private.voice_revocations q where q.session_id=p_session and q.owner_id=actor and q.topic_id=p_topic);
end;
$$;
