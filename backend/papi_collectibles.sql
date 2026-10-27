-- Collecting is a purchase for the owner's backpack, not a transfer to another user.
create table public.coffee_collectibles (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  collectible_id text not null,
  quantity bigint not null check (quantity > 0),
  primary key (owner_id, collectible_id)
);
create table public.coffee_collectible_orders (
  id uuid primary key,
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  collectible_id text not null,
  quantity integer not null check (quantity between 1 and 99),
  total integer not null check (total > 0),
  created_at timestamptz not null default now()
);
alter table public.coffee_collectibles enable row level security;
alter table public.coffee_collectible_orders enable row level security;
revoke all on public.coffee_collectibles, public.coffee_collectible_orders from public, anon, authenticated;
grant select on public.coffee_collectibles, public.coffee_collectible_orders to authenticated;
create policy collectibles_read_own on public.coffee_collectibles for select to authenticated
  using (owner_id = (select auth.uid()));
create policy collectible_orders_read_own on public.coffee_collectible_orders for select to authenticated
  using (owner_id = (select auth.uid()));

create function papi_private.collect_item(order_id uuid, item text, item_quantity integer) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  price integer;
  total_price integer;
  balance bigint;
  previous public.coffee_collectible_orders%rowtype;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  price := case item when 'love' then 80 when 'peach' then 120
    when 'umbrella' then 180 when 'cake' then 260 when 'bird' then 360
    when 'headphones' then 520 when 'car' then 900 when 'crown' then 1400 else null end;
  if order_id is null or price is null or item_quantity is null or item_quantity not between 1 and 99 then
    raise exception 'Invalid collectible order';
  end if;
  total_price := price * item_quantity;
  select w.balance into balance from public.coffee_wallets w where w.owner_id = actor for update;
  if not found then raise exception 'Wallet unavailable'; end if;
  select * into previous from public.coffee_collectible_orders o where o.id = order_id;
  if found then
    if previous.owner_id <> actor or previous.collectible_id <> item or previous.quantity <> item_quantity then
      raise exception 'Order identifier already used';
    end if;
    return balance;
  end if;
  if balance < total_price then raise exception 'Insufficient coins'; end if;
  update public.coffee_wallets w set balance = w.balance - total_price, updated_at = now()
    where w.owner_id = actor returning w.balance into balance;
  insert into public.coffee_collectible_orders (id, owner_id, collectible_id, quantity, total)
    values (order_id, actor, item, item_quantity, total_price);
  insert into public.coffee_collectibles as inventory (owner_id, collectible_id, quantity)
    values (actor, item, item_quantity)
    on conflict (owner_id, collectible_id) do update set quantity = inventory.quantity + excluded.quantity;
  insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
    values (actor, -total_price, 'Backpack collectible', 'collectible-' || order_id::text);
  return balance;
end;
$$;
revoke all on function papi_private.collect_item(uuid, text, integer) from public, anon;
grant execute on function papi_private.collect_item(uuid, text, integer) to authenticated;

create function public.collect_coffee_item(order_id uuid, item text, item_quantity integer) returns bigint
language sql security invoker set search_path = ''
as $$ select papi_private.collect_item(order_id, item, item_quantity); $$;
revoke all on function public.collect_coffee_item(uuid, text, integer) from public, anon;
grant execute on function public.collect_coffee_item(uuid, text, integer) to authenticated;
