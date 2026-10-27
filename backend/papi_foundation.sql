-- Papi community foundation. Server-owned moderation and money operations are
-- deliberately not exposed as client writes.
create schema if not exists papi_private;
revoke all on schema papi_private from public, anon, authenticated;
grant usage on schema papi_private to authenticated;

create table public.coffee_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  biography text not null default '' check (char_length(biography) <= 2000),
  avatar_path text,
  cover_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.coffee_blocks (
  blocker_id uuid not null references public.coffee_profiles(id) on delete cascade,
  blocked_id uuid not null references public.coffee_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index coffee_blocks_target_idx on public.coffee_blocks(blocked_id, blocker_id);

-- Only a participant may ask whether this pair is blocked. The private schema
-- prevents direct Data API exposure; the function itself checks the caller.
create function papi_private.clear_pair(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select auth.uid()) in (a, b)
    and not exists (select 1 from public.coffee_blocks
      where (blocker_id = a and blocked_id = b)
         or (blocker_id = b and blocked_id = a));
$$;
revoke all on function papi_private.clear_pair(uuid, uuid) from public, anon;
grant execute on function papi_private.clear_pair(uuid, uuid) to authenticated;

create table public.coffee_follows (
  follower_id uuid not null references public.coffee_profiles(id) on delete cascade,
  followed_id uuid not null references public.coffee_profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  check (follower_id <> followed_id)
);
create index coffee_follows_followed_idx on public.coffee_follows(followed_id, follower_id);

create function papi_private.mutual_follow(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = ''
as $$
  select papi_private.clear_pair(a, b)
    and exists (select 1 from public.coffee_follows where follower_id = a and followed_id = b)
    and exists (select 1 from public.coffee_follows where follower_id = b and followed_id = a);
$$;
revoke all on function papi_private.mutual_follow(uuid, uuid) from public, anon;
grant execute on function papi_private.mutual_follow(uuid, uuid) to authenticated;

create table public.coffee_friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.coffee_profiles(id) on delete cascade,
  recipient_id uuid not null references public.coffee_profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  check (requester_id <> recipient_id),
  unique (requester_id, recipient_id)
);
create index coffee_requests_recipient_idx on public.coffee_friend_requests(recipient_id, created_at desc);

create table public.coffee_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.coffee_profiles(id) on delete cascade,
  recipient_id uuid not null references public.coffee_profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  check (sender_id <> recipient_id)
);
create index coffee_messages_sender_idx on public.coffee_messages(sender_id, created_at desc);
create index coffee_messages_recipient_idx on public.coffee_messages(recipient_id, created_at desc);

create table public.coffee_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.coffee_profiles(id) on delete cascade,
  caption text not null check (char_length(trim(caption)) between 1 and 2000),
  media_path text not null,
  media_kind text not null check (media_kind in ('photo', 'video')),
  moderation_status text not null default 'pending' check (moderation_status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);
create index coffee_posts_author_idx on public.coffee_posts(author_id, created_at desc);
create index coffee_posts_approved_idx on public.coffee_posts(created_at desc) where moderation_status = 'approved';

create table public.coffee_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.coffee_posts(id) on delete cascade,
  author_id uuid not null references public.coffee_profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  moderation_status text not null default 'pending' check (moderation_status in ('pending', 'approved', 'rejected')),
  created_at timestamptz not null default now()
);
create index coffee_comments_post_idx on public.coffee_comments(post_id, created_at);
create index coffee_comments_author_idx on public.coffee_comments(author_id);

create table public.coffee_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.coffee_profiles(id) on delete cascade,
  subject_kind text not null check (subject_kind in ('profile', 'post', 'comment', 'message')),
  subject_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index coffee_reports_reporter_idx on public.coffee_reports(reporter_id, created_at desc);

alter table public.coffee_profiles enable row level security;
alter table public.coffee_blocks enable row level security;
alter table public.coffee_follows enable row level security;
alter table public.coffee_friend_requests enable row level security;
alter table public.coffee_messages enable row level security;
alter table public.coffee_posts enable row level security;
alter table public.coffee_comments enable row level security;
alter table public.coffee_reports enable row level security;

revoke all on public.coffee_profiles, public.coffee_blocks, public.coffee_follows,
  public.coffee_friend_requests, public.coffee_messages, public.coffee_posts,
  public.coffee_comments, public.coffee_reports from public, anon, authenticated;
grant select, insert on public.coffee_profiles to authenticated;
grant update (display_name, biography, avatar_path, cover_path, updated_at) on public.coffee_profiles to authenticated;
grant select, insert, delete on public.coffee_blocks, public.coffee_follows to authenticated;
grant select, delete on public.coffee_friend_requests to authenticated;
grant insert (id, requester_id, recipient_id) on public.coffee_friend_requests to authenticated;
grant update (status) on public.coffee_friend_requests to authenticated;
grant select on public.coffee_messages to authenticated;
grant insert (id, sender_id, recipient_id, body) on public.coffee_messages to authenticated;
grant select, delete on public.coffee_posts, public.coffee_comments to authenticated;
grant insert (id, author_id, caption, media_path, media_kind) on public.coffee_posts to authenticated;
grant insert (id, post_id, author_id, body) on public.coffee_comments to authenticated;
grant select on public.coffee_reports to authenticated;
grant insert (id, reporter_id, subject_kind, subject_id, reason) on public.coffee_reports to authenticated;

create policy profile_read on public.coffee_profiles for select to authenticated
  using ((id = (select auth.uid()) or papi_private.clear_pair((select auth.uid()), id))
    and not exists (select 1 from public.coffee_reports r where r.reporter_id = (select auth.uid())
      and r.subject_kind = 'profile' and r.subject_id = coffee_profiles.id));
create policy profile_create on public.coffee_profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profile_change on public.coffee_profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy blocks_read on public.coffee_blocks for select to authenticated using (blocker_id = (select auth.uid()));
create policy blocks_create on public.coffee_blocks for insert to authenticated with check (blocker_id = (select auth.uid()));
create policy blocks_delete on public.coffee_blocks for delete to authenticated using (blocker_id = (select auth.uid()));
create policy follows_read on public.coffee_follows for select to authenticated
  using (((select auth.uid()) in (follower_id, followed_id)) and papi_private.clear_pair(follower_id, followed_id));
create policy follows_create on public.coffee_follows for insert to authenticated
  with check (follower_id = (select auth.uid()) and papi_private.clear_pair(follower_id, followed_id));
create policy follows_delete on public.coffee_follows for delete to authenticated using (follower_id = (select auth.uid()));
create policy requests_read on public.coffee_friend_requests for select to authenticated
  using ((select auth.uid()) in (requester_id, recipient_id) and papi_private.clear_pair(requester_id, recipient_id));
create policy requests_create on public.coffee_friend_requests for insert to authenticated
  with check (requester_id = (select auth.uid()) and status = 'pending' and papi_private.clear_pair(requester_id, recipient_id));
create policy requests_answer on public.coffee_friend_requests for update to authenticated
  using (recipient_id = (select auth.uid()) and status = 'pending' and papi_private.clear_pair(requester_id, recipient_id))
  with check (recipient_id = (select auth.uid()) and status in ('accepted', 'declined') and papi_private.clear_pair(requester_id, recipient_id));
create policy requests_delete on public.coffee_friend_requests for delete to authenticated
  using ((select auth.uid()) in (requester_id, recipient_id));
create policy messages_read on public.coffee_messages for select to authenticated
  using ((select auth.uid()) in (sender_id, recipient_id) and papi_private.clear_pair(sender_id, recipient_id)
    and not exists (select 1 from public.coffee_reports r where r.reporter_id = (select auth.uid())
      and r.subject_kind = 'message' and r.subject_id = coffee_messages.id));
create policy messages_send on public.coffee_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and papi_private.mutual_follow(sender_id, recipient_id));
create policy posts_read on public.coffee_posts for select to authenticated
  using ((author_id = (select auth.uid()) or (moderation_status = 'approved' and papi_private.clear_pair((select auth.uid()), author_id)))
    and not exists (select 1 from public.coffee_reports r where r.reporter_id = (select auth.uid()) and r.subject_kind = 'post' and r.subject_id = coffee_posts.id));
create policy posts_create on public.coffee_posts for insert to authenticated with check (author_id = (select auth.uid()) and moderation_status = 'pending');
create policy posts_delete on public.coffee_posts for delete to authenticated using (author_id = (select auth.uid()));
create policy comments_read on public.coffee_comments for select to authenticated
  using ((author_id = (select auth.uid()) or (moderation_status = 'approved' and papi_private.clear_pair((select auth.uid()), author_id)))
    and exists (select 1 from public.coffee_posts p where p.id = post_id)
    and not exists (select 1 from public.coffee_reports r where r.reporter_id = (select auth.uid()) and r.subject_kind = 'comment' and r.subject_id = coffee_comments.id));
create policy comments_create on public.coffee_comments for insert to authenticated
  with check (author_id = (select auth.uid()) and moderation_status = 'pending'
    and exists (select 1 from public.coffee_posts p where p.id = post_id and p.moderation_status = 'approved'));
create policy comments_delete on public.coffee_comments for delete to authenticated using (author_id = (select auth.uid()));
create policy reports_read on public.coffee_reports for select to authenticated using (reporter_id = (select auth.uid()));
create policy reports_create on public.coffee_reports for insert to authenticated with check (reporter_id = (select auth.uid()));
