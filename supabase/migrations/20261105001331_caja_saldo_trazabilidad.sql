-- Conservar las asociaciones del origen en el contrasiento monetario.
begin;
create or replace function public.marathon_saldo_anular(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$
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
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,compensacion_de,motivo,created_by,updated_by,categoria,profesional_asociado_id,terapia_asociada_id,secretaria_asociada)
 values(mid,marathon.agenda_date(p_data->>'fecha'),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA','EGRESO',source.dni,original.monto,original.medio,original.sede,'Anulación de ingreso de saldo',original.id,p_data->>'motivo',auth.uid(),auth.uid(),original.categoria,coalesce(original.profesional_asociado_id,(select profesional_id from marathon.turnos where id=original.turno_id),(select profesional_id from marathon.bonos_serie where id=original.bono_id),(select profesional_id from marathon.anticipos where id=original.anticipo_id)),coalesce(original.terapia_asociada_id,(select terapia_id from marathon.turnos where id=original.turno_id),(select terapia_id from marathon.bonos_serie where id=original.bono_id),(select terapia_id from marathon.anticipos where id=original.anticipo_id),(select ap.terapia_id from marathon.agenda_planes ap join marathon.agenda_cuotas q on q.plan_id=ap.id where q.id=original.cuota_id)),original.secretaria_asociada);
 insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(source.dni,source.id,'DEVOLUCION',original.monto,mid,p_request_id,auth.uid(),'anular:ingreso');
 reply=jsonb_build_object('id',mid,'cuenta',marathon.saldo_cuenta_info(source.dni),'message','Ingreso anulado. Las deudas vuelven a quedar pendientes.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'saldo',original.id,'anular',to_jsonb(original),reply);
 return reply;
end$$;

commit;
