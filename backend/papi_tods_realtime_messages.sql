-- Private per-account invalidations contain no message content or peer identity.
create policy papi_message_events_read on realtime.messages
for select to authenticated
using (
  extension = 'broadcast'
  and (select auth.uid()) is not null
  and (select realtime.topic()) = 'papi-messages:' || (select auth.uid())::text
);

create function papi_private.notify_coffee_message() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform realtime.send('{}'::jsonb, 'message_changed', 'papi-messages:' || new.sender_id::text, true);
  perform realtime.send('{}'::jsonb, 'message_changed', 'papi-messages:' || new.recipient_id::text, true);
  return new;
end;
$$;
revoke all on function papi_private.notify_coffee_message() from public, anon, authenticated;

create trigger coffee_message_realtime_notice
after insert on public.coffee_messages
for each row execute function papi_private.notify_coffee_message();
