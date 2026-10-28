-- Draft only. Requires isolated validation before deployment or accepting charges.
-- Rows are inserted only by the service after Apple's notification and nested
-- transaction signatures are verified. Store no user-supplied receipt data.
create table papi_private.apple_verified_notifications (
  notification_id uuid primary key,
  event_type text not null check (event_type in ('ONE_TIME_CHARGE','REFUND','REVOKE','REFUND_REVERSED')),
  transaction_id text not null check (transaction_id ~ '^[0-9]{1,32}$'),
  order_id uuid not null,
  product_id text not null check (char_length(product_id) between 1 and 200),
  environment text not null check (environment in ('Production','Sandbox')),
  received_at timestamptz not null default now()
);
create index apple_verified_notifications_transaction_idx on papi_private.apple_verified_notifications(transaction_id,environment);
alter table papi_private.apple_verified_notifications enable row level security;
revoke all on papi_private.apple_verified_notifications from public,anon,authenticated;

create function public.record_verified_apple_notification(
  p_id uuid,p_type text,p_transaction text,p_order uuid,p_product text,p_environment text
) returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','') <> 'service_role' or p_id is null or p_order is null
     or p_type not in ('ONE_TIME_CHARGE','REFUND','REVOKE','REFUND_REVERSED')
     or p_transaction is null or p_transaction !~ '^[0-9]{1,32}$'
     or p_product is null or char_length(p_product) not between 1 and 200
     or p_environment not in ('Production','Sandbox') then raise exception 'Invalid notification'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apple-event:'||p_environment||':'||p_transaction,0));
  insert into papi_private.apple_verified_notifications(notification_id,event_type,transaction_id,order_id,product_id,environment)
    values(p_id,p_type,p_transaction,p_order,p_product,p_environment) on conflict(notification_id) do nothing;
  if not exists(select 1 from papi_private.apple_verified_notifications n where n.notification_id=p_id
      and n.event_type=p_type and n.transaction_id=p_transaction and n.order_id=p_order
      and n.product_id=p_product and n.environment=p_environment) then raise exception 'Notification conflict'; end if;
  return true;
end; $$;
revoke all on function public.record_verified_apple_notification(uuid,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_verified_apple_notification(uuid,text,text,uuid,text,text) to service_role;

-- Fail closed on any refund/revocation until a durable refund/reversal ledger exists.
create function public.has_verified_apple_charge(p_order uuid,p_transaction text,p_product text,p_environment text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','') <> 'service_role' then raise exception 'Unavailable'; end if;
  return exists(select 1 from papi_private.apple_verified_notifications n
      where n.event_type='ONE_TIME_CHARGE' and n.order_id=p_order and n.transaction_id=p_transaction
        and n.product_id=p_product and n.environment=p_environment)
    and not exists(select 1 from papi_private.apple_verified_notifications n
      where n.transaction_id=p_transaction and n.environment=p_environment and n.event_type in ('REFUND','REVOKE','REFUND_REVERSED'));
end; $$;
revoke all on function public.has_verified_apple_charge(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.has_verified_apple_charge(uuid,text,text,text) to service_role;

-- Check the signed notification and settle under the same per-transaction lock.
create function public.settle_notified_apple_charge(
  p_order uuid,p_owner uuid,p_product text,p_transaction text,p_environment text
) returns bigint language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt())->>'role','') <> 'service_role' or p_transaction is null
     or p_transaction !~ '^[0-9]{1,32}$' or p_environment not in ('Production','Sandbox') then raise exception 'Unavailable'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('apple-event:'||p_environment||':'||p_transaction,0));
  if not public.has_verified_apple_charge(p_order,p_transaction,p_product,p_environment) then raise exception 'Verified charge unavailable'; end if;
  return papi_private.settle_apple_order(p_order,p_owner,p_product,p_transaction,p_environment);
end; $$;
revoke all on function public.settle_notified_apple_charge(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.settle_notified_apple_charge(uuid,uuid,text,text,text) to service_role;
