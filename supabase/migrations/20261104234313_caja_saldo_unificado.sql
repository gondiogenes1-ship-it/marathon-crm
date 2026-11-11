-- Fase 2. Preparado y probado solo en base aislada. Requiere la migración de
-- estructura saldo anterior. La activación y la importación son explícitas.
begin;
create table marathon.saldo_config(id boolean primary key default true check(id),activo boolean not null default false,corte timestamptz);
insert into marathon.saldo_config(id)values(true);
alter table marathon.saldo_config enable row level security;
revoke all on marathon.saldo_config from public,anon,authenticated;
create table marathon.saldo_base_legacy(tipo text not null,id text not null,pagado numeric(18,2)not null check(pagado>=0),primary key(tipo,id));
alter table marathon.saldo_base_legacy enable row level security;
revoke all on marathon.saldo_base_legacy from public,anon,authenticated;
create trigger saldo_base_inmutable before update or delete on marathon.saldo_base_legacy for each row execute function marathon.saldo_inmutable();
alter table marathon.movimientos add column subtipo text,add column terapia_asociada_id text references marathon.terapias(id);
alter table marathon.movimientos add constraint saldo_subtipo_check check(subtipo is null or
 (subtipo='SALDO_INGRESO'and origen='CAJA'and tipo='INGRESO'and dni is not null and num_nonnulls(turno_id,cuota_id,bono_id,anticipo_id,operacion_id)=0)or
 (subtipo='SALDO_DEVOLUCION'and origen='CAJA'and tipo='EGRESO'and dni is not null and num_nonnulls(turno_id,cuota_id,bono_id,anticipo_id,operacion_id)=0)or
 (subtipo in('OTRO_INGRESO','GASTO_GENERAL','OTRO_EGRESO','PAGO_PROFESIONAL')and origen='CAJA'and dni is null and num_nonnulls(turno_id,cuota_id,bono_id,anticipo_id,operacion_id)=0 and
 ((subtipo='OTRO_INGRESO'and tipo='INGRESO')or(subtipo<>'OTRO_INGRESO'and tipo='EGRESO'))and
 (subtipo<>'PAGO_PROFESIONAL'or(profesional_asociado_id is not null and terapia_asociada_id is not null))));
create function marathon.saldo_legacy_pagado(p_tipo text,p_id text)returns numeric language sql stable set search_path=''as $$
 select case p_tipo when 'sesion'then marathon.turn_cash_paid(p_id)+marathon.advance_paid(p_id)
 when 'cuota'then(select coalesce(sum(case when m.tipo in('PAGO','INGRESO')then m.monto else -m.monto end),0)from marathon.movimientos m left join marathon.movimientos original on original.id=m.compensacion_de where m.cuota_id=p_id::uuid or original.cuota_id=p_id::uuid)
 when 'bono'then(select coalesce(sum(case when tipo in('EGRESO','REINTEGRO')then -monto else monto end),0)from marathon.movimientos where bono_id=p_id)else 0 end
$$;
create function marathon.saldo_pagado(p_tipo text,p_id text)returns numeric language sql stable set search_path=''as $$
 select marathon.saldo_legacy_pagado(p_tipo,p_id)-coalesce((select pagado from marathon.saldo_base_legacy where tipo=p_tipo and id=p_id),0)+
 coalesce((select sum(case e.tipo when 'APLICACION'then e.monto when 'REVERSO_APLICACION'then -e.monto else 0 end)
 from marathon.saldo_aplicaciones a join marathon.saldo_eventos e on e.aplicacion_id=a.id
 where case p_tipo when 'sesion'then a.turno_id=p_id when 'cuota'then a.cuota_id::text=p_id when 'bono'then a.bono_id=p_id else false end),0)
$$;
create function marathon.saldo_deudas(p_dni text)returns table(tipo text,id text,fecha date,hora time,created_at timestamptz,cargo numeric,pagado numeric,deuda numeric,sede text,profesional text,terapia text)
 language sql stable set search_path=''as $$
 with all_debts as(
 select 'sesion'::text tipo,t.id,t.fecha,t.hora,t.created_at,
 greatest(0,t.importe-coalesce((select sum(a.monto)from marathon.saldo_ajustes_sesion a where a.turno_id=t.id),0))cargo,
 marathon.saldo_pagado('sesion',t.id)pagado,t.sede,t.profesional_id profesional,t.terapia_id terapia
 from marathon.turnos t where t.dni=p_dni and t.estado='PRESENTE'
 union all
 select 'cuota',q.id::text,q.fecha,'00:00'::time,q.created_at,greatest(0,q.importe-coalesce((select sum(a.importe)from marathon.agenda_ajustes a where a.cuota_id=q.id),0)),marathon.saldo_pagado('cuota',q.id::text),q.sede,
 (select hs.profesional_id from marathon.agenda_horarios hs where hs.plan_id=q.plan_id order by hs.dia,hs.hora,hs.id limit 1),p.terapia_id
 from marathon.agenda_cuotas q join marathon.agenda_planes p on p.id=q.plan_id where p.dni=p_dni
 union all
 select 'bono',b.id,b.fecha,b.hora,b.created_at,b.importe,marathon.saldo_pagado('bono',b.id),b.sede,b.profesional_id,b.terapia_id
 from marathon.bonos_serie b where b.dni=p_dni and b.estado='ACTIVO')
 select d.tipo,d.id,d.fecha,d.hora,d.created_at,d.cargo,d.pagado,greatest(0,d.cargo-d.pagado),d.sede,d.profesional,d.terapia from all_debts d
 order by d.fecha,d.hora,d.created_at,d.tipo,d.id
$$;
create function marathon.saldo_version(p_dni text)returns bigint language sql stable set search_path=''as $$select coalesce((select version from marathon.saldo_cuentas where dni=p_dni),0)$$;
create function marathon.saldo_importe(p_value text)returns numeric language plpgsql immutable set search_path=''as $$begin
 if p_value is null or p_value!~'^[0-9]{1,10}(\.[0-9]{1,2})?$'or p_value::numeric<=0 then raise exception 'Indicá un importe positivo, con hasta dos decimales.'using errcode='22023';end if;return p_value::numeric;end$$;
create function marathon.saldo_cuenta_info(p_dni text)returns jsonb language sql stable set search_path=''as $$
 select jsonb_build_object('dni',p.dni,'name',concat_ws(' ',p.apellido,p.nombre),'version',marathon.saldo_version(p.dni),'saldo',marathon.saldo_disponible(p.dni)::text,
 'deuda',coalesce((select sum(d.deuda)from marathon.saldo_deudas(p.dni)d),0)::text,
 'deudas',coalesce((select jsonb_agg(to_jsonb(d)order by d.fecha,d.hora,d.created_at,d.tipo,d.id)from marathon.saldo_deudas(p.dni)d),'[]'::jsonb))from marathon.pacientes p where p.dni=p_dni
$$;
create function marathon.saldo_prever(p_data jsonb)returns jsonb language plpgsql stable set search_path=''as $$
declare person text:=p_data->>'dni';kind text:=p_data->>'subtipo';amount numeric;account jsonb;available numeric;remaining numeric;used numeric:=0;d record;piece numeric;details jsonb:='[]';fingerprint text;begin
 if kind not in('SALDO_INGRESO','SALDO_DEVOLUCION','REINTEGRO_SESION','OTRO_INGRESO','PAGO_PROFESIONAL','GASTO_GENERAL','OTRO_EGRESO')or kind is null then raise exception 'Subtipo inválido.'using errcode='22023';end if;
 if kind in('SALDO_INGRESO','SALDO_DEVOLUCION','REINTEGRO_SESION')then
  account=marathon.saldo_cuenta_info(person);if account is null then raise exception 'Elegí un paciente existente.'using errcode='22023';end if;
 else if nullif(person,'')is not null then raise exception 'Este movimiento no lleva paciente.'using errcode='22023';end if;account=jsonb_build_object('saldo','0','deuda','0','version',0);end if;
 available=(account->>'saldo')::numeric;
 if kind='REINTEGRO_SESION'then
  select *into d from marathon.saldo_deudas(person)x where x.tipo='sesion'and x.id=p_data->>'turno_id';
  if not found or d.pagado<=0 then raise exception 'Elegí una sesión presente con pago recuperable.'using errcode='22023';end if;
  amount=d.pagado;remaining=available+amount;details=jsonb_build_array(jsonb_build_object('tipo','sesion','id',d.id,'pagado_liberado',d.pagado::text,'deuda_bonificada',d.deuda::text));
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
create function public.marathon_saldo_consultar(p_dni text)returns jsonb language plpgsql stable security definer set search_path=''as $$declare r jsonb;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;r=marathon.saldo_cuenta_info(p_dni);if r is null then raise exception 'Paciente no encontrado.'using errcode='PT404';end if;return r;end$$;
create function public.marathon_saldo_prever(p_data jsonb)returns jsonb language plpgsql stable security definer set search_path=''as $$begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;return marathon.saldo_prever(p_data);end$$;
create function marathon.saldo_aplicar(p_dni text,p_request text)returns void language plpgsql set search_path=''as $$declare d record;f record;amount numeric;app uuid;counter int:=0;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 for d in select *from marathon.saldo_deudas(p_dni)where deuda>0 loop
  for f in select sf.id,marathon.saldo_fuente_disponible(sf.id)available from marathon.saldo_fuentes sf join marathon.movimientos m on m.id=sf.movimiento_id where sf.dni=p_dni and marathon.saldo_fuente_disponible(sf.id)>0 order by m.fecha,m.hora,m.created_at,m.id,sf.id loop
   amount=least(d.deuda,f.available);exit when amount<=0;
   insert into marathon.saldo_aplicaciones(dni,fuente_id,turno_id,cuota_id,bono_id,monto,request_id,actor)
   values(p_dni,f.id,case when d.tipo='sesion'then d.id end,case when d.tipo='cuota'then d.id::uuid end,case when d.tipo='bono'then d.id end,amount,p_request,auth.uid())returning id into app;
   counter=counter+1;
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(p_dni,f.id,'APLICACION',amount,app,p_request,auth.uid(),'aplicar:'||app);
   d.deuda=d.deuda-amount;exit when d.deuda<=0;
  end loop;
 end loop;
end$$;
create function marathon.saldo_evento_limites()returns trigger language plpgsql set search_path=''as $$declare d record;a marathon.saldo_aplicaciones%rowtype;begin
 if new.tipo='APLICACION'then
  select *into strict a from marathon.saldo_aplicaciones where id=new.aplicacion_id;
  select *into d from marathon.saldo_deudas(new.dni)x where(x.tipo='sesion'and x.id=a.turno_id)or(x.tipo='cuota'and x.id=a.cuota_id::text)or(x.tipo='bono'and x.id=a.bono_id);
  if d.id is null or new.monto>d.deuda then raise exception 'La aplicación supera la deuda vigente.'using errcode='22023';end if;
 end if;
 insert into marathon.saldo_cuentas(dni)values(new.dni)on conflict(dni)do update set version=marathon.saldo_cuentas.version+1;
 return new;
end$$;
create trigger saldo_evento_limites before insert on marathon.saldo_eventos for each row execute function marathon.saldo_evento_limites();

create function public.marathon_saldo_command(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$
declare previous jsonb;proposal jsonb;kind text:=p_data->>'subtipo';person text:=nullif(p_data->>'dni','');amount numeric;mid text;source uuid;f record;a record;available numeric;piece numeric;remaining numeric;turno marathon.turnos%rowtype;reply jsonb;begin
 previous=marathon.operation_begin(p_request_id,'saldo:'||coalesce(kind,''),p_data);if previous is not null then return previous;end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'El nuevo circuito de saldo todavía no está habilitado.'using errcode='55000';end if;
 proposal=marathon.saldo_prever(p_data);
 if p_data->>'huella' is distinct from proposal->>'huella'or p_data->>'version'is distinct from proposal->>'version'then raise exception 'La cuenta cambió. Revisá la nueva vista previa antes de confirmar.'using errcode='PT409';end if;
 amount=(proposal->>'monto')::numeric;
 if kind='REINTEGRO_SESION'then
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
 reply=jsonb_build_object('id',mid,'cuenta',case when person is not null then marathon.saldo_cuenta_info(person)end,'message','Movimiento registrado.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'saldo',coalesce(mid,person),kind,reply);
 return reply;
end$$;
-- Mantener las funciones internas fuera de la API y autorizar solo los RPC.
revoke all on function marathon.saldo_legacy_pagado(text,text),marathon.saldo_pagado(text,text),marathon.saldo_deudas(text),marathon.saldo_version(text),marathon.saldo_importe(text),marathon.saldo_cuenta_info(text),marathon.saldo_prever(jsonb),marathon.saldo_aplicar(text,text),marathon.saldo_evento_limites()from public,anon,authenticated;
revoke all on function public.marathon_saldo_consultar(text),public.marathon_saldo_prever(jsonb),public.marathon_saldo_command(text,jsonb)from public,anon;
grant execute on function public.marathon_saldo_consultar(text),public.marathon_saldo_prever(jsonb),public.marathon_saldo_command(text,jsonb)to authenticated;
commit;
