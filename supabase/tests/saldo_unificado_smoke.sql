-- SOLO base aislada: datos sintéticos y ROLLBACK al finalizar.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id)values('00000000-0000-4000-8000-000000009901');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000009901';
insert into marathon.app_users(user_id,role,active,display_name)values(auth.uid(),'ADMIN',true,'Prueba aislada de saldo');
insert into marathon.sedes(nombre,estado)values('SALDO_QA','ACTIVO');
insert into marathon.terapias(id,nombre,especialidad,duracion_min,capacidad,estado)values('SALDO_QA','Terapia de prueba','QA',30,15,'ACTIVO');
insert into marathon.profesionales(id,nombre,apellido,estado)values('SALDO_QA','Profesional','Prueba','ACTIVO');
insert into marathon.profesional_terapias(profesional_id,terapia_id)values('SALDO_QA','SALDO_QA');
insert into marathon.horarios(id,profesional_id,sede,dia,inicio,fin)select 'SALDO-QA-'||d,'SALDO_QA','SALDO_QA',d,'08:00','18:00'from generate_series(0,6)d;
insert into marathon.pacientes(dni,nombre,apellido)values('99001001','Paciente','Uno'),('99001002','Paciente','Dos'),('99001003','Paciente','Tres');
insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)
values('SALDO-T1','2026-10-01','10:00','SALDO_QA','99001001','SALDO_QA','SALDO_QA',1000,'PRESENTE',30),('SALDO-T2','2026-10-02','10:00','SALDO_QA','99001001','SALDO_QA','SALDO_QA',500,'PRESENTE',30);
update marathon.saldo_config set activo=true;
do $test$
declare data jsonb;preview jsonb;r jsonb;repeated jsonb;before_count bigint;begin
 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','1200.00','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04','observaciones','Prueba aislada');
 preview=public.marathon_saldo_prever(data);
 assert preview->>'aplicar'='1200.00' or (preview->>'aplicar')::numeric=1200;
 data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');
 r=public.marathon_saldo_command('saldo_qa_ingreso_001',data);
 assert (r->'cuenta'->>'deuda')::numeric=300,'Ingreso parcial';
 assert (r->'cuenta'->>'saldo')::numeric=0,'Sin sobrante en pago parcial';
 assert marathon.saldo_pagado('sesion','SALDO-T1')=1000,'La sesión más antigua primero';
 assert marathon.saldo_pagado('sesion','SALDO-T2')=200,'Aplicación parcial a segunda sesión';
 select count(*)into before_count from marathon.movimientos;
 repeated=public.marathon_saldo_command('saldo_qa_ingreso_001',data);assert r=repeated,'Reintento devuelve resultado guardado';
 assert(select count(*)from marathon.movimientos)=before_count,'Reintento no duplica ingreso';
 begin perform public.marathon_saldo_command('saldo_qa_ingreso_001',data||'{"monto":"1201"}');raise exception 'No rechazó cambio de payload';exception when sqlstate '22023'then null;end;

 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','500','medio','TRANSFERENCIA','sede','SALDO_QA','fecha','2026-11-04');
 preview=public.marathon_saldo_prever(data);data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');r=public.marathon_saldo_command('saldo_qa_ingreso_002',data);
 assert(r->'cuenta'->>'deuda')::numeric=0;assert(r->'cuenta'->>'saldo')::numeric=200,'Sobrante disponible';
 assert(select count(*)from marathon.movimientos)=before_count+1,'Aplicaciones no crean movimientos';

 data=jsonb_build_object('subtipo','SALDO_DEVOLUCION','dni','99001001','monto','201','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04','observaciones','Devolución de prueba');
 begin perform public.marathon_saldo_prever(data);raise exception 'Permitió devolver más que el saldo';exception when sqlstate '22023'then null;end;
 data=data||'{"monto":"50"}';preview=public.marathon_saldo_prever(data);data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');perform public.marathon_saldo_command('saldo_qa_devolver_001',data);
 assert marathon.saldo_disponible('99001001')=150;

 data=jsonb_build_object('subtipo','REINTEGRO_SESION','dni','99001001','turno_id','SALDO-T1','observaciones','Reintegro a saldo de prueba');
 preview=public.marathon_saldo_prever(data);data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');select count(*)into before_count from marathon.movimientos;perform public.marathon_saldo_command('saldo_qa_reintegro_01',data);
 assert marathon.saldo_disponible('99001001')=1150,'Libera pago neto al saldo';
 assert(select deuda from marathon.saldo_deudas('99001001')where id='SALDO-T1')=0,'Sesión reintegrada sin deuda';
 assert(select estado from marathon.turnos where id='SALDO-T1')='PRESENTE','Conserva asistencia';
 assert(select count(*)from marathon.movimientos)=before_count,'Reintegro interno sin egreso';

 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001002','monto','100.001','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04');
 begin perform public.marathon_saldo_prever(data);raise exception 'Aceptó fracción de centavo';exception when sqlstate '22023'then null;end;
 data=data||'{"monto":"100.01"}';preview=public.marathon_saldo_prever(data);data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');r=public.marathon_saldo_command('saldo_qa_ingreso_003',data);
 assert(r->'cuenta'->>'saldo')::numeric=100.01,'Ingreso sin deuda queda íntegro a favor';

 data=jsonb_build_object('subtipo','PAGO_PROFESIONAL','monto','25','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04','observaciones','Pago profesional de prueba','profesional','SALDO_QA','terapia','SALDO_QA');
 preview=public.marathon_saldo_prever(data);data=data||jsonb_build_object('huella',preview->>'huella','version',preview->>'version');r=public.marathon_saldo_command('saldo_qa_profesional1',data);
 assert exists(select 1 from marathon.movimientos where id=r->>'id'and tipo='EGRESO'and dni is null and profesional_asociado_id='SALDO_QA'and terapia_asociada_id='SALDO_QA');
 assert marathon.saldo_disponible('99001001')=1150,'Pago a profesional no toca saldo paciente';
 raise notice 'OK: parcial, orden, sobrante, devolución, reintegro, centavos, pago profesional e idempotencia.';
end $test$;
rollback;
