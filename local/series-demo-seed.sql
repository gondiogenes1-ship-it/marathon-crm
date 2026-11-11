-- Solo demostración aislada con identidades ficticias.
do $$declare uid uuid:='00000000-0000-4000-8000-000000009901';r jsonb;begin
 if current_database()<>'marathon_saldo_demo_20261104'then raise exception 'Solo demo';end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 if exists(select 1 from marathon.pacientes where dni='99001004')then return;end if;
 insert into marathon.pacientes(dni,nombre,apellido,created_by,updated_by)values('99001004','Valentina','Serie de prueba',uid,uid);
 r=public.marathon_agenda_plan_command('demo-series-'||gen_random_uuid(),'create',jsonb_build_object('dni','99001004','therapy','MARATHON','mode','fixed','billing','none','amount',0,'start',marathon.agenda_hoy(),'coverage',jsonb_build_object('type','ART','name','Demostración','affiliate',''),'notes','Paciente ficticio para probar edición y cancelación de serie.','schedules',jsonb_build_array(jsonb_build_object('day',extract(dow from marathon.agenda_hoy())::int,'site','MARATHON','prof','MARATHON','time','12:00'))));
end$$;
