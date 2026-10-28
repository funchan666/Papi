-- Close only orders for which the client received a terminal StoreKit failure
-- or never submitted a payment. Keep the record and prevent later settlement.
alter table public.coffee_purchase_orders add column cancelled_at timestamptz;

create function papi_private.reject_cancelled_apple_settlement() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.cancelled_at is not null and new.apple_transaction_id is not null then
    raise exception 'Order cancelled';
  end if;
  return new;
end;
$$;
revoke all on function papi_private.reject_cancelled_apple_settlement() from public, anon, authenticated;
create trigger coffee_reject_cancelled_apple_settlement
  before update of apple_transaction_id on public.coffee_purchase_orders
  for each row execute function papi_private.reject_cancelled_apple_settlement();

create function public.cancel_coffee_purchase_order(p_order uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  purchase public.coffee_purchase_orders%rowtype;
begin
  if actor is null or p_order is null then raise exception 'Account unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text, 0));
  if not papi_private.coffee_actor_active() then raise exception 'Account unavailable'; end if;
  select * into purchase from public.coffee_purchase_orders
    where id = p_order and owner_id = actor for update;
  if not found or purchase.apple_transaction_id is not null then return false; end if;
  if purchase.cancelled_at is null then
    update public.coffee_purchase_orders set cancelled_at = now(), completed_at = now() where id = p_order;
  end if;
  return true;
end;
$$;
revoke all on function public.cancel_coffee_purchase_order(uuid) from public, anon;
grant execute on function public.cancel_coffee_purchase_order(uuid) to authenticated;
