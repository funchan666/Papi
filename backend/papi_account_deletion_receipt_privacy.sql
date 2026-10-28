-- The foundation table is empty and disabled when this migration is applied.
-- A completed receipt must remain retrievable without retaining the account ID.
do $$
begin
  if coalesce((select enabled from papi_private.account_deletion_runtime where singleton),true)
     or exists(select 1 from papi_private.account_deletions) then
    raise exception 'Deletion foundation must be empty and disabled';
  end if;
end;
$$;
alter table papi_private.account_deletions drop constraint account_deletions_pkey;
alter table papi_private.account_deletions alter column owner_id drop not null;
alter table papi_private.account_deletions add column id uuid not null default gen_random_uuid();
alter table papi_private.account_deletions add constraint account_deletions_pkey primary key(id);
alter table papi_private.account_deletions add constraint account_deletions_owner_key unique(owner_id);
alter table papi_private.account_deletions add constraint account_deletions_owner_state_check
  check ((state='requested' and owner_id is not null) or (state='complete' and owner_id is null));
