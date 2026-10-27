-- Read under the caller's RLS; timestamps and UUIDs together form a stable cursor.
create function public.coffee_comment_page(p_post uuid,p_before_time timestamptz default null,p_before_id uuid default null)
returns setof public.coffee_comments language sql stable security invoker set search_path = '' as $$
  select c.* from public.coffee_comments c where c.post_id=p_post and (select auth.uid()) is not null
    and ((p_before_time is null and p_before_id is null)
      or (p_before_time is not null and p_before_id is not null and (c.created_at,c.id)<(p_before_time,p_before_id)))
  order by c.created_at desc,c.id desc limit 100;
$$;
revoke all on function public.coffee_comment_page(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.coffee_comment_page(uuid,timestamptz,uuid) to authenticated;

create function public.coffee_profile_image_page(p_owner uuid,p_before_time timestamptz default null,p_before_id uuid default null)
returns setof public.coffee_profile_images language sql stable security invoker set search_path = '' as $$
  select i.* from public.coffee_profile_images i where i.owner_id=p_owner and (select auth.uid()) is not null
    and ((p_before_time is null and p_before_id is null)
      or (p_before_time is not null and p_before_id is not null and (i.created_at,i.id)<(p_before_time,p_before_id)))
  order by i.created_at desc,i.id desc limit 100;
$$;
revoke all on function public.coffee_profile_image_page(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.coffee_profile_image_page(uuid,timestamptz,uuid) to authenticated;
create index coffee_comments_page_idx on public.coffee_comments(post_id,created_at desc,id desc);
create index coffee_profile_images_page_idx on public.coffee_profile_images(owner_id,created_at desc,id desc);
