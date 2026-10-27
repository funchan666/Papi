-- Column-level privileges must be revoked separately from table-level grants.
revoke insert (id, author_id, caption, media_path, media_kind)
  on public.coffee_posts from authenticated;
