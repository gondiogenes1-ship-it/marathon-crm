\set ON_ERROR_STOP on
\ir saldo_fixture.sql
insert into marathon.agenda_planes(id,dni,terapia_id,modalidad,facturacion,importe,inicio,coverage)values('00000000-0000-4000-8000-000000009903','99001001','SALDO_QA','monthly','monthly',300,'2026-10-01','{}');
insert into marathon.agenda_periodos(id,plan_id,inicio)values('00000000-0000-4000-8000-000000009904','00000000-0000-4000-8000-000000009903','2026-10-01');
insert into marathon.agenda_cuotas(id,plan_id,periodo_id,fecha,hasta,importe,sede)values('00000000-0000-4000-8000-000000009905','00000000-0000-4000-8000-000000009903','00000000-0000-4000-8000-000000009904','2026-10-01','2026-11-01',300,'SALDO_QA');
insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones)values('SALDO-B1','SALDO-T1','99001001','SALDO_QA','SALDO_QA','SALDO_QA',200,'2026-10-01','09:00','2026-10-01',2);
update marathon.saldo_config set activo=true;
do $$declare d jsonb;p jsonb;r jsonb;begin
 d=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','650','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04');p=public.marathon_saldo_prever(d);
 assert p->'detalle'->0->>'tipo'='cuota';assert p->'detalle'->1->>'tipo'='bono';assert p->'detalle'->2->>'id'='SALDO-T1';
 r=public.marathon_saldo_command('saldo_orden_ingreso01',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 assert marathon.saldo_pagado('cuota','00000000-0000-4000-8000-000000009905')=300;
 assert marathon.saldo_pagado('bono','SALDO-B1')=200;
 assert marathon.saldo_pagado('sesion','SALDO-T1')=150;
 assert marathon.saldo_pagado('sesion','SALDO-T2')=0;
 assert(r->'cuenta'->>'deuda')::numeric=1350;
 d=d||'{"monto":"1350"}';p=public.marathon_saldo_prever(d);
 r=public.marathon_saldo_command('saldo_orden_ingreso02',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 assert(r->'cuenta'->>'deuda')::numeric=0;assert(r->'cuenta'->>'saldo')::numeric=0,'Ingreso exacto';
 assert(select count(*)from marathon.movimientos)=2,'Caja sin duplicación por tipo de deuda';
 raise notice 'OK: orden entre cuota, bono y sesiones con misma fecha; aplicación parcial e importe exacto.';
end$$;
rollback;
