-- The brew book is separate from server-owned recipe entitlements and coins.
-- A revision and request ledger prevent a retry or a second device from
-- silently overwriting a different version.
lock table public.coffee_profiles in share row exclusive mode;
create table public.coffee_brew_books (
  owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,
  revision bigint not null default 0 check (revision >= 0),
  contents jsonb,
  updated_at timestamptz not null default now(),
  check (contents is null or (jsonb_typeof(contents) = 'object' and octet_length(contents::text) <= 524288))
);
alter table public.coffee_brew_books enable row level security;
revoke all on public.coffee_brew_books from public, anon, authenticated;
grant select on public.coffee_brew_books to authenticated;
create policy brew_book_read_own on public.coffee_brew_books for select to authenticated
  using (owner_id = (select auth.uid()));

create table papi_private.brew_book_writes (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  request_id uuid not null,
  expected_revision bigint not null,
  contents_hash bytea not null,
  committed_revision bigint not null,
  created_at timestamptz not null default now(),
  primary key (owner_id, request_id)
);
alter table papi_private.brew_book_writes enable row level security;
revoke all on papi_private.brew_book_writes from public, anon, authenticated;

insert into public.coffee_brew_books (owner_id)
  select id from public.coffee_profiles on conflict do nothing;
create function papi_private.open_brew_book() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.coffee_brew_books (owner_id) values (new.id);
  return new;
end;
$$;
revoke all on function papi_private.open_brew_book() from public, anon, authenticated;
create trigger coffee_profile_opens_brew_book after insert on public.coffee_profiles
  for each row execute function papi_private.open_brew_book();

create function papi_private.save_brew_book(p_request uuid, p_revision bigint, p_contents jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  existing public.coffee_brew_books%rowtype;
  previous papi_private.brew_book_writes%rowtype;
  body_hash bytea;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  if p_request is null or p_revision is null or p_revision < 0 or p_contents is null or
     jsonb_typeof(p_contents) <> 'object' or octet_length(p_contents::text) > 524288 then
    raise exception 'Invalid brew book';
  end if;
  body_hash := pg_catalog.sha256(pg_catalog.convert_to(p_contents::text, 'UTF8'));
  select * into existing from public.coffee_brew_books b where b.owner_id = actor for update;
  if not found then raise exception 'Brew book unavailable'; end if;
  select * into previous from papi_private.brew_book_writes w
    where w.owner_id = actor and w.request_id = p_request;
  if found then
    if previous.expected_revision <> p_revision or previous.contents_hash <> body_hash then
      raise exception 'Request identifier already used';
    end if;
    return jsonb_build_object('committed_revision', previous.committed_revision, 'current_revision', existing.revision);
  end if;
  if existing.revision <> p_revision then raise exception 'Brew book revision conflict'; end if;
  update public.coffee_brew_books set contents = p_contents, revision = revision + 1, updated_at = now()
    where owner_id = actor returning revision into existing.revision;
  insert into papi_private.brew_book_writes (owner_id, request_id, expected_revision, contents_hash, committed_revision)
    values (actor, p_request, p_revision, body_hash, existing.revision);
  return jsonb_build_object('committed_revision', existing.revision, 'current_revision', existing.revision);
end;
$$;
revoke all on function papi_private.save_brew_book(uuid,bigint,jsonb) from public, anon;
grant execute on function papi_private.save_brew_book(uuid,bigint,jsonb) to authenticated;

create function public.save_coffee_brew_book(p_request uuid, p_revision bigint, p_contents jsonb)
returns jsonb language sql security invoker set search_path = ''
as $$ select papi_private.save_brew_book(p_request, p_revision, p_contents); $$;
revoke all on function public.save_coffee_brew_book(uuid,bigint,jsonb) from public, anon;
grant execute on function public.save_coffee_brew_book(uuid,bigint,jsonb) to authenticated;
