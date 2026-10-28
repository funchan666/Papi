-- Private helpers are deployed but not attached to policies or triggers.
create function papi_private.coffee_actor_active() returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
    and exists(select 1 from auth.users u where u.id=(select auth.uid()))
    and exists(select 1 from auth.sessions s where s.user_id=(select auth.uid())
      and s.id::text=coalesce((select auth.jwt())->>'session_id','')
      and (s.not_after is null or s.not_after>now()))
    and not exists(select 1 from papi_private.account_deletions d where d.owner_id=(select auth.uid()));
$$;
revoke all on function papi_private.coffee_actor_active() from public,anon;
grant execute on function papi_private.coffee_actor_active() to authenticated;

create function papi_private.guard_coffee_actor_write() returns trigger
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is not null and coalesce((select auth.jwt())->>'role','')<>'service_role' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
    if not papi_private.coffee_actor_active() then raise exception 'Account unavailable'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function papi_private.guard_coffee_actor_write() from public,anon,authenticated;

