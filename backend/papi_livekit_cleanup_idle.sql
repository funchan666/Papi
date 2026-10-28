-- Avoid waking the hosted worker while there is no expired session or queued removal.
-- The scheduler still ticks so newly expired sessions are discovered promptly.
create index if not exists coffee_calls_accepted_expiry_idx
  on public.coffee_calls(expires_at) where status='accepted';
create index if not exists voice_members_active_heartbeat_idx
  on papi_private.voice_members(heartbeat_at) where status='active';

create or replace function papi_private.wake_coffee_cleanup() returns void
language plpgsql security definer set search_path = '' as $$
declare ticket text;
begin
  delete from papi_private.cleanup_tickets where expires_at < clock_timestamp()-interval '15 minutes';
  if not exists(select 1 from papi_private.voice_revocations where completed_at is null)
     and not exists(select 1 from papi_private.call_revocations where completed_at is null)
     and not exists(select 1 from papi_private.voice_members where status='active' and heartbeat_at<now()-interval '45 seconds')
     and not exists(select 1 from public.coffee_calls where status='accepted' and expires_at<=now()) then return; end if;
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
