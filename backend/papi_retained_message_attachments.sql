-- Preserve a manifest of sender-owned files whose message row disappears
-- during a recipient's account deletion. This never deletes Storage objects.
create table papi_private.retained_message_attachments (
  deletion_id uuid not null references papi_private.account_deletions(id),
  message_id uuid not null,
  sender_id uuid not null,
  media_path text not null,
  media_kind text not null check (media_kind in ('photo','voice')),
  recorded_at timestamptz not null default now(),
  primary key(deletion_id,message_id,media_path)
);
alter table papi_private.retained_message_attachments enable row level security;
revoke all on papi_private.retained_message_attachments from public,anon,authenticated;

create function papi_private.retain_deleted_recipient_attachment() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.media_path is not null and old.kind in ('photo','voice') and old.sender_id<>old.recipient_id then
    insert into papi_private.retained_message_attachments(deletion_id,message_id,sender_id,media_path,media_kind)
      select d.id,old.id,old.sender_id,old.media_path,old.kind
      from papi_private.account_deletions d where d.owner_id=old.recipient_id and d.state='requested'
      on conflict(deletion_id,message_id,media_path) do nothing;
  end if;
  return old;
end;
$$;
revoke all on function papi_private.retain_deleted_recipient_attachment() from public,anon,authenticated;
create trigger coffee_retain_recipient_attachment before delete on public.coffee_messages
  for each row execute function papi_private.retain_deleted_recipient_attachment();
