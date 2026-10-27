alter table public.coffee_messages add column kind text not null default 'text' check (kind in ('text','photo','voice'));
alter table public.coffee_messages add column media_path text unique;
alter table public.coffee_messages add constraint coffee_message_attachment_shape check (
  (kind='text' and media_path is null) or (kind in ('photo','voice') and media_path is not null)
);

create or replace function papi_private.send_coffee_message(p_id uuid,p_recipient uuid,p_body text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); previous public.coffee_messages%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_id is null or p_recipient is null or p_recipient=actor or p_body is null or
     char_length(trim(p_body)) not between 1 and 2000 then raise exception 'Invalid message'; end if;
  perform papi_private.lock_social_pair(actor,p_recipient);
  select * into previous from public.coffee_messages m where m.id=p_id;
  if found then
    if previous.sender_id<>actor or previous.recipient_id<>p_recipient or previous.body<>p_body or previous.kind<>'text' then
      raise exception 'Message identifier already used';
    end if;
    return true;
  end if;
  if not papi_private.mutual_follow(actor,p_recipient) then raise exception 'Mutual following required'; end if;
  insert into public.coffee_messages(id,sender_id,recipient_id,body) values(p_id,actor,p_recipient,p_body);
  return true;
end;
$$;

create function papi_private.send_coffee_attachment(p_id uuid,p_recipient uuid,p_kind text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); path text; previous public.coffee_messages%rowtype; label text;
begin
  if actor is null or p_id is null or p_recipient is null or p_recipient=actor
     or p_kind not in ('photo','voice') then raise exception 'Invalid attachment'; end if;
  path := actor::text || '/message-' || p_id::text || case p_kind when 'photo' then '.jpg' else '.m4a' end;
  label := case p_kind when 'photo' then 'Photo' else 'Voice' end;
  perform papi_private.lock_social_pair(actor,p_recipient);
  select * into previous from public.coffee_messages m where m.id=p_id;
  if found then
    if previous.sender_id<>actor or previous.recipient_id<>p_recipient or previous.kind<>p_kind or previous.media_path<>path then
      raise exception 'Message identifier already used';
    end if;
    return true;
  end if;
  if not papi_private.mutual_follow(actor,p_recipient) then raise exception 'Mutual following required'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id='coffee-media' and o.name=path and o.owner_id=actor::text) then
    raise exception 'Uploaded attachment unavailable';
  end if;
  insert into public.coffee_messages(id,sender_id,recipient_id,body,kind,media_path)
    values(p_id,actor,p_recipient,label,p_kind,path);
  return true;
end;
$$;
revoke all on function papi_private.send_coffee_attachment(uuid,uuid,text) from public,anon;
grant execute on function papi_private.send_coffee_attachment(uuid,uuid,text) to authenticated;
create function public.send_coffee_attachment(p_id uuid,p_recipient uuid,p_kind text) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.send_coffee_attachment(p_id,p_recipient,p_kind); $$;
revoke all on function public.send_coffee_attachment(uuid,uuid,text) from public,anon;
grant execute on function public.send_coffee_attachment(uuid,uuid,text) to authenticated;

-- The message RLS policy checks recipient membership, blocks and reports.
create policy coffee_media_read_message_attachment on storage.objects for select to authenticated
  using (bucket_id='coffee-media' and exists (
    select 1 from public.coffee_messages m where m.media_path=objects.name and m.kind in ('photo','voice')
  ));
