-- Reports must point to content the reporter can actually see under RLS.
alter policy reports_create on public.coffee_reports to authenticated with check (
  reporter_id = (select auth.uid()) and case subject_kind
    when 'profile' then exists (select 1 from public.coffee_profiles x where x.id = subject_id)
    when 'post' then exists (select 1 from public.coffee_posts x where x.id = subject_id)
    when 'comment' then exists (select 1 from public.coffee_comments x where x.id = subject_id)
    when 'message' then exists (select 1 from public.coffee_messages x where x.id = subject_id)
    else false end
);

alter table public.coffee_reports add column review_status text not null default 'pending'
  check (review_status in ('pending', 'resolved'));
alter table public.coffee_reports add column reviewed_at timestamptz;
create index coffee_reports_pending_idx on public.coffee_reports(created_at) where review_status = 'pending';

-- This log is not exposed to app clients. The operator identifier describes
-- the actual reviewer; it must be supplied by the trusted moderation service.
create table papi_private.moderation_events (
  id uuid primary key,
  subject_kind text not null check (subject_kind in ('post', 'comment', 'report')),
  subject_id uuid not null,
  decision text not null,
  reviewer text not null check (char_length(trim(reviewer)) between 1 and 120),
  note text not null check (char_length(trim(note)) between 1 and 2000),
  created_at timestamptz not null default now()
);
alter table papi_private.moderation_events enable row level security;
revoke all on papi_private.moderation_events from public, anon, authenticated;

create function papi_private.review_content(event_id uuid, kind text, subject uuid,
  outcome text, reviewer_name text, review_note text) returns void
language plpgsql security definer set search_path = ''
as $$
declare prior papi_private.moderation_events%rowtype;
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'Service authorization required';
  end if;
  if event_id is null or subject is null or kind is null or outcome is null or
     reviewer_name is null or char_length(trim(reviewer_name)) not between 1 and 120 or
     review_note is null or char_length(trim(review_note)) not between 1 and 2000 or
     not ((kind in ('post', 'comment') and outcome in ('approved', 'rejected')) or
          (kind = 'report' and outcome = 'resolved')) then
    raise exception 'Invalid review';
  end if;
  if kind = 'post' then
    perform 1 from public.coffee_posts where id = subject for update;
  elsif kind = 'comment' then
    perform 1 from public.coffee_comments where id = subject for update;
  else
    perform 1 from public.coffee_reports where id = subject for update;
  end if;
  if not found then raise exception 'Review subject unavailable'; end if;
  select * into prior from papi_private.moderation_events where id = event_id;
  if found then
    if prior.subject_kind <> kind or prior.subject_id <> subject or prior.decision <> outcome or
       prior.reviewer <> reviewer_name or prior.note <> review_note then
      raise exception 'Review identifier already used';
    end if;
    return;
  end if;
  if kind = 'post' then
    update public.coffee_posts set moderation_status = outcome where id = subject;
  elsif kind = 'comment' then
    update public.coffee_comments set moderation_status = outcome where id = subject;
  else
    update public.coffee_reports set review_status = outcome, reviewed_at = now() where id = subject;
  end if;
  insert into papi_private.moderation_events (id, subject_kind, subject_id, decision, reviewer, note)
    values (event_id, kind, subject, outcome, reviewer_name, review_note);
end;
$$;
revoke all on function papi_private.review_content(uuid,text,uuid,text,text,text) from public, anon, authenticated;
grant execute on function papi_private.review_content(uuid,text,uuid,text,text,text) to service_role;

create function public.review_coffee_content(event_id uuid, kind text, subject uuid,
  outcome text, reviewer_name text, review_note text) returns void
language sql security invoker set search_path = ''
as $$ select papi_private.review_content(event_id, kind, subject, outcome, reviewer_name, review_note); $$;
revoke all on function public.review_coffee_content(uuid,text,uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.review_coffee_content(uuid,text,uuid,text,text,text) to service_role;
