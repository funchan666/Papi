-- A tombstone retains the path until Storage confirms deletion and prevents
-- a later submission from reusing a path that is being removed.
create table papi_private.removed_post_media (
  post_id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  media_path text not null,
  removed_at timestamptz not null default now(),
  unique (owner_id, media_path)
);
alter table papi_private.removed_post_media enable row level security;
revoke all on papi_private.removed_post_media from public, anon, authenticated;
create unique index coffee_posts_unique_author_media on public.coffee_posts(author_id, media_path);
revoke delete on public.coffee_posts from authenticated;

create function papi_private.remove_coffee_post(p_post_id uuid) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  path text;
begin
  if actor is null or p_post_id is null then raise exception 'Authentication required'; end if;
  select p.media_path into path from public.coffee_posts p where p.id = p_post_id and p.author_id = actor;
  if not found then
    select r.media_path into path from papi_private.removed_post_media r
      where r.post_id = p_post_id and r.owner_id = actor;
    if not found then raise exception 'Post unavailable'; end if;
    return path;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text || '/' || path, 0));
  select p.media_path into path from public.coffee_posts p where p.id = p_post_id and p.author_id = actor for update;
  if not found then
    select r.media_path into path from papi_private.removed_post_media r
      where r.post_id = p_post_id and r.owner_id = actor;
    if not found then raise exception 'Post unavailable'; end if;
    return path;
  end if;
  insert into papi_private.removed_post_media (post_id, owner_id, media_path) values (p_post_id, actor, path);
  delete from public.coffee_posts p where p.id = p_post_id and p.author_id = actor;
  return path;
end;
$$;
revoke all on function papi_private.remove_coffee_post(uuid) from public, anon;
grant execute on function papi_private.remove_coffee_post(uuid) to authenticated;

create function public.remove_coffee_post(post_id uuid) returns text
language sql security invoker set search_path = ''
as $$ select papi_private.remove_coffee_post(post_id); $$;
revoke all on function public.remove_coffee_post(uuid) from public, anon;
grant execute on function public.remove_coffee_post(uuid) to authenticated;

-- Prevent reuse while deletion and submission are concurrent.
-- Charge once and create a pending post in one transaction. Uploaded media
-- must already exist in the caller's private folder; approval remains separate.
create or replace function papi_private.submit_moment(moment_id uuid, caption text, media_path text, media_kind text)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  price bigint;
  current_balance bigint;
  previous public.coffee_posts%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if moment_id is null or caption is null or char_length(trim(caption)) not between 1 and 2000 then
    raise exception 'Invalid moment';
  end if;
  price := case media_kind when 'photo' then 40 when 'video' then 80 else null end;
  if price is null or media_path is null or split_part(media_path, '/', 1) <> actor::text then
    raise exception 'Invalid media';
  end if;
  select balance into current_balance from public.coffee_wallets where owner_id = actor for update;
  if not found then raise exception 'Wallet unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(actor::text || '/' || media_path, 0));
  if exists (select 1 from papi_private.removed_post_media r
    where r.post_id = moment_id or (r.owner_id = actor and r.media_path = submit_moment.media_path)) then
    raise exception 'Removed post or media cannot be reused';
  end if;
  select * into previous from public.coffee_posts p where p.id = moment_id;
  if found then
    if previous.author_id <> actor or previous.caption <> caption or previous.media_path <> media_path or previous.media_kind <> media_kind then
      raise exception 'Moment identifier already used';
    end if;
    return current_balance;
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id = 'coffee-media'
      and o.name = media_path and o.owner_id = actor::text) then
    raise exception 'Uploaded media unavailable';
  end if;
  if current_balance < price then raise exception 'Insufficient coins'; end if;
  update public.coffee_wallets set balance = balance - price, updated_at = now()
    where owner_id = actor returning balance into current_balance;
  insert into public.coffee_posts (id, author_id, caption, media_path, media_kind)
    values (moment_id, actor, caption, media_path, media_kind);
  insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
    values (actor, -price, 'Moment submission', 'moment-' || moment_id::text);
  return current_balance;
end;
$$;
revoke all on function papi_private.submit_moment(uuid, text, text, text) from public, anon;
grant execute on function papi_private.submit_moment(uuid, text, text, text) to authenticated;
