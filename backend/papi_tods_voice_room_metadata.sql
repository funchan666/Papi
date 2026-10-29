-- Add the existing room artwork associations without replacing live topic data.
alter table public.coffee_voice_topics add column cover_asset text;
alter table public.coffee_voice_topics add column host_reference text;
update public.coffee_voice_topics as topic
set cover_asset=coalesce(topic.cover_asset,seed.cover_asset),
    host_reference=coalesce(topic.host_reference,seed.host_reference)
from (values
  ('room-chat','roomMorningArt','preview-member-0'),
  ('room-learn','roomBrewingArt','preview-member-1'),
  ('room-match','roomRecipeArt','preview-member-2'),
  ('room-vibe','roomEveningArt','preview-member-3'),
  ('room-breeze','roomWindowArt','preview-member-4'),
  ('room-dream','roomDreamArt','preview-member-5')
) as seed(id,cover_asset,host_reference)
where topic.id=seed.id;
