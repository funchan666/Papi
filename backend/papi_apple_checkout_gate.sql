-- Intentionally disabled until Apple configuration and payment recovery are ready.
-- The client must not accept payment solely because a product exists at Apple.
create table papi_private.apple_checkout_runtime (
  singleton boolean primary key default true check (singleton),
  enabled boolean not null default false
);
insert into papi_private.apple_checkout_runtime(singleton,enabled) values(true,false);
alter table papi_private.apple_checkout_runtime enable row level security;
revoke all on papi_private.apple_checkout_runtime from public,anon,authenticated;

create function public.coffee_checkout_ready() returns boolean
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not papi_private.coffee_actor_active() then return false; end if;
  return coalesce((select r.enabled from papi_private.apple_checkout_runtime r where r.singleton),false);
end; $$;
revoke all on function public.coffee_checkout_ready() from public,anon;
grant execute on function public.coffee_checkout_ready() to authenticated;
