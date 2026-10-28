-- Interactions on Papi's first-party collection; the collection is not a user account.
create table papi_private.editorial_likes (
  content_id text not null, member_id uuid not null references public.coffee_profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(content_id,member_id)
);
create index editorial_likes_member_idx on papi_private.editorial_likes(member_id);
create table papi_private.editorial_comments (
  id uuid primary key, content_id text not null, author_id uuid not null references public.coffee_profiles(id) on delete cascade,
  body text not null check(char_length(btrim(body)) between 1 and 2000),
  moderation_status text not null default 'pending' check(moderation_status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create index editorial_comments_content_idx on papi_private.editorial_comments(content_id,created_at desc,id desc);
create index editorial_comments_author_idx on papi_private.editorial_comments(author_id);
create table papi_private.editorial_reports (
  id uuid primary key, reporter_id uuid not null references public.coffee_profiles(id) on delete cascade,
  content_id text not null, comment_id uuid references papi_private.editorial_comments(id) on delete set null,
  reason text not null check(char_length(btrim(reason)) between 1 and 500),
  review_status text not null default 'pending' check(review_status in ('pending','resolved')),
  created_at timestamptz not null default now()
);
create index editorial_reports_reporter_idx on papi_private.editorial_reports(reporter_id);
create index editorial_reports_pending_idx on papi_private.editorial_reports(created_at) where review_status='pending';
alter table papi_private.editorial_likes enable row level security;
alter table papi_private.editorial_comments enable row level security;
alter table papi_private.editorial_reports enable row level security;
revoke all on papi_private.editorial_likes,papi_private.editorial_comments,papi_private.editorial_reports from public,anon,authenticated;

create function papi_private.editorial_key_valid(p_key text) returns boolean language sql immutable set search_path='' as $$
 select p_key ~ '^editorial-(photo|video)-(0|[1-9][0-9]?)$' and case split_part(p_key,'-',2) when 'photo' then split_part(p_key,'-',3)::integer <= 30 when 'video' then split_part(p_key,'-',3)::integer <= 20 else false end;
$$;
revoke all on function papi_private.editorial_key_valid(text) from public,anon,authenticated;

create function papi_private.editorial_summary(p_keys text[])
returns table(content_id text,like_count bigint,comment_count bigint,liked boolean) language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if actor is null or not papi_private.coffee_actor_active() or coalesce(cardinality(p_keys),0)>100 then raise exception 'Unavailable'; end if;
 return query select k.key,(select count(*) from papi_private.editorial_likes l where l.content_id=k.key),
 (select count(*) from papi_private.editorial_comments c where c.content_id=k.key and (c.author_id=actor or c.moderation_status='approved') and papi_private.clear_pair(actor,c.author_id)
 and not exists(select 1 from papi_private.editorial_reports r where r.reporter_id=actor and r.comment_id=c.id)),
 exists(select 1 from papi_private.editorial_likes l where l.content_id=k.key and l.member_id=actor)
 from (select distinct unnest(p_keys) as key) k where papi_private.editorial_key_valid(k.key);
end; $$;
create function public.coffee_editorial_summary(p_keys text[]) returns table(content_id text,like_count bigint,comment_count bigint,liked boolean)
language sql stable security invoker set search_path='' as $$ select * from papi_private.editorial_summary(p_keys); $$;

create function papi_private.editorial_like(p_key text,p_enabled boolean) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if actor is null or p_enabled is null or not papi_private.editorial_key_valid(p_key) then raise exception 'Unavailable'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 if p_enabled then insert into papi_private.editorial_likes(content_id,member_id) values(p_key,actor) on conflict do nothing;
 else delete from papi_private.editorial_likes where content_id=p_key and member_id=actor; end if;
 return true;
end; $$;
create function public.set_coffee_editorial_like(p_key text,p_enabled boolean) returns boolean language sql security invoker set search_path='' as $$ select papi_private.editorial_like(p_key,p_enabled); $$;

create function papi_private.editorial_comment_page(p_key text) returns table(id uuid,content_id text,author_id uuid,body text,moderation_status text,created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if actor is null or not papi_private.coffee_actor_active() or not papi_private.editorial_key_valid(p_key) then raise exception 'Unavailable'; end if;
 return query select c.id,c.content_id,c.author_id,c.body,c.moderation_status,c.created_at from papi_private.editorial_comments c
 where c.content_id=p_key and (c.author_id=actor or c.moderation_status='approved') and papi_private.clear_pair(actor,c.author_id)
 and not exists(select 1 from papi_private.editorial_reports r where r.reporter_id=actor and r.comment_id=c.id)
 order by c.created_at desc,c.id desc limit 100;
end; $$;
create function public.coffee_editorial_comments(p_key text) returns table(id uuid,content_id text,author_id uuid,body text,moderation_status text,created_at timestamptz)
language sql stable security invoker set search_path='' as $$ select * from papi_private.editorial_comment_page(p_key); $$;

create function papi_private.editorial_send_comment(p_key text,p_id uuid,p_body text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); clean text:=btrim(p_body); prior papi_private.editorial_comments%rowtype;
begin
 if actor is null or p_id is null or not papi_private.editorial_key_valid(p_key) or clean is null or char_length(clean) not between 1 and 2000 then raise exception 'Invalid comment'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 select * into prior from papi_private.editorial_comments where id=p_id;
 if found then if prior.author_id<>actor or prior.content_id<>p_key or prior.body<>clean then raise exception 'Identifier already used'; end if; return p_id; end if;
 if (select count(*) from papi_private.editorial_comments where author_id=actor and created_at>now()-interval '10 seconds')>=5 then raise exception 'Please wait'; end if;
 insert into papi_private.editorial_comments(id,content_id,author_id,body) values(p_id,p_key,actor,clean); return p_id;
end; $$;
create function public.send_coffee_editorial_comment(p_key text,p_id uuid,p_body text) returns uuid language sql security invoker set search_path='' as $$ select papi_private.editorial_send_comment(p_key,p_id,p_body); $$;

create function papi_private.editorial_delete_comment(p_id uuid) returns boolean language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid());
begin
 if actor is null or p_id is null then raise exception 'Unavailable'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 delete from papi_private.editorial_comments where id=p_id and author_id=actor; return true;
end; $$;
create function public.delete_coffee_editorial_comment(p_id uuid) returns boolean language sql security invoker set search_path='' as $$ select papi_private.editorial_delete_comment(p_id); $$;

create function papi_private.editorial_report(p_id uuid,p_key text,p_comment uuid,p_reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid:=(select auth.uid()); prior papi_private.editorial_reports%rowtype;
begin
 if actor is null or p_id is null or not papi_private.editorial_key_valid(p_key) or p_reason is null or char_length(btrim(p_reason)) not between 1 and 500 then raise exception 'Invalid report'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:'||actor::text,0));
 if not papi_private.coffee_actor_active() then raise exception 'Unavailable'; end if;
 select * into prior from papi_private.editorial_reports where id=p_id;
 if found then if prior.reporter_id<>actor or prior.content_id<>p_key or prior.comment_id is distinct from p_comment or prior.reason<>p_reason then raise exception 'Identifier already used'; end if; return p_id; end if;
 if p_comment is not null and not exists(select 1 from papi_private.editorial_comments c where c.id=p_comment and c.content_id=p_key and (c.author_id=actor or c.moderation_status='approved') and papi_private.clear_pair(actor,c.author_id)) then raise exception 'Unavailable'; end if;
 insert into papi_private.editorial_reports(id,reporter_id,content_id,comment_id,reason) values(p_id,actor,p_key,p_comment,p_reason); return p_id;
end; $$;
create function public.report_coffee_editorial(p_id uuid,p_key text,p_comment uuid,p_reason text) returns uuid language sql security invoker set search_path='' as $$ select papi_private.editorial_report(p_id,p_key,p_comment,p_reason); $$;

-- Only the trusted moderation service can read/review the private queue.
create function papi_private.review_editorial_comment(p_id uuid,p_outcome text) returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_outcome not in ('approved','rejected') then raise exception 'Unavailable'; end if;
 update papi_private.editorial_comments set moderation_status=p_outcome where id=p_id; return found;
end; $$;
create function public.review_coffee_editorial_comment(p_id uuid,p_outcome text) returns boolean language sql security invoker set search_path='' as $$ select papi_private.review_editorial_comment(p_id,p_outcome); $$;
revoke all on function papi_private.review_editorial_comment(uuid,text),public.review_coffee_editorial_comment(uuid,text) from public,anon,authenticated;
grant execute on function papi_private.review_editorial_comment(uuid,text),public.review_coffee_editorial_comment(uuid,text) to service_role;

revoke all on function papi_private.editorial_summary(text[]),papi_private.editorial_like(text,boolean),papi_private.editorial_comment_page(text),papi_private.editorial_send_comment(text,uuid,text),papi_private.editorial_delete_comment(uuid),papi_private.editorial_report(uuid,text,uuid,text),public.coffee_editorial_summary(text[]),public.set_coffee_editorial_like(text,boolean),public.coffee_editorial_comments(text),public.send_coffee_editorial_comment(text,uuid,text),public.delete_coffee_editorial_comment(uuid),public.report_coffee_editorial(uuid,text,uuid,text) from public,anon;
grant execute on function papi_private.editorial_summary(text[]),papi_private.editorial_like(text,boolean),papi_private.editorial_comment_page(text),papi_private.editorial_send_comment(text,uuid,text),papi_private.editorial_delete_comment(uuid),papi_private.editorial_report(uuid,text,uuid,text),public.coffee_editorial_summary(text[]),public.set_coffee_editorial_like(text,boolean),public.coffee_editorial_comments(text),public.send_coffee_editorial_comment(text,uuid,text),public.delete_coffee_editorial_comment(uuid),public.report_coffee_editorial(uuid,text,uuid,text) to authenticated;
