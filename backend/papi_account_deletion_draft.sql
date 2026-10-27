-- Draft only: do not deploy until purchase settlement, receipt recovery,
-- Storage concurrency, session revocation and operational retries are verified.
create table papi_private.account_deletions (
  owner_id uuid primary key,
  receipt_hash bytea not null unique,
  state text not null default 'requested' check (state in ('requested','complete')),
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
alter table papi_private.account_deletions enable row level security;
revoke all on papi_private.account_deletions from public,anon,authenticated;

-- Lock uploads and deletion on the same owner key. A stale JWT cannot add a
-- new object after deletion begins, even if it remains valid for a short time.
create function papi_private.coffee_upload_allowed() returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null then return false; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  return not exists(select 1 from papi_private.account_deletions d where d.owner_id=actor);
end;
$$;
revoke all on function papi_private.coffee_upload_allowed() from public,anon;
grant execute on function papi_private.coffee_upload_allowed() to authenticated;
create policy coffee_media_not_deleting on storage.objects as restrictive for insert to authenticated
  with check (bucket_id<>'coffee-media' or papi_private.coffee_upload_allowed());

create function papi_private.begin_coffee_deletion(p_secret text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); digest bytea;
begin
  if actor is null or p_secret is null or p_secret !~ '^[0-9a-f]{64}$' then raise exception 'Invalid deletion request'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('coffee-delete:' || actor::text,0));
  -- Unsettled orders require reconciliation before an account may be removed.
  if exists(select 1 from public.coffee_purchase_orders o where o.owner_id=actor and o.completed_at is null) then
    raise exception 'Purchase reconciliation required';
  end if;
  digest := extensions.digest(p_secret,'sha256');
  insert into papi_private.account_deletions(owner_id,receipt_hash) values(actor,digest)
    on conflict(owner_id) do update set receipt_hash=excluded.receipt_hash
      where papi_private.account_deletions.state='requested';
  return exists(select 1 from papi_private.account_deletions d where d.owner_id=actor and d.receipt_hash=digest);
end;
$$;
revoke all on function papi_private.begin_coffee_deletion(text) from public,anon;
grant execute on function papi_private.begin_coffee_deletion(text) to authenticated;
create function public.begin_coffee_deletion(p_secret text) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.begin_coffee_deletion(p_secret); $$;
revoke all on function public.begin_coffee_deletion(text) from public,anon;
grant execute on function public.begin_coffee_deletion(text) to authenticated;

create function public.coffee_deletion_work(p_secret text)
returns table(owner_id uuid,state text) language sql stable security definer set search_path = '' as $$
  select d.owner_id,d.state from papi_private.account_deletions d
   where coalesce((select auth.jwt())->>'role','')='service_role'
     and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256');
$$;
revoke all on function public.coffee_deletion_work(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_work(text) to service_role;

create function public.coffee_deletion_files(p_secret text)
returns table(name text) language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o join papi_private.account_deletions d on o.owner_id=d.owner_id::text
   where coalesce((select auth.jwt())->>'role','')='service_role' and d.state='requested'
     and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256')
     and o.bucket_id='coffee-media' order by o.name limit 100;
$$;
revoke all on function public.coffee_deletion_files(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_files(text) to service_role;

create function public.coffee_deletion_user_exists(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users u join papi_private.account_deletions d on d.owner_id=u.id
    where coalesce((select auth.jwt())->>'role','')='service_role'
      and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256'));
$$;
revoke all on function public.coffee_deletion_user_exists(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_user_exists(text) to service_role;

create function public.complete_coffee_deletion(p_secret text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid;
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_secret !~ '^[0-9a-f]{64}$' then raise exception 'Service authorization required'; end if;
  select d.owner_id into actor from papi_private.account_deletions d where d.receipt_hash=extensions.digest(p_secret,'sha256') for update;
  if not found then return false; end if;
  if exists(select 1 from auth.users u where u.id=actor) or
     exists(select 1 from storage.objects o where o.bucket_id='coffee-media' and o.owner_id=actor::text) then return false; end if;
  update papi_private.account_deletions set state='complete',completed_at=coalesce(completed_at,now()) where owner_id=actor;
  return true;
end;
$$;
revoke all on function public.complete_coffee_deletion(text) from public,anon,authenticated;
grant execute on function public.complete_coffee_deletion(text) to service_role;
