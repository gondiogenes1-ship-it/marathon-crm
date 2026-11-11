begin;
-- Reforzar ACL explícitas también cuando la copia local se restauró sin privilegios.
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='marathon'and left(p.proname,6)='saldo_'loop
  execute format('revoke all on function %s from public,anon,authenticated',f.signature);
 end loop;
end$$;
alter table marathon.saldo_fuentes alter column movimiento_id set not null;
create function public.marathon_saldo_estado()returns jsonb language plpgsql stable security definer set search_path=''as $$begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 return(select jsonb_build_object('activo',activo,'corte',corte)from marathon.saldo_config where id);
end$$;
revoke all on function public.marathon_saldo_estado()from public,anon;
grant execute on function public.marathon_saldo_estado()to authenticated;
commit;
