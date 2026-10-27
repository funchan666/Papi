-- Durable cleanup survives retries and profile deletion. The worker is not
-- enabled until its credentials, scheduling and LiveKit behavior are verified.
create table papi_private.call_revocations (
  call_id uuid primary key,
  caller_id uuid not null,
  recipient_id uuid not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table papi_private.call_revocations enable row level security;
revoke all on papi_private.call_revocations from public,anon,authenticated;
create index call_revocations_pending_idx on papi_private.call_revocations(created_at,call_id) where completed_at is null;

create function papi_private.queue_call_revocation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.status='accepted' and (tg_op='DELETE' or new.status<>'accepted') then
    insert into papi_private.call_revocations(call_id,caller_id,recipient_id)
      values(old.id,old.caller_id,old.recipient_id) on conflict(call_id) do nothing;
  end if;
  return null;
end;
$$;
revoke all on function papi_private.queue_call_revocation() from public,anon,authenticated;
create trigger coffee_call_revocation_update after update of status on public.coffee_calls
  for each row execute function papi_private.queue_call_revocation();
create trigger coffee_call_revocation_delete after delete on public.coffee_calls
  for each row execute function papi_private.queue_call_revocation();

create function papi_private.pending_call_revocations()
returns table(call_id uuid,caller_id uuid,recipient_id uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Service authorization required'; end if;
  update public.coffee_calls set status='expired' where status='accepted' and expires_at<=now();
  return query select q.call_id,q.caller_id,q.recipient_id from papi_private.call_revocations q
    where q.completed_at is null order by q.created_at,q.call_id limit 20;
end;
$$;
revoke all on function papi_private.pending_call_revocations() from public,anon,authenticated;
grant execute on function papi_private.pending_call_revocations() to service_role;
create function public.pending_call_revocations()
returns table(call_id uuid,caller_id uuid,recipient_id uuid)
language sql security invoker set search_path = '' as $$ select * from papi_private.pending_call_revocations(); $$;
revoke all on function public.pending_call_revocations() from public,anon,authenticated;
grant execute on function public.pending_call_revocations() to service_role;

create function papi_private.complete_call_revocation(p_call uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_call is null then raise exception 'Service authorization required'; end if;
  update papi_private.call_revocations set completed_at=coalesce(completed_at,now()) where call_id=p_call;
  return found;
end;
$$;
revoke all on function papi_private.complete_call_revocation(uuid) from public,anon,authenticated;
grant execute on function papi_private.complete_call_revocation(uuid) to service_role;
create function public.complete_call_revocation(p_call uuid) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.complete_call_revocation(p_call); $$;
revoke all on function public.complete_call_revocation(uuid) from public,anon,authenticated;
grant execute on function public.complete_call_revocation(uuid) to service_role;
