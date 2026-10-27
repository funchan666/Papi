-- Profile images are private until a human reviewer approves them.
create table public.coffee_profile_images (
  id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  kind text not null check (kind in ('avatar','cover','album')),
  media_path text not null unique,
  moderation_status text not null default 'pending' check (moderation_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create index coffee_profile_images_owner_kind_idx on public.coffee_profile_images(owner_id,kind,created_at desc,id desc);
create index coffee_profile_images_pending_idx on public.coffee_profile_images(created_at) where moderation_status='pending';
alter table public.coffee_profile_images enable row level security;
revoke all on public.coffee_profile_images from public, anon, authenticated;
grant select on public.coffee_profile_images to authenticated;
grant insert (id,owner_id,kind,media_path) on public.coffee_profile_images to authenticated;
create policy profile_images_read on public.coffee_profile_images for select to authenticated
  using (owner_id=(select auth.uid()) or (moderation_status='approved' and exists (
    select 1 from public.coffee_profiles p where p.id=owner_id
  )));
create policy profile_images_submit on public.coffee_profile_images for insert to authenticated
  with check (owner_id=(select auth.uid()) and moderation_status='pending'
    and media_path=(select auth.uid())::text || '/profile-' || id::text || '.jpg'
    and exists (select 1 from storage.objects o where o.bucket_id='coffee-media'
      and o.name=media_path and o.owner_id=(select auth.uid())::text));
create policy coffee_media_read_profile_images on storage.objects for select to authenticated
  using (bucket_id='coffee-media' and exists (
    select 1 from public.coffee_profile_images i where i.media_path=objects.name and i.moderation_status='approved'
  ));

alter table papi_private.moderation_events drop constraint moderation_events_subject_kind_check;
alter table papi_private.moderation_events add constraint moderation_events_subject_kind_check
  check (subject_kind in ('post','comment','report','profile_image'));
create function papi_private.review_profile_image(p_event uuid,p_image uuid,p_outcome text,p_reviewer text,p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare prior papi_private.moderation_events%rowtype;
begin
  if coalesce((select auth.jwt())->>'role','') <> 'service_role' then raise exception 'Service authorization required'; end if;
  if p_event is null or p_image is null or p_outcome not in ('approved','rejected')
     or char_length(trim(coalesce(p_reviewer,''))) not between 1 and 120
     or char_length(trim(coalesce(p_note,''))) not between 1 and 2000 then raise exception 'Invalid review'; end if;
  perform 1 from public.coffee_profile_images where id=p_image for update;
  if not found then raise exception 'Review subject unavailable'; end if;
  select * into prior from papi_private.moderation_events where id=p_event;
  if found then
    if prior.subject_kind<>'profile_image' or prior.subject_id<>p_image or prior.decision<>p_outcome
       or prior.reviewer<>p_reviewer or prior.note<>p_note then raise exception 'Review identifier already used'; end if;
    return;
  end if;
  update public.coffee_profile_images set moderation_status=p_outcome where id=p_image;
  insert into papi_private.moderation_events(id,subject_kind,subject_id,decision,reviewer,note)
    values(p_event,'profile_image',p_image,p_outcome,p_reviewer,p_note);
end;
$$;
revoke all on function papi_private.review_profile_image(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function papi_private.review_profile_image(uuid,uuid,text,text,text) to service_role;
create function public.review_coffee_profile_image(p_event uuid,p_image uuid,p_outcome text,p_reviewer text,p_note text)
returns void language sql security invoker set search_path = ''
as $$ select papi_private.review_profile_image(p_event,p_image,p_outcome,p_reviewer,p_note); $$;
revoke all on function public.review_coffee_profile_image(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.review_coffee_profile_image(uuid,uuid,text,text,text) to service_role;
