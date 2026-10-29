"""Export the existing editorial moments without altering their identifiers."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
moments = json.loads((root / "Docs/BackendAPI/seed/editorial_moments.json").read_text(encoding="utf-8"))
if not moments or len({item["id"] for item in moments}) != len(moments):
    raise ValueError("Archived source is incomplete or has duplicate IDs")
raw = json.dumps(moments, ensure_ascii=False, indent=2) + "\n"
if "$papi_moments$" in raw:
    raise ValueError("Source conflicts with SQL quoting")
archive = root / "Docs/BackendAPI/seed/editorial_moments.json"
archive.write_text(raw, encoding="utf-8")
sql = root / "backend/papi_tods_editorial_catalog.sql"
sql.write_text("""-- Source: Docs/BackendAPI/seed/editorial_moments.json; existing rows are preserved.
create table public.coffee_editorial_catalog (
  id text primary key,
  position integer not null,
  author_id text not null,
  asset text not null references public.coffee_asset_catalog(asset),
  is_video boolean not null,
  caption text not null,
  category text not null,
  created_epoch bigint not null,
  sample_likes integer not null,
  sample_comments jsonb not null
);
alter table public.coffee_editorial_catalog enable row level security;
revoke all on public.coffee_editorial_catalog from public, anon, authenticated;
grant select on public.coffee_editorial_catalog to authenticated;
create policy coffee_editorial_catalog_read on public.coffee_editorial_catalog for select to authenticated
  using ((select auth.uid()) is not null);

with source as (select $papi_moments$""" + raw + """$papi_moments$::jsonb as records)
insert into public.coffee_editorial_catalog(id,position,author_id,asset,is_video,caption,category,created_epoch,sample_likes,sample_comments)
select item->>'id', (ordinality - 1)::integer, item->>'author_id', item->>'asset',
       (item->>'is_video')::boolean, item->>'caption', item->>'category', (item->>'created_epoch')::bigint,
       (item->>'sample_likes')::integer, item->'sample_comments'
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item, ordinality)
on conflict (id) do nothing;
""", encoding="utf-8")
print(f"Archived {len(moments)} editorial moments and prepared {sql.relative_to(root)}")
