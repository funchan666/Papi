alter table public.coffee_voice_topics add column room_description text;
alter table public.coffee_voice_topics add column room_prompt text;
update public.coffee_voice_topics as topic
set room_description=coalesce(topic.room_description,seed.description),
    room_prompt=coalesce(topic.room_prompt,seed.prompt)
from (values
  ('room-chat','A gentle start, one cup at a time.','What makes your first cup feel special?'),
  ('room-learn','Small adjustments, better brews.','Which brewing detail would you change next?'),
  ('room-match','Compare recipes and pouring styles.','What is your favourite coffee-to-water ratio?'),
  ('room-vibe','Espresso and the flavours of the evening.','Which flavour would you pair with espresso?'),
  ('room-breeze','Books, pastries and a window-side cup.','What would you read with your next coffee?'),
  ('room-dream','Unhurried cups and little café discoveries.','Describe your ideal coffee break in one sentence.')
) as seed(id,description,prompt)
where topic.id=seed.id;
