-- Isolated project only. All records and decisions roll back.
begin;
do $$
declare a uuid; b uuid; cid uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid(); eid uuid:=gen_random_uuid(); report_event uuid:=gen_random_uuid();
begin
 select p.id into a from public.coffee_profiles p join auth.users u on u.id=p.id order by p.id limit 1;
 select p.id into b from public.coffee_profiles p join auth.users u on u.id=p.id where p.id<>a order by p.id limit 1;
 if a is null or b is null then raise exception 'Two isolated users required'; end if;
 insert into papi_private.editorial_comments(id,content_id,author_id,body) values(cid,'editorial-video-1',a,'Review fixture');
 insert into papi_private.editorial_reports(id,reporter_id,content_id,comment_id,comment_author_id,comment_excerpt,reason)
 values(rid,b,'editorial-video-1',cid,a,'Review fixture','Harassment or hate');
 perform set_config('papi.test.cid',cid::text,true);perform set_config('papi.test.rid',rid::text,true);
 perform set_config('papi.test.eid',eid::text,true);perform set_config('papi.test.reid',report_event::text,true);
 if has_function_privilege('anon','public.review_coffee_editorial(uuid,text,uuid,text,text,text)','EXECUTE') or
    has_function_privilege('authenticated','public.review_coffee_editorial(uuid,text,uuid,text,text,text)','EXECUTE') or
    has_table_privilege('authenticated','papi_private.editorial_moderation_events','SELECT') then raise exception 'Review access exposed'; end if;
end $$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$
declare eid uuid:=current_setting('papi.test.eid')::uuid; cid uuid:=current_setting('papi.test.cid')::uuid; denied boolean:=false;
begin
 perform public.review_coffee_editorial(eid,'comment',cid,'approved','isolated reviewer','Reviewed the fixture');
 perform public.review_coffee_editorial(eid,'comment',cid,'approved','isolated reviewer','Reviewed the fixture');
 begin perform public.review_coffee_editorial(eid,'comment',cid,'rejected','isolated reviewer','Reviewed the fixture'); exception when others then denied:=true; end;
 if not denied then raise exception 'Conflicting review identifier accepted'; end if;
 perform public.review_coffee_editorial(current_setting('papi.test.reid')::uuid,'report',current_setting('papi.test.rid')::uuid,'resolved','isolated reviewer','Resolved the fixture');
end $$;
reset role;
do $$ begin
 if (select moderation_status from papi_private.editorial_comments where id=current_setting('papi.test.cid')::uuid)<>'approved' then raise exception 'Comment review failed'; end if;
 if (select review_status from papi_private.editorial_reports where id=current_setting('papi.test.rid')::uuid)<>'resolved' then raise exception 'Report resolution failed'; end if;
 if (select count(*) from papi_private.editorial_moderation_events where id in (current_setting('papi.test.eid')::uuid,current_setting('papi.test.reid')::uuid))<>2 then raise exception 'Review was not idempotent'; end if;
end $$;
rollback;
