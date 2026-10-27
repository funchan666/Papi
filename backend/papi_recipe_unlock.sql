create table public.coffee_recipe_unlocks (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  recipe_id text not null check (recipe_id in ('bright-four-pour', 'rounder-cup', 'iced-window')),
  unlocked_at timestamptz not null default now(),
  primary key (owner_id, recipe_id)
);
alter table public.coffee_recipe_unlocks enable row level security;
revoke all on public.coffee_recipe_unlocks from public, anon, authenticated;
grant select on public.coffee_recipe_unlocks to authenticated;
create policy recipes_read_own on public.coffee_recipe_unlocks for select to authenticated
  using (owner_id = (select auth.uid()));

create function papi_private.unlock_recipe(recipe text) returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  price bigint;
  current_balance bigint;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  price := case recipe when 'bright-four-pour' then 120
                       when 'rounder-cup' then 180
                       when 'iced-window' then 240 else null end;
  if price is null then raise exception 'Unknown recipe'; end if;
  select balance into current_balance from public.coffee_wallets where owner_id = actor for update;
  if not found then raise exception 'Wallet unavailable'; end if;
  if exists (select 1 from public.coffee_recipe_unlocks where owner_id = actor and recipe_id = recipe) then
    return current_balance;
  end if;
  if current_balance < price then raise exception 'Insufficient coins'; end if;
  update public.coffee_wallets set balance = balance - price, updated_at = now() where owner_id = actor
    returning balance into current_balance;
  insert into public.coffee_recipe_unlocks (owner_id, recipe_id) values (actor, recipe);
  insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
    values (actor, -price, 'Recipe unlock', 'recipe-' || recipe);
  return current_balance;
end;
$$;
revoke all on function papi_private.unlock_recipe(text) from public, anon;
grant execute on function papi_private.unlock_recipe(text) to authenticated;

create function public.unlock_coffee_recipe(recipe text) returns bigint
language sql security invoker set search_path = ''
as $$ select papi_private.unlock_recipe(recipe); $$;
revoke all on function public.unlock_coffee_recipe(text) from public, anon;
grant execute on function public.unlock_coffee_recipe(text) to authenticated;
