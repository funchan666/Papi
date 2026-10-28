-- Disable call requests and token issuance until the worker and client are ready.
create table papi_private.call_runtime_config (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into papi_private.call_runtime_config(singleton,enabled) values(true,false);
alter table papi_private.call_runtime_config enable row level security;
revoke all on papi_private.call_runtime_config from public,anon,authenticated;
create function papi_private.lock_call_runtime() returns void language sql volatile security definer set search_path = '' as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('papi-call-runtime',0));
$$;
revoke all on function papi_private.lock_call_runtime() from public,anon,authenticated;
create function papi_private.set_call_runtime(p_enabled boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_enabled is null then raise exception 'Service authorization required'; end if;
  perform papi_private.lock_call_runtime();
  update papi_private.call_runtime_config set enabled=p_enabled where singleton;
  if not p_enabled then update public.coffee_calls set status='ended' where status in ('pending','accepted'); end if;
  return true;
end;
$$;
revoke all on function papi_private.set_call_runtime(boolean) from public,anon,authenticated;
grant execute on function papi_private.set_call_runtime(boolean) to service_role;
create function public.set_call_runtime(p_enabled boolean) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.set_call_runtime(p_enabled); $$;
revoke all on function public.set_call_runtime(boolean) from public,anon,authenticated;
grant execute on function public.set_call_runtime(boolean) to service_role;
