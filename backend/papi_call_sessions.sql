-- An accepted call requires explicit consent from both mutually following users.
create table public.coffee_calls (
  id uuid primary key,
  caller_id uuid not null references public.coffee_profiles(id) on delete cascade,
  recipient_id uuid not null references public.coffee_profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','ended','expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now()+interval '2 minutes'),
  check (caller_id<>recipient_id)
);
create index coffee_calls_caller_idx on public.coffee_calls(caller_id,created_at desc);
create index coffee_calls_recipient_idx on public.coffee_calls(recipient_id,created_at desc);
create unique index coffee_calls_one_active_pair on public.coffee_calls(least(caller_id,recipient_id),greatest(caller_id,recipient_id))
  where status in ('pending','accepted');
alter table public.coffee_calls enable row level security;
revoke all on public.coffee_calls from public,anon,authenticated;
grant select on public.coffee_calls to authenticated;
create policy coffee_calls_read on public.coffee_calls for select to authenticated
  using ((select auth.uid()) in (caller_id,recipient_id) and papi_private.clear_pair(caller_id,recipient_id));

create function papi_private.request_coffee_call(p_id uuid,p_recipient uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); previous public.coffee_calls%rowtype;
begin
  if actor is null or p_id is null or p_recipient is null or p_recipient=actor then raise exception 'Invalid call'; end if;
  perform papi_private.lock_social_pair(actor,p_recipient);
  select * into previous from public.coffee_calls c where c.id=p_id;
  if found then
    if previous.caller_id<>actor or previous.recipient_id<>p_recipient then raise exception 'Call identifier already used'; end if;
    return previous.id;
  end if;
  if not papi_private.mutual_follow(actor,p_recipient) then raise exception 'Mutual following required'; end if;
  update public.coffee_calls set status='expired' where status in ('pending','accepted') and expires_at<=now()
    and ((caller_id=actor and recipient_id=p_recipient) or (caller_id=p_recipient and recipient_id=actor));
  select * into previous from public.coffee_calls c where c.status in ('pending','accepted')
    and ((c.caller_id=actor and c.recipient_id=p_recipient) or (c.caller_id=p_recipient and c.recipient_id=actor));
  if found then return previous.id; end if;
  insert into public.coffee_calls(id,caller_id,recipient_id) values(p_id,actor,p_recipient);
  return p_id;
end;
$$;
revoke all on function papi_private.request_coffee_call(uuid,uuid) from public,anon;
grant execute on function papi_private.request_coffee_call(uuid,uuid) to authenticated;
create function public.request_coffee_call(p_id uuid,p_recipient uuid) returns uuid language sql security invoker set search_path = ''
as $$ select papi_private.request_coffee_call(p_id,p_recipient); $$;
revoke all on function public.request_coffee_call(uuid,uuid) from public,anon;
grant execute on function public.request_coffee_call(uuid,uuid) to authenticated;

create or replace function papi_private.answer_coffee_call(p_id uuid,p_accept boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); session_row public.coffee_calls%rowtype;
begin
  select * into session_row from public.coffee_calls c where c.id=p_id and c.recipient_id=actor;
  if not found or actor is null or p_accept is null then raise exception 'Call unavailable'; end if;
  perform papi_private.lock_social_pair(session_row.caller_id,session_row.recipient_id);
  select * into session_row from public.coffee_calls c where c.id=p_id and c.recipient_id=actor for update;
  if not found then raise exception 'Call unavailable'; end if;
  if not p_accept and session_row.status='declined' then return true; end if;
  if p_accept and session_row.status='accepted' then
    return session_row.expires_at>now() and papi_private.mutual_follow(session_row.caller_id,session_row.recipient_id);
  end if;
  if session_row.status<>'pending' or session_row.expires_at<=now() or not papi_private.mutual_follow(session_row.caller_id,session_row.recipient_id) then return false; end if;
  update public.coffee_calls set status=case when p_accept then 'accepted' else 'declined' end,
    expires_at=case when p_accept then now()+interval '1 hour' else expires_at end where id=p_id;
  return true;
end;
$$;
revoke all on function papi_private.answer_coffee_call(uuid,boolean) from public,anon;
grant execute on function papi_private.answer_coffee_call(uuid,boolean) to authenticated;
create function public.answer_coffee_call(p_id uuid,p_accept boolean) returns boolean language sql security invoker set search_path = ''
as $$ select papi_private.answer_coffee_call(p_id,p_accept); $$;
revoke all on function public.answer_coffee_call(uuid,boolean) from public,anon;
grant execute on function public.answer_coffee_call(uuid,boolean) to authenticated;

create function papi_private.end_coffee_call(p_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); session_row public.coffee_calls%rowtype;
begin
  select * into session_row from public.coffee_calls c where c.id=p_id and actor in (c.caller_id,c.recipient_id);
  if not found or actor is null then raise exception 'Call unavailable'; end if;
  perform papi_private.lock_social_pair(session_row.caller_id,session_row.recipient_id);
  update public.coffee_calls c set status='ended' where c.id=p_id and actor in (c.caller_id,c.recipient_id) and c.status in ('pending','accepted');
  return true;
end;
$$;
revoke all on function papi_private.end_coffee_call(uuid) from public,anon;
grant execute on function papi_private.end_coffee_call(uuid) to authenticated;
create function public.end_coffee_call(p_id uuid) returns boolean language sql security invoker set search_path = ''
as $$ select papi_private.end_coffee_call(p_id); $$;
revoke all on function public.end_coffee_call(uuid) from public,anon;
grant execute on function public.end_coffee_call(uuid) to authenticated;

create function papi_private.finish_calls_after_relationship_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare a uuid; b uuid;
begin
  if tg_table_name='coffee_blocks' then a:=new.blocker_id; b:=new.blocked_id;
  else a:=old.follower_id; b:=old.followed_id; end if;
  update public.coffee_calls set status='ended' where status in ('pending','accepted')
    and ((caller_id=a and recipient_id=b) or (caller_id=b and recipient_id=a));
  return null;
end;
$$;
revoke all on function papi_private.finish_calls_after_relationship_change() from public,anon,authenticated;
create trigger coffee_block_ends_calls after insert on public.coffee_blocks for each row execute function papi_private.finish_calls_after_relationship_change();
create trigger coffee_unfollow_ends_calls after delete on public.coffee_follows for each row execute function papi_private.finish_calls_after_relationship_change();

create function papi_private.can_join_coffee_call(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.coffee_calls c where c.id=p_id and (select auth.uid()) in (c.caller_id,c.recipient_id)
    and c.status='accepted' and c.expires_at>now() and papi_private.mutual_follow(c.caller_id,c.recipient_id));
$$;
revoke all on function papi_private.can_join_coffee_call(uuid) from public,anon;
grant execute on function papi_private.can_join_coffee_call(uuid) to authenticated;
create function public.can_join_coffee_call(p_id uuid) returns boolean language sql stable security invoker set search_path = ''
as $$ select papi_private.can_join_coffee_call(p_id); $$;
revoke all on function public.can_join_coffee_call(uuid) from public,anon;
grant execute on function public.can_join_coffee_call(uuid) to authenticated;
