\ir saldo_fixture.sql
update marathon.saldo_config set activo=true;
\if :{?cash_edit_as_secretary}
update marathon.app_users set role='SECRETARIA'where user_id=auth.uid();
\endif
do $$declare d jsonb;v jsonb;r jsonb;mid text;newid text;n bigint;h text;failed boolean;olduid uuid:=auth.uid();x record;begin
 d=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','1200','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-06','observaciones','Original de prueba');
 v=public.marathon_saldo_prever(d);r=public.marathon_saldo_command('qa-edit-original-001',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));mid=r->>'id';
 d=jsonb_build_object('id',mid,'version',1,'subtipo','SALDO_INGRESO','dni','99001001','monto','600','medio','TRANSFERENCIA','sede','SALDO_QA','fecha','2026-11-05','hora','12:30','concepto','Ingreso corregido','observaciones','Prueba','motivo','Importe y medio equivocados');
 n=(select count(*)from marathon.movimientos);h=(select md5(jsonb_agg(to_jsonb(s)order by id)::text)from marathon.saldo_eventos s);
 v=public.marathon_cash_edit_preview(d);
 assert(select count(*)from marathon.movimientos)=n,'Preview no crea movimientos';
 assert(select md5(jsonb_agg(to_jsonb(s)order by id)::text)from marathon.saldo_eventos s)=h,'Preview no libera pagos';
 assert(v->'cuentas_despues'->'anterior'->>'deuda')::numeric=900,'Reducción vuelve a dejar deuda';
 r=public.marathon_cash_edit_save('qa-edit-reduce-0001',d||jsonb_build_object('huella',v->>'huella'));newid=r->>'id';
 assert marathon.turn_paid('SALDO-T1')=600 and marathon.turn_paid('SALDO-T2')=0,'Pagos corregidos';
 assert(select monto from marathon.movimientos where id=mid)=1200,'Original conservado';
 assert not exists(select 1 from marathon.daily_cash where id=mid),'Caja solo muestra la versión efectiva';
 assert(select monto from marathon.daily_cash where id=newid)=600;
 assert(public.marathon_cash_list('2026-11-05','SALDO_QA')->'totals'->'TRANSFERENCIA'->>'income')::numeric=600,'Inicio y Caja coinciden';
 assert jsonb_array_length(public.marathon_cash_edit_get(newid)->'history')=1,'Historial disponible';
 n=(select count(*)from marathon.movimientos);
 assert public.marathon_cash_edit_save('qa-edit-reduce-0001',d||jsonb_build_object('huella',v->>'huella'))=r;
 assert(select count(*)from marathon.movimientos)=n,'Reintento no duplica';
 -- Cambiar solamente el medio conserva exactamente las aplicaciones.
 select *into x from marathon.movimientos where id=newid;
 d=d||jsonb_build_object('id',newid,'version',x.version,'monto','600','medio','EFECTIVO');
 h=(select md5(jsonb_agg(to_jsonb(s)order by id)::text)from marathon.saldo_eventos s);
 v=public.marathon_cash_edit_preview(d);r=public.marathon_cash_edit_save('qa-edit-metadata-01',d||jsonb_build_object('huella',v->>'huella'));
 assert r->>'id'=newid and not(r->>'corrige_pagos')::boolean;
 assert(select md5(jsonb_agg(to_jsonb(s)order by id)::text)from marathon.saldo_eventos s)=h,'Medio no redistribuye pagos';
 -- Datos obsoletos y huella desactualizada no se guardan.
 failed=false;begin perform public.marathon_cash_edit_save('qa-edit-stale-00001',d||jsonb_build_object('huella',v->>'huella'));exception when sqlstate 'PT409'then failed=true;end;assert failed;
 select *into x from marathon.movimientos where id=newid;
 d=d||jsonb_build_object('version',x.version,'dni','99001002','monto','800','fecha','2026-11-06');
 v=public.marathon_cash_edit_preview(d);r=public.marathon_cash_edit_save('qa-edit-patient-001',d||jsonb_build_object('huella',v->>'huella'));newid=r->>'id';
 assert marathon.turn_paid('SALDO-T1')=0 and marathon.turn_paid('SALDO-T2')=0,'Paciente anterior recupera su deuda';
 assert marathon.saldo_disponible('99001002')=800,'Paciente correcto recibe su saldo';
 -- Otro ingreso se reclasifica a paciente sin duplicar Caja.
 d=jsonb_build_object('subtipo','OTRO_INGRESO','monto','7000','medio','TRANSFERENCIA','sede','SALDO_QA','fecha','2026-11-06','observaciones','Ingreso sin paciente');
 v=public.marathon_saldo_prever(d);r=public.marathon_saldo_command('qa-edit-manual-0001',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));mid=r->>'id';
 d=jsonb_build_object('id',mid,'version',1,'subtipo','SALDO_INGRESO','dni','99001003','monto','7000','medio','TRANSFERENCIA','sede','SALDO_QA','fecha','2026-11-06','hora','18:14','concepto','Ingreso asociado','observaciones','Asignación corregida','motivo','Faltaba el paciente');
 v=public.marathon_cash_edit_preview(d);r=public.marathon_cash_edit_save('qa-edit-manual-fix1',d||jsonb_build_object('huella',v->>'huella'));
 assert marathon.saldo_disponible('99001003')=7000,'Ingreso general ahora es crédito del paciente';
 assert(select sum(monto)from marathon.daily_cash where dni='99001003')=7000,'Ingreso efectivo no se duplica';
 -- Una devolución física previa se conserva: se permite el dato descriptivo,
 -- pero no se inventa saldo al trasladar un ingreso que ya tuvo devolución.
 d=jsonb_build_object('subtipo','SALDO_DEVOLUCION','dni','99001002','monto','100','medio','EFECTIVO','sede','SALDO_QA','fecha','2026-11-06','observaciones','Devolución física de prueba');
 v=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('qa-edit-refund-0001',d||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 select *into x from marathon.movimientos where id=newid;
 d=jsonb_build_object('id',newid,'version',x.version,'subtipo','SALDO_INGRESO','dni','99001002','monto','800','medio',x.medio,'sede',x.sede,'fecha',x.fecha,'hora',x.hora,'concepto','Dato descriptivo corregido','observaciones','Prueba','motivo','Corrección de concepto');
 v=public.marathon_cash_edit_preview(d);r=public.marathon_cash_edit_save('qa-edit-refund-meta',d||jsonb_build_object('huella',v->>'huella'));
 assert marathon.saldo_disponible('99001002')=700,'La edición descriptiva conserva la devolución';
 select version into n from marathon.movimientos where id=newid;d=d||jsonb_build_object('version',n,'monto','900');
 failed=false;begin perform public.marathon_cash_edit_preview(d);exception when sqlstate '22023'then failed=true;end;assert failed,'No modifica dinero devuelto sin conciliación';
 assert marathon.saldo_disponible('99001002')=700;
 -- Usuarios inactivos siguen excluidos, incluso con rol de Secretaría.
 insert into auth.users(id)values('00000000-0000-4000-8000-000000009902');
 insert into marathon.app_users(user_id,role,active,display_name)values('00000000-0000-4000-8000-000000009902','SECRETARIA',false,'Secretaría QA inactiva');
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009902',true);
 failed=false;begin perform public.marathon_cash_edit_get(newid);exception when sqlstate '42501'then failed=true;end;assert failed;
 failed=false;begin perform public.marathon_cash_edit_preview(d);exception when sqlstate '42501'then failed=true;end;assert failed;
 failed=false;begin perform public.marathon_cash_edit_save('qa-edit-forbidden1',d);exception when sqlstate '42501'then failed=true;end;assert failed;
 assert not has_function_privilege('authenticated','marathon.cash_edit_run(text,jsonb)','execute');
 assert not has_function_privilege('anon','public.marathon_cash_edit_save(text,jsonb)','execute');
 raise notice 'PASS: preview sin escrituras, reducción y paciente corrigen pagos, medio conserva aplicaciones, historial, Caja/Inicio, reclasificación, concurrencia, idempotencia y permisos.';
end$$;
rollback;
