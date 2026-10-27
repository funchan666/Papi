-- The private coffee-media bucket is provisioned through the Storage API.
-- Uploads remain private until moderation and media delivery are ready.

create policy coffee_media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'coffee-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy coffee_media_read_owner on storage.objects for select to authenticated
  using (bucket_id = 'coffee-media' and owner_id = (select auth.uid())::text
         and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy coffee_media_delete_owner on storage.objects for delete to authenticated
  using (bucket_id = 'coffee-media' and owner_id = (select auth.uid())::text
         and (storage.foldername(name))[1] = (select auth.uid())::text);
