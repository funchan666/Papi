create function papi_private.removed_media_exists(p_path text) returns boolean
language plpgsql stable security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or not exists (select 1 from papi_private.removed_post_media r
    where r.owner_id = actor and r.media_path = p_path) then
    raise exception 'Removal unavailable';
  end if;
  return exists (select 1 from storage.objects o where o.bucket_id = 'coffee-media' and o.name = p_path);
end;
$$;
revoke all on function papi_private.removed_media_exists(text) from public, anon;
grant execute on function papi_private.removed_media_exists(text) to authenticated;

create function public.removed_coffee_media_exists(p_path text) returns boolean
language sql stable security invoker set search_path = ''
as $$ select papi_private.removed_media_exists(p_path); $$;
revoke all on function public.removed_coffee_media_exists(text) from public, anon;
grant execute on function public.removed_coffee_media_exists(text) to authenticated;
