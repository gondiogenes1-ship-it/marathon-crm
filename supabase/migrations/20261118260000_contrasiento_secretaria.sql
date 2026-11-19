-- Habilita "Anular con contrasiento" (ingresos de saldo y movimientos de caja clínica/caja)
-- para ADMIN y SECRETARIA, no solo ADMIN. Se mantiene sin cambios para ORTOPEDIA
-- (marathon_ortho_command sigue exigiendo ADMIN, no se tocó).

create or replace function public.marathon_saldo_anular(p_request_id text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '3s'
as $function$
declare previous jsonb;source marathon.saldo_fuentes%rowtype;original marathon.movimientos%rowtype;a record;mid text;reply jsonb;begin
 if not marathon.active_user()then raise exception 'Solo administración o secretaría pueden anular un ingreso.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'saldo:anular',p_data);if previous is not null then return previous;end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'Circuito de saldo no habilitado.'using errcode='55000';end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','motivo','fecha']))then raise exception 'Campos de anulación inválidos.'using errcode='22023';end if;
 perform marathon.master_text(p_data,'motivo',1000,true);
 if length(btrim(p_data->>'motivo'))<3 then raise exception 'Indicá el motivo.'using errcode='22023';end if;
 select *into source from marathon.saldo_fuentes where movimiento_id=p_data->>'id';
 if not found then raise exception 'Ingreso de saldo no encontrado.'using errcode='PT404';end if;
 if marathon.saldo_version(source.dni)<>marathon.operation_version(p_data)then raise exception 'La cuenta cambió. Revisala antes de anular.'using errcode='PT409';end if;
 select *into strict original from marathon.movimientos where id=source.movimiento_id for update;
 if exists(select 1 from marathon.saldo_eventos where fuente_id=source.id and tipo='DEVOLUCION')or exists(select 1 from marathon.movimientos where compensacion_de=original.id)then raise exception 'El ingreso tiene devoluciones o ya fue anulado. Requiere revisión administrativa.'using errcode='22023';end if;
 for a in select sa.*,marathon.saldo_aplicado(sa.id)actual from marathon.saldo_aplicaciones sa where sa.fuente_id=source.id and marathon.saldo_aplicado(sa.id)>0 order by sa.created_at,sa.id loop
  insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(source.dni,source.id,'REVERSO_APLICACION',a.actual,a.id,p_request_id,auth.uid(),'anular:'||a.id);
 end loop;
 if marathon.saldo_fuente_disponible(source.id)<>original.monto then raise exception 'El origen no concilia con su ingreso. No se anuló.'using errcode='22023';end if;
 mid='MOV-'||gen_random_uuid()::text;
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,compensacion_de,motivo,created_by,updated_by,categoria,profesional_asociado_id,terapia_asociada_id,secretaria_asociada)
 values(mid,marathon.agenda_date(p_data->>'fecha'),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA','EGRESO',source.dni,original.monto,original.medio,original.sede,'Anulación de ingreso de saldo',original.id,p_data->>'motivo',auth.uid(),auth.uid(),original.categoria,coalesce(original.profesional_asociado_id,(select profesional_id from marathon.turnos where id=original.turno_id),(select profesional_id from marathon.bonos_serie where id=original.bono_id),(select profesional_id from marathon.anticipos where id=original.anticipo_id)),coalesce(original.terapia_asociada_id,(select terapia_id from marathon.turnos where id=original.turno_id),(select terapia_id from marathon.bonos_serie where id=original.bono_id),(select terapia_id from marathon.anticipos where id=original.anticipo_id),(select ap.terapia_id from marathon.agenda_planes ap join marathon.agenda_cuotas q on q.plan_id=ap.id where q.id=original.cuota_id)),original.secretaria_asociada);
 insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(source.dni,source.id,'DEVOLUCION',original.monto,mid,p_request_id,auth.uid(),'anular:ingreso');
 reply=jsonb_build_object('id',mid,'cuenta',marathon.saldo_cuenta_info(source.dni),'message','Ingreso anulado. Las deudas vuelven a quedar pendientes.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'saldo',original.id,'anular',to_jsonb(original),reply);
 return reply;
end$function$;

create or replace function public.marathon_cash_command(p_request_id text, p_action text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '3s'
as $function$
#variable_conflict use_variable
declare reply jsonb;t marathon.turnos%rowtype;old marathon.movimientos%rowtype;m numeric;paid numeric;medium text;site text;dni text;concept text;obs text;reason text;kind text;origin text;id text;tid text;comp text;d date;after_data jsonb;category text;associated_prof text;associated_sec text;
begin
 if exists(select 1 from marathon.saldo_config where activo)and(p_action<>'reverse' or exists(select 1 from marathon.saldo_fuentes where movimiento_id=p_data->>'id'))then raise exception 'Usá Registrar movimiento del nuevo circuito de Caja.'using errcode='55000';end if;
 reply=marathon.operation_begin(p_request_id,'cash:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action is null or p_action not in ('pay','refund','cash','reverse') or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case p_action when 'cash' then array['tipo','sede','dni','monto','medio','concepto','observaciones','fecha','categoria','profesional_asociado_id','secretaria_asociada'] when 'reverse' then array['id','version','motivo','fecha'] else array['id','version','monto','medio','observaciones','fecha'] end)) then raise sqlstate '22023' using message='Operación de caja inválida.';end if;
 d=case when coalesce(p_data->>'fecha','')='' then(now() at time zone 'America/Argentina/Buenos_Aires')::date else marathon.agenda_date(marathon.master_text(p_data,'fecha',10,true)) end;
 if p_action='reverse' then
  if not marathon.active_user() then raise sqlstate '42501' using message='Solo administración o secretaría pueden aprobar un contrasiento.';end if;
  reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
  select * into old from marathon.movimientos x where x.id=marathon.master_text(p_data,'id',100,true) for update;
  if old.id is null or old.compensacion_de is not null or not((old.tipo='PAGO' and old.origen='CLINICA' and old.turno_id is not null)or(old.origen='CAJA' and old.tipo in('INGRESO','EGRESO')))then raise sqlstate '22023' using message='Solo se corrigen cobros clínicos o movimientos manuales originales mediante contrasiento.';end if;
  if old.version<>marathon.operation_version(p_data) or exists(select 1 from marathon.movimientos where compensacion_de=old.id) then raise sqlstate 'PT409' using message='El cobro cambió o ya tiene contrasiento.';end if;
  if old.origen='CAJA'then
   m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;comp=old.id;kind=case when old.tipo='EGRESO'then'INGRESO'else'EGRESO'end;origin='CAJA';concept='Contrasiento de '||old.id;obs=reason;category=old.categoria;associated_prof=old.profesional_asociado_id;associated_sec=old.secretaria_asociada;
  else
  select * into t from marathon.turnos where turnos.id=old.turno_id for update;paid=marathon.turn_cash_paid(t.id);
  if paid<old.monto then raise sqlstate '22023' using message='Hay reintegros previos. El cobro completo no puede anularse; registrá el reintegro del saldo correspondiente.';end if;
  m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;tid=old.turno_id;comp=old.id;kind='REINTEGRO';origin='CLINICA';concept='Contrasiento de '||old.id;obs=reason;
 end if;
 elsif p_action in ('pay','refund') then
  select * into t from marathon.turnos where turnos.id=marathon.master_text(p_data,'id',100,true) for update;
  if t.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
  if t.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir su cuenta.';end if;
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);paid=marathon.turn_paid(t.id);
  if p_action='pay' and(t.estado<>'PRESENTE' or m>t.importe-paid) then raise sqlstate '22023' using message='Solo se cobran turnos presentes y hasta su saldo pendiente.';end if;
  if p_action='refund' and m>marathon.turn_cash_paid(t.id) then raise sqlstate '22023' using message='El reintegro supera lo cobrado.';end if;
  site=t.sede;dni=t.dni;tid=t.id;kind=case when p_action='pay' then 'PAGO' else 'REINTEGRO' end;origin='CLINICA';concept=case when p_action='pay' then 'Cobro de turno' else 'Reintegro de turno' end;
 else
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);site=marathon.master_text(p_data,'sede',40,true);dni=nullif(marathon.master_text(p_data,'dni',12),'');concept=marathon.master_text(p_data,'concepto',200,true);kind=marathon.master_text(p_data,'tipo',7,true);origin='CAJA';
  if kind not in ('INGRESO','EGRESO') or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO') or(dni is not null and not exists(select 1 from marathon.pacientes p where p.dni=dni)) then raise sqlstate '22023' using message='Tipo, sede o paciente inválidos.';end if;
 end if;
 if p_action='cash'then
 category=nullif(marathon.master_text(p_data,'categoria',100),'');associated_prof=nullif(marathon.master_text(p_data,'profesional_asociado_id',100),'');associated_sec=nullif(marathon.master_text(p_data,'secretaria_asociada',100),'');
 if(associated_prof is not null and associated_sec is not null)or(associated_prof is not null and not exists(select 1 from marathon.profesionales pr where pr.id=associated_prof and pr.estado='ACTIVO'))or(associated_sec is not null and not exists(select 1 from marathon.secretarias where nombre=associated_sec and estado='ACTIVO'))then raise sqlstate '22023'using message='Elegí un profesional o una secretaria activos para asociar.';end if;
 end if;
 if medium not in ('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
 id='MOV-'||gen_random_uuid()::text;
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,turno_id,concepto,observaciones_legacy,compensacion_de,motivo,created_by,updated_by,categoria,profesional_asociado_id,secretaria_asociada)
 values(id,d,(now() at time zone 'America/Argentina/Buenos_Aires')::time,origin,kind,dni,m,medium,site,tid,concept,obs,comp,reason,auth.uid(),auth.uid(),category,associated_prof,associated_sec);
 select to_jsonb(x) into after_data from marathon.movimientos x where x.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'movement',id,p_action,case when old.id is not null then to_jsonb(old) end,after_data);
 reply=jsonb_build_object('id',id,'message',case p_action when 'pay' then 'Cobro registrado.' when 'refund' then 'Reintegro registrado.' when 'reverse' then 'Contrasiento registrado. El cobro original se conserva.' else 'Movimiento de caja registrado.' end);
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $function$;
