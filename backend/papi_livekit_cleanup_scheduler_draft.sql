-- Foundation deployed; the scheduler job is inactive. Do not enable until
-- revocation, scheduler latency, retries and permission boundaries are verified.
-- Requires pg_cron, pg_net and pgcrypto. The short-lived single-use ticket is
-- visible to database roles able to read pg_net's request queue; it grants only
-- one cleanup invocation, never the Supabase service or LiveKit credentials.

create table papi_private.cleanup_tickets (
  ticket_hash bytea primary key,
  expires_at timestamptz not null,
  consumed_at timestamptz
);
alter table papi_private.cleanup_tickets enable row level security;
revoke all on papi_private.cleanup_tickets from public,anon,authenticated;

create function papi_private.consume_coffee_cleanup_ticket(p_ticket text) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','') <> 'service_role'
     or p_ticket is null or p_ticket !~ '^[0-9a-f]{64}$' then return false; end if;
  update papi_private.cleanup_tickets set consumed_at=clock_timestamp()
    where ticket_hash=extensions.digest(p_ticket,'sha256')
      and consumed_at is null and expires_at>clock_timestamp();
  return found;
end;
$$;
revoke all on function papi_private.consume_coffee_cleanup_ticket(text) from public,anon,authenticated;
grant execute on function papi_private.consume_coffee_cleanup_ticket(text) to service_role;
create function public.consume_coffee_cleanup_ticket(p_ticket text) returns boolean
language sql security invoker set search_path = '' as $$
  select papi_private.consume_coffee_cleanup_ticket(p_ticket);
$$;
revoke all on function public.consume_coffee_cleanup_ticket(text) from public,anon,authenticated;
grant execute on function public.consume_coffee_cleanup_ticket(text) to service_role;

-- Run only as the privileged scheduler owner, never expose this through PostgREST.
create function papi_private.wake_coffee_cleanup() returns void
language plpgsql security definer set search_path = '' as $$
declare ticket text;
begin
  delete from papi_private.cleanup_tickets where expires_at < clock_timestamp()-interval '15 minutes';
  -- While either feature is enabled the worker also discovers expired sessions.
  if not coalesce((select enabled from papi_private.voice_runtime_config where singleton),false)
     and not coalesce((select enabled from papi_private.call_runtime_config where singleton),false)
     and not exists(select 1 from papi_private.voice_revocations where completed_at is null)
     and not exists(select 1 from papi_private.call_revocations where completed_at is null) then return; end if;
  ticket=encode(extensions.gen_random_bytes(32),'hex');
  insert into papi_private.cleanup_tickets(ticket_hash,expires_at)
    values(extensions.digest(ticket,'sha256'),clock_timestamp()+interval '90 seconds');
  perform net.http_post(
    url := 'https://cquoffowtjnxmgaxavym.supabase.co/functions/v1/livekit-call-cleanup',
    headers := jsonb_build_object('Content-Type','application/json','x-papi-cleanup-ticket',ticket),
    body := '{}'::jsonb,
    timeout_milliseconds := 55000
  );
end;
$$;
revoke all on function papi_private.wake_coffee_cleanup() from public,anon,authenticated,service_role;

-- The job papi-livekit-cleanup was created inactive by a separate migration.
-- After full verification, activate it as its privileged owner, not via the API.
