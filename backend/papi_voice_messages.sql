-- Room messages are visible only while the reader has an active room session.
create table papi_private.voice_messages (
  id uuid primary key,
  topic_id text not null references public.coffee_voice_topics(id),
  sender_id uuid not null references public.coffee_profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 300),
  created_at timestamptz not null default now()
);
create index voice_messages_topic_time_idx on papi_private.voice_messages(topic_id,created_at desc,id desc);
create index voice_messages_sender_time_idx on papi_private.voice_messages(sender_id,created_at desc);
alter table papi_private.voice_messages enable row level security;
revoke all on papi_private.voice_messages from public,anon,authenticated;

create function papi_private.send_voice_message(p_topic text,p_session uuid,p_id uuid,p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); previous papi_private.voice_messages%rowtype; clean text := btrim(p_body);
begin
  if actor is null or p_id is null or p_topic is null or p_session is null or clean is null
     or char_length(clean) not between 1 and 300 then raise exception 'Invalid room message'; end if;
  perform papi_private.lock_voice_membership();
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.can_join_coffee_voice(p_topic,p_session) then raise exception 'Voice room unavailable'; end if;
  select * into previous from papi_private.voice_messages where id=p_id;
  if found then
    if previous.sender_id<>actor or previous.topic_id<>p_topic or previous.body<>clean then raise exception 'Message identifier already used'; end if;
    return p_id;
  end if;
  if (select count(*) from papi_private.voice_messages m where m.sender_id=actor and m.created_at>now()-interval '10 seconds')>=5 then
    raise exception 'Please wait before sending another message';
  end if;
  if clean ~* '(buy|sell|selling)[[:space:]]+(sex|nudes)|child[[:space:]]+(porn|nudes)|underage[[:space:]]+(porn|nudes)|出售裸照|未成年色情|性交易|杀了你|卖淫' then
    raise exception 'Message not allowed';
  end if;
  insert into papi_private.voice_messages(id,topic_id,sender_id,body) values(p_id,p_topic,actor,clean);
  return p_id;
end;
$$;
revoke all on function papi_private.send_voice_message(text,uuid,uuid,text) from public,anon;
grant execute on function papi_private.send_voice_message(text,uuid,uuid,text) to authenticated;
create function public.send_coffee_voice_message(p_topic text,p_session uuid,p_id uuid,p_body text)
returns uuid language sql security invoker set search_path = '' as $$
  select papi_private.send_voice_message(p_topic,p_session,p_id,p_body);
$$;
revoke all on function public.send_coffee_voice_message(text,uuid,uuid,text) from public,anon;
grant execute on function public.send_coffee_voice_message(text,uuid,uuid,text) to authenticated;

create function papi_private.read_voice_messages(p_topic text,p_session uuid)
returns table(id uuid,sender_id uuid,body text,created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or not papi_private.can_join_coffee_voice(p_topic,p_session) then raise exception 'Voice room unavailable'; end if;
  return query select m.id,m.sender_id,m.body,m.created_at from papi_private.voice_messages m
    where m.topic_id=p_topic and m.created_at>=now()-interval '1 hour'
      and papi_private.clear_pair(actor,m.sender_id)
    order by m.created_at desc,m.id desc limit 80;
end;
$$;
revoke all on function papi_private.read_voice_messages(text,uuid) from public,anon;
grant execute on function papi_private.read_voice_messages(text,uuid) to authenticated;
create function public.coffee_voice_messages(p_topic text,p_session uuid)
returns table(id uuid,sender_id uuid,body text,created_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select * from papi_private.read_voice_messages(p_topic,p_session);
$$;
revoke all on function public.coffee_voice_messages(text,uuid) from public,anon;
grant execute on function public.coffee_voice_messages(text,uuid) to authenticated;
