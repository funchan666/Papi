-- Curated topics are not participant counts or claims of an active room.
create table public.coffee_voice_topics (
  id text primary key,
  title text not null,
  category text not null,
  enabled boolean not null default true,
  sort_order integer not null unique,
  check (id ~ '^room-[a-z]+$')
);
alter table public.coffee_voice_topics enable row level security;
revoke all on public.coffee_voice_topics from public,anon,authenticated;
grant select on public.coffee_voice_topics to authenticated;
create policy voice_topics_read on public.coffee_voice_topics for select to authenticated
  using (enabled and (select auth.uid()) is not null);
insert into public.coffee_voice_topics(id,title,category,sort_order) values
 ('room-chat','Slow mornings','Coffee rituals',1),
 ('room-learn','The brewing table','Brew notes',2),
 ('room-match','Recipes over coffee','Pour over',3),
 ('room-vibe','Evening espresso','Roast notes',4),
 ('room-breeze','Window seat','Café reading',5),
 ('room-dream','Coffee daydreams','Slow coffee',6);
