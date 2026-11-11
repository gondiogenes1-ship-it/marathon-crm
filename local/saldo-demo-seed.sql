do $$begin if current_database()<>'marathon_saldo_demo_20261104'or exists(select 1 from marathon.pacientes)then raise exception 'Base de demostracion vacia requerida.';end if;end$$;
-- SOLO base aislada: datos sintéticos y ROLLBACK al finalizar.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id)values('00000000-0000-4000-8000-000000009901');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000009901';
insert into marathon.app_users(user_id,role,active,display_name)values(auth.uid(),'ADMIN',true,'Prueba aislada de saldo');
insert into marathon.sedes(nombre,estado)values('MARATHON','ACTIVO');
insert into marathon.terapias(id,nombre,especialidad,duracion_min,capacidad,estado)values('MARATHON','Terapia de prueba','QA',30,15,'ACTIVO');
insert into marathon.profesionales(id,nombre,apellido,estado)values('MARATHON','Profesional','Prueba','ACTIVO');
insert into marathon.profesional_terapias(profesional_id,terapia_id)values('MARATHON','MARATHON');
insert into marathon.horarios(id,profesional_id,sede,dia,inicio,fin)select 'SALDO-QA-'||d,'MARATHON','MARATHON',d,'08:00','18:00'from generate_series(0,6)d;
insert into marathon.pacientes(dni,nombre,apellido)values('99001001','Paciente','Uno'),('99001002','Paciente','Dos'),('99001003','Paciente','Tres');
insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)
values('SALDO-T1','2026-10-01','10:00','MARATHON','99001001','MARATHON','MARATHON',1000,'PRESENTE',30),('SALDO-T2','2026-10-02','10:00','MARATHON','99001001','MARATHON','MARATHON',500,'PRESENTE',30);

update marathon.app_users set display_name='Equipo demo';
update marathon.pacientes set nombre='Lucía',apellido='Pérez (ejemplo)'where dni='99001001';
update marathon.pacientes set nombre='Martín',apellido='Gómez (ejemplo)'where dni='99001002';
update marathon.pacientes set nombre='Sofía',apellido='López (ejemplo)'where dni='99001003';
update marathon.profesionales set nombre='Ana',apellido='Profesional demo';
update marathon.terapias set nombre='Kinesiología';
update marathon.turnos set fecha=case when id='SALDO-T1'then marathon.agenda_hoy()else marathon.agenda_hoy()-1 end,importe=case when id='SALDO-T1'then 15000 else 10000 end;
insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)values('SALDO-T3',marathon.agenda_hoy(),'11:00','MARATHON','99001002','MARATHON','MARATHON',15000,'PENDIENTE',30);
insert into marathon.agenda_planes(id,dni,terapia_id,modalidad,facturacion,importe,inicio,coverage)values('00000000-0000-4000-8000-000000009903','99001001','MARATHON','monthly','monthly',5000,'2026-11-01','{}');
insert into marathon.agenda_periodos(id,plan_id,inicio)values('00000000-0000-4000-8000-000000009904','00000000-0000-4000-8000-000000009903','2026-11-01');
insert into marathon.agenda_cuotas(id,plan_id,periodo_id,fecha,hasta,importe,sede)values('00000000-0000-4000-8000-000000009905','00000000-0000-4000-8000-000000009903','00000000-0000-4000-8000-000000009904','2026-11-01','2026-12-01',5000,'MARATHON');
insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones)values('SALDO-B1','SALDO-T1','99001001','MARATHON','MARATHON','MARATHON',3000,'2026-11-02','09:00','2026-11-04',2);
update marathon.saldo_config set activo=true;
do $$declare d jsonb;p jsonb;begin
 d=jsonb_build_object('subtipo','SALDO_INGRESO','dni','99001001','monto','5000','medio','EFECTIVO','sede','MARATHON','fecha','2026-11-04');p=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('saldo_demo_ingreso001',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
 d=d||'{"dni":"99001002","monto":"12000"}';p=public.marathon_saldo_prever(d);perform public.marathon_saldo_command('saldo_demo_ingreso002',d||jsonb_build_object('version',p->>'version','huella',p->>'huella'));
end$$;
commit;
