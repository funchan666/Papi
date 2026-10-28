-- Keep known exits available and prevent unbounded unknown-session requests.
alter table papi_private.livekit_token_limits drop constraint livekit_token_limits_token_kind_check;
alter table papi_private.livekit_token_limits add constraint livekit_token_limits_token_kind_check
  check (token_kind in ('call','voice','voice_leave'));

create or replace function papi_private.consume_livekit_token_budget(p_kind text) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); n integer; t timestamptz := clock_timestamp();
begin
  if actor is null or p_kind not in ('call','voice','voice_leave') then return false; end if;
  insert into papi_private.livekit_token_limits as budget(owner_id,token_kind,window_started_at,attempts)
    values(actor,p_kind,t,1)
  on conflict(owner_id,token_kind) do update set
    window_started_at=case when budget.window_started_at<=t-interval '1 minute' then t else budget.window_started_at end,
    attempts=case when budget.window_started_at<=t-interval '1 minute' then 1 else least(budget.attempts+1,7) end
  returning attempts into n;
  return n<=6;
end;
$$;
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
  if exists(select 1 from papi_private.voice_members m where m.owner_id=actor) or
     exists(select 1 from papi_private.voice_revocations q where q.owner_id=actor and q.completed_at is null) or
     not exists(select 1 from public.coffee_voice_topics t where t.id=p_topic) then return false; end if;
  if not papi_private.consume_livekit_token_budget('voice_leave') then return false; end if;
  -- An unknown session cannot have obtained a token while disabled, but its
  -- tombstone is still needed if a delayed enter arrives after re-enabling.
  insert into papi_private.voice_revocations(session_id,owner_id,topic_id,completed_at)
    values(p_session,actor,p_topic,case when coalesce((select enabled from papi_private.voice_runtime_config where singleton),false) then null else now() end)
    on conflict(session_id) do nothing;
  return exists(select 1 from papi_private.voice_revocations q where q.session_id=p_session and q.owner_id=actor and q.topic_id=p_topic);
end;
$$;
