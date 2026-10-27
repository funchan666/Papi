-- A block ends existing follows and friendship requests in both directions.
-- Unblocking must never restore an earlier relationship automatically.
create function papi_private.end_blocked_relationships() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.coffee_follows
    where (follower_id = new.blocker_id and followed_id = new.blocked_id)
       or (follower_id = new.blocked_id and followed_id = new.blocker_id);
  delete from public.coffee_friend_requests
    where (requester_id = new.blocker_id and recipient_id = new.blocked_id)
       or (requester_id = new.blocked_id and recipient_id = new.blocker_id);
  return new;
end;
$$;
revoke all on function papi_private.end_blocked_relationships() from public, anon, authenticated;
create trigger coffee_block_ends_relationships
  after insert on public.coffee_blocks
  for each row execute function papi_private.end_blocked_relationships();
