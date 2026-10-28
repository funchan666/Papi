-- Inert private implementation; client roles cannot execute it.
create function papi_private.begin_coffee_deletion(p_secret text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); digest bytea;
begin
  if actor is null or p_secret is null or p_secret !~ '^[0-9a-f]{64}$' then raise exception 'Invalid deletion request'; end if;
  if not coalesce((select enabled from papi_private.account_deletion_runtime where singleton),false) then raise exception 'Deletion unavailable'; end if;
  -- Keep the same lock order as room joins and call requests. Marking a
  -- session closed queues its LiveKit revocation before deleting the user.
  perform papi_private.lock_voice_membership();
  perform papi_private.lock_call_runtime();
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() then raise exception 'Account unavailable'; end if;
  if exists(select 1 from public.coffee_purchase_orders o where o.owner_id=actor and o.completed_at is null) then raise exception 'Purchase reconciliation required'; end if;
  update papi_private.voice_members set status='closing' where owner_id=actor and status='active';
  update public.coffee_calls set status='ended' where actor in (caller_id,recipient_id) and status in ('pending','accepted');
  digest:=extensions.digest(p_secret,'sha256');
  insert into papi_private.account_deletions(owner_id,receipt_hash) values(actor,digest) on conflict(owner_id) do nothing;
  return exists(select 1 from papi_private.account_deletions d where d.owner_id=actor and d.receipt_hash=digest);
end;
$$;

revoke all on function papi_private.begin_coffee_deletion(text) from public,anon,authenticated;
