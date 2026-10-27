create table public.coffee_likes (
  moment_id uuid not null references public.coffee_posts(id) on delete cascade,
  member_id uuid not null references public.coffee_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (moment_id, member_id)
);
create index coffee_likes_member_idx on public.coffee_likes(member_id);
create table public.coffee_bookmarks (
  moment_id uuid not null references public.coffee_posts(id) on delete cascade,
  member_id uuid not null references public.coffee_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (moment_id, member_id)
);
create index coffee_bookmarks_member_idx on public.coffee_bookmarks(member_id);
alter table public.coffee_likes enable row level security;
alter table public.coffee_bookmarks enable row level security;
revoke all on public.coffee_likes, public.coffee_bookmarks from public, anon, authenticated;
grant select, insert, delete on public.coffee_likes, public.coffee_bookmarks to authenticated;
create policy likes_read on public.coffee_likes for select to authenticated
  using (papi_private.clear_pair((select auth.uid()), member_id)
    and exists (select 1 from public.coffee_posts p where p.id = moment_id and p.moderation_status = 'approved'));
create policy likes_add on public.coffee_likes for insert to authenticated
  with check (member_id = (select auth.uid())
    and exists (select 1 from public.coffee_posts p where p.id = moment_id and p.moderation_status = 'approved'));
create policy likes_remove on public.coffee_likes for delete to authenticated using (member_id = (select auth.uid()));
create policy bookmarks_read on public.coffee_bookmarks for select to authenticated
  using (member_id = (select auth.uid())
    and exists (select 1 from public.coffee_posts p where p.id = moment_id and p.moderation_status = 'approved'));
create policy bookmarks_add on public.coffee_bookmarks for insert to authenticated
  with check (member_id = (select auth.uid())
    and exists (select 1 from public.coffee_posts p where p.id = moment_id and p.moderation_status = 'approved'));
create policy bookmarks_remove on public.coffee_bookmarks for delete to authenticated using (member_id = (select auth.uid()));
