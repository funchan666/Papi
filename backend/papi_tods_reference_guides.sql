-- Source: Docs/BackendAPI/seed/reference_guides.json.
create table public.coffee_reference_guides (
  id text primary key,
  kind text not null check (kind in ('bean','cafe')),
  title text not null,
  asset text not null,
  detail text not null,
  position integer not null
);
alter table public.coffee_reference_guides enable row level security;
revoke all on public.coffee_reference_guides from public, anon, authenticated;
grant select on public.coffee_reference_guides to authenticated;
create policy coffee_reference_guides_read on public.coffee_reference_guides for select to authenticated
  using ((select auth.uid()) is not null);
with source as (select $papi_guides$[
  {
    "id": "beanArabica",
    "kind": "bean",
    "title": "Arabica",
    "asset": "beanArabica",
    "detail": "Often enjoyed for a nuanced cup. Try recording the aroma, sweetness and finish of your own brew.",
    "position": 0
  },
  {
    "id": "beanRobusta",
    "kind": "bean",
    "title": "Robusta",
    "asset": "beanRobusta",
    "detail": "A fuller-bodied coffee often used in blends. Compare different brew ratios in your journal.",
    "position": 1
  },
  {
    "id": "beanGeisha",
    "kind": "bean",
    "title": "Geisha",
    "asset": "beanGeisha",
    "detail": "Take time with the aroma and let the cup cool before adding your tasting notes.",
    "position": 2
  },
  {
    "id": "beanBourbon",
    "kind": "bean",
    "title": "Bourbon",
    "asset": "beanBourbon",
    "detail": "Compare roast levels and note how sweetness changes in your cup.",
    "position": 3
  },
  {
    "id": "beanPacamara",
    "kind": "bean",
    "title": "Pacamara",
    "asset": "beanPacamara",
    "detail": "Explore your brewing recipe and note the texture and finish.",
    "position": 4
  },
  {
    "id": "beanSL28",
    "kind": "bean",
    "title": "SL28",
    "asset": "beanSL28",
    "detail": "Keep track of grind size and water temperature as you explore each cup.",
    "position": 5
  },
  {
    "id": "home-espresso-corner",
    "kind": "cafe",
    "title": "The home coffee corner",
    "asset": "home-espresso-corner",
    "detail": "Tools within reach, room for a careful pour",
    "position": 0
  },
  {
    "id": "glasshouse-cafe",
    "kind": "cafe",
    "title": "Under the glass roof",
    "asset": "glasshouse-cafe",
    "detail": "Natural light across a busy coffee bar",
    "position": 1
  },
  {
    "id": "rose-front-cafe",
    "kind": "cafe",
    "title": "A rose-coloured terrace",
    "asset": "rose-front-cafe",
    "detail": "Outdoor tables and a quieter evening cup",
    "position": 2
  },
  {
    "id": "courtyard-brunch",
    "kind": "cafe",
    "title": "The courtyard table",
    "asset": "courtyard-brunch",
    "detail": "Coffee and pastry in the open air",
    "position": 3
  }
]
$papi_guides$::jsonb as records)
insert into public.coffee_reference_guides(id,kind,title,asset,detail,position)
select item->>'id',item->>'kind',item->>'title',item->>'asset',item->>'detail',(item->>'position')::integer
from source cross join lateral jsonb_array_elements(records) as item on conflict(id) do nothing;
