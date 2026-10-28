-- Run only on Papi-Isolated-Validation. All fixture changes roll back.
begin;
do $$
declare a uuid; b uuid; c uuid; sa uuid; sb uuid; sc uuid; va uuid:=gen_random_uuid(); vb uuid:=gen_random_uuid(); vc uuid:=gen_random_uuid();
begin
  select u.id,s.id into a,sa from auth.users u join auth.sessions s on s.user_id=u.id
    join public.coffee_profiles p on p.id=u.id
    where (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id)
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=u.id) order by u.id limit 1;
  select u.id,s.id into b,sb from auth.users u join auth.sessions s on s.user_id=u.id
    join public.coffee_profiles p on p.id=u.id
    where u.id<>a and (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id)
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=u.id) order by u.id limit 1;
  select u.id,s.id into c,sc from auth.users u join auth.sessions s on s.user_id=u.id
    join public.coffee_profiles p on p.id=u.id
    where u.id not in (a,b) and (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id)
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=u.id) order by u.id limit 1;
  if a is null or b is null or c is null then raise exception 'Three isolated test sessions required'; end if;
  update papi_private.voice_runtime_config set enabled=true where singleton;
  insert into papi_private.voice_members(owner_id,topic_id,session_id) values(a,'room-chat',va),(b,'room-chat',vb),(c,'room-learn',vc);
  perform set_config('papi.test.a',a::text,true); perform set_config('papi.test.b',b::text,true); perform set_config('papi.test.c',c::text,true);
  perform set_config('papi.test.sa',sa::text,true); perform set_config('papi.test.sb',sb::text,true); perform set_config('papi.test.sc',sc::text,true);
  perform set_config('papi.test.va',va::text,true); perform set_config('papi.test.vb',vb::text,true); perform set_config('papi.test.vc',vc::text,true);
  perform set_config('papi.test.msg',gen_random_uuid()::text,true);
  if has_table_privilege('authenticated','papi_private.voice_messages','SELECT') or has_function_privilege('anon','public.send_coffee_voice_message(text,uuid,uuid,text)','EXECUTE') then
    raise exception 'Public access to room messages';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.a'),'session_id',current_setting('papi.test.sa'))::text,true);
do $$
declare mid uuid:=current_setting('papi.test.msg')::uuid; sid uuid:=current_setting('papi.test.va')::uuid; denied boolean:=false; i integer;
begin
  perform public.send_coffee_voice_message('room-chat',sid,mid,'A coffee message');
  perform public.send_coffee_voice_message('room-chat',sid,mid,'A coffee message');
  begin perform public.send_coffee_voice_message('room-chat',sid,mid,'different'); exception when others then denied:=true; end;
  if not denied then raise exception 'Conflicting identifier accepted'; end if;
  if (select count(*) from public.coffee_voice_messages('room-chat',sid) where id=mid)<>1 then raise exception 'Own message not visible'; end if;
  for i in 1..4 loop perform public.send_coffee_voice_message('room-chat',sid,gen_random_uuid(),'another message'); end loop;
  denied:=false; begin perform public.send_coffee_voice_message('room-chat',sid,gen_random_uuid(),'rate test'); exception when others then denied:=true; end;
  if not denied then raise exception 'Message rate limit missing'; end if;
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ begin
 if (select count(*) from public.coffee_voice_messages('room-chat',current_setting('papi.test.vb')::uuid) where id=current_setting('papi.test.msg')::uuid)<>1 then raise exception 'Room member cannot see message'; end if;
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.c'),'session_id',current_setting('papi.test.sc'))::text,true);
do $$ declare denied boolean:=false; begin
  begin perform public.coffee_voice_messages('room-chat',current_setting('papi.test.vc')::uuid); exception when others then denied:=true; end;
  if not denied then raise exception 'Other room can read messages'; end if;
  denied:=false; begin perform public.send_coffee_voice_message('room-chat',current_setting('papi.test.vc')::uuid,gen_random_uuid(),'cross room'); exception when others then denied:=true; end;
  if not denied then raise exception 'Other room can send messages'; end if;
end $$;
reset role;
insert into public.coffee_blocks(blocker_id,blocked_id) values(current_setting('papi.test.b')::uuid,current_setting('papi.test.a')::uuid) on conflict do nothing;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ begin
 if (select count(*) from public.coffee_voice_messages('room-chat',current_setting('papi.test.vb')::uuid) where id=current_setting('papi.test.msg')::uuid)<>0 then raise exception 'Blocked sender visible'; end if;
end $$;
reset role;
rollback;
