"""Export the existing bean and cafe guide arrays with stable asset IDs."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
def array(source: str, name: str) -> list[str]:
    match = re.search(rf'private let {name}=(\[.*\])', source)
    if not match:
        raise ValueError(f"Missing {name}")
    return json.loads(match.group(1))

bean = (root / "Papi/CoffeeHouse/Beans/BeanVarieties.swift").read_text(encoding="utf-8")
cafe = (root / "Papi/CoffeeHouse/Cafes/CafeNotebook.swift").read_text(encoding="utf-8")
entries = []
for kind, source, name_key, asset_key, note_key in [
    ("bean", bean, "names", "assets", "notes"),
    ("cafe", cafe, "names", "images", "subtitles"),
]:
    names, assets, notes = [array(source, key) for key in (name_key, asset_key, note_key)]
    if not names or len(names) != len(assets) or len(names) != len(notes):
        raise ValueError(f"Incomplete {kind} source arrays")
    entries += [{"id": asset, "kind": kind, "title": name, "asset": asset, "detail": note, "position": i}
                for i, (name, asset, note) in enumerate(zip(names, assets, notes))]
if len({item["id"] for item in entries}) != len(entries):
    raise ValueError("Guide IDs must be unique")
raw = json.dumps(entries, ensure_ascii=False, indent=2) + "\n"
if "$papi_guides$" in raw:
    raise ValueError("Source conflicts with SQL quoting")
archive = root / "Docs/BackendAPI/seed/reference_guides.json"
archive.write_text(raw, encoding="utf-8")
sql = root / "backend/papi_tods_reference_guides.sql"
sql.write_text("""-- Source: Docs/BackendAPI/seed/reference_guides.json.
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
with source as (select $papi_guides$""" + raw + """$papi_guides$::jsonb as records)
insert into public.coffee_reference_guides(id,kind,title,asset,detail,position)
select item->>'id',item->>'kind',item->>'title',item->>'asset',item->>'detail',(item->>'position')::integer
from source cross join lateral jsonb_array_elements(records) as item on conflict(id) do nothing;
""", encoding="utf-8")
print(f"Archived {len(entries)} guides and prepared {sql.relative_to(root)}")
