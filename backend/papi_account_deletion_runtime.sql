-- Dormant foundation. Existing accounts and files are not modified.
create table papi_private.account_deletion_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into papi_private.account_deletion_runtime(singleton,enabled) values (true,false);
alter table papi_private.account_deletion_runtime enable row level security;
revoke all on papi_private.account_deletion_runtime from public,anon,authenticated;

-- Kept independently of Auth so an interrupted deletion can be retried.
create table papi_private.account_deletions (
  owner_id uuid primary key,
  receipt_hash bytea not null unique,
  state text not null default 'requested' check (state in ('requested','complete')),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table papi_private.account_deletions enable row level security;
revoke all on papi_private.account_deletions from public,anon,authenticated;

create function papi_private.coffee_deletion_available() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select auth.jwt())->>'role','')='service_role'
    and coalesce((select enabled from papi_private.account_deletion_runtime where singleton),false);
$$;
revoke all on function papi_private.coffee_deletion_available() from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_available() to service_role;
create function public.coffee_deletion_available() returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.coffee_deletion_available(); $$;
revoke all on function public.coffee_deletion_available() from public,anon,authenticated;
grant execute on function public.coffee_deletion_available() to service_role;
