-- Limit token minting per account without exposing the counter to clients.
-- This does not limit an already connected participant's LiveKit refreshes.
create table papi_private.livekit_token_limits (
  owner_id uuid not null references auth.users(id) on delete cascade,
  token_kind text not null check (token_kind in ('call','voice','voice_leave')),
  window_started_at timestamptz not null,
  attempts integer not null check (attempts between 1 and 7),
  primary key(owner_id,token_kind)
);
alter table papi_private.livekit_token_limits enable row level security;
revoke all on papi_private.livekit_token_limits from public,anon,authenticated;

create function papi_private.consume_livekit_token_budget(p_kind text) returns boolean
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
revoke all on function papi_private.consume_livekit_token_budget(text) from public,anon,authenticated;

create function papi_private.reserve_coffee_call_token(p_id uuid) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not papi_private.can_join_coffee_call(p_id) then return false; end if;
  return papi_private.consume_livekit_token_budget('call');
end;
$$;
revoke all on function papi_private.reserve_coffee_call_token(uuid) from public,anon;
grant execute on function papi_private.reserve_coffee_call_token(uuid) to authenticated;
create function public.reserve_coffee_call_token(p_id uuid) returns boolean
language sql volatile security invoker set search_path = '' as $$ select papi_private.reserve_coffee_call_token(p_id); $$;
revoke all on function public.reserve_coffee_call_token(uuid) from public,anon;
grant execute on function public.reserve_coffee_call_token(uuid) to authenticated;

create function papi_private.reserve_coffee_voice_token(p_topic text,p_session uuid) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not papi_private.can_join_coffee_voice(p_topic,p_session) then return false; end if;
  return papi_private.consume_livekit_token_budget('voice');
end;
$$;
revoke all on function papi_private.reserve_coffee_voice_token(text,uuid) from public,anon;
grant execute on function papi_private.reserve_coffee_voice_token(text,uuid) to authenticated;
create function public.reserve_coffee_voice_token(p_topic text,p_session uuid) returns boolean
language sql volatile security invoker set search_path = '' as $$ select papi_private.reserve_coffee_voice_token(p_topic,p_session); $$;
revoke all on function public.reserve_coffee_voice_token(text,uuid) from public,anon;
grant execute on function public.reserve_coffee_voice_token(text,uuid) to authenticated;
