-- ONLY Papi-Isolated-Validation. Mutations are rolled back, never production data.
begin;
do $$
declare a uuid; b uuid; sa uuid; sb uuid; idea uuid:=gen_random_uuid();
begin
 select u.id,s.id into a,sa from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id where (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id) order by u.id limit 1;
 select u.id,s.id into b,sb from auth.users u join auth.sessions s on s.user_id=u.id join public.coffee_profiles p on p.id=u.id where u.id<>a and (s.not_after is null or s.not_after>now()) and not exists(select 1 from papi_private.account_deletions d where d.owner_id=u.id) order by u.id limit 1;
 if a is null or b is null then raise exception 'Two isolated sessions required'; end if;
 perform set_config('papi.test.a',a::text,true); perform set_config('papi.test.b',b::text,true);
 perform set_config('papi.test.sa',sa::text,true); perform set_config('papi.test.sb',sb::text,true); perform set_config('papi.test.idea',idea::text,true);
 insert into public.coffee_collectibles(owner_id,collectible_id,quantity) values(a,'love',1) on conflict(owner_id,collectible_id) do nothing;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.a'),'session_id',current_setting('papi.test.sa'))::text,true);
do $$ declare rejected boolean:=false; idea uuid:=current_setting('papi.test.idea')::uuid; begin
 perform public.set_saved_coffee_scene('home-espresso-corner',true);
 if not exists(select 1 from public.coffee_saved_scenes where scene_id='home-espresso-corner') then raise exception 'Own saved scene missing'; end if;
 perform public.set_coffee_displayed_gift('love');
 if not exists(select 1 from public.coffee_displayed_gifts where gift_id='love') then raise exception 'Own displayed gift missing'; end if;
 begin perform public.set_coffee_displayed_gift('unknown-gift'); exception when others then rejected:=true; end;
 if not rejected then raise exception 'Unowned gift accepted'; end if;
 perform public.save_coffee_gift_idea(idea,'love',2,'fixture');
 perform public.save_coffee_gift_idea(idea,'love',2,'fixture');
 if (select count(*) from public.coffee_gift_ideas where id=idea)<>1 then raise exception 'Gift idea retry mismatch'; end if;
 rejected:=false;
 begin perform public.save_coffee_gift_idea(idea,'love',3,'fixture'); exception when others then rejected:=true; end;
 if not rejected then raise exception 'Conflicting idea accepted'; end if;
 perform public.record_coffee_room_visit('room-chat');
 if not exists(select 1 from public.coffee_recent_voice_rooms where topic_id='room-chat') then raise exception 'Visit missing'; end if;
end $$;
select set_config('request.jwt.claims',json_build_object('role','authenticated','sub',current_setting('papi.test.b'),'session_id',current_setting('papi.test.sb'))::text,true);
do $$ declare rejected boolean:=false; begin
 if exists(select 1 from public.coffee_saved_scenes where owner_id=current_setting('papi.test.a')::uuid) or
    exists(select 1 from public.coffee_displayed_gifts where owner_id=current_setting('papi.test.a')::uuid) or
    exists(select 1 from public.coffee_gift_ideas where id=current_setting('papi.test.idea')::uuid) or
    exists(select 1 from public.coffee_recent_voice_rooms where owner_id=current_setting('papi.test.a')::uuid) then raise exception 'Cross-account data exposed'; end if;
 begin perform public.save_coffee_gift_idea(current_setting('papi.test.idea')::uuid,'love',2,'fixture'); exception when others then rejected:=true; end;
 if not rejected then raise exception 'Another account reused idea ID'; end if;
end $$;
rollback;
