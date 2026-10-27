-- Progress follows successful server actions. Deleting a post does not erase
-- experience already earned, matching the existing local behavior.
lock table public.coffee_profiles, public.coffee_checkins, public.coffee_posts in share row exclusive mode;
do $$ begin
  if exists (select 1 from public.coffee_checkins) or exists (select 1 from public.coffee_posts) then
    raise exception 'Existing activity requires a progress reconciliation before this migration';
  end if;
end $$;
create table public.coffee_progress (
  owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,
  experience bigint not null default 0 check (experience >= 0)
);
alter table public.coffee_progress enable row level security;
revoke all on public.coffee_progress from public, anon, authenticated;
grant select on public.coffee_progress to authenticated;
create policy progress_read_own on public.coffee_progress for select to authenticated
  using (owner_id = (select auth.uid()));

insert into public.coffee_progress (owner_id)
  select id from public.coffee_profiles on conflict do nothing;

create function papi_private.open_coffee_progress() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.coffee_progress (owner_id) values (new.id);
  return new;
end;
$$;
revoke all on function papi_private.open_coffee_progress() from public, anon, authenticated;
create trigger coffee_profile_opens_progress after insert on public.coffee_profiles
  for each row execute function papi_private.open_coffee_progress();

create function papi_private.add_checkin_experience() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.coffee_progress set experience = experience + 20 where owner_id = new.owner_id;
  if not found then raise exception 'Progress unavailable'; end if;
  return new;
end;
$$;
revoke all on function papi_private.add_checkin_experience() from public, anon, authenticated;
create trigger coffee_checkin_adds_experience after insert on public.coffee_checkins
  for each row execute function papi_private.add_checkin_experience();

create function papi_private.add_moment_experience() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  update public.coffee_progress set experience = experience + 10 where owner_id = new.author_id;
  if not found then raise exception 'Progress unavailable'; end if;
  return new;
end;
$$;
revoke all on function papi_private.add_moment_experience() from public, anon, authenticated;
create trigger coffee_moment_adds_experience after insert on public.coffee_posts
  for each row execute function papi_private.add_moment_experience();
