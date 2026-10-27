-- Only approved files belonging to profiles visible to the caller are returned.
create function public.coffee_profile_image_summary(p_members uuid[])
returns table (owner_id uuid,avatar_path text,cover_path text)
language sql stable security invoker set search_path = ''
as $$
  select p.id,
    (select i.media_path from public.coffee_profile_images i where i.owner_id=p.id and i.kind='avatar' and i.moderation_status='approved' order by i.created_at desc,i.id desc limit 1),
    (select i.media_path from public.coffee_profile_images i where i.owner_id=p.id and i.kind='cover' and i.moderation_status='approved' order by i.created_at desc,i.id desc limit 1)
  from public.coffee_profiles p
  where p.id=any(p_members) and (select auth.uid()) is not null;
$$;
revoke all on function public.coffee_profile_image_summary(uuid[]) from public,anon;
grant execute on function public.coffee_profile_image_summary(uuid[]) to authenticated;
