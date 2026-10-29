"""Export the existing editorial moments without altering their identifiers."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
swift = (root / "Papi/CoffeeDomain/CoffeeArchive.swift").read_text(encoding="utf-8")
media = json.loads((root / "Docs/BackendAPI/seed/coffee_collection.json").read_text(encoding="utf-8"))

def notes_between(start: str, end: str) -> dict[int, str]:
    section = swift.split(start, 1)[1].split(end, 1)[0]
    return {int(index): json.loads(value) for index, value in re.findall(r'^\s*(\d+):("(?:[^"\\]|\\.)*")\s*,?\s*$', section, re.MULTILINE)}

captions = notes_between('let captions: [Int:String] = [', 'let photographs=')
films = notes_between('let filmNotes:[Int:String] = [', 'let films=')
conversations = {}
pattern = r'\.init\(momentID:"([^"]+)",contributorIndex:(\d+),appreciationCount:(\d+),cupNotes:(\[.*\])\)'
for line in swift.splitlines():
    match = re.search(pattern, line)
    if match:
        moment, contributor, likes, notes = match.groups()
        conversations[moment] = {"contributor": int(contributor), "likes": int(likes), "comments": json.loads(notes)}

moments = []
for item in media["items"]:
    moment = item.get("momentID")
    if not moment:
        continue
    kind, index = moment.removeprefix("editorial-").rsplit("-", 1)
    index = int(index)
    discussion = conversations[moment]
    caption = (films if kind == "video" else captions)[index]
    moments.append({
        "id": moment, "author_id": f"preview-member-{discussion['contributor']}",
        "asset": item["asset"], "is_video": kind == "video", "caption": caption,
        "category": ("Between cafés" if index in [2, 3, 10, 12] else "Coffee films") if kind == "video" else "Café journal",
        "created_epoch": 1790000000 + index * 3600,
        "sample_likes": discussion["likes"], "sample_comments": discussion["comments"],
    })

if len(moments) != 40 or len({x["id"] for x in moments}) != len(moments) or len(conversations) != len(moments):
    raise ValueError("Editorial IDs or source data are incomplete")
photos = [x for x in moments if not x["is_video"]]
videos = [x for x in moments if x["is_video"]]
moments = photos[:4] + videos + photos[4:]
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
