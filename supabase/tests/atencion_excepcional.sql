-- Solo copia local. Todo se revierte; ningún paciente ni movimiento real se modifica.
begin;
do $$declare uid uuid;h record;d date:=marathon.agenda_hoy()-1;r jsonb;data jsonb;v jsonb;tid text;cash_before text;hours_before text;old_count int;failed boolean;request text;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 select p.id profesional_id,pt.terapia_id,s.nombre sede from marathon.profesionales p join marathon.profesional_terapias pt on pt.profesional_id=p.id join marathon.terapias th on th.id=pt.terapia_id cross join marathon.sedes s where p.estado='ACTIVO'and th.estado='ACTIVO'and s.estado='ACTIVO'and th.duracion_min<=60 order by p.id,s.nombre limit 1 into h;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999501','EXCEPCIONAL','ZZ_QA',uid,uid),('99999502','SUPERPOSICION','ZZ_QA',uid,uid);
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)into cash_before from marathon.movimientos x;
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)into hours_before from marathon.horarios x;
 select count(*)into old_count from marathon.turnos;
 data=jsonb_build_object('date',d,'site',h.sede,'prof',h.profesional_id,'therapy',h.terapia_id,'dni','99999501','time','22:00','amount',3500,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Consulta puntual');
 r=public.marathon_excepcion_prever(data);
 if(select count(*)from marathon.turnos)<>old_count then raise exception 'La vista previa creó turnos';end if;
 request='qa-exception-'||gen_random_uuid();r=public.marathon_excepcion_guardar(request,data);tid=r->'turn'->>'id';
 if not exists(select 1 from marathon.turnos where id=tid and excepcional and estado='PENDIENTE'and fecha=d and attendance_manual_date=d and plan_id is null and original_id is null and importe=3500)then raise exception 'Reserva excepcional incorrecta';end if;
 if(public.marathon_excepcion_guardar(request,data)->'turn'->>'id')<>tid or(select count(*)from marathon.turnos)<>old_count+1 then raise exception 'El reintento duplicó el turno';end if;
 failed=false;begin perform public.marathon_excepcion_guardar('qa-exception-overlap-'||gen_random_uuid(),data);exception when sqlstate 'PT409'then failed=true;end;
 if not failed then raise exception 'Permitió superposición del paciente';end if;
 -- Cambiar profesional/terapia/importe/día usa el mismo turno, no una serie.
 data=data||jsonb_build_object('id',tid,'version',(r->'turn'->>'version')::bigint,'time','22:15','amount',4000);
 r=public.marathon_excepcion_guardar('qa-exception-edit-'||gen_random_uuid(),data);
 if(select count(*)from marathon.turnos)<>old_count+1 or(r->'turn'->>'importe')::numeric<>4000 then raise exception 'Edición incorrecta';end if;
 r=public.marathon_agenda_command('qa-exception-cancel-'||gen_random_uuid(),'status',jsonb_build_object('id',tid,'version',(r->'turn'->>'version')::bigint,'estado','CANCELADO'));
 r=public.marathon_agenda_command('qa-exception-restore-'||gen_random_uuid(),'status',jsonb_build_object('id',tid,'version',(select version from marathon.turnos where id=tid),'estado','PENDIENTE'));
 if not exists(select 1 from marathon.turnos where id=tid and estado='PENDIENTE')then raise exception 'No restauró fuera de horario';end if;
 if hours_before<>(select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.horarios x)then raise exception 'Cambió el horario habitual';end if;
 if cash_before<>(select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.movimientos x)then raise exception 'Cambió Caja al reservar';end if;
 -- Se marca Presente y se cobra con el circuito habitual.
 perform public.marathon_agenda_command('qa-exception-present-'||gen_random_uuid(),'status',jsonb_build_object('id',tid,'version',(select version from marathon.turnos where id=tid),'estado','PRESENTE'));
 if exists(select 1 from marathon.saldo_config where activo)then
 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99999501','monto','4000','medio','TRANSFERENCIA','sede',h.sede,'fecha',marathon.agenda_hoy());v=public.marathon_saldo_prever(data);
 perform public.marathon_saldo_command('qa-exception-paid-'||gen_random_uuid(),data||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 if marathon.turn_paid(tid)<>4000 then raise exception 'No permite cobrar la atención excepcional';end if;
 end if;
 -- La excepción no habilita horarios normales ni permite superposiciones entre sedes.
 if coalesce((marathon.agenda_cupo(d,h.sede,h.profesional_id,h.terapia_id,'22:15')->>'blocked')::boolean,false)is not true then raise exception 'El horario de prueba debe estar fuera de la agenda habitual';end if;
 insert into marathon.sedes(nombre,estado)values('ZZ_QA_EXCEPCION','ACTIVO');
 data=jsonb_build_object('date',d,'site','ZZ_QA_EXCEPCION','prof',h.profesional_id,'therapy',h.terapia_id,'dni','99999502','time','22:15','amount',1000,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Otra sede');
 failed=false;begin perform public.marathon_excepcion_prever(data);exception when sqlstate 'PT409'then failed=true;end;if not failed then raise exception 'Permitió profesional simultáneo en otra sede';end if;
 -- Un domingo sin horarios configurados también admite solo la reserva puntual.
 data=data||jsonb_build_object('date',d-extract(dow from d)::int,'site',h.sede,'time','21:15');
 r=public.marathon_excepcion_guardar('qa-exception-sunday-'||gen_random_uuid(),data);
 if not(r->'turn'->>'excepcional')::boolean or extract(dow from(r->'turn'->>'fecha')::date)<>0 then raise exception 'No admite día sin atención habitual';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000000',true);
 failed=false;begin perform public.marathon_excepcion_prever(data);exception when sqlstate '42501'then failed=true;end;if not failed then raise exception 'Permitió acceso sin usuario activo';end if;
 if has_function_privilege('authenticated','marathon.excepcion_run(text,jsonb)','execute')or has_function_privilege('anon','public.marathon_excepcion_guardar(text,jsonb)','execute')then raise exception 'Funciones expuestas sin autorización';end if;
 raise notice 'PASS: excepción retroactiva puntual, preview reversible, sin duplicados, superposición rechazada, edición y restauración, agenda habitual intacta, cobro por transferencia y permisos.';
end$$;
rollback;

