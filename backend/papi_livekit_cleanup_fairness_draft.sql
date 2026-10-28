-- Deployed with the runtime switches and cleanup scheduler inactive; validate before use.
-- A failed early job must not permanently prevent later jobs from being read.
-- This rotates attempted rows; it is not an exclusive lease, so the worker
-- must remain safe when two invocations process the same job concurrently.
alter table papi_private.call_revocations add column last_attempt_at timestamptz;
alter table papi_private.voice_revocations add column last_attempt_at timestamptz;

create or replace function papi_private.pending_call_revocations()
returns table(call_id uuid,caller_id uuid,recipient_id uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Service authorization required'; end if;
  update public.coffee_calls set status='expired' where status='accepted' and expires_at<=now();
  return query with picked as (
    select q.call_id from papi_private.call_revocations q where q.completed_at is null
      order by q.last_attempt_at nulls first,q.created_at,q.call_id
      limit 20 for update skip locked
  ) update papi_private.call_revocations q set last_attempt_at=clock_timestamp()
    from picked where q.call_id=picked.call_id
    returning q.call_id,q.caller_id,q.recipient_id;
end;
$$;

create or replace function papi_private.pending_voice_revocations()
returns table(session_id uuid,owner_id uuid,topic_id text)
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Service authorization required'; end if;
  perform papi_private.lock_voice_membership();
  update papi_private.voice_members set status='closing' where status='active' and heartbeat_at<now()-interval '45 seconds';
  return query with picked as (
    select q.session_id from papi_private.voice_revocations q where q.completed_at is null
      order by q.last_attempt_at nulls first,q.created_at,q.session_id
      limit 20 for update skip locked
  ) update papi_private.voice_revocations q set last_attempt_at=clock_timestamp()
    from picked where q.session_id=picked.session_id
    returning q.session_id,q.owner_id,q.topic_id;
end;
$$;
