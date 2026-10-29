"""Export collection profiles, retaining the eight existing authored bios."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
people = json.loads((root / "Docs/BackendAPI/seed/editorial_people.json").read_text(encoding="utf-8"))
if not people or len({item["id"] for item in people}) != len(people):
    raise ValueError("Archived source is incomplete or has duplicate IDs")
raw = json.dumps(people, ensure_ascii=False, indent=2) + "\n"
if "$papi_people$" in raw:
    raise ValueError("Source conflicts with SQL quoting")
(root / "Docs/BackendAPI/seed/editorial_people.json").write_text(raw, encoding="utf-8")
sql = root / "backend/papi_tods_editorial_people.sql"
sql.write_text("""-- Source: Docs/BackendAPI/seed/editorial_people.json; existing rows are preserved.
create table public.coffee_editorial_people (
  id text primary key,
  position integer not null,
  name text not null,
  portrait text not null references public.coffee_asset_catalog(asset),
  bio text not null
);
alter table public.coffee_editorial_people enable row level security;
revoke all on public.coffee_editorial_people from public, anon, authenticated;
grant select on public.coffee_editorial_people to authenticated;
create policy coffee_editorial_people_read on public.coffee_editorial_people for select to authenticated
  using ((select auth.uid()) is not null);
with source as (select $papi_people$""" + raw + """$papi_people$::jsonb as records)
insert into public.coffee_editorial_people(id,position,name,portrait,bio)
select item->>'id', (ordinality-1)::integer, item->>'name', item->>'portrait', item->>'bio'
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item, ordinality)
on conflict (id) do nothing;
""", encoding="utf-8")
print(f"Archived {len(people)} collection profiles and prepared {sql.relative_to(root)}")
