-- Source: Docs/BackendAPI/seed/editorial_people.json; existing rows are preserved.
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
with source as (select $papi_people$[
  {
    "id": "preview-member-0",
    "name": "Clara Voss",
    "portrait": "portrait-clara",
    "bio": "A portrait for those who take the window seat and leave time for a pour-over."
  },
  {
    "id": "preview-member-1",
    "name": "Jun Park",
    "portrait": "portrait-jun",
    "bio": "A coffee portrait inspired by ceramic drippers and tidy brewing notes."
  },
  {
    "id": "preview-member-2",
    "name": "Kai Moreno",
    "portrait": "portrait-kai",
    "bio": "A portrait for a thermos, a trail and a cup worth stopping for."
  },
  {
    "id": "preview-member-3",
    "name": "Theo Ellis",
    "portrait": "portrait-theo",
    "bio": "A coffee portrait inspired by dark chocolate notes and short espresso breaks."
  },
  {
    "id": "preview-member-4",
    "name": "Elise Reed",
    "portrait": "portrait-elise",
    "bio": "A portrait for unhurried café reading and a second cup."
  },
  {
    "id": "preview-member-5",
    "name": "Mateo Silva",
    "portrait": "portrait-mateo",
    "bio": "A coffee portrait inspired by bright iced brews after a morning outside."
  },
  {
    "id": "preview-member-6",
    "name": "Ren Aoki",
    "portrait": "portrait-ren",
    "bio": "A portrait for small roasteries, new beans and handwritten recipes."
  },
  {
    "id": "preview-member-7",
    "name": "Dae Han",
    "portrait": "portrait-dae",
    "bio": "A coffee portrait inspired by quiet counters and the first cup of the day."
  },
  {
    "id": "collection-person-26",
    "name": "Adrian Bell",
    "portrait": "portrait-adrian-bell",
    "bio": "An espresso stop before heading back into town."
  },
  {
    "id": "collection-person-27",
    "name": "Mila Hayes",
    "portrait": "portrait-mila-hayes",
    "bio": "A café terrace and a few pages to read."
  },
  {
    "id": "collection-person-28",
    "name": "Sora Kim",
    "portrait": "portrait-sora-kim",
    "bio": "Cold coffee for a walk around the neighbourhood."
  },
  {
    "id": "collection-person-29",
    "name": "Elliot Lane",
    "portrait": "portrait-elliot-lane",
    "bio": "A small cup between the busy parts of the day."
  },
  {
    "id": "collection-person-31",
    "name": "Felix Ward",
    "portrait": "portrait-felix-ward",
    "bio": "A coffee break after an early start."
  },
  {
    "id": "collection-person-32",
    "name": "Luca Moretti",
    "portrait": "portrait-luca-moretti",
    "bio": "A quiet counter and a favourite ceramic cup."
  },
  {
    "id": "collection-person-33",
    "name": "Noah Laurent",
    "portrait": "portrait-noah-laurent",
    "bio": "Trying a different roast for the next morning brew."
  },
  {
    "id": "collection-person-34",
    "name": "Owen Brooks",
    "portrait": "portrait-owen-brooks",
    "bio": "A slow cup after putting the camera away."
  },
  {
    "id": "collection-person-35",
    "name": "Hugo Martin",
    "portrait": "portrait-hugo-martin",
    "bio": "Coffee in the kitchen before the day gets going."
  },
  {
    "id": "collection-person-36",
    "name": "Lena Hart",
    "portrait": "portrait-lena-hart",
    "bio": "A little time set aside for the first pour."
  },
  {
    "id": "collection-person-37",
    "name": "Idris Cole",
    "portrait": "portrait-idris-cole",
    "bio": "A favourite table, a short coffee and no rush."
  },
  {
    "id": "collection-person-38",
    "name": "Nina Wells",
    "portrait": "portrait-nina-wells",
    "bio": "Coffee and a snack before heading home."
  },
  {
    "id": "collection-person-39",
    "name": "Oscar Quinn",
    "portrait": "portrait-oscar-quinn",
    "bio": "Keeping the afternoon espresso short."
  },
  {
    "id": "collection-person-40",
    "name": "Dylan Frost",
    "portrait": "portrait-dylan-frost",
    "bio": "A café stop on the way back from the water."
  },
  {
    "id": "collection-person-41",
    "name": "Jasper Reed",
    "portrait": "portrait-jasper-reed",
    "bio": "Taking a notebook along for a coffee break."
  },
  {
    "id": "collection-person-42",
    "name": "Finn Adler",
    "portrait": "portrait-finn-adler",
    "bio": "Something warm after a windy walk."
  },
  {
    "id": "collection-person-43",
    "name": "Toby Shaw",
    "portrait": "portrait-toby-shaw",
    "bio": "Finding a seat outside the café."
  },
  {
    "id": "collection-person-44",
    "name": "Enzo Riva",
    "portrait": "portrait-enzo-riva",
    "bio": "A small strong coffee to start the morning."
  },
  {
    "id": "collection-person-45",
    "name": "Caleb Stone",
    "portrait": "portrait-caleb-stone",
    "bio": "Saving a café stop for the end of the ride."
  },
  {
    "id": "collection-person-46",
    "name": "Freya Moss",
    "portrait": "portrait-freya-moss",
    "bio": "A warm cup after a cool morning by the lake."
  },
  {
    "id": "collection-person-47",
    "name": "Iris Blake",
    "portrait": "portrait-iris-blake",
    "bio": "A quiet place to pause over coffee."
  },
  {
    "id": "collection-person-48",
    "name": "Maeve Ellis",
    "portrait": "portrait-maeve-ellis",
    "bio": "A new bag of beans for the weekend."
  },
  {
    "id": "collection-person-49",
    "name": "Simon Hale",
    "portrait": "portrait-simon-hale",
    "bio": "Coffee after a long afternoon outdoors."
  },
  {
    "id": "collection-person-50",
    "name": "Arlo Finch",
    "portrait": "portrait-arlo-finch",
    "bio": "A familiar coffee order in an unfamiliar street."
  },
  {
    "id": "collection-person-51",
    "name": "Miles Rowan",
    "portrait": "portrait-miles-rowan",
    "bio": "A pause between one part of the day and the next."
  },
  {
    "id": "collection-person-52",
    "name": "Louis Mercer",
    "portrait": "portrait-louis-mercer",
    "bio": "Looking for a small neighbourhood roastery."
  },
  {
    "id": "collection-person-53",
    "name": "Eva Silva",
    "portrait": "portrait-eva-silva",
    "bio": "Coffee and a pastry at the same table."
  },
  {
    "id": "collection-person-54",
    "name": "Chloe Bennett",
    "portrait": "portrait-chloe-bennett",
    "bio": "A window seat with a view of the counter."
  },
  {
    "id": "collection-person-55",
    "name": "Leon West",
    "portrait": "portrait-leon-west",
    "bio": "A morning cup before leaving the house."
  },
  {
    "id": "collection-person-56",
    "name": "Rory Vale",
    "portrait": "portrait-rory-vale",
    "bio": "Something warm after a walk in the hills."
  },
  {
    "id": "collection-person-57",
    "name": "Asher Dean",
    "portrait": "portrait-asher-dean",
    "bio": "One more coffee before the table is cleared."
  },
  {
    "id": "collection-person-58",
    "name": "Isla Hartley",
    "portrait": "portrait-isla-hartley",
    "bio": "A coffee stop on the road out of town."
  },
  {
    "id": "collection-person-59",
    "name": "Niko Wells",
    "portrait": "portrait-niko-wells",
    "bio": "An easy afternoon and the next place to try coffee."
  }
]
$papi_people$::jsonb as records)
insert into public.coffee_editorial_people(id,position,name,portrait,bio)
select item->>'id', (ordinality-1)::integer, item->>'name', item->>'portrait', item->>'bio'
from source cross join lateral jsonb_array_elements(records) with ordinality as entries(item, ordinality)
on conflict (id) do nothing;
