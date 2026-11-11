-- SOLO base aislada: datos sintéticos y ROLLBACK al finalizar.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id)values('00000000-0000-4000-8000-000000009901');
set local request.jwt.claim.sub='00000000-0000-4000-8000-000000009901';
insert into marathon.app_users(user_id,role,active,display_name)values(auth.uid(),'ADMIN',true,'Prueba aislada de saldo');
insert into marathon.sedes(nombre,estado)values('SALDO_QA','ACTIVO');
insert into marathon.terapias(id,nombre,especialidad,duracion_min,capacidad,estado)values('SALDO_QA','Terapia de prueba','QA',30,15,'ACTIVO');
insert into marathon.profesionales(id,nombre,apellido,estado)values('SALDO_QA','Profesional','Prueba','ACTIVO');
insert into marathon.profesional_terapias(profesional_id,terapia_id)values('SALDO_QA','SALDO_QA');
insert into marathon.horarios(id,profesional_id,sede,dia,inicio,fin)select 'SALDO-QA-'||d,'SALDO_QA','SALDO_QA',d,'08:00','18:00'from generate_series(0,6)d;
insert into marathon.pacientes(dni,nombre,apellido)values('99001001','Paciente','Uno'),('99001002','Paciente','Dos'),('99001003','Paciente','Tres');
insert into marathon.turnos(id,fecha,hora,sede,dni,terapia_id,profesional_id,importe,estado,duracion_min)
values('SALDO-T1','2026-10-01','10:00','SALDO_QA','99001001','SALDO_QA','SALDO_QA',1000,'PRESENTE',30),('SALDO-T2','2026-10-02','10:00','SALDO_QA','99001001','SALDO_QA','SALDO_QA',500,'PRESENTE',30);
