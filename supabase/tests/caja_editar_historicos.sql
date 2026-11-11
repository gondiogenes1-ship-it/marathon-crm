-- Copia local restaurada con saldo activo. Se revierte todo.
begin;
\if :{?cash_edit_as_secretary}
set local marathon.qa_cash_secretary='1';
\endif
do $$declare uid uuid;x record;d jsonb;p jsonb;r jsonb;deuda numeric;aplicado numeric;n int:=0;before_source numeric;begin
 select user_id into uid from marathon.app_users where active and role='ADMIN'order by user_id limit 1;perform set_config('request.jwt.claim.sub',uid::text,true);
 if current_setting('marathon.qa_cash_secretary',true)='1'then update marathon.app_users set role='SECRETARIA'where user_id=uid;end if;
 insert into marathon.pacientes(dni,nombre,apellido)values('99999401','EDICION','QA HISTORICOS');
 for x in select distinct on(m.origen,m.cuota_id is not null)m.* from marathon.movimientos m join marathon.saldo_fuentes f on f.movimiento_id=m.id where m.monto>0 and not exists(select 1 from marathon.saldo_eventos where fuente_id=f.id and tipo='DEVOLUCION')and not exists(select 1 from marathon.movimientos r where r.compensacion_de=m.id)order by m.origen,m.cuota_id is not null,m.id loop
  n=n+1;
  select coalesce(sum(a.deuda),0)into deuda from marathon.saldo_deudas(x.dni)a;
  select coalesce(sum(marathon.saldo_aplicado(a.id)),0)into aplicado from marathon.saldo_aplicaciones a join marathon.saldo_fuentes f on f.id=a.fuente_id where f.movimiento_id=x.id;
  select marathon.saldo_disponible('99999401')into before_source;
  d=jsonb_build_object('id',x.id,'version',x.version,'subtipo','SALDO_INGRESO','dni','99999401','monto',x.monto::text,'medio',x.medio,'sede',x.sede,'fecha',x.fecha,'hora',x.hora,'concepto',coalesce(nullif(x.concepto,''),'Ingreso corregido'),'observaciones',coalesce(x.observaciones_legacy,''),'motivo','Corrección sintética de paciente');
  p=public.marathon_cash_edit_preview(d);r=public.marathon_cash_edit_save('qa-edit-history-'||n,d||jsonb_build_object('huella',p->>'huella'));
  assert(select coalesce(sum(a.deuda),0)from marathon.saldo_deudas(x.dni)a)=deuda+aplicado,'El histórico reabre exactamente lo liberado';
  assert marathon.saldo_disponible('99999401')=before_source+x.monto,'Crédito correcto sin duplicación';
  assert not exists(select 1 from marathon.saldo_deudas(x.dni)where pagado<0),'No introduce pagos negativos';
  assert not exists(select 1 from marathon.movimientos where compensacion_de=x.id and cuota_id is not null),'Reverso de edición no descuenta dos veces la cuota';
 end loop;
 assert n>=3,'Debe probar varios orígenes históricos';
 raise notice 'PASS: % variantes históricas de sesión/bono/anticipo/cuota/general; deuda exacta y sin pagos negativos.',n;
end$$;
rollback;
