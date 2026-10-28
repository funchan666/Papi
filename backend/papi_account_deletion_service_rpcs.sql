-- Service-only receipt and status operations. Deletion remains disabled.
grant usage on schema papi_private to service_role;
create function papi_private.coffee_deletion_work(p_secret text)
returns table(owner_id uuid,state text) language sql stable security definer set search_path = '' as $$
  select d.owner_id,d.state from papi_private.account_deletions d
   where coalesce((select auth.jwt())->>'role','')='service_role'
     and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256');
$$;
revoke all on function papi_private.coffee_deletion_work(text) from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_work(text) to service_role;
create function public.coffee_deletion_work(p_secret text) returns table(owner_id uuid,state text)
language sql stable security invoker set search_path = '' as $$ select * from papi_private.coffee_deletion_work(p_secret); $$;
revoke all on function public.coffee_deletion_work(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_work(text) to service_role;

create function papi_private.coffee_deletion_files(p_secret text)
returns table(name text) language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o join papi_private.account_deletions d on o.owner_id=d.owner_id::text
   where coalesce((select auth.jwt())->>'role','')='service_role' and d.state='requested'
     and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256')
     and o.bucket_id='coffee-media' order by o.name limit 100;
$$;
revoke all on function papi_private.coffee_deletion_files(text) from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_files(text) to service_role;
create function public.coffee_deletion_files(p_secret text) returns table(name text)
language sql stable security invoker set search_path = '' as $$ select * from papi_private.coffee_deletion_files(p_secret); $$;
revoke all on function public.coffee_deletion_files(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_files(text) to service_role;

-- An unexpected owner or legacy object under the account prefix requires
-- attention; it must not be silently deleted or ignored before Auth removal.
create function papi_private.coffee_deletion_storage_clear(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from papi_private.account_deletions d
    where coalesce((select auth.jwt())->>'role','')='service_role' and d.state='requested'
      and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256')
      and not exists(select 1 from storage.objects o where o.bucket_id='coffee-media'
        and (o.owner_id=d.owner_id::text or o.name like d.owner_id::text || '/%')));
$$;
revoke all on function papi_private.coffee_deletion_storage_clear(text) from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_storage_clear(text) to service_role;
create function public.coffee_deletion_storage_clear(p_secret text) returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.coffee_deletion_storage_clear(p_secret); $$;
revoke all on function public.coffee_deletion_storage_clear(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_storage_clear(text) to service_role;

create function papi_private.coffee_deletion_user_exists(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users u join papi_private.account_deletions d on d.owner_id=u.id
    where coalesce((select auth.jwt())->>'role','')='service_role'
      and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256'));
$$;
revoke all on function papi_private.coffee_deletion_user_exists(text) from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_user_exists(text) to service_role;
create function public.coffee_deletion_user_exists(p_secret text) returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.coffee_deletion_user_exists(p_secret); $$;
revoke all on function public.coffee_deletion_user_exists(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_user_exists(text) to service_role;

-- Do not delete Auth or Storage until every device's real-time access is
-- removed and its cleanup job has acknowledged successful revocation.
create function papi_private.coffee_deletion_sessions_cleared(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from papi_private.account_deletions d
    where coalesce((select auth.jwt())->>'role','')='service_role' and d.state='requested'
      and p_secret ~ '^[0-9a-f]{64}$' and d.receipt_hash=extensions.digest(p_secret,'sha256')
      and not exists(select 1 from papi_private.voice_members m where m.owner_id=d.owner_id)
      and not exists(select 1 from papi_private.voice_revocations v where v.owner_id=d.owner_id and v.completed_at is null)
      and not exists(select 1 from public.coffee_calls c where d.owner_id in (c.caller_id,c.recipient_id) and c.status in ('pending','accepted'))
      and not exists(select 1 from papi_private.call_revocations c where d.owner_id in (c.caller_id,c.recipient_id) and c.completed_at is null));
$$;
revoke all on function papi_private.coffee_deletion_sessions_cleared(text) from public,anon,authenticated;
grant execute on function papi_private.coffee_deletion_sessions_cleared(text) to service_role;
create function public.coffee_deletion_sessions_cleared(p_secret text) returns boolean
language sql stable security invoker set search_path = '' as $$ select papi_private.coffee_deletion_sessions_cleared(p_secret); $$;
revoke all on function public.coffee_deletion_sessions_cleared(text) from public,anon,authenticated;
grant execute on function public.coffee_deletion_sessions_cleared(text) to service_role;

create function papi_private.complete_coffee_deletion(p_secret text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare actor uuid; current_state text;
begin
  if coalesce((select auth.jwt())->>'role','')<>'service_role' or p_secret is null or p_secret !~ '^[0-9a-f]{64}$' then raise exception 'Service authorization required'; end if;
  select d.owner_id,d.state into actor,current_state from papi_private.account_deletions d where d.receipt_hash=extensions.digest(p_secret,'sha256') for update;
  if not found then return false; end if;
  if current_state='complete' then return true; end if;
  if not papi_private.coffee_deletion_sessions_cleared(p_secret) or
     exists(select 1 from public.coffee_purchase_orders o where o.owner_id=actor and o.completed_at is null) or
     exists(select 1 from auth.users u where u.id=actor) or
     not papi_private.coffee_deletion_storage_clear(p_secret) then return false; end if;
  update papi_private.account_deletions set state='complete',owner_id=null,completed_at=coalesce(completed_at,now()) where owner_id=actor;
  return true;
end;
$$;
revoke all on function papi_private.complete_coffee_deletion(text) from public,anon,authenticated;
grant execute on function papi_private.complete_coffee_deletion(text) to service_role;
create function public.complete_coffee_deletion(p_secret text) returns boolean
language sql security invoker set search_path = '' as $$ select papi_private.complete_coffee_deletion(p_secret); $$;
revoke all on function public.complete_coffee_deletion(text) from public,anon,authenticated;
grant execute on function public.complete_coffee_deletion(text) to service_role;
