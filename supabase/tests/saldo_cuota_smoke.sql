\set ON_ERROR_STOP on
\ir saldo_fixture.sql
insert into marathon.agenda_planes(id,dni,terapia_id,modalidad,facturacion,importe,inicio,coverage)values('00000000-0000-4000-8000-000000009903','99001003','SALDO_QA','monthly','monthly',500,'2026-11-01','{}');
insert into marathon.agenda_periodos(id,plan_id,inicio)values('00000000-0000-4000-8000-000000009904','00000000-0000-4000-8000-000000009903','2026-11-01');
insert into marathon.agenda_cuotas(id,plan_id,periodo_id,fecha,hasta,importe,sede)values('00000000-0000-4000-8000-000000009905','00000000-0000-4000-8000-000000009903','00000000-0000-4000-8000-000000009904','2026-11-01','2026-12-01',500,'SALDO_QA');
update marathon.saldo_config set activo=true;
do $$declare d jsonb;p jsonb;r jsonb;n bigint;begin
 d=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001003','monto','200','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04');p=public.marathon_saldo_prever(d);
 perform public.marathon_saldo_command('saldo_cuota_ingreso01',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 assert marathon.agenda_cuota_pagado('00000000-0000-4000-8000-000000009905')=200;
 n=(select count(*)from marathon.movimientos);
 d=jsonb_build_object('subtipo','REINTEGRO_CUOTA','dni','99001003','cuota_id','00000000-0000-4000-8000-000000009905','observaciones','Reintegro de cuota a saldo del paciente');p=public.marathon_saldo_prever(d);
 assert(p->>'monto')::numeric=200,'Libera solo lo realmente pagado';
 assert(p->'detalle'->0->>'deuda_bonificada')::numeric=300,'Pendiente que se bonifica, sin convertirlo en dinero';
 d=d||jsonb_build_object('version',p->>'version','huella',p->>'huella');r=public.marathon_saldo_command('saldo_cuota_reintegro1',d);
 assert marathon.saldo_disponible('99001003')=200,'Importe a favor del paciente';
 assert marathon.agenda_cuota_saldo('00000000-0000-4000-8000-000000009905')=0,'Cuota sin deuda';
 assert(select count(*)from marathon.movimientos)=n,'Reintegro interno no crea egreso';
 assert position('No se devolvió dinero de Caja' in r->>'message')>0,'Confirmación inequívoca';
 assert public.marathon_saldo_command('saldo_cuota_reintegro1',d)=r,'Reintento no duplica saldo';
 begin perform public.marathon_saldo_prever(d-'huella'-'version');raise exception 'Reintegró dos veces';exception when sqlstate '22023'then null;end;
 d=jsonb_build_object('subtipo','SALDO_DEVOLUCION','dni','99001003','monto','200','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04','observaciones','Devolución efectiva del saldo');p=public.marathon_saldo_prever(d);
 perform public.marathon_saldo_command('saldo_cuota_devolver01',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 assert marathon.saldo_disponible('99001003')=0;
 assert(select count(*)from marathon.movimientos where tipo='EGRESO')=1,'Dinero devuelto únicamente por devolución de saldo';
 assert(select count(*)from marathon.movimientos)=n+1;
 raise notice 'OK: reintegro de cuota parcial a saldo, cuota sin deuda, aviso explícito, reintento y devolución física separada.';
end$$;
rollback;
