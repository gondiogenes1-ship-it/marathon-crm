begin;
lock table marathon.movimientos,marathon.saldo_fuentes,marathon.saldo_aplicaciones,marathon.saldo_eventos in share mode;
create temporary table cash_edit_install_before on commit drop as
select 'movimientos' tabla,md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)huella from marathon.movimientos x
union all select 'saldo_fuentes',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.saldo_fuentes x
union all select 'saldo_aplicaciones',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.saldo_aplicaciones x
union all select 'saldo_eventos',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)from marathon.saldo_eventos x;

CREATE OR REPLACE FUNCTION public.marathon_cash_edit_preview(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb;fingerprint text;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar ingresos.'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 fingerprint=marathon.cash_edit_fingerprint(p_data);
 begin
  r=marathon.cash_edit_run('preview-edit-'||gen_random_uuid(),p_data);
  raise sqlstate 'ZP002'using message='preview_rollback';
 exception when sqlstate 'ZP002'then null;end;
 return r||jsonb_build_object('huella',fingerprint);
end$function$;

CREATE OR REPLACE FUNCTION public.marathon_cash_edit_get(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare m marathon.movimientos%rowtype;history jsonb;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar ingresos.'using errcode='42501';end if;
 select *into m from marathon.movimientos where id=p_id;
 if not found or m.tipo not in('INGRESO','PAGO')or m.compensacion_de is not null then raise exception 'Ingreso original no encontrado.'using errcode='PT404';end if;
 if exists(select 1 from marathon.movimientos where compensacion_de=m.id)then raise exception 'El ingreso ya fue anulado o reemplazado.'using errcode='PT409';end if;
 with recursive chain(id,depth)as(select m.id,0 union all select e.original_id,c.depth+1 from chain c join marathon.cash_edits e on e.replacement_id=c.id where c.depth<100)
 select coalesce(jsonb_agg(jsonb_build_object('fecha',a.created_at,'responsable',u.display_name,'antes',a.before_data,'despues',a.after_data)order by a.created_at desc),'[]')into history
 from chain c join marathon.operation_audit a on a.entity_id=c.id and a.entity='cash_edit'left join marathon.app_users u on u.user_id=a.actor;
 return jsonb_build_object('movement',to_jsonb(m),'patient',case when m.dni is not null then(select jsonb_build_object('dni',p.dni,'nombre',p.nombre,'apellido',p.apellido,'segundo_nombre',p.segundo_nombre)from marathon.pacientes p where p.dni=m.dni)end,
 'account',case when m.dni is not null then marathon.saldo_cuenta_info(m.dni)end,'history',history);
end$function$;

CREATE OR REPLACE FUNCTION marathon.agenda_movimiento_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare q marathon.agenda_cuotas%rowtype;begin
 if exists(select 1 from marathon.cash_edits where reversal_id=new.id and original_id=new.compensacion_de)then
 if not marathon.active_user()then raise sqlstate '42501'using message='Se requiere un usuario activo para corregir ingresos.';end if;
 return new;end if;
 if new.cuota_id is null and new.compensacion_de is not null then select cuota_id into new.cuota_id from marathon.movimientos where id=new.compensacion_de;end if;
 if new.cuota_id is null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 select * into strict q from marathon.agenda_cuotas where id=new.cuota_id for update;
 if new.tipo='INGRESO'and new.monto>marathon.agenda_cuota_saldo(q.id)or new.tipo='EGRESO'and new.monto>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El movimiento supera el saldo de la cuota. Revisá los pagos y reintegros previos.';end if;
 update marathon.agenda_planes set updated_at=now()where id=q.plan_id;return new;
end$function$;

CREATE OR REPLACE FUNCTION public.marathon_cash_edit_save(p_request_id text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare previous jsonb;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar ingresos.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'cash:edit',p_data);if previous is not null then return previous;end if;
 if p_data->>'huella'is distinct from marathon.cash_edit_fingerprint(p_data)then raise exception 'Los datos o saldos cambiaron. Volvé a revisar la edición.'using errcode='PT409';end if;
 return marathon.cash_edit_run(p_request_id,p_data);
end$function$;

CREATE OR REPLACE FUNCTION marathon.cash_edit_run(p_request_id text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare old marathon.movimientos%rowtype;newrow marathon.movimientos%rowtype;f marathon.saldo_fuentes%rowtype;a record;
 previous jsonb;payload jsonb;proposal jsonb;reply jsonb;rev text;newid text;kind text;person text;amount numeric;financial boolean;before_accounts jsonb;after_accounts jsonb;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar ingresos.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'cash:edit',p_data);if previous is not null then return previous;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','fecha','hora','monto','medio','sede','concepto','observaciones','categoria','profesional','terapia','secretaria','dni','subtipo','motivo','huella']))then raise exception 'Campos de edición inválidos.'using errcode='22023';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'Circuito de saldo no habilitado.'using errcode='55000';end if;
 perform public.marathon_cash_edit_get(p_data->>'id');
 select *into strict old from marathon.movimientos where id=p_data->>'id'for update;
 if old.version<>marathon.operation_version(p_data)then raise exception 'El ingreso cambió. Volvé a abrirlo.'using errcode='PT409';end if;
 perform marathon.master_text(p_data,'motivo',1000,true);perform marathon.master_text(p_data,'concepto',200,true);
 perform marathon.master_text(p_data,'observaciones',1000,false);perform marathon.master_text(p_data,'categoria',100,false);
 if length(btrim(p_data->>'motivo'))<3 then raise exception 'Indicá el motivo de la edición.'using errcode='22023';end if;
 amount=marathon.saldo_importe(p_data->>'monto');person=nullif(p_data->>'dni','');kind=p_data->>'subtipo';
 if kind not in('SALDO_INGRESO','OTRO_INGRESO','CONSERVAR')or kind is null or(kind='SALDO_INGRESO'and person is null)or(kind='OTRO_INGRESO'and person is not null)then raise exception 'Elegí A favor del paciente con paciente, u Otro ingreso sin paciente.'using errcode='22023';end if;
 if kind='CONSERVAR'and(amount<>old.monto or person is distinct from old.dni)then raise exception 'Para cambiar paciente o importe del histórico, elegí A favor del paciente u Otro ingreso.'using errcode='22023';end if;
 if person is not null and not exists(select 1 from marathon.pacientes where dni=person)then raise exception 'Elegí un paciente existente.'using errcode='22023';end if;
 if p_data->>'medio'not in('EFECTIVO','TRANSFERENCIA')or nullif(p_data->>'medio','')is null or p_data->>'hora'!~'^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\.[0-9]{1,6})?)?$'or nullif(p_data->>'hora','')is null then raise exception 'Medio u hora inválidos.'using errcode='22023';end if;
 perform marathon.agenda_date(p_data->>'fecha');
 if not exists(select 1 from marathon.sedes where nombre=p_data->>'sede'and(estado='ACTIVO'or nombre=old.sede))then raise exception 'Sede inválida.'using errcode='22023';end if;
 if nullif(p_data->>'profesional','')is not null and not exists(select 1 from marathon.profesionales where id=p_data->>'profesional'and(estado='ACTIVO'or id=old.profesional_asociado_id))then raise exception 'Profesional inválido.'using errcode='22023';end if;
 if nullif(p_data->>'secretaria','')is not null and not exists(select 1 from marathon.secretarias where nombre=p_data->>'secretaria'and(estado='ACTIVO'or nombre=old.secretaria_asociada))then raise exception 'Secretaría inválida.'using errcode='22023';end if;
 if nullif(p_data->>'profesional','')is not null and nullif(p_data->>'secretaria','')is not null then raise exception 'Asociá un profesional o una secretaría.'using errcode='22023';end if;
 if nullif(p_data->>'terapia','')is not null and not exists(select 1 from marathon.terapias where id=p_data->>'terapia'and(estado='ACTIVO'or id=old.terapia_asociada_id))then raise exception 'Terapia inválida.'using errcode='22023';end if;
 select *into f from marathon.saldo_fuentes where movimiento_id=old.id;
 financial=kind<>'CONSERVAR'and(amount<>old.monto or person is distinct from old.dni or(kind='SALDO_INGRESO')<>(f.id is not null));
 before_accounts=jsonb_build_object('anterior',case when old.dni is not null then marathon.saldo_cuenta_info(old.dni)end,'nuevo',case when person is not null then marathon.saldo_cuenta_info(person)end);
 if not financial then
  update marathon.movimientos set fecha=(p_data->>'fecha')::date,hora=(p_data->>'hora')::time,medio=p_data->>'medio',sede=p_data->>'sede',concepto=btrim(p_data->>'concepto'),observaciones_legacy=nullif(p_data->>'observaciones',''),categoria=nullif(p_data->>'categoria',''),profesional_asociado_id=nullif(p_data->>'profesional',''),terapia_asociada_id=nullif(p_data->>'terapia',''),secretaria_asociada=nullif(p_data->>'secretaria',''),updated_by=auth.uid()where id=old.id returning *into newrow;
  newid=newrow.id;
 else
  if old.origen='ORTOPEDIA'then raise exception 'Para cambiar paciente o importe de una venta usá la corrección de Ortopedia; se conservan sus artículos y stock.'using errcode='22023';end if;
  if f.id is not null and exists(select 1 from marathon.saldo_eventos where fuente_id=f.id and tipo='DEVOLUCION')then raise exception 'Este ingreso tiene dinero devuelto. Se pueden editar sus datos descriptivos; para cambiar paciente o importe debe conciliarse la devolución.'using errcode='22023';end if;
  rev='MOV-'||gen_random_uuid();
  insert into marathon.cash_edits(original_id,reversal_id,request_id,actor,motivo)values(old.id,rev,p_request_id,auth.uid(),btrim(p_data->>'motivo'));
  if f.id is not null then
   for a in select sa.*,marathon.saldo_aplicado(sa.id)actual from marathon.saldo_aplicaciones sa where sa.fuente_id=f.id and marathon.saldo_aplicado(sa.id)>0 order by sa.created_at,sa.id loop
    insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(f.dni,f.id,'REVERSO_APLICACION',a.actual,a.id,p_request_id,auth.uid(),'editar:liberar:'||a.id);
   end loop;
   if marathon.saldo_fuente_disponible(f.id)<>old.monto then raise exception 'El ingreso no concilia con el saldo. No se modificó.'using errcode='22023';end if;
  end if;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,compensacion_de,motivo,created_by,updated_by)
  values(rev,old.fecha,old.hora,'CAJA','EGRESO',old.dni,old.monto,old.medio,old.sede,'Contrasiento por edición administrativa',old.id,p_data->>'motivo',auth.uid(),auth.uid());
  if f.id is not null then
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(f.dni,f.id,'DEVOLUCION',old.monto,rev,p_request_id,auth.uid(),'editar:retirar_origen');
  end if;
  payload=jsonb_build_object('subtipo',kind,'monto',p_data->>'monto','medio',p_data->>'medio','sede',p_data->>'sede','fecha',p_data->>'fecha','observaciones',coalesce(nullif(p_data->>'observaciones',''),p_data->>'concepto'),'categoria',p_data->>'categoria','profesional',p_data->>'profesional','terapia',p_data->>'terapia','secretaria',p_data->>'secretaria');
  if person is not null then payload=payload||jsonb_build_object('dni',person);end if;
  proposal=public.marathon_saldo_prever(payload);
  reply=public.marathon_saldo_command('edit-new-'||md5(p_request_id),payload||jsonb_build_object('version',proposal->>'version','huella',proposal->>'huella'));newid=reply->>'id';
  update marathon.movimientos set hora=(p_data->>'hora')::time,concepto=btrim(p_data->>'concepto'),observaciones_legacy=nullif(p_data->>'observaciones',''),updated_by=auth.uid()where id=newid returning *into newrow;
  update marathon.cash_edits set replacement_id=newid where original_id=old.id;
 end if;
 after_accounts=jsonb_build_object('anterior',case when old.dni is not null then marathon.saldo_cuenta_info(old.dni)end,'nuevo',case when person is not null then marathon.saldo_cuenta_info(person)end);
 reply=jsonb_build_object('id',newid,'antes',to_jsonb(old),'despues',to_jsonb(newrow),'cuentas_antes',before_accounts,'cuentas_despues',after_accounts,'corrige_pagos',financial,'motivo',btrim(p_data->>'motivo'),'message','Ingreso corregido. Se conservaron el original y el historial de la edición.');
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'cash_edit',old.id,'editar',to_jsonb(old),reply);
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 return reply;
end$function$;
do $guard$declare r record;h text;begin
 for r in select *from cash_edit_install_before loop
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),''[]'')::text)from marathon.%I x',r.tabla)into h;
 if h<>r.huella then raise exception 'La instalación alteró registros financieros de %',r.tabla;end if;
 end loop;
end $guard$;
commit;
