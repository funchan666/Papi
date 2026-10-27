-- Keep recent server versions when a later write replaces a brew book.
create table public.coffee_brew_history (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  revision bigint not null,
  contents jsonb not null,
  saved_at timestamptz not null default now(),
  primary key (owner_id, revision)
);
alter table public.coffee_brew_history enable row level security;
revoke all on public.coffee_brew_history from public, anon, authenticated;
grant select on public.coffee_brew_history to authenticated;
create policy brew_history_read_own on public.coffee_brew_history for select to authenticated
  using (owner_id = (select auth.uid()));

create function papi_private.keep_brew_history() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if old.contents is not null and old.revision <> new.revision then
    insert into public.coffee_brew_history (owner_id, revision, contents)
      values (old.owner_id, old.revision, old.contents) on conflict do nothing;
    delete from public.coffee_brew_history
      where owner_id = old.owner_id and revision < new.revision - 20;
  end if;
  return new;
end;
$$;
revoke all on function papi_private.keep_brew_history() from public, anon, authenticated;
create trigger coffee_brew_book_keeps_history before update on public.coffee_brew_books
  for each row execute function papi_private.keep_brew_history();
