"""Export the existing media catalog without changing any of its identifiers."""
from pathlib import Path
import json

root = Path(__file__).resolve().parents[2]
source = root / "Papi/Resources/Media/CoffeeCollection.json"
archive = root / "Docs/BackendAPI/seed/coffee_collection.json"
sql = root / "backend/papi_tods_media_catalog.sql"
raw = source.read_text(encoding="utf-8")
catalog = json.loads(raw)
items = catalog["items"]
if not items or len({item["asset"] for item in items}) != len(items):
    raise ValueError("Media asset IDs must be present and unique")
if "$papi_catalog$" in raw:
    raise ValueError("Catalog conflicts with SQL quoting")
archive.parent.mkdir(parents=True, exist_ok=True)
archive.write_text(raw, encoding="utf-8")
sql.write_text("""-- Source: Docs/BackendAPI/seed/coffee_collection.json; never overwrite an existing row.
create table public.coffee_asset_catalog (
  asset text primary key,
  position integer not null,
  base_url text not null,
  item jsonb not null,
  check (item ->> 'asset' = asset)
);
alter table public.coffee_asset_catalog enable row level security;
revoke all on public.coffee_asset_catalog from public, anon, authenticated;
grant select on public.coffee_asset_catalog to authenticated;
create policy coffee_asset_catalog_read on public.coffee_asset_catalog for select to authenticated
  using ((select auth.uid()) is not null);

with source as (select $papi_catalog$""" + raw + """$papi_catalog$::jsonb as catalog)
insert into public.coffee_asset_catalog(asset, position, base_url, item)
select item ->> 'asset', (ordinality - 1)::integer, catalog ->> 'baseURL', item
from source cross join lateral jsonb_array_elements(catalog -> 'items') with ordinality as entries(item, ordinality)
on conflict (asset) do nothing;
""", encoding="utf-8")
print(f"Archived {len(items)} media records and prepared {sql.relative_to(root)}")
