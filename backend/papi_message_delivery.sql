-- Serialize a pair's follow/block changes and message sends. A repeated message
-- ID returns the original result only for the same sender, recipient and text.
create function papi_private.lock_social_pair(a uuid, b uuid) returns void
language sql volatile security definer set search_path = ''
as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'coffee-pair:' || least(a::text,b::text) || ':' || greatest(a::text,b::text), 0));
$$;
revoke all on function papi_private.lock_social_pair(uuid,uuid) from public, anon, authenticated;

create function papi_private.lock_follow_pair() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform papi_private.lock_social_pair(old.follower_id, old.followed_id);
    return old;
  end if;
  perform papi_private.lock_social_pair(new.follower_id, new.followed_id);
  return new;
end;
$$;
revoke all on function papi_private.lock_follow_pair() from public, anon, authenticated;
create trigger coffee_follow_pair_lock before insert or delete on public.coffee_follows
  for each row execute function papi_private.lock_follow_pair();

create function papi_private.lock_block_pair() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  perform papi_private.lock_social_pair(new.blocker_id, new.blocked_id);
  return new;
end;
$$;
revoke all on function papi_private.lock_block_pair() from public, anon, authenticated;
create trigger coffee_block_pair_lock before insert on public.coffee_blocks
  for each row execute function papi_private.lock_block_pair();

revoke insert (id, sender_id, recipient_id, body) on public.coffee_messages from authenticated;
revoke insert on public.coffee_messages from authenticated;
create function papi_private.send_coffee_message(p_id uuid, p_recipient uuid, p_body text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  previous public.coffee_messages%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_id is null or p_recipient is null or p_recipient = actor or p_body is null or
     char_length(trim(p_body)) not between 1 and 2000 then raise exception 'Invalid message'; end if;
  perform papi_private.lock_social_pair(actor, p_recipient);
  select * into previous from public.coffee_messages m where m.id = p_id;
  if found then
    if previous.sender_id <> actor or previous.recipient_id <> p_recipient or previous.body <> p_body then
      raise exception 'Message identifier already used';
    end if;
    return true;
  end if;
  if not papi_private.mutual_follow(actor, p_recipient) then raise exception 'Mutual following required'; end if;
  insert into public.coffee_messages (id, sender_id, recipient_id, body)
    values (p_id, actor, p_recipient, p_body);
  return true;
end;
$$;
revoke all on function papi_private.send_coffee_message(uuid,uuid,text) from public, anon;
grant execute on function papi_private.send_coffee_message(uuid,uuid,text) to authenticated;

create function public.send_coffee_message(p_id uuid, p_recipient uuid, p_body text) returns boolean
language sql security invoker set search_path = ''
as $$ select papi_private.send_coffee_message(p_id, p_recipient, p_body); $$;
revoke all on function public.send_coffee_message(uuid,uuid,text) from public, anon;
grant execute on function public.send_coffee_message(uuid,uuid,text) to authenticated;
