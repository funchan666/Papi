-- Read as the caller so post, reaction and comment RLS remain in force.
create function public.recent_coffee_moments(
  p_before_time timestamptz default null, p_before_id uuid default null, p_target uuid default null
)
returns table (
  id uuid, author_id uuid, caption text, media_path text, media_kind text,
  moderation_status text, created_at timestamptz,
  like_count bigint, comment_count bigint, liked boolean, bookmarked boolean
) language sql stable security invoker set search_path = ''
as $$
  select p.id, p.author_id, p.caption, p.media_path, p.media_kind,
         p.moderation_status, p.created_at,
         (select count(*) from public.coffee_likes l where l.moment_id=p.id),
         (select count(*) from public.coffee_comments c where c.post_id=p.id),
         exists(select 1 from public.coffee_likes l where l.moment_id=p.id and l.member_id=(select auth.uid())),
         exists(select 1 from public.coffee_bookmarks b where b.moment_id=p.id and b.member_id=(select auth.uid()))
    from public.coffee_posts p
   where (select auth.uid()) is not null and p.moderation_status='approved'
     and (p_target is null or p.id=p_target)
     and ((p_before_time is null and p_before_id is null)
          or (p_before_time is not null and p_before_id is not null and (p.created_at,p.id)<(p_before_time,p_before_id)))
   order by p.created_at desc, p.id desc limit 50;
$$;
revoke all on function public.recent_coffee_moments(timestamptz,uuid,uuid) from public, anon;
grant execute on function public.recent_coffee_moments(timestamptz,uuid,uuid) to authenticated;
