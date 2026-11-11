begin;
CREATE OR REPLACE FUNCTION marathon.agenda_materializar(d date, e date)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v record;n int:=0;root text;begin
 if e<d or e-d>31 then raise sqlstate '22023' using message='Consultá hasta 32 días.';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 for v in select virtual_row.*,dt::date fecha from generate_series(d,e,interval '1 day')dt cross join lateral marathon.agenda_virtual(dt::date)virtual_row order by dt,virtual_row.hora,virtual_row.id loop
  select t.id into root from marathon.turnos t where t.plan_id=v.plan_id order by t.created_at,t.id limit 1;
  insert into marathon.turnos(id,original_id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,coverage,booking_notes,plan_id,horario_id,fecha_habitual,created_by,updated_by)
  select 'TUR-'||gen_random_uuid()::text,root,v.fecha,v.sede,v.hora,v.duracion_min,v.terapia_id,v.profesional_id,v.dni,case when p.facturacion in('class','bonus_class') then p.importe else 0 end,'PENDIENTE',p.coverage,p.observaciones,p.id,v.horario_id,v.fecha,auth.uid(),auth.uid() from marathon.agenda_planes p where p.id=v.plan_id
  on conflict(horario_id,fecha_habitual)where horario_id is not null do nothing;n=n+1;
 end loop;
 -- Una corrección de asistencia puede reabrir el saldo. Las cancelaciones manuales no se restauran.
 for v in select t.* from marathon.turnos t join marathon.agenda_planes p on p.id=t.plan_id where t.fecha between d and e and t.agenda_motivo='SESIONES_COMPLETAS' and t.estado='CANCELADO' and(p.baja is null or t.fecha<p.baja) and marathon.agenda_presentes(p.id)<marathon.agenda_total(p.id) loop
  update marathon.turnos set estado='PENDIENTE',agenda_motivo=null where id=v.id;
 end loop;
 if not exists(select 1 from marathon.saldo_config where activo)or marathon.active_user()then perform marathon.agenda_cuotas_generar();end if;return n;
end$function$
;
CREATE OR REPLACE FUNCTION public.marathon_turn_cancel_charge(p_request_id text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare
 reply jsonb; old_row marathon.turnos%rowtype; new_row marathon.turnos%rowtype;
 v_id text; v_reason text; v_paid numeric; v_debt numeric; v_expected numeric;
begin
 reply=marathon.operation_begin(p_request_id,'turn:cancel_charge',p_data);
 if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in('id','version','saldo','motivo')) then
  raise sqlstate '22023' using message='Datos de cancelación inválidos.';
 end if;
 v_id=marathon.master_text(p_data,'id',100,true);
 v_reason=btrim(marathon.master_text(p_data,'motivo',1000,true));
 if length(v_reason)<3 then raise sqlstate '22023' using message='Indicá el motivo de la cancelación (3 a 1000 caracteres).';end if;
 if coalesce(p_data->>'saldo','') !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$' then
  raise sqlstate '22023' using message='El saldo esperado es inválido.';
 end if;
 v_expected=(p_data->>'saldo')::numeric;
 select * into old_row from marathon.turnos where id=v_id for update;
 if old_row.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 if old_row.version<>marathon.operation_version(p_data) then
  raise sqlstate 'PT409' using message='La sesión cambió. Volvé a abrir la cancelación.';
 end if;
 v_paid=marathon.turn_paid(v_id);v_debt=greatest(0,marathon.saldo_cargo_sesion(v_id)-v_paid);
 if old_row.estado<>'PRESENTE' or v_debt<=0 then
  raise sqlstate '22023' using message='Solo se cancela el saldo pendiente de una sesión presente.';
 end if;
 if v_expected<>v_debt then raise sqlstate 'PT409' using message='Cambió el saldo de la sesión. Volvé a abrir la cancelación.';end if;
 -- Mantener pagos y anticipos aplicados; anular solamente la parte adeudada.
 update marathon.turnos set importe=old_row.importe-v_debt where id=v_id returning * into new_row;
 insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)
 values(p_request_id,auth.uid(),v_id,'cancel_charge',to_jsonb(old_row),to_jsonb(new_row)||jsonb_build_object(
  'motivo_cancelacion',v_reason,'importe_cancelado',v_debt,'saldo_anterior',v_debt,'saldo_resultante',0,
  'pagos_conservados',v_paid,'tipo_ajuste','CONTRAASIENTO_SALDO_SIN_CAJA'));
 reply=jsonb_build_object('id',v_id,'cancelled_amount',v_debt,'debt',0,'message','Saldo de la sesión cancelado. Presente y pagos conservados; ajuste registrado con su motivo.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 return reply;
end $function$
;
-- Este archivo se incorpora al final de la migración de cierre por preparar_cierre_saldo.py.
create function public.marathon_saldo_anular_prever(p_id text)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare f marathon.saldo_fuentes%rowtype;m marathon.movimientos%rowtype;blocked boolean;begin
 if not marathon.is_admin()then raise exception 'Solo ADMIN puede anular un ingreso.'using errcode='42501';end if;
 select *into f from marathon.saldo_fuentes where movimiento_id=p_id;
 if not found then raise exception 'Ingreso no encontrado.'using errcode='PT404';end if;
 select *into strict m from marathon.movimientos where id=p_id;
 blocked=exists(select 1 from marathon.saldo_eventos where fuente_id=f.id and tipo='DEVOLUCION')or exists(select 1 from marathon.movimientos where compensacion_de=p_id);
 return jsonb_build_object('id',m.id,'dni',f.dni,'importe',m.monto::text,'medio',m.medio,'sede',m.sede,'version',marathon.saldo_version(f.dni),'bloqueado',blocked,
 'motivo_bloqueo',case when blocked then'El ingreso tiene devoluciones o ya fue anulado. Requiere revisión administrativa.'end,
 'aplicaciones',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'turno_id',a.turno_id,'cuota_id',a.cuota_id,'bono_id',a.bono_id,'liberar',marathon.saldo_aplicado(a.id)::text)order by a.created_at,a.id)from marathon.saldo_aplicaciones a where a.fuente_id=f.id and marathon.saldo_aplicado(a.id)>0),'[]'));
end$$;
revoke all on function public.marathon_saldo_anular_prever(text)from public,anon;
grant execute on function public.marathon_saldo_anular_prever(text)to authenticated;

-- Un índice para consultas frecuentes del saldo por paciente; el resto ya se creó en estructura.
create index saldo_eventos_paciente_fecha on marathon.saldo_eventos(dni,created_at desc,id desc);
create index saldo_fuentes_paciente on marathon.saldo_fuentes(dni);
commit;
