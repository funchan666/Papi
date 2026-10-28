-- Isolated environment only; no fixture changes survive rollback.
begin;
do $$
declare a uuid; b uuid; sa uuid; sb uuid;
begin
 select u.id,s.id into a,sa from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id where (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id) order by u.id limit 1;
 select u.id,s.id into b,sb from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id where u.id<>a and (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id) order by u.id limit 1;
 if a is null or b is null then raise exception 'Two isolated sessions required'; end if;
 perform set_config('papi.test.a',a::text,true);perform set_config('papi.test.b',b::text,true);
 perform set_config('papi.test.sa',sa::text,true);perform set_config('papi.test.sb',sb::text,true);
 perform set_config('papi.test.comment',gen_random_uuid()::text,true);perform set_config('papi.test.report',gen_random_uuid()::text,true);
 if has_table_privilege('authenticated','papi_private.editorial_comments','SELECT') or has_function_privilege('anon','public.send_coffee_editorial_comment(text,uuid,text)','EXECUTE') then raise exception 'Editorial data exposed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.a'),'session_id',current_setting('papi.test.sa'))::text,true);
do $$ declare denied boolean:=false; cid uuid:=current_setting('papi.test.comment')::uuid; begin
 perform public.set_coffee_editorial_like('editorial-video-1',true);
 perform public.set_coffee_editorial_like('editorial-video-1',true);
 if not exists(select 1 from public.coffee_editorial_summary(array['editorial-video-1']) where liked and like_count>=1) then raise exception 'Like unavailable'; end if;
 perform public.send_coffee_editorial_comment('editorial-video-1',cid,'An isolated comment');
 perform public.send_coffee_editorial_comment('editorial-video-1',cid,'An isolated comment');
 begin perform public.send_coffee_editorial_comment('editorial-video-1',cid,'Different text'); exception when others then denied:=true; end;
 if not denied then raise exception 'Conflicting retry accepted'; end if;
 if (select count(*) from public.coffee_editorial_comments('editorial-video-1') where id=cid and moderation_status='pending')<>1 then raise exception 'Own pending comment unavailable'; end if;
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ begin if exists(select 1 from public.coffee_editorial_comments('editorial-video-1') where id=current_setting('papi.test.comment')::uuid) then raise exception 'Pending comment exposed'; end if; end $$;
reset role;
update papi_private.editorial_comments set moderation_status='approved' where id=current_setting('papi.test.comment')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ declare cid uuid:=current_setting('papi.test.comment')::uuid; rid uuid:=current_setting('papi.test.report')::uuid; begin
 if not exists(select 1 from public.coffee_editorial_comments('editorial-video-1') where id=cid) then raise exception 'Approved comment missing'; end if;
 perform public.report_coffee_editorial(rid,'editorial-video-1',cid,'Harassment or hate');
 perform public.report_coffee_editorial(rid,'editorial-video-1',cid,'Harassment or hate');
 if exists(select 1 from public.coffee_editorial_comments('editorial-video-1') where id=cid) then raise exception 'Reported comment still visible'; end if;
 perform public.delete_coffee_editorial_comment(cid);
end $$;
reset role;
do $$ begin if not exists(select 1 from papi_private.editorial_comments where id=current_setting('papi.test.comment')::uuid) then raise exception 'Non-owner deleted comment'; end if; end $$;
do $$ begin
 if not exists(select 1 from papi_private.editorial_reports where id=current_setting('papi.test.report')::uuid and comment_excerpt='An isolated comment') then raise exception 'Report lacks review context'; end if;
end $$;
insert into public.coffee_blocks(blocker_id,blocked_id) values(current_setting('papi.test.b')::uuid,current_setting('papi.test.a')::uuid) on conflict do nothing;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ begin if exists(select 1 from public.coffee_editorial_comments('editorial-video-1') where author_id=current_setting('papi.test.a')::uuid) then raise exception 'Blocked author visible'; end if; end $$;
reset role;
rollback;
