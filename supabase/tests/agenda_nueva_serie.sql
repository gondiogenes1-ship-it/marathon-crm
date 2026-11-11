begin;
do $$declare uid uuid;h record;d date:=marathon.agenda_hoy();booking jsonb;r jsonb;seed jsonb;data jsonb;payment jsonb;v jsonb;oldpid uuid;newpid uuid;start_date date;oldbonus text;oldcash text;oldturns jsonb;key text;failed boolean;before_count int;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 if exists(select 1 from marathon.pacientes where dni in('99999301','99999302'))then raise exception 'Fixture ocupado';end if;
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id where x.dia=extract(dow from d)::int and th.estado='ACTIVO'and th.capacidad>=5 and(marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int>=3 order by th.capacidad desc,x.inicio limit 1;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999301','NUEVA SERIE','ZZ_QA',uid,uid),('99999302','OTRO PACIENTE','ZZ_QA',uid,uid);
 booking=jsonb_build_object('dni','99999301','therapy',h.terapia_id,'mode','sessions','billing','bonus_class','amount',1000,'bonus_amount',200,'bonus_paid',false,'total',2,'start',d,'coverage',jsonb_build_object('type','PARTICULAR'),'notes','Original','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-new-series-old-'||gen_random_uuid(),'create',booking);oldpid=(r->>'id')::uuid;oldbonus=r->'bonus'->>'id';
 if oldbonus is null then raise exception 'Fixture sin bono';end if;
 payment=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99999301','monto','200','medio','TRANSFERENCIA','sede',h.sede,'fecha',d);v=public.marathon_saldo_prever(payment);perform public.marathon_saldo_command('qa-new-series-paid-'||gen_random_uuid(),payment||jsonb_build_object('version',v->>'version','huella',v->>'huella'));
 seed=public.marathon_extension_context(oldpid::text);
 if seed->>'billing'<>'bonus_class'or(seed->>'bonus_amount')::numeric<>200 or(seed->>'importe')::numeric<>1000 or seed->'coverage'->>'type'<>'PARTICULAR'or(seed->>'total')::int<>2 then raise exception 'No se precargaron todos los datos';end if;
 start_date=(seed->>'after_date')::date;start_date=start_date+((h.dia-extract(dow from start_date)::int+7)%7);
 booking=booking||jsonb_build_object('start',start_date,'total',3,'amount',1500,'bonus_amount',500,'coverage',jsonb_build_object('type','CLUB','name','Nuevo club'),'notes','Nueva serie modificada');
 data=jsonb_build_object('source_id',seed->>'source_id','source_huella',seed->>'source_huella','booking',booking);
 -- No se cancelan turnos ya agendados cuando se elige un inicio anterior.
 failed=false;begin perform public.marathon_agenda_continue('qa-new-series-overlap-'||gen_random_uuid(),data||jsonb_build_object('booking',booking||jsonb_build_object('start',d)));exception when sqlstate '22023'then failed=true;end;
 if not failed or(select baja from marathon.agenda_planes where id=oldpid)is not null then raise exception 'Se cerró la serie con turnos pendientes';end if;
 -- Si falla la reserva nueva, se revierte también el cierre de la anterior.
 failed=false;begin perform public.marathon_agenda_continue('qa-new-series-invalid-'||gen_random_uuid(),data||jsonb_build_object('booking',booking||jsonb_build_object('schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof','NO_EXISTE_QA','time',to_char(h.inicio,'HH24:MI'))))));exception when others then failed=true;end;
 if not failed or(select baja from marathon.agenda_planes where id=oldpid)is not null then raise exception 'El cierre no fue atómico';end if;
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into oldcash from marathon.movimientos x;select jsonb_agg(to_jsonb(x)order by id)into oldturns from marathon.turnos x where x.plan_id=oldpid;
 key='qa-new-series-save-'||gen_random_uuid();r=public.marathon_agenda_continue(key,data);newpid=(r->>'id')::uuid;
 if newpid=oldpid or(select baja from marathon.agenda_planes where id=oldpid)<>start_date or(select count(*)from marathon.agenda_autorizaciones where plan_id=newpid and cantidad=3)<>1 then raise exception 'No creó una serie independiente';end if;
 if(select jsonb_agg(to_jsonb(x)order by id)from marathon.turnos x where x.plan_id=oldpid)<>oldturns then raise exception 'Se cambiaron turnos anteriores';end if;
 if r->'bonus'->>'id'is null or r->'bonus'->>'id'=oldbonus or(r->'bonus'->>'importe')::numeric is distinct from 500 or marathon.saldo_pagado('bono',oldbonus)<>200 then raise exception 'Se reutilizó el bono o su pago anterior';end if;
 if not exists(select 1 from marathon.turnos where plan_id=newpid and importe=1500 and coverage->>'type'='CLUB'and booking_notes='Nueva serie modificada'and hora=h.inicio)then raise exception 'No respetó los datos modificados';end if;
 before_count=(select count(*)from marathon.bonos_serie);if public.marathon_agenda_continue(key,data)<>r or(select count(*)from marathon.bonos_serie)<>before_count then raise exception 'Reintento duplicó la reserva';end if;
 if oldcash<>(select md5(jsonb_agg(to_jsonb(x)order by id)::text)from marathon.movimientos x)then raise exception 'Copió pagos o cambió Caja';end if;
 -- Cambiar el paciente permite una reserva normal sin modificar el tratamiento de origen.
 seed=public.marathon_extension_context(oldpid::text);data=data||jsonb_build_object('source_id',seed->>'source_id','source_huella',seed->>'source_huella');
 r=public.marathon_agenda_continue('qa-new-series-other-'||gen_random_uuid(),data||jsonb_build_object('booking',booking||jsonb_build_object('dni','99999302','mode','fixed','billing','class','bonus_amount',0,'amount',1200,'notes','Otro paciente')));
 if(select baja from marathon.agenda_planes where id=oldpid)<>start_date or not exists(select 1 from marathon.agenda_planes where id=(r->>'id')::uuid and dni='99999302'and importe=1200)then raise exception 'Cambiar paciente afectó el tratamiento anterior';end if;
 if has_function_privilege('anon','public.marathon_agenda_continue(text,jsonb)','execute')then raise exception 'Acceso anónimo';end if;
 raise notice 'PASS: precarga completa, nueva serie independiente, nuevo bono sin copiar pago, datos editables, cierre desde nuevo inicio, pendientes anteriores intactos, atomicidad y reintentos.';
end$$;
rollback;
