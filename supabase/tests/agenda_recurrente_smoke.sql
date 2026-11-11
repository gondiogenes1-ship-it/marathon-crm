-- Prueba controlada de los RPC instalados. Todas las filas sintéticas se revierten.
begin;
do $$
declare actor uuid;h record;d date:=marathon.agenda_hoy();payload jsonb;r jsonb;r2 jsonb;p jsonb;quota jsonb;t marathon.turnos%rowtype;key text:='QA-'||gen_random_uuid()::text;before_room int;after_room int;
begin
 select user_id into actor from marathon.app_users where active and role='ADMIN'order by created_at limit 1;
 if actor is null then raise exception 'Falta un usuario administrador para el contexto de prueba.';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 if exists(select 1 from marathon.pacientes where dni in('99999001','99999002'))then raise exception 'DNI sintético ocupado: la prueba no modifica pacientes existentes.';end if;
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id and th.estado='ACTIVO'
 where x.dia=extract(dow from d)::int and coalesce((marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int,0)>=2 order by th.capacidad desc,x.inicio,x.id limit 1;
 if h.id is null then raise exception 'No hay un horario hábil con dos lugares para una prueba sin sobrecupo.';end if;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999001','PRUEBA TRANSACCIONAL','ZZ_INTEGRACION',actor,actor),('99999002','PRUEBA TRANSACCIONAL','ZZ_INTEGRACION',actor,actor);
 payload=jsonb_build_object('dni','99999001','therapy',h.terapia_id,'mode','sessions','billing','none','amount',0,'start',d,'total',2,'coverage',jsonb_build_object('type','ART','name','Prueba transaccional','affiliate',''),'notes','No es un paciente real','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command(key,'create',payload);r2=public.marathon_agenda_plan_command(key,'create',payload);
 if r->>'id'<>r2->>'id'then raise exception 'Falló la idempotencia.';end if;
 select * into t from marathon.turnos where plan_id=(r->>'id')::uuid and fecha=d order by hora limit 1;
 perform public.marathon_agenda_command('QA-'||gen_random_uuid()::text,'status',jsonb_build_object('id',t.id,'version',t.version,'estado','PRESENTE'));
 if marathon.agenda_presentes((r->>'id')::uuid)<>1 then raise exception 'No se guardó el presente.';end if;
 r2=public.marathon_agenda_flexible(jsonb_build_object('from',d,'to',d),null,100);
 if not exists(select 1 from jsonb_array_elements(r2->'rows')x where x->>'id'=t.id and x->>'estado'='PRESENTE'and(x->'plan'->>'done')::int=1)then raise exception 'El presente no vuelve desde la búsqueda real.';end if;
 payload=payload||jsonb_build_object('dni','99999002','mode','monthly','billing','monthly','amount',1,'total',0);
 r=public.marathon_agenda_plan_command('QA-'||gen_random_uuid()::text,'create',payload);p=r->'plan';quota=p->'quotas'->0;
 if jsonb_array_length(p->'quotas')<>1 or(p->>'debt')::numeric<>1 then raise exception 'No se generó la cuota inicial.';end if;
 r=public.marathon_agenda_plan_command('QA-'||gen_random_uuid()::text,'quota_pay',jsonb_build_object('id',p->>'id','version',p->'version','quota',quota->>'id','amount',1,'medium','EFECTIVO'));p=r->'plan';
 if(p->>'debt')::numeric<>0 or not exists(select 1 from marathon.movimientos m where m.cuota_id=(quota->>'id')::uuid and m.monto=1 and m.tipo='INGRESO')then raise exception 'No se vinculó el pago de cuota con Caja.';end if;
 before_room=(marathon.agenda_cupo(d,h.sede,h.profesional_id,h.terapia_id,h.inicio)->>'remaining')::int;
 r=public.marathon_agenda_plan_command('QA-'||gen_random_uuid()::text,'pause',jsonb_build_object('id',p->>'id','version',p->'version','date',d,'reason','Pausa de prueba transaccional'));p=r->'plan';
 after_room=(marathon.agenda_cupo(d,h.sede,h.profesional_id,h.terapia_id,h.inicio)->>'remaining')::int;
 if not marathon.agenda_pausado((p->>'id')::uuid,d)or before_room<>after_room then raise exception 'La pausa no conservó su lugar.';end if;
 if has_function_privilege('anon','public.marathon_agenda_plan_command(text,text,jsonb)','EXECUTE')then raise exception 'Acceso anónimo no permitido.';end if;
end$$;
rollback;
select 'OK: reserva, idempotencia, presente, cuota, caja, pausa y permisos. Prueba revertida.' as resultado;
