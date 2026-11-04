-- Records quota use without storing questions or answers.
create table papi_private.coffee_ai_requests (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index coffee_ai_requests_owner_time_idx on papi_private.coffee_ai_requests(owner_id,created_at);
create index coffee_ai_requests_time_idx on papi_private.coffee_ai_requests(created_at);
revoke all on papi_private.coffee_ai_requests from public, anon, authenticated;

create function public.reserve_coffee_ai_request(p_id uuid,p_owner uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if p_id is null or p_owner is null then return false; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('papi-ai-quota',0));
  if exists(select 1 from papi_private.coffee_ai_requests where id=p_id)
     or (select count(*) from papi_private.coffee_ai_requests
         where owner_id=p_owner and created_at>now()-interval '1 minute') >= 3
     or (select count(*) from papi_private.coffee_ai_requests
         where owner_id=p_owner and created_at>now()-interval '1 day') >= 40
     or (select count(*) from papi_private.coffee_ai_requests
         where created_at>now()-interval '1 day') >= 1000 then return false; end if;
  insert into papi_private.coffee_ai_requests(id,owner_id) values(p_id,p_owner);
  return true;
end;
$$;
revoke all on function public.reserve_coffee_ai_request(uuid,uuid) from public, anon, authenticated;
grant execute on function public.reserve_coffee_ai_request(uuid,uuid) to service_role;
