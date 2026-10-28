-- Restore reported collection posts after switching devices.
alter table papi_private.editorial_reports drop constraint if exists editorial_reports_comment_id_fkey;
alter table papi_private.editorial_reports add column if not exists comment_excerpt text;
create or replace function papi_private.editorial_report(p_id uuid,p_key text,p_comment uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); prior papi_private.editorial_reports%rowtype;
begin
 if actor is null or p_id is null or not papi_private.editorial_key_valid(p_key) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then raise exception 'Invalid report'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 select * into prior from papi_private.editorial_reports where id=p_id;
 if found then if prior.reporter_id<>actor or prior.content_id<>p_key or prior.comment_id is distinct from p_comment or prior.reason<>p_reason then raise exception 'Identifier already used'; end if; return p_id; end if;
 if p_comment is not null and not exists(select 1 from papi_private.editorial_comments c where c.id=p_comment and c.content_id=p_key and (c.author_id=actor or c.moderation_status='approved') and papi_private.clear_pair(actor,c.author_id)) then raise exception 'Unavailable'; end if;
 insert into papi_private.editorial_reports(id,reporter_id,content_id,comment_id,comment_excerpt,reason)
 values(p_id,actor,p_key,p_comment,(select c.body from papi_private.editorial_comments c where c.id=p_comment),p_reason); return p_id;
end; $$;
create function papi_private.editorial_reported_posts() returns table(content_id text)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if actor is null or not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 return query select distinct r.content_id from papi_private.editorial_reports r where r.reporter_id=actor and r.comment_id is null;
end; $$;
create function public.coffee_editorial_reported_posts() returns table(content_id text)
language sql stable security invoker set search_path='' as $$ select * from papi_private.editorial_reported_posts(); $$;
revoke all on function papi_private.editorial_reported_posts(),public.coffee_editorial_reported_posts() from public,anon;
grant execute on function papi_private.editorial_reported_posts(),public.coffee_editorial_reported_posts() to authenticated;

create or replace function papi_private.review_editorial_comment(p_id uuid,p_outcome text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_outcome not in ('approved','rejected') then raise exception 'Unavailable'; end if;
 update papi_private.editorial_comments set moderation_status=p_outcome where id=p_id;
 if not found then return false; end if;
 insert into papi_private.moderation_events(id,subject_kind,subject_id,decision,reviewer,note)
 values(gen_random_uuid(),'comment',p_id,p_outcome,'trusted moderation service','Collection comment reviewed');
 return true;
end; $$;
create function papi_private.review_editorial_report(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Unavailable'; end if;
 update papi_private.editorial_reports set review_status='resolved' where id=p_id and review_status='pending';
 if not found then return false; end if;
 insert into papi_private.moderation_events(id,subject_kind,subject_id,decision,reviewer,note)
 values(gen_random_uuid(),'report',p_id,'resolved','trusted moderation service','Collection report reviewed');
 return true;
end; $$;
create function public.review_coffee_editorial_report(p_id uuid) returns boolean language sql security invoker set search_path='' as $$ select papi_private.review_editorial_report(p_id); $$;
revoke all on function papi_private.review_editorial_report(uuid),public.review_coffee_editorial_report(uuid) from public,anon,authenticated;
grant execute on function papi_private.review_editorial_report(uuid),public.review_coffee_editorial_report(uuid) to service_role;
