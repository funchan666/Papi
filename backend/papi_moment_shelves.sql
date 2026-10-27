-- Profile and saved shelves page independently of the public feed, under RLS.
create function public.coffee_moment_shelf(
  p_author uuid default null, p_saved boolean default false,
  p_before_time timestamptz default null, p_before_id uuid default null
) returns table (
  id uuid, author_id uuid, caption text, media_path text, media_kind text,
  moderation_status text, created_at timestamptz,
  like_count bigint, comment_count bigint, liked boolean, bookmarked boolean
) language sql stable security invoker set search_path = '' as $$
  select p.id,p.author_id,p.caption,p.media_path,p.media_kind,p.moderation_status,p.created_at,
    (select count(*) from public.coffee_likes l where l.moment_id=p.id),
    (select count(*) from public.coffee_comments c where c.post_id=p.id),
    exists(select 1 from public.coffee_likes l where l.moment_id=p.id and l.member_id=(select auth.uid())),
    exists(select 1 from public.coffee_bookmarks b where b.moment_id=p.id and b.member_id=(select auth.uid()))
  from public.coffee_posts p
  where (select auth.uid()) is not null and p.moderation_status='approved'
    and ((p_saved and p_author is null and exists(select 1 from public.coffee_bookmarks b
           where b.moment_id=p.id and b.member_id=(select auth.uid())))
      or (not p_saved and p_author is not null and p.author_id=p_author))
    and ((p_before_time is null and p_before_id is null)
      or (p_before_time is not null and p_before_id is not null and (p.created_at,p.id)<(p_before_time,p_before_id)))
  order by p.created_at desc,p.id desc limit 50;
$$;
revoke all on function public.coffee_moment_shelf(uuid,boolean,timestamptz,uuid) from public,anon;
grant execute on function public.coffee_moment_shelf(uuid,boolean,timestamptz,uuid) to authenticated;
create index coffee_posts_author_page_idx on public.coffee_posts(author_id,created_at desc,id desc)
  where moderation_status='approved';
