create table public.coffee_saved_scenes (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  scene_id text not null references public.coffee_reference_guides(id),
  saved_at timestamptz not null default now(),
  primary key(owner_id,scene_id)
);
alter table public.coffee_saved_scenes enable row level security;
revoke all on public.coffee_saved_scenes from public,anon,authenticated;
grant select on public.coffee_saved_scenes to authenticated;
create policy coffee_saved_scenes_read on public.coffee_saved_scenes for select to authenticated
  using (owner_id=(select auth.uid()) and (select papi_private.coffee_actor_active()));

create function papi_private.set_saved_coffee_scene(p_scene text,p_enabled boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or p_scene is null or p_enabled is null then raise exception 'Unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  if not papi_private.coffee_actor_active() or not exists (
    select 1 from public.coffee_reference_guides where id=p_scene and kind='cafe'
  ) then raise exception 'Unavailable'; end if;
  if p_enabled then
    insert into public.coffee_saved_scenes(owner_id,scene_id) values(actor,p_scene) on conflict do nothing;
  else
    delete from public.coffee_saved_scenes where owner_id=actor and scene_id=p_scene;
  end if;
  return p_enabled;
end; $$;
revoke all on function papi_private.set_saved_coffee_scene(text,boolean) from public,anon;
grant execute on function papi_private.set_saved_coffee_scene(text,boolean) to authenticated;
create function public.set_saved_coffee_scene(p_scene text,p_enabled boolean) returns boolean
language sql security invoker set search_path='' as $$
  select papi_private.set_saved_coffee_scene(p_scene,p_enabled);
$$;
revoke all on function public.set_saved_coffee_scene(text,boolean) from public,anon;
grant execute on function public.set_saved_coffee_scene(text,boolean) to authenticated;
