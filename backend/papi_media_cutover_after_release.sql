-- Applied to Papi production on 2026-11-03 at the user's request.
-- Historical record only: do not re-run after cutover.
-- Keep previous objects intact; this changes only the catalog address.
do $$
declare
  old_base constant text := 'https://pub-6ba5fcb7fe264001a73e75d43c95636c.r2.dev';
  new_base constant text := 'https://cquoffowtjnxmgaxavym.supabase.co/storage/v1/object/public/papi-content';
begin
  if (select count(*) from public.coffee_asset_catalog) <> 81
     or (select count(*) from public.coffee_asset_catalog where base_url=old_base) <> 81
     or (select count(*) from storage.objects where bucket_id='papi-content' and name in
          (select item->>'path' from public.coffee_asset_catalog)) <> 81 then
    raise exception 'Catalog or verified object set differs; do not cut over';
  end if;
  update public.coffee_asset_catalog set base_url=new_base where base_url=old_base;
end $$;
