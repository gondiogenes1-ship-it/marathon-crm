-- Ejecutar en la copia local: se revierten pacientes, sesiones, cuotas y configuración.
begin;
do $$declare uid uuid;h record;d date:=marathon.agenda_hoy();r jsonb;data jsonb;pid uuid;pastpid uuid;openpid uuid;failed boolean;key text;cash_hash text;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id where x.dia=extract(dow from d)::int and th.estado='ACTIVO'and th.capacidad>=5 and(marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int>=4 order by th.capacidad desc,x.inicio limit 1;
 if h.id is null then raise exception 'Sin horario de prueba';end if;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999401','MENSUAL','ZZ_QA',uid,uid),('99999402','MENSUAL PASADA','ZZ_QA',uid,uid),('99999403','MENSUAL ABIERTA','ZZ_QA',uid,uid);
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)into cash_hash from marathon.movimientos x;
 data=jsonb_build_object('dni','99999401','therapy',h.terapia_id,'mode','monthly','billing','monthly','amount',1000,'start',d-35,'end',d+7,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Fechas de prueba','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 key='qa-monthly-dates-'||gen_random_uuid();r=public.marathon_agenda_plan_command(key,'create',data);pid=(r->>'id')::uuid;
 if(select baja from marathon.agenda_planes where id=pid)<>d+8 or not(select registro_retroactivo from marathon.agenda_planes where id=pid)then raise exception 'Límites de plan incorrectos';end if;
 if exists(select 1 from marathon.agenda_horarios where plan_id=pid and hasta<>d+8)or exists(select 1 from marathon.agenda_periodos where plan_id=pid and fin<>d+8)then raise exception 'No se acotó agenda o cuotas';end if;
 if(select count(*)from marathon.agenda_cuotas where plan_id=pid)<>2 then raise exception 'Cuotas retroactivas incorrectas';end if;
 perform marathon.agenda_materializar(d-7,d+8);
 if not exists(select 1 from marathon.turnos where plan_id=pid and fecha=d+7)or exists(select 1 from marathon.turnos where plan_id=pid and(fecha<d-35 or fecha>d+7))then raise exception 'Fin no inclusivo o sesiones fuera del período';end if;
 if exists(select 1 from marathon.agenda_virtual(d+14)where plan_id=pid)then raise exception 'La agenda continúa fuera del fin';end if;
 if exists(select 1 from marathon.turnos where plan_id=pid and fecha<d and(estado<>'PENDIENTE'or attendance_manual_date is distinct from fecha))then raise exception 'Asistencia retroactiva incorrecta';end if;
 update marathon.attendance_settings set enabled=true,start_date=d-90 where id=true;
 perform marathon.attendance_rollover(d,h.profesional_id);
 if exists(select 1 from marathon.turnos where plan_id=pid and fecha<d and estado<>'PENDIENTE')then raise exception 'Convirtió carga retroactiva en ausencia';end if;
 if(public.marathon_agenda_plan_command(key,'create',data)->>'id')::uuid<>pid then raise exception 'El reintento duplicó la serie';end if;
 -- Período completamente pasado: no genera cuotas ni lugares posteriores al fin.
 data=data||jsonb_build_object('dni','99999402','end',d-7);r=public.marathon_agenda_plan_command('qa-monthly-past-'||gen_random_uuid(),'create',data);pastpid=(r->>'id')::uuid;
 if(select count(*)from marathon.agenda_cuotas where plan_id=pastpid)<>1 or exists(select 1 from marathon.agenda_cuotas where plan_id=pastpid and fecha>d-7)or exists(select 1 from marathon.agenda_virtual(d)where plan_id=pastpid)then raise exception 'Renovó un período pasado finalizado';end if;
 -- Fin vacío mantiene el comportamiento mensual continuo.
 data=(data-'end')||jsonb_build_object('dni','99999403','start',d);r=public.marathon_agenda_plan_command('qa-monthly-open-'||gen_random_uuid(),'create',data);openpid=(r->>'id')::uuid;
 if(select baja from marathon.agenda_planes where id=openpid)is not null or not exists(select 1 from marathon.agenda_virtual(d+140)where plan_id=openpid)then raise exception 'Se perdió continuidad sin fin';end if;
 failed=false;begin perform public.marathon_agenda_plan_command('qa-monthly-invalid-'||gen_random_uuid(),'create',data||jsonb_build_object('end',d-1));exception when sqlstate '22023'then failed=true;end;if not failed then raise exception 'Aceptó fin anterior al inicio';end if;
 failed=false;begin perform public.marathon_agenda_plan_command('qa-sessions-retro-'||gen_random_uuid(),'create',(data-'end')||jsonb_build_object('mode','sessions','total',2,'start',d-7));exception when sqlstate '22023'then failed=true;end;if not failed then raise exception 'Habilitó retroactivo en otra modalidad';end if;
 if cash_hash<>(select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.movimientos x)then raise exception 'Creó o modificó dinero en Caja';end if;
 raise notice 'PASS: mensual con inicio retroactivo, fin inclusivo, cuotas acotadas, pendientes sin ausencia automática, continuidad opcional, validaciones, reintentos y Caja intacta.';
end$$;
rollback;
