-- Profile artwork is published exclusively from moderated profile images.
-- The client may create its profile and edit text, but cannot set legacy media
-- paths, revision or timestamps directly.
revoke insert on public.coffee_profiles from authenticated;
revoke update (avatar_path, cover_path, updated_at) on public.coffee_profiles from authenticated;
grant insert (id, display_name, biography) on public.coffee_profiles to authenticated;

-- Supports owner lookups and cascading profile deletion as the ledger grows.
create index coffee_collectible_orders_owner_idx on public.coffee_collectible_orders(owner_id);
