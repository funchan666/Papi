-- Product amounts are frozen on the server. Clients can create and read their
-- own order, but only the receipt-verification service may settle it.
create table public.coffee_purchase_orders (
  id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  product_id text not null check (product_id in (
    'rkbybzkkqpeaxovi', 'yiyfivvjmkdiuqus', 'mqtzlpvknayrxwce',
    'vguhlyrrsyfaswwv', 'qqopbybcdridrsjl', 'wspjnqfkxvmdlrya',
    'kokiljjwycwbpasa', 'nylrtdzhiqgywsrh', 'lkcdocdwdjjjmdfr'
  )),
  coins integer generated always as (case product_id
    when 'rkbybzkkqpeaxovi' then 480 when 'yiyfivvjmkdiuqus' then 1000
    when 'mqtzlpvknayrxwce' then 1600 when 'vguhlyrrsyfaswwv' then 2800
    when 'qqopbybcdridrsjl' then 6000 when 'wspjnqfkxvmdlrya' then 9600
    when 'kokiljjwycwbpasa' then 13200 when 'nylrtdzhiqgywsrh' then 36000
    when 'lkcdocdwdjjjmdfr' then 78000 end) stored,
  apple_transaction_id text unique,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);
create index coffee_purchase_orders_owner_idx on public.coffee_purchase_orders(owner_id, created_at desc);
alter table public.coffee_purchase_orders enable row level security;
revoke all on public.coffee_purchase_orders from public, anon, authenticated;
grant select on public.coffee_purchase_orders to authenticated;
grant insert (id, owner_id, product_id) on public.coffee_purchase_orders to authenticated;
create policy orders_read_own on public.coffee_purchase_orders for select to authenticated
  using (owner_id = (select auth.uid()));
create policy orders_create_own on public.coffee_purchase_orders for insert to authenticated
  with check (owner_id = (select auth.uid()) and apple_transaction_id is null and completed_at is null);

-- Keep transaction IDs after an account is deleted, so a finished consumable
-- cannot be credited to another account. No client access is granted.
create table papi_private.apple_transactions (
  transaction_id text primary key,
  order_id uuid not null unique,
  owner_id uuid not null,
  product_id text not null,
  coins integer not null check (coins > 0),
  apple_environment text not null check (apple_environment in ('Sandbox', 'Production')),
  settled_at timestamptz not null default now()
);
alter table papi_private.apple_transactions enable row level security;
revoke all on papi_private.apple_transactions from public, anon, authenticated;

-- This function trusts only a separately verified JWS from the server-side
-- Apple verification endpoint. It is not executable by app clients.
create function papi_private.settle_apple_order(
  p_order uuid, p_owner uuid, p_product text, p_transaction text, p_environment text
) returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  purchase public.coffee_purchase_orders%rowtype;
  prior papi_private.apple_transactions%rowtype;
  result_balance bigint;
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'Service authorization required';
  end if;
  if p_transaction is null or p_transaction !~ '^[0-9]{1,32}$' or p_environment not in ('Sandbox', 'Production') then
    raise exception 'Invalid transaction';
  end if;
  select * into purchase from public.coffee_purchase_orders where id = p_order for update;
  if not found or purchase.owner_id <> p_owner or purchase.product_id <> p_product then
    raise exception 'Order ownership or product mismatch';
  end if;
  select * into prior from papi_private.apple_transactions where transaction_id = p_transaction;
  if found then
    if prior.order_id <> p_order or prior.owner_id <> p_owner or prior.product_id <> p_product or prior.apple_environment <> p_environment then
      raise exception 'Transaction already claimed';
    end if;
    select balance into result_balance from public.coffee_wallets where owner_id = p_owner;
    if not found then raise exception 'Wallet unavailable'; end if;
    return result_balance;
  end if;
  if purchase.apple_transaction_id is not null then raise exception 'Order already settled'; end if;
  update public.coffee_wallets set balance = balance + purchase.coins, updated_at = now()
    where owner_id = p_owner returning balance into result_balance;
  if not found then raise exception 'Wallet unavailable'; end if;
  insert into papi_private.apple_transactions (transaction_id, order_id, owner_id, product_id, coins, apple_environment)
    values (p_transaction, p_order, p_owner, p_product, purchase.coins, p_environment);
  update public.coffee_purchase_orders set apple_transaction_id = p_transaction, completed_at = now() where id = p_order;
  insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
    values (p_owner, purchase.coins, 'Apple purchase', 'apple-' || p_transaction);
  return result_balance;
end;
$$;
revoke all on function papi_private.settle_apple_order(uuid,uuid,text,text,text) from public, anon, authenticated;
grant usage on schema papi_private to service_role;
grant execute on function papi_private.settle_apple_order(uuid,uuid,text,text,text) to service_role;

create function public.settle_verified_apple_order(
  p_order uuid, p_owner uuid, p_product text, p_transaction text, p_environment text
) returns bigint language sql security invoker set search_path = ''
as $$ select papi_private.settle_apple_order(p_order,p_owner,p_product,p_transaction,p_environment); $$;
revoke all on function public.settle_verified_apple_order(uuid,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.settle_verified_apple_order(uuid,uuid,text,text,text) to service_role;
