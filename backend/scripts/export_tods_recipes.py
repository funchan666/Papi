"""Archive the original brew recipes and their timed checkpoints."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Papi/CoffeeDomain/BrewRecords.swift").read_text(encoding="utf-8")
section = source.split("private static let bundledCollection:[BrewRecipe] = [", 1)[1].split("static func recipe", 1)[0]
recipe_pattern = re.compile(
    r'\.init\(id:("(?:[^"\\]|\\.)*"),title:("(?:[^"\\]|\\.)*"),'
    r'brewer:("(?:[^"\\]|\\.)*"),story:("(?:[^"\\]|\\.)*"),'
    r'coffeeGrams:(\d+),hotWaterGrams:(\d+),iceGrams:(\d+),waterCelsius:(\d+),'
    r'drawdownSeconds:(\d+),unlockCoins:(\d+),checkpoints:\[(.*?)\]\)', re.DOTALL)
step_pattern = re.compile(r'\.init\(id:(\d+),cue:("(?:[^"\\]|\\.)*"),elapsedSeconds:(\d+),cumulativeWaterFraction:([\d.]+)\)')
recipes = []
for match in recipe_pattern.finditer(section):
    ident, title, brewer, story, dose, hot, ice, temp, duration, cost, steps = match.groups()
    checkpoints = [{"id":int(i),"cue":json.loads(cue),"elapsedSeconds":int(seconds),"cumulativeWaterFraction":float(fraction)}
                   for i,cue,seconds,fraction in step_pattern.findall(steps)]
    if not checkpoints:
        raise ValueError("Recipe has no checkpoints")
    recipes.append({"id":json.loads(ident),"title":json.loads(title),"brewer":json.loads(brewer),"story":json.loads(story),
                    "coffeeGrams":int(dose),"hotWaterGrams":int(hot),"iceGrams":int(ice),"waterCelsius":int(temp),
                    "drawdownSeconds":int(duration),"unlockCoins":int(cost),"checkpoints":checkpoints})
if len(recipes) != 5 or len({r["id"] for r in recipes}) != len(recipes):
    raise ValueError("Recipe source is incomplete")
raw = json.dumps(recipes, ensure_ascii=False, indent=2) + "\n"
if "$papi_recipes$" in raw:
    raise ValueError("Source conflicts with SQL quoting")
(root / "Docs/BackendAPI/seed/brew_recipes.json").write_text(raw, encoding="utf-8")
sql = root / "backend/papi_tods_brew_recipes.sql"
sql.write_text("""-- Source: Docs/BackendAPI/seed/brew_recipes.json.
create table public.coffee_brew_recipes (
  id text primary key,
  position integer not null,
  item jsonb not null,
  check (item->>'id'=id)
);
alter table public.coffee_brew_recipes enable row level security;
revoke all on public.coffee_brew_recipes from public,anon,authenticated;
grant select on public.coffee_brew_recipes to authenticated;
create policy coffee_brew_recipes_read on public.coffee_brew_recipes for select to authenticated
  using ((select auth.uid()) is not null);
with source as (select $papi_recipes$""" + raw + """$papi_recipes$::jsonb as records)
insert into public.coffee_brew_recipes(id,position,item)
select item->>'id',(ordinality-1)::integer,item
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item,ordinality)
on conflict(id) do nothing;
""", encoding="utf-8")
print(f"Archived {len(recipes)} recipes and prepared {sql.relative_to(root)}")
