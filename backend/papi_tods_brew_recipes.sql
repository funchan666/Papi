-- Source: Docs/BackendAPI/seed/brew_recipes.json.
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
with source as (select $papi_recipes$[
  {
    "id": "morning-cone",
    "title": "The morning cone",
    "brewer": "Cone dripper",
    "story": "A gentle bloom and two steady pours. Keep the kettle low and let the bed drain naturally.",
    "coffeeGrams": 18,
    "hotWaterGrams": 300,
    "iceGrams": 0,
    "waterCelsius": 93,
    "drawdownSeconds": 180,
    "unlockCoins": 0,
    "checkpoints": [
      {
        "id": 0,
        "cue": "Bloom the grounds",
        "elapsedSeconds": 0,
        "cumulativeWaterFraction": 0.18
      },
      {
        "id": 1,
        "cue": "Pour in slow circles",
        "elapsedSeconds": 45,
        "cumulativeWaterFraction": 0.6
      },
      {
        "id": 2,
        "cue": "Finish the final pour",
        "elapsedSeconds": 90,
        "cumulativeWaterFraction": 1.0
      }
    ]
  },
  {
    "id": "quiet-immersion",
    "title": "A quiet immersion",
    "brewer": "Immersion brewer",
    "story": "Wet all the grounds, give one gentle stir, then let time do the work. Release the brewer into a stable server.",
    "coffeeGrams": 20,
    "hotWaterGrams": 300,
    "iceGrams": 0,
    "waterCelsius": 92,
    "drawdownSeconds": 270,
    "unlockCoins": 0,
    "checkpoints": [
      {
        "id": 0,
        "cue": "Add water and stir gently",
        "elapsedSeconds": 0,
        "cumulativeWaterFraction": 1.0
      },
      {
        "id": 1,
        "cue": "Release and let it drain",
        "elapsedSeconds": 240,
        "cumulativeWaterFraction": 1.0
      }
    ]
  },
  {
    "id": "bright-four-pour",
    "title": "Four pours, brighter finish",
    "brewer": "Cone dripper",
    "story": "Four small pours make it easier to compare clarity. Try this with the same beans as your morning cone and record what changes.",
    "coffeeGrams": 18,
    "hotWaterGrams": 306,
    "iceGrams": 0,
    "waterCelsius": 94,
    "drawdownSeconds": 210,
    "unlockCoins": 120,
    "checkpoints": [
      {
        "id": 0,
        "cue": "Bloom the grounds",
        "elapsedSeconds": 0,
        "cumulativeWaterFraction": 0.18
      },
      {
        "id": 1,
        "cue": "Begin the second pour",
        "elapsedSeconds": 40,
        "cumulativeWaterFraction": 0.45
      },
      {
        "id": 2,
        "cue": "Build the third pour",
        "elapsedSeconds": 80,
        "cumulativeWaterFraction": 0.73
      },
      {
        "id": 3,
        "cue": "Finish the final pour",
        "elapsedSeconds": 120,
        "cumulativeWaterFraction": 1.0
      }
    ]
  },
  {
    "id": "rounder-cup",
    "title": "A rounder cup",
    "brewer": "Flat-bottom dripper",
    "story": "A slightly shorter ratio and cooler water offer another starting point. Compare sweetness and texture after the cup cools.",
    "coffeeGrams": 20,
    "hotWaterGrams": 300,
    "iceGrams": 0,
    "waterCelsius": 90,
    "drawdownSeconds": 210,
    "unlockCoins": 180,
    "checkpoints": [
      {
        "id": 0,
        "cue": "Bloom the grounds",
        "elapsedSeconds": 0,
        "cumulativeWaterFraction": 0.2
      },
      {
        "id": 1,
        "cue": "Pour in slow circles",
        "elapsedSeconds": 45,
        "cumulativeWaterFraction": 0.6
      },
      {
        "id": 2,
        "cue": "Finish the final pour",
        "elapsedSeconds": 100,
        "cumulativeWaterFraction": 1.0
      }
    ]
  },
  {
    "id": "iced-window",
    "title": "The iced window pour",
    "brewer": "Dripper over ice",
    "story": "Place the measured ice in the server before brewing. Hot water is only part of the final drink; swirl gently to melt the ice.",
    "coffeeGrams": 20,
    "hotWaterGrams": 160,
    "iceGrams": 140,
    "waterCelsius": 92,
    "drawdownSeconds": 150,
    "unlockCoins": 240,
    "checkpoints": [
      {
        "id": 0,
        "cue": "Bloom over the ice-filled server",
        "elapsedSeconds": 0,
        "cumulativeWaterFraction": 0.25
      },
      {
        "id": 1,
        "cue": "Pour in slow circles",
        "elapsedSeconds": 35,
        "cumulativeWaterFraction": 0.63
      },
      {
        "id": 2,
        "cue": "Finish the final pour",
        "elapsedSeconds": 70,
        "cumulativeWaterFraction": 1.0
      }
    ]
  }
]
$papi_recipes$::jsonb as records)
insert into public.coffee_brew_recipes(id,position,item)
select item->>'id',(ordinality-1)::integer,item
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item,ordinality)
on conflict(id) do nothing;
