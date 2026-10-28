-- DRAFT ONLY. Pair-lock reactions and comments with the post author before
-- the generic actor-write trigger; apply atomically with deletion guards.
create function papi_private.guard_coffee_post_target() returns trigger
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); target uuid; post_id uuid;
begin
  if coalesce((select auth.jwt())->>'role','')='service_role' then return new; end if;
  if actor is null then raise exception 'Account unavailable'; end if;
  if tg_table_name='coffee_comments' then
    if new.author_id<>actor then raise exception 'Account unavailable'; end if;
    post_id:=new.post_id;
  else
    if new.member_id<>actor then raise exception 'Account unavailable'; end if;
    post_id:=new.moment_id;
  end if;
  select p.author_id into target from public.coffee_posts p where p.id=post_id;
  if not found then raise exception 'Post unavailable'; end if;
  perform papi_private.lock_coffee_account_pair(actor,target);
  if not papi_private.coffee_actor_active() or
     exists(select 1 from papi_private.account_deletions d where d.owner_id=target) or
     not papi_private.clear_pair(actor,target) or
     not exists(select 1 from public.coffee_posts p where p.id=post_id and p.author_id=target and p.moderation_status='approved') then
    raise exception 'Post unavailable';
  end if;
  return new;
end;
$$;
revoke all on function papi_private.guard_coffee_post_target() from public,anon,authenticated;
create trigger coffee_00_target_writer before insert on public.coffee_comments
  for each row execute function papi_private.guard_coffee_post_target();
create trigger coffee_00_target_writer before insert on public.coffee_likes
  for each row execute function papi_private.guard_coffee_post_target();
create trigger coffee_00_target_writer before insert on public.coffee_bookmarks
  for each row execute function papi_private.guard_coffee_post_target();
