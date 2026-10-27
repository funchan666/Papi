-- Acquire the pair lock before row mutation. This avoids a row-lock/advisory-
-- lock inversion between an unfollow and the cleanup triggered by a block.
drop trigger coffee_follow_pair_lock on public.coffee_follows;
drop trigger coffee_block_pair_lock on public.coffee_blocks;
revoke insert, delete on public.coffee_follows, public.coffee_blocks from authenticated;

create function papi_private.set_coffee_follow(p_member uuid, p_enabled boolean) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_member is null or p_member = actor or p_enabled is null then
    raise exception 'Invalid follow';
  end if;
  perform papi_private.lock_social_pair(actor, p_member);
  if p_enabled then
    if not papi_private.clear_pair(actor, p_member) then raise exception 'Profile unavailable'; end if;
    insert into public.coffee_follows (follower_id, followed_id) values (actor, p_member) on conflict do nothing;
  else
    delete from public.coffee_follows where follower_id = actor and followed_id = p_member;
  end if;
  return true;
end;
$$;
revoke all on function papi_private.set_coffee_follow(uuid,boolean) from public, anon;
grant execute on function papi_private.set_coffee_follow(uuid,boolean) to authenticated;
create function public.set_coffee_follow(p_member uuid, p_enabled boolean) returns boolean
language sql security invoker set search_path = ''
as $$ select papi_private.set_coffee_follow(p_member,p_enabled); $$;
revoke all on function public.set_coffee_follow(uuid,boolean) from public, anon;
grant execute on function public.set_coffee_follow(uuid,boolean) to authenticated;

create function papi_private.set_coffee_block(p_member uuid, p_enabled boolean) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_member is null or p_member = actor or p_enabled is null then
    raise exception 'Invalid block';
  end if;
  perform papi_private.lock_social_pair(actor, p_member);
  if p_enabled then
    insert into public.coffee_blocks (blocker_id, blocked_id) values (actor, p_member) on conflict do nothing;
  else
    delete from public.coffee_blocks where blocker_id = actor and blocked_id = p_member;
  end if;
  return true;
end;
$$;
revoke all on function papi_private.set_coffee_block(uuid,boolean) from public, anon;
grant execute on function papi_private.set_coffee_block(uuid,boolean) to authenticated;
create function public.set_coffee_block(p_member uuid, p_enabled boolean) returns boolean
language sql security invoker set search_path = ''
as $$ select papi_private.set_coffee_block(p_member,p_enabled); $$;
revoke all on function public.set_coffee_block(uuid,boolean) from public, anon;
grant execute on function public.set_coffee_block(uuid,boolean) to authenticated;
