-- Submission must be enabled only through a server-side operation that charges
-- the correct wallet atomically and places the post in the moderation queue.
revoke insert on public.coffee_posts from authenticated;
