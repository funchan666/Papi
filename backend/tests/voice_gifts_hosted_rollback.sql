-- Run only on Papi-Isolated-Validation; fixture changes always roll back.
begin;
do $$
declare a uuid; b uuid; sa uuid; sb uuid; va uuid:=gen_random_uuid(); vb uuid:=gen_random_uuid();
begin
  select u.id,s.id into a,sa from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id
    where (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id)
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=u.id) order by u.id limit 1;
  select u.id,s.id into b,sb from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id
    where u.id<>a and (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id)
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=u.id) order by u.id limit 1;
  if a is null or b is null then raise exception 'Two isolated test sessions required'; end if;
  update papi_private.voice_runtime_config set enabled=true where singleton;
  update public.coffee_wallets set balance=1000 where owner_id=a;
  insert into papi_private.voice_members(owner_id,topic_id,session_id) values(a,'room-chat',va),(b,'room-chat',vb);
  perform set_config('papi.test.a',a::text,true);perform set_config('papi.test.b',b::text,true);
  perform set_config('papi.test.sa',sa::text,true);perform set_config('papi.test.sb',sb::text,true);
  perform set_config('papi.test.va',va::text,true);perform set_config('papi.test.vb',vb::text,true);
  perform set_config('papi.test.gift',gen_random_uuid()::text,true);perform set_config('papi.test.cancel',gen_random_uuid()::text,true);
  perform set_config('papi.test.insufficient',gen_random_uuid()::text,true);
  if has_table_privilege('authenticated','papi_private.voice_gift_orders','SELECT') or has_function_privilege('anon','public.send_coffee_voice_gift(text,uuid,uuid,text,integer,boolean)','EXECUTE') then raise exception 'Gift access exposed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.a'),'session_id',current_setting('papi.test.sa'))::text,true);
do $$
declare got record; denied boolean:=false; sid uuid:=current_setting('papi.test.va')::uuid;
begin
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.gift')::uuid,'love',1,false);
 if got.status<>'settled' or got.balance<>920 then raise exception 'Gift debit mismatch'; end if;
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.gift')::uuid,'love',1,false);
 if got.status<>'settled' or got.balance<>920 then raise exception 'Gift retry charged twice'; end if;
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.gift')::uuid,'love',1,true);
 if got.status<>'settled' or got.balance<>920 then raise exception 'Committed gift cancelled'; end if;
 begin perform public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.gift')::uuid,'peach',1,false); exception when others then denied:=true; end;
 if not denied then raise exception 'Conflicting gift identifier accepted'; end if;
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.cancel')::uuid,'love',1,true);
 if got.status<>'cancelled' or got.balance<>920 then raise exception 'Cancellation failed'; end if;
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.cancel')::uuid,'love',1,false);
 if got.status<>'cancelled' or got.balance<>920 then raise exception 'Delayed request charged after cancellation'; end if;
 select * into got from public.send_coffee_voice_gift('room-chat',sid,current_setting('papi.test.insufficient')::uuid,'crown',1,false);
 if got.status<>'insufficient' or got.balance<>920 then raise exception 'Insufficient balance handling failed'; end if;
end $$;
reset role;
update public.coffee_wallets set balance=2000 where owner_id=current_setting('papi.test.a')::uuid;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.a'),'session_id',current_setting('papi.test.sa'))::text,true);
do $$ declare got record; begin
 select * into got from public.send_coffee_voice_gift('room-chat',current_setting('papi.test.va')::uuid,current_setting('papi.test.insufficient')::uuid,'crown',1,false);
 if got.status<>'insufficient' or got.balance<>2000 then raise exception 'Rejected order later charged'; end if;
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ begin
 if (select count(*) from public.coffee_voice_gifts('room-chat',current_setting('papi.test.vb')::uuid) where id=current_setting('papi.test.gift')::uuid)<>1 then raise exception 'Gift not visible to participant'; end if;
 if (select count(*) from public.coffee_voice_gifts('room-chat',current_setting('papi.test.vb')::uuid) where id in (current_setting('papi.test.cancel')::uuid,current_setting('papi.test.insufficient')::uuid))<>0 then raise exception 'Rejected gift visible'; end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.coffee_wallet_movements where owner_id=current_setting('papi.test.a')::uuid and idempotency_key='voice-gift-'||current_setting('papi.test.gift'))<>1 then raise exception 'Wallet movement mismatch'; end if;
end $$;
rollback;
