\set ON_ERROR_STOP on
\ir saldo_fixture.sql
update marathon.saldo_config set activo=true;
create function pg_temp.receive(dni text,monto text,request text)returns jsonb language plpgsql as $$declare data jsonb;p jsonb;begin
 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni',dni,'monto',monto,'medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04');
 p=public.marathon_saldo_prever(data);return public.marathon_saldo_command(request,data||jsonb_build_object('version',p->>'version','huella',p->>'huella'));end$$;
do $test$declare data jsonb;p jsonb;r jsonb;mid text;n bigint;v bigint;begin
 r=pg_temp.receive('99001001','1200','saldo_eventos_ingreso1');mid=r->>'id';
 n=(select count(*)from marathon.movimientos);
 data=jsonb_build_object('id',mid,'version',marathon.saldo_version('99001001'),'motivo','Prueba de anulación','fecha','2026-11-04');
 r=public.marathon_saldo_anular('saldo_eventos_anular01',data);
 assert(r->'cuenta'->>'deuda')::numeric=1500,'Anulación reabre deudas';
 assert(r->'cuenta'->>'saldo')::numeric=0,'Anulación no deja saldo negativo';
 assert(select count(*)from marathon.movimientos)=n+1,'Un contrasiento';
 perform public.marathon_saldo_anular('saldo_eventos_anular01',data);
 assert(select count(*)from marathon.movimientos)=n+1,'Reintento de anulación';
 begin perform public.marathon_saldo_anular('saldo_eventos_anular02',data||jsonb_build_object('version',marathon.saldo_version('99001001')));raise exception 'Doble anulación';exception when sqlstate '22023'then null;end;
 -- Huella vencida por otro ingreso.
 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001002','monto','50','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04');p=public.marathon_saldo_prever(data);
 perform pg_temp.receive('99001002','100.01','saldo_eventos_ingreso2');
 begin perform public.marathon_saldo_command('saldo_eventos_obsoleta',data||jsonb_build_object('version',p->>'version','huella',p->>'huella'));raise exception 'Aceptó vista previa obsoleta';exception when sqlstate 'PT409'then null;end;
 n=(select count(*)from marathon.movimientos);
 insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)values('SALDO-T3','2026-11-04','11:00','SALDO_QA','99001002','SALDO_QA','SALDO_QA',150,'PENDIENTE',30);
 perform public.marathon_agenda_command('saldo_eventos_presente', 'status',jsonb_build_object('id','SALDO-T3','version',(select version from marathon.turnos where id='SALDO-T3'),'estado','PRESENTE'));
 assert marathon.saldo_pagado('sesion','SALDO-T3')=100.01,'Presente aplica saldo parcial';
 assert(select deuda from marathon.saldo_deudas('99001002')where id='SALDO-T3')=49.99;
 v=marathon.saldo_version('99001002');
 update marathon.turnos set estado='PRESENTE'where id='SALDO-T3';assert marathon.saldo_version('99001002')=v,'Presente repetido sin aplicaciones extra';
 perform public.marathon_agenda_command('saldo_eventos_ausente1','status',jsonb_build_object('id','SALDO-T3','version',(select version from marathon.turnos where id='SALDO-T3'),'estado','AUSENTE'));
 assert marathon.saldo_disponible('99001002')=100.01,'Ausente devuelve aplicación al saldo';
 assert(select count(*)from marathon.movimientos)=n,'Asistencia no mueve Caja';
 update marathon.turnos set estado='PRESENTE'where id='SALDO-T3';
 data=jsonb_build_object('subtipo','REINTEGRO_SESION','dni','99001002','turno_id','SALDO-T3','observaciones','Reintegro parcial de prueba');p=public.marathon_saldo_prever(data);
 perform public.marathon_saldo_command('saldo_eventos_reintegr',data||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 assert marathon.saldo_disponible('99001002')=100.01;
 assert(select deuda from marathon.saldo_deudas('99001002')where id='SALDO-T3')=0,'Bonifica parte impaga sin inventar crédito';
 assert(public.marathon_turn_account('SALDO-T3')->>'debt')::numeric=0,'Ficha usa cargo neto';
 assert(select debt from marathon.daily_turns where id='SALDO-T3')=0,'Grilla usa cargo neto';
 assert(public.marathon_patient_account('99001002')->>'debt')::numeric=0,'Cuenta no recrea deuda bonificada';
 assert(select count(*)from marathon.movimientos)=n;
 -- El ingreso a otro paciente no paga deudas de los anteriores.
 perform pg_temp.receive('99001003','1000','saldo_eventos_ingreso3');
 insert into marathon.agenda_planes(id,dni,terapia_id,modalidad,facturacion,importe,inicio,coverage)values('00000000-0000-4000-8000-000000009903','99001003','SALDO_QA','monthly','monthly',300,'2026-11-01','{}');
 insert into marathon.agenda_periodos(id,plan_id,inicio)values('00000000-0000-4000-8000-000000009904','00000000-0000-4000-8000-000000009903','2026-11-01');
 insert into marathon.agenda_cuotas(id,plan_id,periodo_id,fecha,hasta,importe,sede)values('00000000-0000-4000-8000-000000009905','00000000-0000-4000-8000-000000009903','00000000-0000-4000-8000-000000009904','2026-11-01','2026-12-01',300,'SALDO_QA');
 assert marathon.saldo_pagado('cuota','00000000-0000-4000-8000-000000009905')=300,'Cuota usa saldo';
 insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones)values('SALDO-B1','SALDO-T1','99001003','SALDO_QA','SALDO_QA','SALDO_QA',200,'2026-11-04','12:00','2026-11-05',1);
 assert marathon.saldo_pagado('bono','SALDO-B1')=200,'Bono usa saldo';
 assert marathon.saldo_disponible('99001003')=500;
 update marathon.bonos_serie set estado='ANULADO'where id='SALDO-B1';
 assert marathon.saldo_disponible('99001003')=700,'Anular bono devuelve saldo sin egreso';
 data=jsonb_build_object('subtipo','SALDO_DEVOLUCION','dni','99001003','monto','1','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-04','observaciones','Retiro de prueba');p=public.marathon_saldo_prever(data);
 perform public.marathon_saldo_command('saldo_eventos_retirar1',data||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 mid=(select movimiento_id from marathon.saldo_fuentes where dni='99001003');
 assert(public.marathon_saldo_anular_prever(mid)->>'bloqueado')::boolean,'Vista previa advierte devolución previa';
 begin perform public.marathon_saldo_anular('saldo_eventos_anulaout',jsonb_build_object('id',mid,'version',marathon.saldo_version('99001003'),'fecha','2026-11-04','motivo','Prueba administrativa'));raise exception 'Anuló luego de devolución';exception when sqlstate '22023'then null;end;
 assert marathon.saldo_pagado('sesion','SALDO-T1')=0,'No mezcla pacientes';
 -- El ledger no permite edición ni borrado.
 begin delete from marathon.saldo_eventos;raise exception 'Borró historial';exception when insufficient_privilege then null;end;
 begin update marathon.saldo_fuentes set origen='EDITADO';raise exception 'Editó fuente';exception when insufficient_privilege then null;end;
 raise notice 'OK: anulación, vista previa vencida, presente parcial/repetido, ausente, reintegro parcial, cuota y bono automáticos, inmutabilidad.';
end$test$;
insert into auth.users(id)values('00000000-0000-4000-8000-000000009902');
insert into marathon.app_users(user_id,role,active,display_name)values('00000000-0000-4000-8000-000000009902','SECRETARIA',true,'Secretaría de prueba');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000009902';
set local role authenticated;
do $$begin
 perform public.marathon_saldo_consultar('99001001');
 perform public.marathon_patient_history('99001001','clinic',null,25);
 perform public.marathon_bonus_get('SALDO-B1',null,25);
 begin perform public.marathon_saldo_anular('saldo_secretaria_anula','{}');raise exception 'Secretaría anuló';exception when insufficient_privilege then null;end;
 begin perform marathon.saldo_disponible('99001001');raise exception 'Acceso directo';exception when insufficient_privilege then null;end;
 raise notice 'OK: consulta autenticada, secretaría sin anulación y funciones internas privadas.';
end$$;
reset role;
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000009999';
do $$begin
 begin perform public.marathon_saldo_consultar('99001001');raise exception 'Acceso sin alta';exception when insufficient_privilege then null;end;
 begin perform public.marathon_patient_history('99001001','clinic',null,25);raise exception 'Historial sin alta';exception when insufficient_privilege then null;end;
 begin perform public.marathon_bonus_get('SALDO-B1',null,25);raise exception 'Bono sin alta';exception when insufficient_privilege then null;end;
end$$;
rollback;
