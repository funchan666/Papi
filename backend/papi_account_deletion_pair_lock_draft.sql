-- DRAFT ONLY: apply atomically with the deletion guards, after auditing lock
-- order across calls, blocks, follow changes and account deletion.
-- The account locks make a new pair operation serialize against deletion of
-- either participant; the existing pair lock still serializes the relationship.
create or replace function papi_private.lock_social_pair(a uuid,b uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform papi_private.lock_coffee_account_pair(a,b);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'coffee-pair:' || least(a::text,b::text) || ':' || greatest(a::text,b::text),0));
end;
$$;
