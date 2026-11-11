create function marathon.excepcion_run(p_request_id text,p_data jsonb)returns jsonb language plpgsql set search_path=''set lock_timeout='5s'as $$
declare reply jsonb;d date;site text;prof text;therapy text;person text;at_hour time;duration integer;cost numeric;cov jsonb;memo text;tid text;old marathon.turnos%rowtype;after_row jsonb;begin
 reply=marathon.operation_begin(p_request_id,'agenda:excepcion',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['date','site','prof','therapy','dni','time','amount','coverage','notes','id','version']))then raise exception 'La atención excepcional permite un único turno.'using errcode='22023';end if;
 d=marathon.agenda_date(p_data->>'date');site=marathon.master_text(p_data,'site',40,true);prof=marathon.master_text(p_data,'prof',100,true);therapy=marathon.master_text(p_data,'therapy',100,true);person=marathon.master_text(p_data,'dni',12,true);
 if d>marathon.agenda_hoy()+366 then raise exception 'Elegí una fecha hasta un año en adelante.'using errcode='22023';end if;
 if person!~'^[0-9]{1,12}$'or not exists(select 1 from marathon.pacientes where dni=person)then raise exception 'Seleccioná un paciente registrado.'using errcode='22023';end if;
 if coalesce(p_data->>'time','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$'or jsonb_typeof(p_data->'amount')is distinct from'number'or coalesce(p_data->>'amount','')!~'^[0-9]{1,10}(\.[0-9]{1,2})?$'then raise exception 'Revisá la hora y el importe de la sesión.'using errcode='22023';end if;
 at_hour=(p_data->>'time')::time;cost=(p_data->>'amount')::numeric;
 select duracion_min into duration from marathon.terapias where id=therapy and estado='ACTIVO';
 if duration is null then raise exception 'Seleccioná una terapia activa.'using errcode='22023';end if;
 cov=marathon.normalize_turn_coverage(person,p_data->'coverage');memo=coalesce(marathon.master_text(p_data,'notes',1000),'');
 if nullif(p_data->>'id','')is not null then
  select *into old from marathon.turnos where id=p_data->>'id'for update;
  if old.id is null or not coalesce(old.excepcional,false)or old.estado<>'PENDIENTE'or old.dni<>person or old.version<>marathon.operation_version(p_data)then raise exception 'El turno cambió. Volvé a abrir su edición.'using errcode='PT409';end if;
  if marathon.turn_paid(old.id)>0 then raise exception 'El turno tiene pagos aplicados. Revisalos antes de editar.'using errcode='22023';end if;
  tid=old.id;
 else tid='TUR-'||gen_random_uuid()::text;end if;
 if exists(select 1 from marathon.agenda_pool(d)x where x.dni=person and x.id<>tid and x.hora<at_hour+make_interval(mins=>duration)and at_hour<x.hora+make_interval(mins=>x.duracion_min))then raise exception 'El paciente ya tiene una atención o reserva que se superpone.'using errcode='PT409';end if;
 reply=marathon.excepcion_cupo(d,site,prof,therapy,at_hour,duration,tid);
 if coalesce((reply->>'blocked')::boolean,true)or coalesce((reply->>'remaining')::int,0)<1 then raise exception 'El profesional no está habilitado para esa terapia o tiene una atención incompatible en ese horario.'using errcode='PT409';end if;
 if memo not like 'Atención excepcional%'then memo='Atención excepcional'||case when memo=''then''else E'\n'||memo end;end if;
 if old.id is null then
  insert into marathon.turnos(id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,coverage,observaciones,booking_notes,excepcional,attendance_manual_date,created_by,updated_by)
  values(tid,d,site,at_hour,duration,therapy,prof,person,cost,'PENDIENTE',cov,memo,memo,true,case when d<marathon.agenda_hoy()then d end,auth.uid(),auth.uid());
 else
  update marathon.turnos set fecha=d,sede=site,hora=at_hour,duracion_min=duration,terapia_id=therapy,profesional_id=prof,importe=cost,coverage=cov,booking_notes=memo,attendance_manual_date=case when d<marathon.agenda_hoy()then d end where id=tid;
 end if;
 select to_jsonb(t)into after_row from marathon.turnos t where id=tid;
 insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,auth.uid(),tid,case when old.id is null then'book_exception'else'edit_exception'end,case when old.id is null then null else to_jsonb(old)end,after_row);
 reply=jsonb_build_object('ids',jsonb_build_array(tid),'exceptional',true,'turn',after_row,'message',case when old.id is null then'Atención excepcional reservada. Se conservó el horario habitual.'else'Atención excepcional actualizada.'end);
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end$$;
create function public.marathon_excepcion_prever(p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$
declare reply jsonb;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 begin reply=marathon.excepcion_run('preview-'||gen_random_uuid(),p_data);raise exception using errcode='ZP001',message='Solo vista previa';exception when sqlstate 'ZP001'then null;end;
 return reply||jsonb_build_object('preview',true);
end$$;
create function public.marathon_excepcion_guardar(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $$begin return marathon.excepcion_run(p_request_id,p_data);end$$;
