-- A server-side gate prevents direct room entry while the worker and app are
-- not ready. Service operators can enable it only with the coordinated rollout.
create table papi_private.voice_runtime_config (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into papi_private.voice_runtime_config(singleton,enabled) values(true,false);
alter table papi_private.voice_runtime_config enable row level security;
revoke all on papi_private.voice_runtime_config from public,anon,authenticated;
create function papi_private.set_voice_runtime(p_enabled boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_enabled is null then raise exception 'Service authorization required'; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_runtime_config set enabled=p_enabled where singleton;
  if not p_enabled then update papi_private.voice_members set status='closing' where status='active'; end if;
  return true;
end;
$$;
revoke all on function papi_private.set_voice_runtime(boolean) from public,anon,authenticated;
grant execute on function papi_private.set_voice_runtime(boolean) to service_role;
create function public.set_voice_runtime(p_enabled boolean) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.set_voice_runtime(p_enabled); $$;
revoke all on function public.set_voice_runtime(boolean) from public,anon,authenticated;
grant execute on function public.set_voice_runtime(boolean) to service_role;
