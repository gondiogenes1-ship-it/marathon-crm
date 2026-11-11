begin;
-- Una vez importado, el saldo aplicado histórico se representa en el ledger.
-- Los originales se conservan, pero no vuelven a sumar ni se recalculan con contrasientos nuevos.
create or replace function marathon.saldo_pagado(p_tipo text,p_id text)returns numeric language sql stable set search_path=''as $$
 select case when exists(select 1 from marathon.saldo_base_legacy where tipo=p_tipo and id=p_id)then 0 else marathon.saldo_legacy_pagado(p_tipo,p_id)end+
 coalesce((select sum(case e.tipo when 'APLICACION'then e.monto when 'REVERSO_APLICACION'then -e.monto else 0 end)
 from marathon.saldo_aplicaciones a join marathon.saldo_eventos e on e.aplicacion_id=a.id where
 case p_tipo when 'sesion'then a.turno_id=p_id when 'cuota'then a.cuota_id::text=p_id when 'bono'then a.bono_id=p_id else false end),0)
$$;
create or replace function marathon.turn_paid(p_id text)returns numeric language sql stable set search_path=''as $$
 select case when exists(select 1 from marathon.saldo_config where activo)then marathon.saldo_pagado('sesion',p_id)else marathon.turn_cash_paid(p_id)+marathon.advance_paid(p_id)end
$$;
create or replace function marathon.agenda_cuota_pagado(q uuid)returns numeric language sql stable set search_path=''as $$
 select case when exists(select 1 from marathon.saldo_config where activo)then marathon.saldo_pagado('cuota',q::text)else marathon.saldo_legacy_pagado('cuota',q::text)end
$$;
create or replace function marathon.saldo_automatico()returns trigger language plpgsql set search_path=''as $$
declare person text;request text;reply jsonb;data jsonb;application record;release_payment boolean:=false;apply_credit boolean:=true;begin
 if not exists(select 1 from marathon.saldo_config where activo)then return new;end if;
 if tg_table_name='turnos'then
  person=new.dni;
  if tg_op='UPDATE'and new.estado=old.estado and new.importe=old.importe then return new;end if;
  release_payment=new.estado<>'PRESENTE';apply_credit=not release_payment;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'version',new.version,'estado',new.estado,'importe',new.importe);
 elsif tg_table_name='bonos_serie'then
  person=new.dni;
  if tg_op='UPDATE'and new.estado=old.estado and new.importe=old.importe then return new;end if;
  release_payment=new.estado='ANULADO';apply_credit=not release_payment;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'version',new.version,'estado',new.estado,'importe',new.importe);
 else
  select p.dni into person from marathon.agenda_planes p where p.id=new.plan_id;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'importe',new.importe);
 end if;
 request='saldo_auto_'||md5(data::text);
 reply=marathon.operation_begin(request,'saldo:auto',data);if reply is not null then return new;end if;
 if release_payment then
  for application in select a.*,marathon.saldo_aplicado(a.id)actual from marathon.saldo_aplicaciones a where
   ((tg_table_name='turnos'and a.turno_id=new.id::text)or(tg_table_name='bonos_serie'and a.bono_id=new.id::text))and marathon.saldo_aplicado(a.id)>0 order by a.created_at,a.id loop
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(person,application.fuente_id,'REVERSO_APLICACION',application.actual,application.id,request,auth.uid(),'liberar:'||application.id);
  end loop;
 end if;
 if apply_credit then perform marathon.saldo_aplicar(person,request);end if;
 update marathon.solicitudes set resultado=jsonb_build_object('cuenta',marathon.saldo_cuenta_info(person))where id=request;
 return new;
end$$;

-- Validación de metadatos en el servidor, no solamente en el formulario.
create function marathon.saldo_validar_datos()returns trigger language plpgsql set search_path=''as $$begin
 if new.subtipo is not null then
  if length(coalesce(new.observaciones_legacy,''))>1000 or length(coalesce(new.categoria,''))>100 then raise exception 'Texto demasiado extenso.'using errcode='22023';end if;
  if new.profesional_asociado_id is not null and new.secretaria_asociada is not null then raise exception 'Asociá un profesional o una secretaría.'using errcode='22023';end if;
  if new.profesional_asociado_id is not null and not exists(select 1 from marathon.profesionales where id=new.profesional_asociado_id and estado='ACTIVO')then raise exception 'Profesional inactivo.'using errcode='22023';end if;
  if new.secretaria_asociada is not null and not exists(select 1 from marathon.secretarias where nombre=new.secretaria_asociada and estado='ACTIVO')then raise exception 'Secretaría inactiva.'using errcode='22023';end if;
  if new.terapia_asociada_id is not null and not exists(select 1 from marathon.terapias where id=new.terapia_asociada_id and estado='ACTIVO')then raise exception 'Terapia inactiva.'using errcode='22023';end if;
  if new.subtipo='OTRO_INGRESO'and length(btrim(coalesce(new.observaciones_legacy,'')))<3 then raise exception 'Indicá el concepto del ingreso.'using errcode='22023';end if;
 end if;return new;
end$$;
create trigger saldo_validar_datos before insert on marathon.movimientos for each row execute function marathon.saldo_validar_datos();

create function public.marathon_saldo_anular(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$
declare previous jsonb;source marathon.saldo_fuentes%rowtype;original marathon.movimientos%rowtype;a record;mid text;reply jsonb;begin
 if not marathon.is_admin()then raise exception 'Solo ADMIN puede anular un ingreso.'using errcode='42501';end if;
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
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,compensacion_de,motivo,created_by,updated_by)
 values(mid,marathon.agenda_date(p_data->>'fecha'),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA','EGRESO',source.dni,original.monto,original.medio,original.sede,'Anulación de ingreso de saldo',original.id,p_data->>'motivo',auth.uid(),auth.uid());
 insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(source.dni,source.id,'DEVOLUCION',original.monto,mid,p_request_id,auth.uid(),'anular:ingreso');
 reply=jsonb_build_object('id',mid,'cuenta',marathon.saldo_cuenta_info(source.dni),'message','Ingreso anulado. Las deudas vuelven a quedar pendientes.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'saldo',original.id,'anular',to_jsonb(original),reply);
 return reply;
end$$;
revoke all on function marathon.saldo_validar_datos()from public,anon,authenticated;
revoke all on function public.marathon_saldo_anular(text,jsonb)from public,anon;
grant execute on function public.marathon_saldo_anular(text,jsonb)to authenticated;
commit;
