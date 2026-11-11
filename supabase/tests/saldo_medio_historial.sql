-- Verificación de solo lectura con los datos restaurados o de producción.
begin;
select set_config('request.jwt.claim.sub',(select user_id::text from marathon.app_users where active and role='SECRETARIA' order by user_id limit 1),true);
do $$declare p record;r jsonb;x jsonb;src marathon.movimientos%rowtype;m marathon.movimientos%rowtype;medium text;tot jsonb;actual_tot jsonb;n integer:=0;begin
 for p in select distinct dni from marathon.saldo_eventos loop
  r=public.marathon_saldo_historial(p.dni,null,100);
  if r->'next'<>'null'::jsonb then raise exception 'Esta comprobación requiere paginar';end if;
  for x in select value from jsonb_array_elements(r->'rows')loop
   select o.*into strict src from marathon.saldo_fuentes f join marathon.movimientos o on o.id=f.movimiento_id where f.id=(x->>'fuente_id')::uuid;
   if x->>'medio_origen' is distinct from src.medio then raise exception 'Medio original incorrecto';end if;
   if x->>'movimiento_id' is not null then
    select *into strict m from marathon.movimientos where id=x->>'movimiento_id';
    if x->>'medio' is distinct from m.medio then raise exception 'Medio de caja incorrecto';end if;
   elsif x->>'medio' is not null then raise exception 'Aplicación interna presentada como dinero nuevo';end if;
   n=n+1;
  end loop;
 end loop;
 for medium in select unnest(array['','EFECTIVO','TRANSFERENCIA'])loop
  r=public.marathon_cash_search(jsonb_build_object('from','2026-10-01','to','2026-11-05','medium',medium),null,100);
  if r->'next'<>'null'::jsonb then raise exception 'Esta comprobación requiere paginar';end if;
  for x in select value from jsonb_array_elements(r->'rows')loop
   select *into strict m from marathon.movimientos where id=x->>'id';
   if x->>'medio' is distinct from m.medio or(medium<>''and m.medio<>medium)then raise exception 'Caja muestra otro medio';end if;
  end loop;
  select coalesce(jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense)),'{}')into actual_tot from(
   select medio,coalesce(sum(monto)filter(where tipo in('PAGO','INGRESO')),0)income,coalesce(sum(monto)filter(where tipo in('EGRESO','REINTEGRO')),0)expense
   from marathon.movimientos where fecha between '2026-10-01'and'2026-11-05'and origen in('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO')and(medium=''or medio=medium)group by medio)s;
  if r->'totals'<>actual_tot then raise exception 'Totales por medio distintos de los movimientos';end if;
 end loop;
 raise notice 'PASS: % eventos de historial; filas, filtros y totales de Caja por ambos medios coinciden.',n;
end$$;
rollback;
