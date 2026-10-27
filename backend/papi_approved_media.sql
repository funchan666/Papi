-- Read only media belonging to an approved post that the caller may see.
-- Pending uploads remain visible solely to their owner and moderators.
create policy coffee_media_read_approved on storage.objects for select to authenticated
  using (bucket_id = 'coffee-media' and exists (
    select 1 from public.coffee_posts p
    where p.media_path = objects.name and p.moderation_status = 'approved'
  ));
