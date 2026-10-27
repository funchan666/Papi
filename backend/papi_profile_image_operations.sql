-- A removed image identifier may never be submitted again. Both submission
-- and removal lock the same path before changing metadata.
create table papi_private.removed_profile_media (
  image_id uuid primary key,
  owner_id uuid not null,
  media_path text not null unique,
  removed_at timestamptz not null default now()
);
alter table papi_private.removed_profile_media enable row level security;
revoke all on papi_private.removed_profile_media from public,anon,authenticated;
revoke insert (id,owner_id,kind,media_path) on public.coffee_profile_images from authenticated;

create function papi_private.submit_profile_image(p_id uuid,p_kind text) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); path text; previous public.coffee_profile_images%rowtype;
begin
  if actor is null or p_id is null or p_kind not in ('avatar','cover','album') then raise exception 'Invalid image'; end if;
  path := actor::text || '/profile-' || p_id::text || '.jpg';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(path,0));
  if exists (select 1 from papi_private.removed_profile_media r where r.image_id=p_id or r.media_path=path) then
    raise exception 'Removed image cannot be reused';
  end if;
  select * into previous from public.coffee_profile_images i where i.id=p_id;
  if found then
    if previous.owner_id<>actor or previous.kind<>p_kind or previous.media_path<>path then raise exception 'Image identifier already used'; end if;
    return true;
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id='coffee-media' and o.name=path and o.owner_id=actor::text) then
    raise exception 'Uploaded image unavailable';
  end if;
  insert into public.coffee_profile_images(id,owner_id,kind,media_path) values(p_id,actor,p_kind,path);
  return true;
end;
$$;
revoke all on function papi_private.submit_profile_image(uuid,text) from public,anon;
grant execute on function papi_private.submit_profile_image(uuid,text) to authenticated;
create function public.submit_coffee_profile_image(p_id uuid,p_kind text) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.submit_profile_image(p_id,p_kind); $$;
revoke all on function public.submit_coffee_profile_image(uuid,text) from public,anon;
grant execute on function public.submit_coffee_profile_image(uuid,text) to authenticated;

create function papi_private.remove_profile_image(p_id uuid) returns text
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); path text;
begin
  if actor is null or p_id is null then raise exception 'Authentication required'; end if;
  path := actor::text || '/profile-' || p_id::text || '.jpg';
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(path,0));
  if exists(select 1 from papi_private.removed_profile_media r where r.image_id=p_id and r.owner_id=actor and r.media_path=path) then return path; end if;
  if not exists(select 1 from public.coffee_profile_images i where i.id=p_id and i.owner_id=actor and i.media_path=path) then raise exception 'Image unavailable'; end if;
  insert into papi_private.removed_profile_media(image_id,owner_id,media_path) values(p_id,actor,path);
  delete from public.coffee_profile_images i where i.id=p_id and i.owner_id=actor;
  return path;
end;
$$;
revoke all on function papi_private.remove_profile_image(uuid) from public,anon;
grant execute on function papi_private.remove_profile_image(uuid) to authenticated;
create function public.remove_coffee_profile_image(p_id uuid) returns text
language sql security invoker set search_path = '' as $$ select papi_private.remove_profile_image(p_id); $$;
revoke all on function public.remove_coffee_profile_image(uuid) from public,anon;
grant execute on function public.remove_coffee_profile_image(uuid) to authenticated;

create function papi_private.profile_removed_media_exists(p_id uuid) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); path text;
begin
  if actor is null or p_id is null then raise exception 'Authentication required'; end if;
  select r.media_path into path from papi_private.removed_profile_media r where r.image_id=p_id and r.owner_id=actor;
  if not found then raise exception 'Removed image unavailable'; end if;
  return exists(select 1 from storage.objects o where o.bucket_id='coffee-media' and o.name=path);
end;
$$;
revoke all on function papi_private.profile_removed_media_exists(uuid) from public,anon;
grant execute on function papi_private.profile_removed_media_exists(uuid) to authenticated;
create function public.removed_profile_media_exists(p_id uuid) returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.profile_removed_media_exists(p_id); $$;
revoke all on function public.removed_profile_media_exists(uuid) from public,anon;
grant execute on function public.removed_profile_media_exists(uuid) to authenticated;
