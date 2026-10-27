-- Friendship requires mutual following and the recipient's explicit answer.
-- Pair locking keeps decisions consistent with follow and block operations.
revoke insert (id, requester_id, recipient_id) on public.coffee_friend_requests from authenticated;
revoke update (status) on public.coffee_friend_requests from authenticated;
revoke insert, update, delete on public.coffee_friend_requests from authenticated;

create function papi_private.request_coffee_friendship(p_id uuid, p_recipient uuid) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  existing public.coffee_friend_requests%rowtype;
begin
  if actor is null or p_id is null or p_recipient is null or actor = p_recipient then raise exception 'Invalid request'; end if;
  perform papi_private.lock_social_pair(actor, p_recipient);
  select * into existing from public.coffee_friend_requests r where r.id = p_id;
  if found then
    if existing.requester_id <> actor or existing.recipient_id <> p_recipient then raise exception 'Request identifier already used'; end if;
    return existing.id;
  end if;
  if not papi_private.mutual_follow(actor, p_recipient) then raise exception 'Mutual following required'; end if;
  select * into existing from public.coffee_friend_requests r
    where (r.requester_id = actor and r.recipient_id = p_recipient)
       or (r.requester_id = p_recipient and r.recipient_id = actor)
    order by case r.status when 'accepted' then 0 when 'pending' then 1 else 2 end, r.created_at desc limit 1;
  if found and existing.status in ('accepted','pending') then return existing.id; end if;
  delete from public.coffee_friend_requests r
    where r.requester_id = actor and r.recipient_id = p_recipient and r.status = 'declined';
  insert into public.coffee_friend_requests (id, requester_id, recipient_id)
    values (p_id, actor, p_recipient);
  return p_id;
end;
$$;
revoke all on function papi_private.request_coffee_friendship(uuid,uuid) from public, anon;
grant execute on function papi_private.request_coffee_friendship(uuid,uuid) to authenticated;
create function public.request_coffee_friendship(p_id uuid, p_recipient uuid) returns uuid
language sql security invoker set search_path = ''
as $$ select papi_private.request_coffee_friendship(p_id,p_recipient); $$;
revoke all on function public.request_coffee_friendship(uuid,uuid) from public, anon;
grant execute on function public.request_coffee_friendship(uuid,uuid) to authenticated;

create function papi_private.answer_coffee_friendship(p_id uuid, p_accept boolean) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); existing public.coffee_friend_requests%rowtype; desired text;
begin
  if actor is null or p_id is null or p_accept is null then raise exception 'Invalid answer'; end if;
  select * into existing from public.coffee_friend_requests r where r.id = p_id and r.recipient_id = actor;
  if not found then raise exception 'Request unavailable'; end if;
  perform papi_private.lock_social_pair(actor, existing.requester_id);
  select * into existing from public.coffee_friend_requests r where r.id = p_id and r.recipient_id = actor for update;
  if not found then raise exception 'Request unavailable'; end if;
  desired := case when p_accept then 'accepted' else 'declined' end;
  if existing.status = desired then return true; end if;
  if existing.status <> 'pending' or not papi_private.mutual_follow(actor, existing.requester_id) then raise exception 'Request unavailable'; end if;
  update public.coffee_friend_requests set status = desired where id = p_id;
  return true;
end;
$$;
revoke all on function papi_private.answer_coffee_friendship(uuid,boolean) from public, anon;
grant execute on function papi_private.answer_coffee_friendship(uuid,boolean) to authenticated;
create function public.answer_coffee_friendship(p_id uuid, p_accept boolean) returns boolean
language sql security invoker set search_path = ''
as $$ select papi_private.answer_coffee_friendship(p_id,p_accept); $$;
revoke all on function public.answer_coffee_friendship(uuid,boolean) from public, anon;
grant execute on function public.answer_coffee_friendship(uuid,boolean) to authenticated;

create function papi_private.cancel_coffee_friendship(p_id uuid) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); existing public.coffee_friend_requests%rowtype;
begin
  if actor is null or p_id is null then raise exception 'Invalid request'; end if;
  select * into existing from public.coffee_friend_requests r where r.id = p_id and r.requester_id = actor;
  if not found then return true; end if;
  perform papi_private.lock_social_pair(actor, existing.recipient_id);
  delete from public.coffee_friend_requests r where r.id = p_id and r.requester_id = actor and r.status in ('pending','declined');
  if not found and exists (select 1 from public.coffee_friend_requests r where r.id = p_id and r.requester_id = actor) then
    raise exception 'Request unavailable';
  end if;
  return true;
end;
$$;
revoke all on function papi_private.cancel_coffee_friendship(uuid) from public, anon;
grant execute on function papi_private.cancel_coffee_friendship(uuid) to authenticated;
create function public.cancel_coffee_friendship(p_id uuid) returns boolean
language sql security invoker set search_path = ''
as $$ select papi_private.cancel_coffee_friendship(p_id); $$;
revoke all on function public.cancel_coffee_friendship(uuid) from public, anon;
grant execute on function public.cancel_coffee_friendship(uuid) to authenticated;
