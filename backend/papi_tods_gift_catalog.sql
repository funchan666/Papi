-- Source: Docs/BackendAPI/seed/gifts.json.
create table public.coffee_gift_catalog (
  id text primary key,
  position integer not null,
  item jsonb not null,
  check (item->>'id'=id)
);
alter table public.coffee_gift_catalog enable row level security;
revoke all on public.coffee_gift_catalog from public,anon,authenticated;
grant select on public.coffee_gift_catalog to authenticated;
create policy coffee_gift_catalog_read on public.coffee_gift_catalog for select to authenticated
  using ((select auth.uid()) is not null);
with source as (select $papi_gifts$[
  {
    "id": "love",
    "name": "Sending love",
    "asset": "giftLove",
    "cost": 80
  },
  {
    "id": "peach",
    "name": "Peach",
    "asset": "giftPeach",
    "cost": 120
  },
  {
    "id": "umbrella",
    "name": "Sweet brew",
    "asset": "giftUmbrella",
    "cost": 180
  },
  {
    "id": "cake",
    "name": "Three wishes",
    "asset": "giftCake",
    "cost": 260
  },
  {
    "id": "bird",
    "name": "Little bird",
    "asset": "giftBird",
    "cost": 360
  },
  {
    "id": "headphones",
    "name": "Coffee beats",
    "asset": "giftHeadphones",
    "cost": 520
  },
  {
    "id": "car",
    "name": "Dream ride",
    "asset": "giftCar",
    "cost": 900
  },
  {
    "id": "crown",
    "name": "Café royalty",
    "asset": "giftCrown",
    "cost": 1400
  }
]
$papi_gifts$::jsonb as records)
insert into public.coffee_gift_catalog(id,position,item)
select item->>'id',(ordinality-1)::integer,item
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item,ordinality)
on conflict(id) do nothing;
