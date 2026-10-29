-- Account-scoped personal state; existing device archives are not imported or removed.
create table public.coffee_displayed_gifts (
  owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,
  gift_id text references public.coffee_gift_catalog(id),
  updated_at timestamptz not null default now()
);
create table public.coffee_gift_ideas (
  id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  gift_id text not null references public.coffee_gift_catalog(id),
  quantity integer not null check (quantity between 1 and 99),
  context text not null check (char_length(context) between 1 and 128),
  created_at timestamptz not null default now()
);
create index coffee_gift_ideas_owner_created_idx on public.coffee_gift_ideas(owner_id,created_at desc,id desc);
create table public.coffee_recent_voice_rooms (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  topic_id text not null references public.coffee_voice_topics(id),
  visited_at timestamptz not null default now(),
  primary key(owner_id,topic_id)
);
create index coffee_recent_voice_rooms_owner_visited_idx on public.coffee_recent_voice_rooms(owner_id,visited_at desc,topic_id);
alter table public.coffee_displayed_gifts enable row level security;
alter table public.coffee_gift_ideas enable row level security;
alter table public.coffee_recent_voice_rooms enable row level security;
revoke all on public.coffee_displayed_gifts,public.coffee_gift_ideas,public.coffee_recent_voice_rooms from public,anon,authenticated;
grant select on public.coffee_displayed_gifts,public.coffee_gift_ideas,public.coffee_recent_voice_rooms to authenticated;
create policy coffee_displayed_gifts_own on public.coffee_displayed_gifts for select to authenticated
  using (owner_id=(select auth.uid()) and (select papi_private.coffee_actor_active()));
create policy coffee_gift_ideas_own on public.coffee_gift_ideas for select to authenticated
  using (owner_id=(select auth.uid()) and (select papi_private.coffee_actor_active()));
create policy coffee_recent_voice_rooms_own on public.coffee_recent_voice_rooms for select to authenticated
  using (owner_id=(select auth.uid()) and (select papi_private.coffee_actor_active()));

create function papi_private.set_coffee_displayed_gift(p_gift text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid()); gift text := nullif(p_gift,'');
begin
  if actor is null or p_gift is null then raise exception 'Unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
  if gift is not null and not exists(select 1 from public.coffee_collectibles where owner_id=actor and collectible_id=gift and quantity>0) then
    raise exception 'Gift is not owned';
  end if;
  insert into public.coffee_displayed_gifts(owner_id,gift_id) values(actor,gift)
  on conflict(owner_id) do update set gift_id=excluded.gift_id,updated_at=now();
  return true;
end; $$;
create function papi_private.save_coffee_gift_idea(p_id uuid,p_gift text,p_quantity integer,p_context text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_id is null or p_gift is null or p_quantity is null or p_quantity not between 1 and 99
     or p_context is null or char_length(p_context) not between 1 and 128 then raise exception 'Unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() or not exists(select 1 from public.coffee_gift_catalog where id=p_gift) then raise exception 'Unavailable'; end if;
  insert into public.coffee_gift_ideas(id,owner_id,gift_id,quantity,context) values(p_id,actor,p_gift,p_quantity,p_context)
  on conflict(id) do nothing;
  if not exists(select 1 from public.coffee_gift_ideas where id=p_id and owner_id=actor and gift_id=p_gift and quantity=p_quantity and context=p_context) then raise exception 'Unavailable'; end if;
  return true;
end; $$;
create function papi_private.record_coffee_room_visit(p_topic text) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_topic is null then raise exception 'Unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() or not exists(select 1 from public.coffee_voice_topics where id=p_topic and enabled) then raise exception 'Unavailable'; end if;
  insert into public.coffee_recent_voice_rooms(owner_id,topic_id) values(actor,p_topic)
  on conflict(owner_id,topic_id) do update set visited_at=now();
  return true;
end; $$;
revoke all on function papi_private.set_coffee_displayed_gift(text),papi_private.save_coffee_gift_idea(uuid,text,integer,text),papi_private.record_coffee_room_visit(text) from public,anon;
grant execute on function papi_private.set_coffee_displayed_gift(text),papi_private.save_coffee_gift_idea(uuid,text,integer,text),papi_private.record_coffee_room_visit(text) to authenticated;
create function public.set_coffee_displayed_gift(p_gift text) returns boolean language sql security invoker set search_path='' as $$ select papi_private.set_coffee_displayed_gift(p_gift); $$;
create function public.save_coffee_gift_idea(p_id uuid,p_gift text,p_quantity integer,p_context text) returns boolean language sql security invoker set search_path='' as $$ select papi_private.save_coffee_gift_idea(p_id,p_gift,p_quantity,p_context); $$;
create function public.record_coffee_room_visit(p_topic text) returns boolean language sql security invoker set search_path='' as $$ select papi_private.record_coffee_room_visit(p_topic); $$;
revoke all on function public.set_coffee_displayed_gift(text),public.save_coffee_gift_idea(uuid,text,integer,text),public.record_coffee_room_visit(text) from public,anon;
grant execute on function public.set_coffee_displayed_gift(text),public.save_coffee_gift_idea(uuid,text,integer,text),public.record_coffee_room_visit(text) to authenticated;
