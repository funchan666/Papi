-- Protective policies and triggers are deployed with deletion disabled.
-- Full production acceptance remains required before enabling deletion.
-- Requires the deployed private helpers in papi_account_deletion_private_guards.sql.
-- Requires the deployed private begin function in papi_account_deletion_private_begin.sql.
-- Restrictive policies apply alongside each table's existing ownership rules.
do $$
declare name text;
begin
  foreach name in array array[
    'coffee_blocks','coffee_bookmarks','coffee_brew_books','coffee_brew_history','coffee_calls',
    'coffee_checkins','coffee_collectible_orders','coffee_collectibles','coffee_comments','coffee_follows',
    'coffee_friend_requests','coffee_likes','coffee_messages','coffee_posts','coffee_profile_images',
    'coffee_profiles','coffee_progress','coffee_purchase_orders','coffee_recipe_unlocks','coffee_reports',
    'coffee_voice_topics','coffee_wallet_movements','coffee_wallets'
  ] loop
    execute format('create policy coffee_active_session on public.%I as restrictive for all to authenticated using ((select papi_private.coffee_actor_active())) with check ((select papi_private.coffee_actor_active()))',name);
    if name<>'coffee_voice_topics' then
      execute format('create trigger coffee_active_writer before insert or update or delete on public.%I for each row execute function papi_private.guard_coffee_actor_write()',name);
    end if;
  end loop;
  foreach name in array array['brew_book_writes','removed_post_media','removed_profile_media','voice_members'] loop
    execute format('create trigger coffee_active_writer before insert or update or delete on papi_private.%I for each row execute function papi_private.guard_coffee_actor_write()',name);
  end loop;
end;
$$;
create policy coffee_media_active_session on storage.objects as restrictive for all to authenticated
  using (bucket_id<>'coffee-media' or (select papi_private.coffee_actor_active()))
  with check (bucket_id<>'coffee-media' or (select papi_private.coffee_actor_active()));

create or replace function papi_private.clear_pair(a uuid,b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select papi_private.coffee_actor_active() and (select auth.uid()) in (a,b)
    and not exists(select 1 from papi_private.account_deletions d where d.owner_id in (a,b))
    and not exists(select 1 from public.coffee_blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a));
$$;

create or replace function papi_private.can_join_coffee_call(p_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select papi_private.coffee_actor_active() and coalesce((select enabled from papi_private.call_runtime_config where singleton),false) and exists(select 1 from public.coffee_calls c
    where c.id=p_id and (select auth.uid()) in (c.caller_id,c.recipient_id) and c.status='accepted'
      and c.expires_at>now() and papi_private.mutual_follow(c.caller_id,c.recipient_id));
$$;
create or replace function papi_private.can_join_coffee_voice(p_topic text,p_session uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select papi_private.coffee_actor_active() and coalesce((select enabled from papi_private.voice_runtime_config where singleton),false) and exists(select 1 from papi_private.voice_members m
    join public.coffee_voice_topics t on t.id=m.topic_id where m.owner_id=(select auth.uid())
      and m.topic_id=p_topic and m.session_id=p_session and m.status='active'
      and m.heartbeat_at>=now()-interval '45 seconds' and t.enabled);
$$;
