-- Pruebas con pacientes ficticios, incluido dinero simulado; todo se revierte.
begin;
do $$declare uid uuid;h record;d date:=marathon.agenda_hoy();r jsonb;c jsonb;data jsonb;payment jsonb;v jsonb;pid uuid;pm uuid;t marathon.turnos%rowtype;old_turn jsonb;old_cash text;first_id text;qid uuid;failed boolean:=false;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 if exists(select 1 from marathon.pacientes where dni in('99999201','99999202'))then raise exception 'Fixture ocupado';end if;
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id where x.dia=extract(dow from d)::int and x.fin-x.inicio>=interval '2 hours'and th.estado='ACTIVO'and th.capacidad>=5 and(marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int>=3 order by th.capacidad desc,x.inicio limit 1;
 if h.id is null then raise exception 'Fixture sin horario';end if;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999201','CONDICIONES','ZZ_QA',uid,uid),('99999202','CUOTAS','ZZ_QA',uid,uid);
 data=jsonb_build_object('dni','99999201','therapy',h.terapia_id,'mode','fixed','billing','class','amount',1000,'start',d,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Original','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-terms-create-'||gen_random_uuid(),'create',data);pid=(r->>'id')::uuid;perform marathon.agenda_materializar(d,d+28);
 select *into t from marathon.turnos where plan_id=pid and fecha=d;first_id=t.id;
 perform public.marathon_agenda_command('qa-terms-present-'||gen_random_uuid(),'status',jsonb_build_object('id',t.id,'version',t.version,'estado','PRESENTE'));
 payment=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99999201','monto','1000','medio','TRANSFERENCIA','sede',h.sede,'fecha',d);v=public.marathon_saldo_prever(payment);
 perform public.marathon_saldo_command('qa-terms-paid-'||gen_random_uuid(),payment||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 select to_jsonb(x)into old_turn from marathon.turnos x where id=first_id;
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into old_cash from marathon.movimientos x;
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;c=public.marathon_turn_series_context(t.id);
 data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'time',to_char(h.inicio,'HH24:MI'),'site',h.sede,'prof',h.profesional_id,'amount',1500,'coverage',jsonb_build_object('type','ART','name','Nueva entidad','affiliate','REF2'),'notes','Nuevas observaciones');
 r=public.marathon_turn_series_preview(data);
 if(select importe from marathon.turnos where id=t.id)<>1000 then raise exception 'La vista previa cambió el importe';end if;
 r=public.marathon_turn_series_save('qa-terms-update-'||gen_random_uuid(),data);
 if(select to_jsonb(x)from marathon.turnos x where id=first_id)<>old_turn then raise exception 'Se modificó la sesión anterior cobrada';end if;
 if not exists(select 1 from marathon.turnos where id=t.id and importe=1500 and coverage->>'type'='ART'and booking_notes='Nuevas observaciones')then raise exception 'No cambió el turno seleccionado';end if;
 perform marathon.agenda_materializar(d+70,d+70);
 if not exists(select 1 from marathon.turnos where plan_id=pid and fecha=d+70 and importe=1500 and coverage->>'name'='Nueva entidad'and booking_notes='Nuevas observaciones')then raise exception 'No se propagó a la agenda indefinida';end if;
 -- Una excepción individual no cambia las demás condiciones de la serie.
 select *into t from marathon.turnos where plan_id=pid and fecha=d+14;c=public.marathon_turn_series_context(t.id);
 data=data||jsonb_build_object('id',t.id,'huella',c->>'huella','scope','single','date',t.fecha,'amount',900,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','');
 r=public.marathon_turn_series_save('qa-terms-single-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.turnos where id=t.id and importe=900 and coverage->>'type'='PARTICULAR'and booking_notes='')then raise exception 'No se guardó la excepción individual';end if;
 perform marathon.agenda_materializar(d+140,d+140);
 if not exists(select 1 from marathon.turnos where plan_id=pid and fecha=d+140 and importe=1500 and coverage->>'type'='ART'and booking_notes='Nuevas observaciones')then raise exception 'La excepción individual contaminó la serie';end if;
 if old_cash<>(select md5(jsonb_agg(to_jsonb(x)order by id)::text)from marathon.movimientos x)then raise exception 'La edición modificó Caja';end if;
 -- Cuota sin pagos: se cambia la actual, sin crear ingreso alguno.
 data=jsonb_build_object('dni','99999202','therapy',h.terapia_id,'mode','monthly','billing','monthly','amount',1000,'start',d,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Mensual original','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-terms-monthly-'||gen_random_uuid(),'create',data);pm=(r->>'id')::uuid;perform marathon.agenda_materializar(d,d+28);select id into qid from marathon.agenda_cuotas where plan_id=pm order by fecha limit 1;
 select *into t from marathon.turnos where plan_id=pm and fecha=d;c=public.marathon_turn_series_context(t.id);
 data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'time',to_char(h.inicio,'HH24:MI'),'site',h.sede,'prof',h.profesional_id,'amount',2000,'coverage',jsonb_build_object('type','CLUB','name','Club nuevo'),'notes','Mensual nuevo');
 r=public.marathon_turn_series_preview(data);if(r->>'cuotas_actualizadas')::int<>1 or(select importe from marathon.agenda_cuotas where id=qid)<>1000 then raise exception 'Vista previa de cuota incorrecta';end if;
 r=public.marathon_turn_series_save('qa-terms-unpaid-'||gen_random_uuid(),data);
 if(select importe from marathon.agenda_cuotas where id=qid)<>2000 or marathon.agenda_tarifa(pm,d+60)<>2000 then raise exception 'No cambió cuota o tarifa futura';end if;
 -- Cuota parcialmente pagada: conserva cargo y pago; solo próximas cuotas toman el precio nuevo.
 payment=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99999202','monto','500','medio','EFECTIVO','sede',h.sede,'fecha',d);v=public.marathon_saldo_prever(payment);perform public.marathon_saldo_command('qa-terms-quota-pay-'||gen_random_uuid(),payment||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into old_cash from marathon.movimientos x;
 select *into t from marathon.turnos where plan_id=pm and fecha=d+7;c=public.marathon_turn_series_context(t.id);data=data||jsonb_build_object('id',t.id,'huella',c->>'huella','date',t.fecha,'amount',3000);
 r=public.marathon_turn_series_save('qa-terms-partial-'||gen_random_uuid(),data);
 if(select importe from marathon.agenda_cuotas where id=qid)<>2000 or marathon.agenda_cuota_pagado(qid)<>500 or(r->>'cuotas_conservadas')::int<>1 or marathon.agenda_tarifa(pm,d+60)<>3000 then raise exception 'Se alteró cuota pagada o no se cambió la futura';end if;
 if old_cash<>(select md5(jsonb_agg(to_jsonb(x)order by id)::text)from marathon.movimientos x)then raise exception 'Se modificó dinero por editar cuota';end if;
 -- La próxima cuota usa la tarifa nueva; el reloj se simula solo en esta transacción local.
 execute format('create or replace function marathon.agenda_hoy()returns date language sql stable set search_path=''''as %L','select '||quote_literal((d+40)::text)||'::date');
 perform marathon.agenda_cuotas_generar(d+40);
 if not exists(select 1 from marathon.agenda_cuotas where plan_id=pm and fecha>d and importe=3000)or(select importe from marathon.agenda_cuotas where id=qid)<>2000 then raise exception 'La generación futura no respetó la vigencia de tarifas';end if;
 if has_table_privilege('authenticated','marathon.agenda_tarifas','select')or has_function_privilege('authenticated','marathon.agenda_tarifa(uuid,date)','execute')then raise exception 'Condiciones internas expuestas';end if;
 raise notice 'PASS: condiciones desde fecha, presente y cobro anterior conservados, generación indefinida, excepción individual, cuota impaga actualizada, cuota pagada protegida y Caja intacta.';
end$$;
rollback;
