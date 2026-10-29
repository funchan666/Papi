"""Archive the existing collectible catalog without changing server prices."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
items = json.loads((root / "Docs/BackendAPI/seed/gifts.json").read_text(encoding="utf-8"))
if not items or len({item["id"] for item in items}) != len(items):
    raise ValueError("Archived source is incomplete or has duplicate IDs")
raw = json.dumps(items,ensure_ascii=False,indent=2)+"\n"
if "$papi_gifts$" in raw:
    raise ValueError("Source conflicts with SQL quoting")
(root / "Docs/BackendAPI/seed/gifts.json").write_text(raw,encoding="utf-8")
sql=root / "backend/papi_tods_gift_catalog.sql"
sql.write_text("""-- Source: Docs/BackendAPI/seed/gifts.json.
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
with source as (select $papi_gifts$"""+raw+"""$papi_gifts$::jsonb as records)
insert into public.coffee_gift_catalog(id,position,item)
select item->>'id',(ordinality-1)::integer,item
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item,ordinality)
on conflict(id) do nothing;
""",encoding="utf-8")
print(f"Archived {len(items)} gifts and prepared {sql.relative_to(root)}")
