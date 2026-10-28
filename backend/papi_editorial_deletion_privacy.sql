-- Preserve a report snapshot for review while the author retains an account.
alter table papi_private.editorial_reports add column if not exists comment_author_id uuid;
create index editorial_reports_comment_author_idx on papi_private.editorial_reports(comment_author_id) where comment_author_id is not null;
update papi_private.editorial_reports r set comment_author_id=c.author_id
from papi_private.editorial_comments c where r.comment_id=c.id and r.comment_author_id is null;
create or replace function papi_private.editorial_report(p_id uuid,p_key text,p_comment uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); prior papi_private.editorial_reports%rowtype;
begin
 if actor is null or p_id is null or not papi_private.editorial_key_valid(p_key) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then raise exception 'Invalid report'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 select * into prior from papi_private.editorial_reports where id=p_id;
 if found then if prior.reporter_id<>actor or prior.content_id<>p_key or prior.comment_id is distinct from p_comment or prior.reason<>p_reason then raise exception 'Identifier already used'; end if; return p_id; end if;
 if p_comment is not null and not exists(select 1 from papi_private.editorial_comments c where c.id=p_comment and c.content_id=p_key and (c.author_id=actor or c.moderation_status='approved') and papi_private.clear_pair(actor,c.author_id)) then raise exception 'Unavailable'; end if;
 insert into papi_private.editorial_reports(id,reporter_id,content_id,comment_id,comment_author_id,comment_excerpt,reason)
 values(p_id,actor,p_key,p_comment,(select c.author_id from papi_private.editorial_comments c where c.id=p_comment),(select c.body from papi_private.editorial_comments c where c.id=p_comment),p_reason); return p_id;
end; $$;
-- Account deletion must not retain comment text or a link to the removed author
-- inside reports created by other people. The report itself remains for review.
create function papi_private.clear_deleted_editorial_author() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update papi_private.editorial_reports set comment_author_id=null,comment_excerpt=null
 where comment_author_id=old.id;
 return old;
end; $$;
revoke all on function papi_private.clear_deleted_editorial_author() from public,anon,authenticated;
create trigger coffee_clear_editorial_report_author before delete on public.coffee_profiles
for each row execute function papi_private.clear_deleted_editorial_author();
