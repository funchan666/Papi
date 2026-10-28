-- Deployed atomically with the deletion guard policies; deletion remains off.
-- Preserve existing signatures, caller privileges, volatility and result values.
-- Write triggers serialize mutations; an already-started read can race deletion.
create function papi_private.require_coffee_actor_active() returns void
language plpgsql stable security invoker set search_path = '' as $$
begin
  if not papi_private.coffee_actor_active() then raise exception 'Account unavailable'; end if;
end;
$$;
revoke all on function papi_private.require_coffee_actor_active() from public,anon;
grant execute on function papi_private.require_coffee_actor_active() to authenticated;

create or replace function public.answer_coffee_call(p_id uuid, p_accept boolean) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.answer_coffee_call(p_id,p_accept);
end;
$$;

create or replace function public.answer_coffee_friendship(p_id uuid, p_accept boolean) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.answer_coffee_friendship(p_id,p_accept);
end;
$$;

create or replace function public.can_join_coffee_call(p_id uuid) returns boolean
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.can_join_coffee_call(p_id);
end;
$$;

create or replace function public.can_join_coffee_voice(p_topic text, p_session uuid) returns boolean
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.can_join_coffee_voice(p_topic,p_session);
end;
$$;

create or replace function public.cancel_coffee_friendship(p_id uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.cancel_coffee_friendship(p_id);
end;
$$;

create or replace function public.check_in_coffee() returns jsonb
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.daily_checkin();
end;
$$;

create or replace function public.collect_coffee_item(order_id uuid, item text, item_quantity integer) returns bigint
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.collect_item(order_id,item,item_quantity);
end;
$$;

create or replace function public.end_coffee_call(p_id uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.end_coffee_call(p_id);
end;
$$;

create or replace function public.enter_coffee_voice(p_topic text, p_session uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.enter_coffee_voice(p_topic,p_session);
end;
$$;

create or replace function public.heartbeat_coffee_voice(p_topic text, p_session uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.heartbeat_coffee_voice(p_topic,p_session);
end;
$$;

create or replace function public.leave_coffee_voice(p_topic text, p_session uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.leave_coffee_voice(p_topic,p_session);
end;
$$;

create or replace function public.remove_coffee_post(post_id uuid) returns text
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.remove_coffee_post(post_id);
end;
$$;

create or replace function public.remove_coffee_profile_image(p_id uuid) returns text
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.remove_profile_image(p_id);
end;
$$;

create or replace function public.removed_coffee_media_exists(p_path text) returns boolean
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.removed_media_exists(p_path);
end;
$$;

create or replace function public.removed_profile_media_exists(p_id uuid) returns boolean
language plpgsql stable security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.profile_removed_media_exists(p_id);
end;
$$;

create or replace function public.request_coffee_call(p_id uuid, p_recipient uuid) returns uuid
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.request_coffee_call(p_id,p_recipient);
end;
$$;

create or replace function public.request_coffee_friendship(p_id uuid, p_recipient uuid) returns uuid
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.request_coffee_friendship(p_id,p_recipient);
end;
$$;

create or replace function public.reserve_coffee_call_token(p_id uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.reserve_coffee_call_token(p_id);
end;
$$;

create or replace function public.reserve_coffee_voice_token(p_topic text, p_session uuid) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.reserve_coffee_voice_token(p_topic,p_session);
end;
$$;

create or replace function public.save_coffee_brew_book(p_request uuid, p_revision bigint, p_contents jsonb) returns jsonb
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.save_brew_book(p_request,p_revision,p_contents);
end;
$$;

create or replace function public.send_coffee_attachment(p_id uuid, p_recipient uuid, p_kind text) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.send_coffee_attachment(p_id,p_recipient,p_kind);
end;
$$;

create or replace function public.send_coffee_message(p_id uuid, p_recipient uuid, p_body text) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.send_coffee_message(p_id,p_recipient,p_body);
end;
$$;

create or replace function public.set_coffee_block(p_member uuid, p_enabled boolean) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.set_coffee_block(p_member,p_enabled);
end;
$$;

create or replace function public.set_coffee_follow(p_member uuid, p_enabled boolean) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.set_coffee_follow(p_member,p_enabled);
end;
$$;

create or replace function public.submit_coffee_moment(moment_id uuid, caption text, media_path text, media_kind text) returns bigint
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.submit_moment(moment_id,caption,media_path,media_kind);
end;
$$;

create or replace function public.submit_coffee_profile_image(p_id uuid, p_kind text) returns boolean
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.submit_profile_image(p_id,p_kind);
end;
$$;

create or replace function public.unlock_coffee_recipe(recipe text) returns bigint
language plpgsql security invoker set search_path = '' as $$
begin
  perform papi_private.require_coffee_actor_active();
  return papi_private.unlock_recipe(recipe);
end;
$$;
