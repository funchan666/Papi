-- Room gifts are sent to the room, not transferred to any participant.
-- The order id serializes retries and cancellation against charging.
create table papi_private.voice_gift_orders (
  id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  topic_id text not null references public.coffee_voice_topics(id),
  session_id uuid not null,
  gift_id text not null,
  quantity integer not null check (quantity between 1 and 99),
  total integer not null check (total>0),
  status text not null check (status in ('settled','cancelled','insufficient')),
  created_at timestamptz not null default now()
);
create index voice_gift_orders_topic_time_idx on papi_private.voice_gift_orders(topic_id,created_at desc,id desc) where status='settled';
create index voice_gift_orders_owner_time_idx on papi_private.voice_gift_orders(owner_id,created_at desc);
alter table papi_private.voice_gift_orders enable row level security;
revoke all on papi_private.voice_gift_orders from public,anon,authenticated;

create function papi_private.voice_gift_price(p_gift text) returns integer
language sql immutable set search_path = '' as $$
  select case p_gift when 'love' then 80 when 'peach' then 120 when 'umbrella' then 180 when 'cake' then 260
    when 'bird' then 360 when 'headphones' then 520 when 'car' then 900 when 'crown' then 1400 else null end;
$$;
revoke all on function papi_private.voice_gift_price(text) from public,anon,authenticated;

create function papi_private.send_voice_gift(p_topic text,p_session uuid,p_order uuid,p_gift text,p_quantity integer,p_cancel boolean)
returns table(status text,balance bigint) language plpgsql security definer set search_path = '' as $$
declare actor uuid:=(select auth.uid()); price integer:=papi_private.voice_gift_price(p_gift); total_price integer;
  current_balance bigint; previous papi_private.voice_gift_orders%rowtype; next_status text;
begin
  if actor is null or p_topic is null or p_session is null or p_order is null or price is null
     or p_quantity is null or p_quantity not between 1 and 99 or p_cancel is null then raise exception 'Invalid gift'; end if;
  total_price:=price*p_quantity;
  perform papi_private.lock_voice_membership();
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() then raise exception 'Account unavailable'; end if;
  select w.balance into current_balance from public.coffee_wallets w where w.owner_id=actor for update;
  if not found then raise exception 'Wallet unavailable'; end if;
  select * into previous from papi_private.voice_gift_orders o where o.id=p_order;
  if found then
    if previous.owner_id<>actor or previous.topic_id<>p_topic or previous.session_id<>p_session or previous.gift_id<>p_gift or previous.quantity<>p_quantity then
      raise exception 'Gift identifier already used';
    end if;
    return query select previous.status,current_balance; return;
  end if;
  if p_cancel then
    if not exists(select 1 from papi_private.voice_members m where m.owner_id=actor and m.topic_id=p_topic and m.session_id=p_session)
       and not exists(select 1 from papi_private.voice_revocations r where r.owner_id=actor and r.topic_id=p_topic and r.session_id=p_session) then
      raise exception 'Voice session unavailable';
    end if;
    next_status:='cancelled';
  else
    if not papi_private.can_join_coffee_voice(p_topic,p_session) then raise exception 'Voice room unavailable'; end if;
    if (select count(*) from papi_private.voice_gift_orders o where o.owner_id=actor and o.created_at>now()-interval '10 seconds')>=5 then
      raise exception 'Please wait before sending another gift';
    end if;
    if current_balance<total_price then next_status:='insufficient'; else next_status:='settled'; end if;
  end if;
  insert into papi_private.voice_gift_orders(id,owner_id,topic_id,session_id,gift_id,quantity,total,status)
    values(p_order,actor,p_topic,p_session,p_gift,p_quantity,total_price,next_status);
  if next_status='settled' then
    update public.coffee_wallets w set balance=w.balance-total_price,updated_at=now() where w.owner_id=actor returning w.balance into current_balance;
    insert into public.coffee_wallet_movements(owner_id,delta,reason,idempotency_key)
      values(actor,-total_price,'Voice room gift','voice-gift-'||p_order::text);
  end if;
  return query select next_status,current_balance;
end;
$$;
revoke all on function papi_private.send_voice_gift(text,uuid,uuid,text,integer,boolean) from public,anon;
grant execute on function papi_private.send_voice_gift(text,uuid,uuid,text,integer,boolean) to authenticated;
create function public.send_coffee_voice_gift(p_topic text,p_session uuid,p_order uuid,p_gift text,p_quantity integer,p_cancel boolean default false)
returns table(status text,balance bigint) language sql security invoker set search_path='' as $$
  select * from papi_private.send_voice_gift(p_topic,p_session,p_order,p_gift,p_quantity,p_cancel);
$$;
revoke all on function public.send_coffee_voice_gift(text,uuid,uuid,text,integer,boolean) from public,anon;
grant execute on function public.send_coffee_voice_gift(text,uuid,uuid,text,integer,boolean) to authenticated;

create function papi_private.read_voice_gifts(p_topic text,p_session uuid)
returns table(id uuid,sender_id uuid,gift_id text,quantity integer,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
  if actor is null or not papi_private.can_join_coffee_voice(p_topic,p_session) then raise exception 'Voice room unavailable'; end if;
  return query select o.id,o.owner_id,o.gift_id,o.quantity,o.created_at from papi_private.voice_gift_orders o
    where o.topic_id=p_topic and o.status='settled' and o.created_at>=now()-interval '1 hour'
      and papi_private.clear_pair(actor,o.owner_id)
    order by o.created_at desc,o.id desc limit 40;
end;
$$;
revoke all on function papi_private.read_voice_gifts(text,uuid) from public,anon;
grant execute on function papi_private.read_voice_gifts(text,uuid) to authenticated;
create function public.coffee_voice_gifts(p_topic text,p_session uuid)
returns table(id uuid,sender_id uuid,gift_id text,quantity integer,created_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from papi_private.read_voice_gifts(p_topic,p_session); $$;
revoke all on function public.coffee_voice_gifts(text,uuid) from public,anon;
grant execute on function public.coffee_voice_gifts(text,uuid) to authenticated;
