-- Solo copia local. Incluye el fixture transaccional y revierte todo.
\ir saldo_fixture.sql
insert into marathon.profesionales(id,nombre,apellido,estado)values('SALDO_QA2','Segundo','Profesional','ACTIVO');
insert into marathon.terapias(id,nombre,especialidad,duracion_min,capacidad,estado)values('SALDO_QA2','Segunda terapia','QA',30,15,'ACTIVO');
insert into marathon.profesional_terapias(profesional_id,terapia_id)values('SALDO_QA2','SALDO_QA2');
insert into marathon.horarios(id,profesional_id,sede,dia,inicio,fin)select 'SALDO-QA2-'||d,'SALDO_QA2','SALDO_QA',d,'08:00','18:00'from generate_series(0,6)d;
insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)
values('SALDO-T3','2026-10-03','10:00','SALDO_QA','99001001','SALDO_QA2','SALDO_QA2',1500,'PRESENTE',30);
insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones)
values('SALDO-B1','SALDO-T1','99001001','SALDO_QA','SALDO_QA','SALDO_QA',500,'2026-10-01','09:00','2026-10-01',5);
insert into marathon.agenda_planes(id,dni,terapia_id,modalidad,facturacion,importe,inicio,coverage)
values('00000000-0000-4000-8000-000000009903','99001001','SALDO_QA2','monthly','monthly',500,'2026-10-01','{}');
insert into marathon.agenda_periodos(id,plan_id,inicio)values('00000000-0000-4000-8000-000000009904','00000000-0000-4000-8000-000000009903','2026-10-01');
insert into marathon.agenda_cuotas(id,plan_id,periodo_id,fecha,hasta,importe,sede)
values('00000000-0000-4000-8000-000000009905','00000000-0000-4000-8000-000000009903','00000000-0000-4000-8000-000000009904','2026-10-01','2026-11-01',500,'SALDO_QA');
insert into marathon.agenda_horarios(plan_id,dia,hora,sede,profesional_id,desde,duracion_min)
values('00000000-0000-4000-8000-000000009903',1,'11:00','SALDO_QA','SALDO_QA2','2026-10-01',30);
update marathon.saldo_config set activo=true;
do $$declare d jsonb;v jsonb;r jsonb;f jsonb;mid text;original_hash text;after_hash text;cursor jsonb;ids text[]:='{}';part record;begin
 d=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','5000','medio','TRANSFERENCIA','sede','SALDO_QA','fecha','2026-11-06');
 v=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('qa-cash-prof-transfer',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 d=d||jsonb_build_object('dni','99001002','monto','200','medio','EFECTIVO');v=public.marathon_saldo_prever(d);
 perform public.marathon_saldo_command('qa-cash-prof-cash',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 select id into mid from marathon.movimientos where dni='99001001'and subtipo='SALDO_INGRESO';
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into original_hash from marathon.movimientos x;
 f=jsonb_build_object('from','2026-11-06','to','2026-11-06','actor',auth.uid()::text);
 r=public.marathon_cash_search(f);
 assert(r->'totals'->'TRANSFERENCIA'->>'income')::numeric=5000,'Ingreso completo conservado';
 assert(r->'totals'->'EFECTIVO'->>'income')::numeric=200,'Medio efectivo conservado';
 assert(select sum(monto)from marathon.cash_attribution(mid))=5000,'Distribución concilia';
 assert(select sum(monto)from marathon.cash_attribution(mid)where professional_key='SALDO_QA')=2000,'Sesiones y bono profesional 1';
 assert(select sum(monto)from marathon.cash_attribution(mid)where professional_key='SALDO_QA2')=2000,'Sesión y cuota profesional 2';
 assert(select sum(monto)from marathon.cash_attribution(mid)where professional_key is null)=1000,'Remanente sin atribuir';
 r=public.marathon_cash_search(f||jsonb_build_object('prof','SALDO_QA'));
 assert(r->'totals'->'TRANSFERENCIA'->>'income')::numeric=2000;
 assert(r->'rows'->0->>'monto_original')::numeric=5000 and(r->'rows'->0->>'attribution_filtered')::boolean,'Original separado del importe filtrado';
 r=public.marathon_cash_search(f||jsonb_build_object('prof','SALDO_QA','category','T:SALDO_QA2'));
 assert jsonb_array_length(r->'rows')=0,'Cruce profesional/terapia no atribuye importes ajenos';
 r=public.marathon_cash_search(f||jsonb_build_object('prof','SALDO_QA2','medium','TRANSFERENCIA'));
 assert(r->'totals'->'TRANSFERENCIA'->>'income')::numeric=2000;
 r=public.marathon_cash_search(f||jsonb_build_object('prof','__SIN_PROFESIONAL__'));
 assert(r->'totals'->'TRANSFERENCIA'->>'income')::numeric=1000 and(r->'totals'->'EFECTIVO'->>'income')::numeric=200;
 loop
 r=public.marathon_cash_search(f,cursor,1);
 for part in select value from jsonb_array_elements(r->'rows')loop
 assert not(part.value->>'id'=any(ids)),'Paginación duplicada';ids=array_append(ids,part.value->>'id');end loop;
 cursor=r->'next';exit when cursor is null or cursor='null'::jsonb;
 end loop;
 assert cardinality(ids)=2,'Un movimiento por ingreso, incluso con varios profesionales';
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into after_hash from marathon.movimientos x;
 assert original_hash=after_hash,'Consultar y filtrar no reescribe movimientos';
 -- Liberar una sesión a saldo no crea efectivo ni mantiene atribución al profesional.
 d=jsonb_build_object('subtipo','REINTEGRO_SESION','dni','99001001','turno_id','SALDO-T1','observaciones','Prueba de reintegro a saldo');
 v=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('qa-cash-prof-reintegro',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 assert(select sum(monto)from marathon.cash_attribution(mid)where professional_key='SALDO_QA')=1000,'Reverso de aplicación respetado';
 assert(select sum(monto)from marathon.cash_attribution(mid)where professional_key is null)=2000;
 d=jsonb_build_object('subtipo','SALDO_DEVOLUCION','dni','99001001','monto','500','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-06','observaciones','Devolución de prueba');
 v=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('qa-cash-prof-devolucion',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 assert(select sum(monto)from marathon.cash_attribution(mid))=5000,'Devolución concilia con el ingreso original';
 assert(select sum(monto)from marathon.cash_attribution(mid)where category_key='C:Saldo sin aplicar')=1500,'Saldo disponible no incluye dinero devuelto';
 assert(select sum(monto)from marathon.cash_attribution(mid)where category_key='C:Saldo devuelto')=500;
 r=public.marathon_cash_search(f);assert(r->'totals'->'EFECTIVO'->>'expense')::numeric=500,'Egreso por medio real';
 -- Todos los históricos concilian por movimiento, con y sin fuente de saldo.
 assert not exists(select 1 from marathon.daily_cash m cross join lateral(select sum(monto)total from marathon.cash_attribution(m.id))a where a.total is distinct from m.monto),'Históricos conservados';
 assert not has_function_privilege('anon','public.marathon_cash_search(jsonb,jsonb,integer)','execute');
 assert not has_function_privilege('authenticated','marathon.cash_attribution(text)','execute');
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000000',true);
 begin perform public.marathon_cash_search(f);raise exception 'Acceso indebido';exception when sqlstate '42501'then null;end;
 raise notice 'PASS: sesiones, bono, cuota, dos profesionales, remanente, filtros cruzados, medios, paginación, reintegro y devolución; históricos intactos y permisos.';
end$$;
rollback;
