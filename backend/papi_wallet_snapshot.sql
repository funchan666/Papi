-- A single read uses one database snapshot; access remains governed by RLS.
create function public.coffee_wallet_snapshot() returns jsonb
language sql stable security invoker set search_path = ''
as $$
  select jsonb_build_object(
    'balance', w.balance,
    'experience', p.experience,
    'server_day', (now() at time zone 'UTC')::date,
    'checkins', coalesce((select jsonb_agg(jsonb_build_object('checkin_day', c.checkin_day, 'reward', c.reward)
      order by c.checkin_day desc) from public.coffee_checkins c where c.owner_id = w.owner_id), '[]'::jsonb),
    'collectibles', coalesce((select jsonb_agg(jsonb_build_object('collectible_id', i.collectible_id, 'quantity', i.quantity)
      order by i.collectible_id) from public.coffee_collectibles i where i.owner_id = w.owner_id), '[]'::jsonb),
    'recipes', coalesce((select jsonb_agg(r.recipe_id order by r.recipe_id)
      from public.coffee_recipe_unlocks r where r.owner_id = w.owner_id), '[]'::jsonb),
    'movements', coalesce((select jsonb_agg(jsonb_build_object('id', m.id, 'delta', m.delta,
      'reason', m.reason, 'created_at', m.created_at) order by m.created_at desc)
      from (select id, delta, reason, created_at from public.coffee_wallet_movements
        where owner_id = w.owner_id order by created_at desc, id desc limit 40) m), '[]'::jsonb)
  )
  from public.coffee_wallets w join public.coffee_progress p on p.owner_id = w.owner_id
  where w.owner_id = (select auth.uid());
$$;
revoke all on function public.coffee_wallet_snapshot() from public, anon;
grant execute on function public.coffee_wallet_snapshot() to authenticated;
