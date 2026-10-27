create index coffee_messages_sender_conversation_idx on public.coffee_messages(sender_id,recipient_id,created_at desc,id desc);
create index coffee_messages_recipient_conversation_idx on public.coffee_messages(recipient_id,sender_id,created_at desc,id desc);

-- Both functions run under the caller's message RLS; no service role is used.
create function public.coffee_message_inbox() returns setof public.coffee_messages
language sql stable security invoker set search_path = '' as $$
  select recent.* from (
    select distinct on (case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end) m.*
      from public.coffee_messages m
     where (select auth.uid()) in (m.sender_id,m.recipient_id)
     order by case when m.sender_id=(select auth.uid()) then m.recipient_id else m.sender_id end,
              m.created_at desc,m.id desc
  ) recent order by recent.created_at desc,recent.id desc limit 1000;
$$;
revoke all on function public.coffee_message_inbox() from public,anon;
grant execute on function public.coffee_message_inbox() to authenticated;

create function public.coffee_conversation_page(p_peer uuid,p_before_time timestamptz default null,p_before_id uuid default null)
returns setof public.coffee_messages language sql stable security invoker set search_path = '' as $$
  select m.* from public.coffee_messages m
   where (select auth.uid()) is not null and p_peer is not null
     and ((m.sender_id=(select auth.uid()) and m.recipient_id=p_peer)
       or (m.sender_id=p_peer and m.recipient_id=(select auth.uid())))
     and ((p_before_time is null and p_before_id is null)
       or (p_before_time is not null and p_before_id is not null and (m.created_at,m.id)<(p_before_time,p_before_id)))
   order by m.created_at desc,m.id desc limit 100;
$$;
revoke all on function public.coffee_conversation_page(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.coffee_conversation_page(uuid,timestamptz,uuid) to authenticated;
