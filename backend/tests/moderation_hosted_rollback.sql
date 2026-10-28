-- Execute only against the explicitly isolated Supabase validation project.
-- Uses synthetic rows inside a transaction that is always rolled back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $$
declare
  actor uuid;
  post_id uuid := gen_random_uuid(); comment_id uuid := gen_random_uuid();
  image_id uuid := gen_random_uuid(); report_id uuid := gen_random_uuid();
  event_post uuid := gen_random_uuid(); event_comment uuid := gen_random_uuid();
  event_image uuid := gen_random_uuid(); event_report uuid := gen_random_uuid();
  denied boolean;
begin
  if current_database() <> 'postgres' or current_setting('request.jwt.claims',true) <> '{"role":"service_role"}' then
    raise exception 'Unexpected fixture configuration';
  end if;
  select p.id into actor from public.coffee_profiles p
    join auth.users u on u.id=p.id where u.is_anonymous = true
    and p.id = 'f54333f3-d002-4853-ab80-637318ebfa64'::uuid;
  if actor is null then raise exception 'Synthetic test user is required'; end if;
  if has_function_privilege('anon','public.review_coffee_content(uuid,text,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.review_coffee_content(uuid,text,uuid,text,text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.review_coffee_profile_image(uuid,uuid,text,text,text)','EXECUTE') then
    raise exception 'Review functions must not be executable by client roles';
  end if;
  insert into public.coffee_posts(id,author_id,caption,media_path,media_kind)
    values(post_id,actor,'isolated moderation fixture',actor::text||'/moderation-fixture.jpg','photo');
  insert into public.coffee_comments(id,post_id,author_id,body) values(comment_id,post_id,actor,'isolated fixture');
  insert into public.coffee_profile_images(id,owner_id,kind,media_path)
    values(image_id,actor,'avatar',actor::text||'/moderation-avatar-'||image_id::text||'.jpg');
  insert into public.coffee_reports(id,reporter_id,subject_kind,subject_id,reason)
    values(report_id,actor,'post',post_id,'isolated fixture');
  if (select moderation_status from public.coffee_posts where id=post_id) <> 'pending'
     or (select moderation_status from public.coffee_comments where id=comment_id) <> 'pending'
     or (select moderation_status from public.coffee_profile_images where id=image_id) <> 'pending' then
    raise exception 'Submitted material should start pending';
  end if;
  perform public.review_coffee_content(event_post,'post',post_id,'approved','isolated-reviewer','fixture');
  perform public.review_coffee_content(event_post,'post',post_id,'approved','isolated-reviewer','fixture');
  perform public.review_coffee_content(event_comment,'comment',comment_id,'rejected','isolated-reviewer','fixture');
  perform public.review_coffee_profile_image(event_image,image_id,'approved','isolated-reviewer','fixture');
  perform public.review_coffee_content(event_report,'report',report_id,'resolved','isolated-reviewer','fixture');
  if (select moderation_status from public.coffee_posts where id=post_id) <> 'approved'
     or (select moderation_status from public.coffee_comments where id=comment_id) <> 'rejected'
     or (select moderation_status from public.coffee_profile_images where id=image_id) <> 'approved'
     or (select review_status from public.coffee_reports where id=report_id) <> 'resolved'
     or (select count(*) from papi_private.moderation_events where id in (event_post,event_comment,event_image,event_report)) <> 4 then
    raise exception 'Review result or idempotency mismatch';
  end if;
  denied := false;
  begin
    perform public.review_coffee_content(event_post,'post',post_id,'rejected','isolated-reviewer','fixture');
  exception when others then denied := true; end;
  if not denied or (select moderation_status from public.coffee_posts where id=post_id) <> 'approved' then
    raise exception 'Conflicting event reuse should be rejected';
  end if;
  -- Compare an approved post and a still-pending post for a different user.
  perform set_config('papi.test.approved_post',post_id::text,true);
  post_id := gen_random_uuid();
  insert into public.coffee_posts(id,author_id,caption,media_path,media_kind)
    values(post_id,actor,'isolated moderation fixture',actor::text||'/pending-'||post_id::text||'.jpg','photo');
  perform set_config('papi.test.pending_post',post_id::text,true);
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',u.id,'session_id',s.id)::text,true)
  from auth.users u join public.coffee_profiles p on p.id=u.id join auth.sessions s on s.user_id=u.id
  where u.is_anonymous and u.id <> 'f54333f3-d002-4853-ab80-637318ebfa64'::uuid
  order by u.id limit 1;
set local role authenticated;
do $$
declare denied boolean := false;
begin
  if coalesce((select auth.uid())::text,'') = '' then raise exception 'Second synthetic user session is required'; end if;
  if (select count(*) from public.coffee_posts where id=current_setting('papi.test.pending_post')::uuid) <> 0
     or (select count(*) from public.coffee_posts where id=current_setting('papi.test.approved_post')::uuid) <> 1 then
    raise exception 'Pending and approved post visibility mismatch';
  end if;
  begin
    perform public.review_coffee_content(gen_random_uuid(),'post',gen_random_uuid(),'approved','fixture','fixture');
  exception when insufficient_privilege then denied := true; end;
  if not denied then raise exception 'Authenticated clients must not review content'; end if;
end $$;
reset role;
rollback;
