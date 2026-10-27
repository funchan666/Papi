-- The seven-step reward follows successful check-ins, not consecutive days.
-- UTC is determined by the database, not the caller's clock.
create table public.coffee_checkins (
  owner_id uuid not null references public.coffee_profiles(id) on delete cascade,
  checkin_day date not null,
  reward integer not null check (reward between 10 and 70 and reward % 10 = 0),
  created_at timestamptz not null default now(),
  primary key (owner_id, checkin_day)
);
alter table public.coffee_checkins enable row level security;
revoke all on public.coffee_checkins from public, anon, authenticated;
grant select on public.coffee_checkins to authenticated;
create policy checkins_read_own on public.coffee_checkins for select to authenticated
  using (owner_id = (select auth.uid()));

create function papi_private.daily_checkin() returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := (select auth.uid());
  today date := (now() at time zone 'UTC')::date;
  balance bigint;
  days bigint;
  amount integer;
  already_rewarded boolean;
begin
  if actor is null then raise exception 'Authentication required'; end if;
  select w.balance into balance from public.coffee_wallets w where w.owner_id = actor for update;
  if not found then raise exception 'Wallet unavailable'; end if;
  select count(*) into days from public.coffee_checkins c where c.owner_id = actor;
  select c.reward into amount from public.coffee_checkins c
    where c.owner_id = actor and c.checkin_day = today;
  already_rewarded := found;
  if not already_rewarded then
    amount := ((days % 7) + 1)::integer * 10;
    insert into public.coffee_checkins (owner_id, checkin_day, reward) values (actor, today, amount);
    update public.coffee_wallets w set balance = w.balance + amount, updated_at = now()
      where w.owner_id = actor returning w.balance into balance;
    insert into public.coffee_wallet_movements (owner_id, delta, reason, idempotency_key)
      values (actor, amount, 'Daily check-in', 'checkin-' || today::text);
    days := days + 1;
  end if;
  return jsonb_build_object('day', today, 'total_days', days, 'reward', amount,
    'balance', balance, 'awarded', not already_rewarded);
end;
$$;
revoke all on function papi_private.daily_checkin() from public, anon;
grant execute on function papi_private.daily_checkin() to authenticated;

create function public.check_in_coffee() returns jsonb
language sql security invoker set search_path = ''
as $$ select papi_private.daily_checkin(); $$;
revoke all on function public.check_in_coffee() from public, anon;
grant execute on function public.check_in_coffee() to authenticated;
