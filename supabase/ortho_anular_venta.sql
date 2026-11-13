-- Ortopedia: nueva accion 'void' (Anular venta) en marathon_ortho_command.
-- Disponible para cualquier rol activo (respeta las mismas sedes habilitadas que el
-- resto de las acciones, vía el chequeo de sede ya existente sobre "old").
--
-- Solo se puede anular una VENTA que todavia no tenga ningun cobro registrado: el
-- stock se restituye con un ajuste positivo vinculado a la venta original (el sistema
-- nunca edita ni borra movimientos, solo agrega compensaciones), y si ya se cobro algo
-- se explica qué hacer antes: primero reintegrar el pago, y despues pedirle a un
-- administrador que ajuste el stock a mano.
--
-- Correr en el SQL Editor de Supabase (una sola vez), después de los scripts anteriores.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_command(text,text,jsonb)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if p_action is null or p_action not in('sale','rent','purchase','adjust_in','adjust_out','transfer','return','pay','refund','purchase_pay','reverse')or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case
 when p_action in('sale','rent','purchase','adjust_in','adjust_out')then array['product','product_version','sede','cantidad','semanas','dni','pago','medio','observaciones','discount_rate']
 when p_action='transfer'then array['product','product_version','sede','destino','cantidad','observaciones']
 when p_action='return'then array['id','version','cantidad','observaciones']
 when p_action='reverse'then array['id','version','motivo']else array['id','version','monto','medio','observaciones']end))then raise sqlstate '22023' using message='Operación de ortopedia inválida.';end if;$frag$,
  $frag$if p_action is null or p_action not in('sale','rent','purchase','adjust_in','adjust_out','transfer','return','pay','refund','purchase_pay','reverse','void')or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case
 when p_action in('sale','rent','purchase','adjust_in','adjust_out')then array['product','product_version','sede','cantidad','semanas','dni','pago','medio','observaciones','discount_rate']
 when p_action='transfer'then array['product','product_version','sede','destino','cantidad','observaciones']
 when p_action='return'then array['id','version','cantidad','observaciones']
 when p_action in('reverse','void')then array['id','version','motivo']else array['id','version','monto','medio','observaciones']end))then raise sqlstate '22023' using message='Operación de ortopedia inválida.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de la lista de acciones.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'return',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Devolución registrada. La deuda conserva su saldo.');
 else
 paid=marathon.ortho_paid(old.id);$frag$,
  $frag$select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'return',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Devolución registrada. La deuda conserva su saldo.');
 elsif p_action='void'then
 if old.tipo<>'VENTA'then raise sqlstate '22023' using message='Solo se anulan ventas.';end if;
 if exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=old.id and v.tipo='AJUSTE_POSITIVO')then raise sqlstate '22023' using message='Esta venta ya fue anulada.';end if;
 if marathon.ortho_paid(old.id)>0 then raise sqlstate '22023' using message='Esta venta ya tiene un cobro registrado. Primero usá «Registrar reintegro» para devolver el pago completo, y después pedile a un administrador que ajuste el stock.';end if;
 reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,original_id,fecha,hora,tipo,producto_id,sede,cantidad,importe_total,precio_unitario,producto_snapshot,observaciones,created_by,updated_by)values(id,old.id,date_now,hour_now,'AJUSTE_POSITIVO',old.producto_id,old.sede,old.cantidad,0,0,old.producto_snapshot,reason,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'void',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Venta anulada. El stock quedó restituido.');
 else
 paid=marathon.ortho_paid(old.id);$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de la rama return/else.'; end if;

 execute cur;
end $$;

notify pgrst,'reload schema';
commit;
