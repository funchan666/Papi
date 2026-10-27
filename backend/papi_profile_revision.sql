-- Revision changes for every profile update so a device can detect stale edits.
alter table public.coffee_profiles add column revision bigint not null default 0 check (revision >= 0);
create function papi_private.stamp_coffee_profile() returns trigger
language plpgsql security definer set search_path = ''
as $$ begin new.revision := old.revision + 1; new.updated_at := clock_timestamp(); return new; end; $$;
revoke all on function papi_private.stamp_coffee_profile() from public, anon, authenticated;
create trigger coffee_profile_stamp before update on public.coffee_profiles
  for each row execute function papi_private.stamp_coffee_profile();
