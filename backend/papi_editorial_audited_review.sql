-- A trusted reviewer can retry a specific decision without applying it twice.
create table papi_private.editorial_moderation_events (
  id uuid primary key,
  subject_kind text not null check (subject_kind in ('comment','report')),
  subject_id uuid not null,
  decision text not null,
  reviewer text not null check (char_length(btrim(reviewer)) between 1 and 120),
  note text not null check (char_length(btrim(note)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index editorial_moderation_subject_idx on papi_private.editorial_moderation_events(subject_kind,subject_id,created_at desc);
alter table papi_private.editorial_moderation_events enable row level security;
revoke all on papi_private.editorial_moderation_events from public,anon,authenticated;

create function papi_private.review_editorial(
  event_id uuid,kind text,subject uuid,outcome text,reviewer_name text,review_note text
) returns void language plpgsql security definer set search_path='' as $$
declare prior papi_private.editorial_moderation_events%rowtype;
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' then raise exception 'Service authorization required'; end if;
  if event_id is null or subject is null or kind is null or outcome is null or
     reviewer_name is null or char_length(btrim(reviewer_name)) not between 1 and 120 or
     review_note is null or char_length(btrim(review_note)) not between 1 and 2000 or
     not ((kind='comment' and outcome in ('approved','rejected')) or (kind='report' and outcome='resolved')) then
    raise exception 'Invalid review';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('papi-editorial-review:'||event_id::text,0));
  select * into prior from papi_private.editorial_moderation_events e where e.id=event_id;
  if found then
    if prior.subject_kind<>kind or prior.subject_id<>subject or prior.decision<>outcome or
       prior.reviewer<>reviewer_name or prior.note<>review_note then raise exception 'Review identifier already used'; end if;
    return;
  end if;
  if kind='comment' then
    update papi_private.editorial_comments c set moderation_status=outcome where c.id=subject;
  else
    update papi_private.editorial_reports r set review_status=outcome where r.id=subject;
  end if;
  if not found then raise exception 'Review subject unavailable'; end if;
  insert into papi_private.editorial_moderation_events(id,subject_kind,subject_id,decision,reviewer,note)
  values(event_id,kind,subject,outcome,reviewer_name,review_note);
end; $$;
revoke all on function papi_private.review_editorial(uuid,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function papi_private.review_editorial(uuid,text,uuid,text,text,text) to service_role;
create function public.review_coffee_editorial(event_id uuid,kind text,subject uuid,outcome text,reviewer_name text,review_note text)
returns void language sql security invoker set search_path='' as $$
  select papi_private.review_editorial(event_id,kind,subject,outcome,reviewer_name,review_note);
$$;
revoke all on function public.review_coffee_editorial(uuid,text,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.review_coffee_editorial(uuid,text,uuid,text,text,text) to service_role;
