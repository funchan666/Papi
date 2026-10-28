-- Private helper only; it has no effect until the guarded pair migration is applied.
create function papi_private.lock_coffee_account_pair(a uuid,b uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare first_id text; second_id text;
begin
  if a is null or b is null then raise exception 'Invalid account pair'; end if;
  first_id:=least(a::text,b::text);
  second_id:=greatest(a::text,b::text);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || first_id,0));
  if second_id<>first_id then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || second_id,0));
  end if;
end;
$$;
revoke all on function papi_private.lock_coffee_account_pair(uuid,uuid) from public,anon,authenticated;
