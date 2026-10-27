-- Draft: do not deploy or enable Apple notifications until a worker, refund
-- accounting, reconciliation and operational monitoring are in place.
create table papi_private.apple_notification_inbox (
  notification_id uuid primary key,
  environment text not null check (environment in ('Sandbox', 'Production')),
  notification_type text not null,
  signed_payload text not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);
alter table papi_private.apple_notification_inbox enable row level security;
revoke all on papi_private.apple_notification_inbox from public, anon, authenticated;

create function public.queue_apple_notification(
  p_id uuid, p_environment text, p_type text, p_payload text
) returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  if p_id is null or p_environment not in ('Sandbox', 'Production')
     or p_type is null or char_length(p_type) not between 1 and 100
     or p_payload is null or char_length(p_payload) not between 1 and 131072 then
    raise exception 'Invalid notification';
  end if;
  insert into papi_private.apple_notification_inbox
    (notification_id, environment, notification_type, signed_payload)
    values (p_id, p_environment, p_type, p_payload)
    on conflict (notification_id) do nothing;
  -- Repeated delivery is accepted only when it is exactly the same event.
  if not exists (select 1 from papi_private.apple_notification_inbox n
    where n.notification_id = p_id and n.environment = p_environment
      and n.notification_type = p_type and n.signed_payload = p_payload) then
    raise exception 'Notification identifier conflict';
  end if;
  return true;
end;
$$;
revoke all on function public.queue_apple_notification(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.queue_apple_notification(uuid,text,text,text) to service_role;
