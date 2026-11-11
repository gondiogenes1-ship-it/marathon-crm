-- Decisión confirmada: cuota sin deuda; pago liberado al saldo, sin egreso.
begin;
create or replace function marathon.saldo_prever(p_data jsonb)returns jsonb language plpgsql stable set search_path=''as $$
declare person text:=p_data->>'dni';kind text:=p_data->>'subtipo';amount numeric;account jsonb;available numeric;remaining numeric;used numeric:=0;d record;piece numeric;details jsonb:='[]';fingerprint text;begin
 if kind not in('SALDO_INGRESO','SALDO_DEVOLUCION','REINTEGRO_SESION','REINTEGRO_CUOTA','OTRO_INGRESO','PAGO_PROFESIONAL','GASTO_GENERAL','OTRO_EGRESO')or kind is null then raise exception 'Subtipo inválido.'using errcode='22023';end if;
 if kind in('SALDO_INGRESO','SALDO_DEVOLUCION','REINTEGRO_SESION','REINTEGRO_CUOTA')then
  account=marathon.saldo_cuenta_info(person);if account is null then raise exception 'Elegí un paciente existente.'using errcode='22023';end if;
 else if nullif(person,'')is not null then raise exception 'Este movimiento no lleva paciente.'using errcode='22023';end if;account=jsonb_build_object('saldo','0','deuda','0','version',0);end if;
 available=(account->>'saldo')::numeric;
 if kind in('REINTEGRO_SESION','REINTEGRO_CUOTA')then
  select *into d from marathon.saldo_deudas(person)x where x.tipo=case when kind='REINTEGRO_SESION'then 'sesion'else 'cuota'end and x.id=case when kind='REINTEGRO_SESION'then p_data->>'turno_id'else p_data->>'cuota_id'end;
  if not found or d.pagado<=0 then raise exception 'Elegí una sesión presente o una cuota con pago recuperable.'using errcode='22023';end if;
  amount=d.pagado;remaining=available+amount;details=jsonb_build_array(jsonb_build_object('tipo',d.tipo,'id',d.id,'pagado_liberado',d.pagado::text,'deuda_bonificada',d.deuda::text));
 else
  amount=marathon.saldo_importe(p_data->>'monto');remaining=available;
  if kind='SALDO_INGRESO'then
   remaining=available+amount;
   for d in select *from marathon.saldo_deudas(person)where deuda>0 loop
    piece=least(remaining,d.deuda);if piece>0 then details=details||jsonb_build_array(jsonb_build_object('tipo',d.tipo,'id',d.id,'fecha',d.fecha,'hora',d.hora,'deuda',d.deuda::text,'aplicar',piece::text));end if;
    remaining=remaining-piece;used=used+piece;
   end loop;
  elsif kind='SALDO_DEVOLUCION'then
   if amount>available then raise exception 'La devolución supera el saldo disponible.'using errcode='22023';end if;remaining=available-amount;
  end if;
 end if;
 fingerprint=encode(sha256(convert_to(jsonb_build_object('datos',p_data-'huella'-'version','cuenta',account,'detalle',details)::text,'UTF8')),'hex');
 return jsonb_build_object('version',account->'version','huella',fingerprint,'cuenta',account,'monto',amount::text,'aplicar',used::text,'saldo_resultante',remaining::text,'detalle',details);
end$$;

create or replace function public.marathon_saldo_command(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$
declare previous jsonb;proposal jsonb;kind text:=p_data->>'subtipo';person text:=nullif(p_data->>'dni','');amount numeric;mid text;source uuid;f record;a record;available numeric;piece numeric;remaining numeric;turno marathon.turnos%rowtype;quota marathon.agenda_cuotas%rowtype;reply jsonb;begin
 previous=marathon.operation_begin(p_request_id,'saldo:'||coalesce(kind,''),p_data);if previous is not null then return previous;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['dni','subtipo','monto','medio','sede','fecha','observaciones','categoria','profesional','terapia','secretaria','turno_id','cuota_id','huella','version']))then raise exception 'La solicitud contiene campos no admitidos.'using errcode='22023';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'El nuevo circuito de saldo todavía no está habilitado.'using errcode='55000';end if;
 if person is not null and p_data->>'version'is distinct from marathon.saldo_version(person)::text then raise exception 'La cuenta cambió. Revisá la nueva vista previa antes de confirmar.'using errcode='PT409';end if;
 proposal=marathon.saldo_prever(p_data);
 if p_data->>'huella' is distinct from proposal->>'huella'or p_data->>'version'is distinct from proposal->>'version'then raise exception 'La cuenta cambió. Revisá la nueva vista previa antes de confirmar.'using errcode='PT409';end if;
 amount=(proposal->>'monto')::numeric;
 if kind='REINTEGRO_CUOTA'then
  if length(btrim(coalesce(p_data->>'observaciones','')))<3 or length(p_data->>'observaciones')>1000 then raise exception 'Indicá el motivo del reintegro de cuota (3 a 1000 caracteres).'using errcode='22023';end if;
  select q.*into strict quota from marathon.agenda_cuotas q join marathon.agenda_planes p on p.id=q.plan_id where q.id=(p_data->>'cuota_id')::uuid and p.dni=person for update of q;
  for a in select sa.*,marathon.saldo_aplicado(sa.id)actual from marathon.saldo_aplicaciones sa where sa.cuota_id=quota.id and marathon.saldo_aplicado(sa.id)>0 order by sa.created_at,sa.id loop
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(person,a.fuente_id,'REVERSO_APLICACION',a.actual,a.id,p_request_id,auth.uid(),'reintegro_cuota:'||a.id);
  end loop;
  if marathon.saldo_pagado('cuota',quota.id::text)<>0 then raise exception 'La cuota histórica requiere completar la importación antes de reintegrarla.'using errcode='55000';end if;
  insert into marathon.agenda_ajustes(cuota_id,importe,motivo,created_by)values(quota.id,quota.importe-(select coalesce(sum(importe),0)from marathon.agenda_ajustes where cuota_id=quota.id),p_data->>'observaciones',auth.uid());
 elsif kind='REINTEGRO_SESION'then
  if length(btrim(coalesce(p_data->>'observaciones','')))<3 then raise exception 'Indicá el motivo del reintegro.'using errcode='22023';end if;
  select *into strict turno from marathon.turnos where id=p_data->>'turno_id'and dni=person for update;
  for a in select sa.*,marathon.saldo_aplicado(sa.id)actual from marathon.saldo_aplicaciones sa where sa.turno_id=turno.id and marathon.saldo_aplicado(sa.id)>0 order by sa.created_at,sa.id loop
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(person,a.fuente_id,'REVERSO_APLICACION',a.actual,a.id,p_request_id,auth.uid(),'reintegro:'||a.id);
  end loop;
  if marathon.saldo_pagado('sesion',turno.id)<>0 then raise exception 'Este pago histórico requiere completar la importación antes de reintegrarlo.'using errcode='55000';end if;
  insert into marathon.saldo_ajustes_sesion(turno_id,monto,motivo,request_id,actor)values(turno.id,turno.importe-(select coalesce(sum(monto),0)from marathon.saldo_ajustes_sesion where turno_id=turno.id),p_data->>'observaciones',p_request_id,auth.uid());
 else
  if p_data->>'medio'not in('EFECTIVO','TRANSFERENCIA')or nullif(p_data->>'medio','')is null then raise exception 'Elegí un medio de pago.'using errcode='22023';end if;
  if not exists(select 1 from marathon.sedes where nombre=p_data->>'sede'and estado='ACTIVO')then raise exception 'Elegí una sede activa.'using errcode='22023';end if;
  perform marathon.agenda_date(p_data->>'fecha');
  if kind in('SALDO_DEVOLUCION','OTRO_EGRESO','PAGO_PROFESIONAL','GASTO_GENERAL')and length(btrim(coalesce(p_data->>'observaciones','')))<3 then raise exception 'Indicá el concepto o motivo del egreso.'using errcode='22023';end if;
  if kind='PAGO_PROFESIONAL'and not exists(select 1 from marathon.profesionales pr join marathon.profesional_terapias pt on pt.profesional_id=pr.id join marathon.terapias th on th.id=pt.terapia_id where pr.id=p_data->>'profesional'and pt.terapia_id=p_data->>'terapia'and pr.estado='ACTIVO'and th.estado='ACTIVO')then raise exception 'Elegí un profesional y una terapia compatibles.'using errcode='22023';end if;
  mid='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,observaciones_legacy,categoria,profesional_asociado_id,terapia_asociada_id,secretaria_asociada,subtipo,created_by,updated_by)
  values(mid,(p_data->>'fecha')::date,(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA',case when kind in('SALDO_INGRESO','OTRO_INGRESO')then'INGRESO'else'EGRESO'end,person,amount,p_data->>'medio',p_data->>'sede',case kind when 'SALDO_INGRESO'then'Ingreso a favor del paciente'when'SALDO_DEVOLUCION'then'Devolución de saldo'when'PAGO_PROFESIONAL'then'Pago a profesional'when'GASTO_GENERAL'then'Gasto general'when'OTRO_EGRESO'then'Otro egreso'else'Otro ingreso'end,p_data->>'observaciones',nullif(p_data->>'categoria',''),nullif(p_data->>'profesional',''),nullif(p_data->>'terapia',''),nullif(p_data->>'secretaria',''),kind,auth.uid(),auth.uid());
  if kind='SALDO_INGRESO'then
   insert into marathon.saldo_fuentes(dni,movimiento_id,origen)values(person,mid,'NUEVO')returning id into source;
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(person,source,'INGRESO',amount,mid,p_request_id,auth.uid(),'ingreso');
   perform marathon.saldo_aplicar(person,p_request_id);
  elsif kind='SALDO_DEVOLUCION'then
   remaining=amount;
   for f in select sf.id,marathon.saldo_fuente_disponible(sf.id)available from marathon.saldo_fuentes sf join marathon.movimientos m on m.id=sf.movimiento_id where sf.dni=person and marathon.saldo_fuente_disponible(sf.id)>0 order by m.fecha,m.hora,m.created_at,m.id,sf.id loop
    piece=least(remaining,f.available);if piece>0 then insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(person,f.id,'DEVOLUCION',piece,mid,p_request_id,auth.uid(),'devolucion:'||f.id);end if;
    remaining=remaining-piece;exit when remaining=0;
   end loop;
   if remaining<>0 then raise exception 'Saldo insuficiente al confirmar.'using errcode='PT409';end if;
  end if;
 end if;
 reply=jsonb_build_object('id',mid,'cuenta',case when person is not null then marathon.saldo_cuenta_info(person)end,'message',case when kind='REINTEGRO_CUOTA'then 'Cuota reintegrada al saldo a favor del paciente. No se devolvió dinero de Caja. Para devolver dinero, registrá una Devolución de saldo.'else 'Movimiento registrado.'end);
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'saldo',coalesce(mid,person),kind,reply);
 return reply;
end$$;


commit;
