\set ON_ERROR_STOP on
\ir saldo_fixture.sql
-- Historia artificial: pago directo, anticipo parcialmente usado y bono ya pago.
insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,turno_id,concepto,created_by,updated_by)values('SALDO-OLD-PAGO','2026-10-01','10:00','CLINICA','PAGO','99001001',600,'EFECTIVO','SALDO_QA','SALDO-T1','Cobro sintético',auth.uid(),auth.uid());
insert into marathon.anticipos(id,dni,sede,importe,fecha,hora,created_by,updated_by)values('SALDO-OLD-ADV','99001001','SALDO_QA',500,'2026-10-02','09:00',auth.uid(),auth.uid());
insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,anticipo_id,concepto,created_by,updated_by)values('SALDO-OLD-DEPOSITO','2026-10-02','09:00','ANTICIPO','INGRESO','99001001',500,'EFECTIVO','SALDO_QA','SALDO-OLD-ADV','Anticipo sintético',auth.uid(),auth.uid());
select marathon.operation_begin('saldo_qa_historia_001','qa','{}');
insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,movimiento_id,request_id,actor)values('SALDO-OLD-ADV','DEPOSITO',500,'SALDO-OLD-DEPOSITO','saldo_qa_historia_001',auth.uid());
insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,turno_id,request_id,actor)values('SALDO-OLD-ADV','APLICACION',100,'SALDO-T2','saldo_qa_historia_001',auth.uid());
insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones)values('SALDO-OLD-BONO','SALDO-T1','99001001','SALDO_QA','SALDO_QA','SALDO_QA',200,'2026-10-01','09:00','2026-10-01',2);
insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,bono_id,concepto,created_by,updated_by)values('SALDO-OLD-BONOPAGO','2026-10-01','09:00','BONO','INGRESO','99001001',200,'EFECTIVO','SALDO_QA','SALDO-OLD-BONO','Bono sintético',auth.uid(),auth.uid());
-- ID aprobado de Carlos, pero paciente y datos de prueba en esta base aislada.
insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,created_by,updated_by)values('MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95','2026-11-04','09:00','CAJA','INGRESO','99001003',40000,'EFECTIVO','SALDO_QA','GIMNASIO X 3',auth.uid(),auth.uid());
insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,created_by,updated_by)values('MOV-69c21c72-3972-4294-a2d2-600a50f5b883','2026-11-01','09:00','CAJA','INGRESO','99001002',1,'EFECTIVO','SALDO_QA','anticipo',auth.uid(),auth.uid());
do $$declare plan jsonb;result jsonb;n bigint;begin
 plan=marathon.saldo_importacion_prever();assert plan->'bloqueos'='[]'::jsonb;
 assert(select count(*)from marathon.saldo_fuentes)=0,'Prueba en seco no escribe';
 begin perform marathon.saldo_importar('saldo_import_stale_01','obsoleta');raise exception 'Importó con huella incorrecta';exception when sqlstate 'PT409'then null;end;
 n=(select count(*)from marathon.movimientos);
 result=marathon.saldo_importar('saldo_import_real_001',plan->>'huella');assert(result->>'conciliado')::boolean;
 assert marathon.saldo_disponible('99001001')=400,'Solo remanente del anticipo';
 assert marathon.saldo_disponible('99001003')=40000,'Ingreso de Carlos sin duplicar Caja';
 assert marathon.saldo_disponible('99001002')=0,'Prueba histórica excluida del crédito';
 assert marathon.saldo_pagado('sesion','SALDO-T1')=600;
 assert marathon.saldo_pagado('sesion','SALDO-T2')=100;
 assert marathon.saldo_pagado('bono','SALDO-OLD-BONO')=200,'Bono pagado sigue aplicado';
 assert (select sum(deuda)from marathon.saldo_deudas('99001001'))=800,'Deuda se conserva';
 assert(select count(*)from marathon.movimientos)=n,'Importar no mueve Caja';
 assert marathon.saldo_importar('saldo_import_real_001',plan->>'huella')=result,'Reintento de importación';
 update marathon.saldo_config set activo=true;
 assert marathon.turn_paid('SALDO-T1')=600;
 perform public.marathon_agenda_command('saldo_import_ausente1','status',jsonb_build_object('id','SALDO-T1','version',(select version from marathon.turnos where id='SALDO-T1'),'estado','AUSENTE'));
 assert marathon.saldo_disponible('99001001')=1000,'Libera pago importado al cambiar asistencia';
 assert marathon.turn_paid('SALDO-T1')=0,'No vuelve a sumar pago histórico';
 assert(select count(*)from marathon.movimientos)=n;
 raise notice 'OK: prueba en seco, huella, conversión, conciliación exacta, bono sin crédito duplicado, prueba excluida y reversión de pago importado.';
end$$;
rollback;
