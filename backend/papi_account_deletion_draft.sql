-- Draft only: do not deploy until purchase settlement, receipt recovery,
-- Storage concurrency, session revocation and operational retries are verified.
-- Requires the disabled foundation in papi_account_deletion_runtime.sql.

-- Lock uploads and deletion on the same owner key. A stale JWT cannot add a
-- new object after deletion begins, even if it remains valid for a short time.
create function papi_private.coffee_upload_allowed() returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null then return false; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  return not exists(select 1 from papi_private.account_deletions d where d.owner_id=actor);
end;
$$;
revoke all on function papi_private.coffee_upload_allowed() from public,anon;
grant execute on function papi_private.coffee_upload_allowed() to authenticated;
create policy coffee_media_not_deleting on storage.objects as restrictive for insert to authenticated
  with check (bucket_id<>'coffee-media' or papi_private.coffee_upload_allowed());

-- Requires the deployed private begin function; do not expose until guard policies are applied.
revoke all on function papi_private.begin_coffee_deletion(text) from public,anon;
grant execute on function papi_private.begin_coffee_deletion(text) to authenticated;
create function public.begin_coffee_deletion(p_secret text) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.begin_coffee_deletion(p_secret); $$;
revoke all on function public.begin_coffee_deletion(text) from public,anon;
grant execute on function public.begin_coffee_deletion(text) to authenticated;

-- The service-only RPCs are in papi_account_deletion_service_rpcs.sql.
