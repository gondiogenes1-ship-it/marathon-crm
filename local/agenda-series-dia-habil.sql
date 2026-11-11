-- Datos sintéticos y cambios de prueba revertidos por completo.
begin;
create or replace function marathon.agenda_hoy()returns date language sql stable set search_path=''as $$select date '2026-11-05'$$;

do $$declare uid uuid;h record;h2 record;d date:=marathon.agenda_hoy();r jsonb;c jsonb;data jsonb;saved jsonb;t marathon.turnos%rowtype;pid uuid;oldid text;before_hash text;cash_before text;newtime text;failed boolean:=false;begin
 select user_id into uid from marathon.app_users where active and role='SECRETARIA'order by user_id limit 1;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 if exists(select 1 from marathon.pacientes where dni in('99999111','99999112','99999113'))then raise exception 'Fixture ocupado';end if;
 select x.*,pt.terapia_id into h from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id join marathon.terapias th on th.id=pt.terapia_id
 where x.dia=extract(dow from d)::int and x.fin-x.inicio>=interval '2 hours'and th.estado='ACTIVO'and th.capacidad>=5
 and(marathon.agenda_cupo(d,x.sede,x.profesional_id,pt.terapia_id,x.inicio)->>'remaining')::int>=3 order by th.capacidad desc,x.inicio limit 1;
 if h.id is null then raise exception 'No hay horario para fixture';end if;
 newtime=to_char(h.inicio+interval '1 hour','HH24:MI');
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99999111','SERIE','ZZ_QA',uid,uid),('99999112','SERIE','ZZ_QA',uid,uid),('99999113','SERIE','ZZ_QA',uid,uid);
 select md5(jsonb_agg(to_jsonb(x)order by id)::text)into cash_before from marathon.movimientos x;
 data=jsonb_build_object('dni','99999111','therapy',h.terapia_id,'mode','fixed','billing','none','amount',0,'start',d,'coverage',jsonb_build_object('type','ART','name','Prueba','affiliate',''),'notes','Prueba revertida','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-series-create-'||gen_random_uuid(),'create',data);pid=(r->>'id')::uuid;
 perform marathon.agenda_materializar(d,d+28);
 select *into t from marathon.turnos where plan_id=pid and fecha=d;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','cancel','scope','single');
 select md5(jsonb_build_object('turns',(select jsonb_agg(to_jsonb(x)order by id)from marathon.turnos x),'requests',(select count(*)from marathon.solicitudes),'audit',(select count(*)from marathon.turn_audit))::text)into before_hash;
 r=public.marathon_turn_series_preview(data);
 if before_hash<>md5(jsonb_build_object('turns',(select jsonb_agg(to_jsonb(x)order by id)from marathon.turnos x),'requests',(select count(*)from marathon.solicitudes),'audit',(select count(*)from marathon.turn_audit))::text)then raise exception 'Preview persistió cambios';end if;
 r=public.marathon_turn_series_save('qa-series-cancel-'||gen_random_uuid(),data);
 if exists(select 1 from marathon.agenda_pool(d)where plan_id=pid)or not exists(select 1 from marathon.agenda_pool(d+140)where plan_id=pid)then raise exception 'Cancelación individual tocó repetición';end if;
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','cancel','scope','following');
 r=public.marathon_turn_series_save('qa-series-end-'||gen_random_uuid(),data);
 if exists(select 1 from marathon.agenda_pool(d+140)where plan_id=pid)or(select baja from marathon.agenda_planes where id=pid)<>d+7 then raise exception 'No terminó la serie indefinida';end if;
 -- Segunda serie: preservar presente anterior, editar las siguientes y la regla indefinida.
 data=jsonb_build_object('dni','99999112','therapy',h.terapia_id,'mode','fixed','billing','none','amount',0,'start',d,'coverage',jsonb_build_object('type','ART','name','Prueba','affiliate',''),'notes','Prueba revertida','schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'site',h.sede,'prof',h.profesional_id,'time',to_char(h.inicio,'HH24:MI'))));
 r=public.marathon_agenda_plan_command('qa-series-create-'||gen_random_uuid(),'create',data);pid=(r->>'id')::uuid;perform marathon.agenda_materializar(d,d+28);
 select *into t from marathon.turnos where plan_id=pid and fecha=d;oldid=t.id;
 perform public.marathon_agenda_command('qa-series-present-'||gen_random_uuid(),'status',jsonb_build_object('id',t.id,'version',t.version,'estado','PRESENTE'));
 select *into t from marathon.turnos where plan_id=pid and fecha=d+21;
 perform public.marathon_agenda_command('qa-series-except-'||gen_random_uuid(),'status',jsonb_build_object('id',t.id,'version',t.version,'estado','CANCELADO'));
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'time',newtime,'site',h.sede,'prof',h.profesional_id)));
 r=public.marathon_turn_series_preview(data);
 r=public.marathon_turn_series_save('qa-series-edit-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.agenda_pool(d+140)where plan_id=pid and hora=newtime::time)then raise exception 'La edición no cambió las repeticiones indefinidas';end if;
 if not exists(select 1 from marathon.turnos where id=oldid and estado='PRESENTE'and hora=h.inicio)then raise exception 'Se alteró el presente anterior';end if;
 if exists(select 1 from marathon.agenda_pool(d+21)where plan_id=pid)then raise exception 'Se regeneró una excepción cancelada';end if;
 begin perform public.marathon_turn_series_save('qa-series-stale-'||gen_random_uuid(),data);exception when sqlstate 'PT409'then failed=true;end;
 if not failed then raise exception 'No detectó vista previa obsoleta';end if;
 -- Un conflicto lejano (fuera de las próximas semanas) revierte toda la edición.
 r=public.marathon_agenda_command('qa-series-block-'||gen_random_uuid(),'book',jsonb_build_object('dni','99999112','therapy',h.terapia_id,'sede',h.sede,'prof',h.profesional_id,'hora',to_char(h.inicio,'HH24:MI'),'importe',0,'dates',jsonb_build_array(d+140),'observaciones','Conflicto lejano de prueba','coverage',jsonb_build_object('type','ART','name','Prueba','affiliate','')));
 select *into t from marathon.turnos where plan_id=pid and fecha=d+7;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'time',to_char(h.inicio,'HH24:MI'),'site',h.sede,'prof',h.profesional_id);failed=false;
 begin perform public.marathon_turn_series_save('qa-series-conflict-'||gen_random_uuid(),data);exception when sqlstate 'PT409'or sqlstate '22023'then failed=true;end;
 if not failed or(public.marathon_turn_series_context(t.id)->>'huella')<>(c->>'huella')then raise exception 'No revirtió el conflicto lejano';end if;
 -- Series finitas anteriores: el alcance comienza en el día seleccionado.
 r=public.marathon_agenda_command('qa-series-legacy-'||gen_random_uuid(),'book',jsonb_build_object('dni','99999113','therapy',h.terapia_id,'sede',h.sede,'prof',h.profesional_id,'hora',to_char(h.inicio,'HH24:MI'),'importe',0,'dates',jsonb_build_array(d,d+7,d+14),'observaciones','Serie finita de prueba','coverage',jsonb_build_object('type','ART','name','Prueba','affiliate','')));
 select *into t from marathon.turnos where dni='99999113'and fecha=d+7;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','following','date',t.fecha,'time',newtime,'site',h.sede,'prof',h.profesional_id);
 r=public.marathon_turn_series_save('qa-series-legacyedit-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.turnos where dni='99999113'and fecha=d and hora=h.inicio)or(select count(*)from marathon.turnos where dni='99999113'and fecha>d and hora=newtime::time)<>2 then raise exception 'Se editó fuera del alcance de la serie finita';end if;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','cancel','scope','following');
 r=public.marathon_turn_series_save('qa-series-legacycancel-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.turnos where dni='99999113'and fecha=d and estado='PENDIENTE')or exists(select 1 from marathon.turnos where dni='99999113'and fecha>d and estado<>'CANCELADO')then raise exception 'Se canceló fuera del alcance finito';end if;
 -- Edición individual mediante el mismo payload del formulario de reserva.
 select *into t from marathon.turnos where dni='99999113'and fecha=d;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','single','date',t.fecha,'schedules',jsonb_build_array(jsonb_build_object('day',h.dia,'time',newtime,'site',h.sede,'prof',h.profesional_id)));
 r=public.marathon_turn_series_save('qa-series-singleedit-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.turnos where id=t.id and hora=newtime::time)or exists(select 1 from marathon.turnos where dni='99999113'and fecha>d and estado<>'CANCELADO')then raise exception 'Edición individual alteró otras sesiones';end if;
 -- Mover una sesión a otro día conserva su identidad y las otras cancelaciones.
 select x.*into h2 from marathon.horarios x join marathon.profesional_terapias pt on pt.profesional_id=x.profesional_id and pt.terapia_id=h.terapia_id where x.dia=extract(dow from d+1)::int and(marathon.agenda_cupo(d+1,x.sede,x.profesional_id,h.terapia_id,x.inicio)->>'remaining')::int>0 order by x.inicio limit 1;
 if h2.id is null then raise exception 'Fixture sin disponibilidad al día siguiente';end if;
 c=public.marathon_turn_series_context(t.id);data=jsonb_build_object('id',t.id,'huella',c->>'huella','action','edit','scope','single','date',d+1,'schedules',jsonb_build_array(jsonb_build_object('day',h2.dia,'time',to_char(h2.inicio,'HH24:MI'),'site',h2.sede,'prof',h2.profesional_id)));
 r=public.marathon_turn_series_save('qa-series-date-'||gen_random_uuid(),data);
 if not exists(select 1 from marathon.turnos where id=t.id and fecha=d+1)then raise exception 'No se cambió la fecha';end if;
 if cash_before<>(select md5(jsonb_agg(to_jsonb(x)order by id)::text)from marathon.movimientos x)then raise exception 'Se alteró Caja';end if;
 if has_function_privilege('anon','public.marathon_turn_series_save(text,jsonb)','execute')or has_function_privilege('authenticated','marathon.turn_series_run(text,jsonb)','execute')then raise exception 'Permisos incorrectos';end if;
 raise notice 'PASS: preview reversible, cancelación individual y futura, baja indefinida, edición futura, presente anterior, excepción cancelada, huella obsoleta, Caja y permisos.';
end$$;
rollback;
