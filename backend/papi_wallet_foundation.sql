-- Wallet values and movements are server-owned. Clients may read their own
-- rows but cannot create credits, change balances or settle Apple purchases.
create table public.coffee_wallets (
  owner_id uuid primary key references public.coffee_profiles(id) on delete cascade,
  balance bigint not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table public.coffee_wallet_movements (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  delta bigint not null check (delta <> 0),
  reason text not null check (char_length(reason) between 1 and 80),
  idempotency_key text not null check (char_length(idempotency_key) between 1 and 200),
  created_at timestamptz not null default now(),
  unique (owner_id, idempotency_key)
);
create index coffee_wallet_movements_owner_idx on public.coffee_wallet_movements(owner_id, created_at desc);

alter table public.coffee_wallets enable row level security;
alter table public.coffee_wallet_movements enable row level security;
revoke all on public.coffee_wallets, public.coffee_wallet_movements from public, anon, authenticated;
grant select on public.coffee_wallets, public.coffee_wallet_movements to authenticated;
create policy wallet_read_own on public.coffee_wallets for select to authenticated
  using (owner_id = (select auth.uid()));
create policy wallet_movements_read_own on public.coffee_wallet_movements for select to authenticated
  using (owner_id = (select auth.uid()));

create function papi_private.open_coffee_wallet() returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.coffee_wallets (owner_id, balance) values (new.id, 800);
  insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
    values (new.id, 800, 'First brew welcome gift', 'first-brew-welcome');
  return new;
end;
$$;
revoke all on function papi_private.open_coffee_wallet() from public, anon, authenticated;
create trigger coffee_profile_opens_wallet after insert on public.coffee_profiles
  for each row execute function papi_private.open_coffee_wallet();
