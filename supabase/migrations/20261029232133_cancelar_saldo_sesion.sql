-- Cancelación del saldo pendiente: ajuste clínico sin movimiento de caja.
-- El importe anterior y el motivo se conservan en la auditoría existente.
create or replace function public.marathon_turn_cancel_charge(p_request_id text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='3s'
as $$
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
 v_paid=marathon.turn_paid(v_id);v_debt=greatest(0,old_row.importe-v_paid);
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
end $$;
revoke all on function public.marathon_turn_cancel_charge(text,jsonb) from public,anon;
grant execute on function public.marathon_turn_cancel_charge(text,jsonb) to authenticated;

create or replace function public.marathon_turn_account(p_id text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare t marathon.turnos%rowtype;paid numeric;history jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 select * into t from marathon.turnos where id=p_id;
 if t.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 paid=marathon.turn_paid(t.id);
 select coalesce(jsonb_agg(jsonb_build_object('created_at',a.created_at,'before_amount',a.before_data->'importe',
  'amount',a.after_data->'importe_cancelado','after_amount',a.after_data->'importe',
  'reason',a.after_data->>'motivo_cancelacion','actor',coalesce(to_jsonb(u)->>'name',to_jsonb(u)->>'nombre','Usuario autorizado')) order by a.created_at desc,a.id desc),'[]'::jsonb)
 into history from marathon.turn_audit a left join marathon.app_users u on u.user_id=a.actor
 where a.turn_id=t.id and a.action='cancel_charge';
 return to_jsonb(t)||jsonb_build_object('paid',paid,'cash_paid',marathon.turn_cash_paid(t.id),
  'advance_paid',marathon.advance_paid(t.id),'debt',case when t.estado='PRESENTE' then greatest(0,t.importe-paid) else 0 end,'charge_cancellations',history);
end $$;
revoke all on function public.marathon_turn_account(text) from public,anon;
grant execute on function public.marathon_turn_account(text) to authenticated;
