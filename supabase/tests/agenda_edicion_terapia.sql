-- Solo ejecutar en la copia local. Fixtures y cambios se revierten completos.
begin;
do $$declare uid uuid;h record;d date:=marathon.agenda_hoy();r jsonb;c jsonb;data jsonb;pid uuid;t marathon.turnos%rowtype;prev jsonb;cash_hash text;failed boolean:=false;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id where x.dia=extract(dow from d)::int and x.fin-x.inicio>=interval '2 hours'and th.estado='ACTIVO'and th.capacidad>=5 and(marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int>=3 order by th.capacidad desc,x.inicio limit 1;
 if h.id is null then raise exception 'Sin horario de prueba';end if;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999301','TERAPIA','ZZ_QA',uid,uid);
 insert into marathon.terapias(id,especialidad,nombre,duracion_min,capacidad,estado)select 'ZZ_QA_TERAPIA',especialidad,'Terapia de prueba',30,capacidad,'ACTIVO'from marathon.terapias where id=h.terapia_id;
 insert into marathon.profesional_terapias(profesional_id,terapia_id)values(h.profesional_id,'ZZ_QA_TERAPIA');
 data=jsonb_build_object('dni','99999301','therapy',h.terapia_id,'mode','fixed','billing','class','amount',1000,'start',d,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Original','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-therapy-create-'||gen_random_uuid(),'create',data);pid=(r->>'id')::uuid;perform marathon.agenda_materializar(d,d+28);
 select to_jsonb(x)into prev from marathon.turnos x where plan_id=pid and fecha=d;
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)into cash_hash from marathon.movimientos x;
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;c=public.marathon_turn_series_context(t.id);
 data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'therapy','ZZ_QA_TERAPIA','time',to_char(h.inicio,'HH24:MI'),'site',h.sede,'prof',h.profesional_id,'amount',1500,'notes','Cambio de terapia');
 r=public.marathon_turn_series_preview(data);
 if(select terapia_id from marathon.turnos where id=t.id)<>h.terapia_id then raise exception 'La vista previa modificó datos';end if;
 r=public.marathon_turn_series_save('qa-therapy-save-'||gen_random_uuid(),data);
 if(select to_jsonb(x)from marathon.turnos x where plan_id=pid and fecha=d)<>prev then raise exception 'Cambió la sesión anterior';end if;
 if exists(select 1 from marathon.turnos where plan_id=pid and fecha>=d+7 and(terapia_id<>'ZZ_QA_TERAPIA'or importe<>1500))then raise exception 'No cambió la serie';end if;
 if not exists(select 1 from marathon.agenda_virtual(d+140)where plan_id=pid and terapia_id='ZZ_QA_TERAPIA')then raise exception 'No cambió repetición virtual';end if;
 perform marathon.agenda_materializar(d+140,d+140);
 if not exists(select 1 from marathon.turnos where plan_id=pid and fecha=d+140 and terapia_id='ZZ_QA_TERAPIA'and importe=1500)then raise exception 'No se materializó la terapia nueva';end if;
 -- Cambiar solo una sesión no cambia las posteriores.
 select *into t from marathon.turnos where plan_id=pid and fecha=d+14;c=public.marathon_turn_series_context(t.id);
 data=data||jsonb_build_object('id',t.id,'huella',c->>'huella','scope','single','date',t.fecha,'therapy',h.terapia_id);
 r=public.marathon_turn_series_save('qa-therapy-single-'||gen_random_uuid(),data);
 if(select terapia_id from marathon.turnos where id=t.id)<>h.terapia_id or(select terapia_id from marathon.turnos where plan_id=pid and fecha=d+21)<>'ZZ_QA_TERAPIA'then raise exception 'Alcance individual incorrecto';end if;
 c=public.marathon_turn_series_context(t.id);data=data||jsonb_build_object('huella',c->>'huella','therapy','NO_EXISTE');
 begin perform public.marathon_turn_series_save('qa-therapy-invalid-'||gen_random_uuid(),data);exception when sqlstate '22023'then failed=true;end;
 if not failed then raise exception 'Permitió terapia inexistente';end if;
 if cash_hash<>(select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.movimientos x)then raise exception 'Modificó Caja';end if;
 -- La nueva terapia sigue permitiendo registrar asistencia y cobrarla.
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;
 perform public.marathon_agenda_command('qa-therapy-present-'||gen_random_uuid(),'status',jsonb_build_object('id',t.id,'version',t.version,'estado','PRESENTE'));
 data=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99999301','monto','1500','medio','TRANSFERENCIA','sede',h.sede,'fecha',d);c=public.marathon_saldo_prever(data);
 perform public.marathon_saldo_command('qa-therapy-payment-'||gen_random_uuid(),data||jsonb_build_object('version',c->>'version','huella',c->>'huella'));
 if marathon.turn_paid(t.id)<>1500 then raise exception 'No permite cobrar la terapia editada';end if;
 raise notice 'PASS: terapia individual y futura, vista previa sin efectos, repetición indefinida, historia y Caja intactas, terapia inválida rechazada.';
end$$;
rollback;
