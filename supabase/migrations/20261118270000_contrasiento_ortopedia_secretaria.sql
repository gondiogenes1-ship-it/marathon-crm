-- Extiende el cambio anterior (20261118260000) a ortopedia: "Anular con contrasiento"
-- de un cobro de ortopedia queda disponible para ADMIN y SECRETARIA, no solo ADMIN.
-- Comprar, ajustar stock y pagar compras (purchase/adjust_in/adjust_out/purchase_pay)
-- siguen siendo exclusivos de ADMIN, sin cambios.

create or replace function public.marathon_ortho_command(p_request_id text, p_action text, p_data jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '3s'
as $function$
#variable_conflict use_variable
declare reply jsonb;p marathon.productos%rowtype;old marathon.ortopedia_operaciones%rowtype;move marathon.movimientos%rowtype;
 product text;site text;destination text;dni text;obs text;medium text;reason text;kind text;id text;second_id text;mid text;comp text;
 qty integer;weeks integer;price numeric;total numeric;subtotal numeric;discount_rate numeric:=0;discount_amount numeric:=0;payment numeric;paid numeric;date_now date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;hour_now time:=(now() at time zone 'America/Argentina/Buenos_Aires')::time;transfer uuid;after_data jsonb;ids text[]:=array[]::text[];
begin
 reply=marathon.operation_begin(p_request_id,'ortho:'||coalesce(p_action,''),p_data,array['ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA']);if reply is not null then return reply;end if;
 if p_action is null or p_action not in('sale','rent','purchase','adjust_in','adjust_out','transfer','return','pay','refund','purchase_pay','reverse','void')or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case
 when p_action in('sale','rent','purchase','adjust_in','adjust_out')then array['product','product_version','sede','cantidad','semanas','dni','pago','medio','observaciones','discount_rate']
 when p_action='transfer'then array['product','product_version','sede','destino','cantidad','observaciones']
 when p_action='return'then array['id','version','cantidad','observaciones']
 when p_action in('reverse','void')then array['id','version','motivo']else array['id','version','monto','medio','observaciones']end))then raise sqlstate '22023' using message='Operación de ortopedia inválida.';end if;
 if p_action in('purchase','adjust_in','adjust_out','purchase_pay')and not marathon.is_admin()then raise sqlstate '42501' using message='Solo ADMIN puede comprar, ajustar stock o pagar compras.';end if;
 if p_action='reverse' and not marathon.active_user()then raise sqlstate '42501' using message='Solo administración o secretaría pueden aprobar un contrasiento.';end if;
 if p_action='rent' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede registrar alquileres.';end if;
 if p_action='transfer' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede trasladar stock entre sedes. Pedile a administración.';end if;
 obs=marathon.master_text(p_data,'observaciones',2000);
 if p_action in('sale','rent','purchase','adjust_in','adjust_out','transfer')then
 product=marathon.master_text(p_data,'product',100,true);site=marathon.master_text(p_data,'sede',40,true);qty=marathon.ortho_int(p_data,'cantidad',1,10000);
 select * into p from marathon.productos where productos.id=product for update;
 if p.id is null or p.estado<>'ACTIVO'or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')then raise sqlstate '22023' using message='Elegí un producto y una sede activos.';end if;
 if not marathon.ortho_sede_allowed(site) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;
 if p.version<>marathon.ortho_int(p_data,'product_version',1,999999999999999999)then raise sqlstate 'PT409' using message='El producto o sus precios cambiaron. Volvé a abrir la operación.';end if;
 if not exists(select 1 from marathon.stock_config where producto_id=product and sede=site)then raise sqlstate '22023' using message='Habilitá el producto por sede antes de operar.';end if;
 if p_action in('sale','rent','adjust_out','transfer')and qty>marathon.ortho_stock(product,site)then raise sqlstate 'PT409' using message='Stock insuficiente. Actualizá el inventario.';end if;
 if p_action='transfer'then
 destination=marathon.master_text(p_data,'destino',40,true);
 if not marathon.ortho_sede_allowed(destination) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;
 if destination=site or not exists(select 1 from marathon.sedes where nombre=destination and estado='ACTIVO')then raise sqlstate '22023' using message='Elegí otra sede activa.';end if;
 insert into marathon.stock_config(producto_id,sede,minimo,initial_loaded,created_by,updated_by)values(product,destination,0,true,auth.uid(),auth.uid())on conflict on constraint stock_config_pkey do nothing;
 if obs=''then raise sqlstate '22023' using message='Indicá el motivo del traslado.';end if;
 transfer=gen_random_uuid();id='ORT-'||gen_random_uuid()::text;second_id='ORT-'||gen_random_uuid()::text;
 insert into marathon.ortopedia_operaciones(id,original_id,fecha,hora,tipo,producto_id,sede,cantidad,importe_total,precio_unitario,producto_snapshot,transfer_id,observaciones,created_by,updated_by)values
 (id,null,date_now,hour_now,'AJUSTE_NEGATIVO',product,site,qty,0,0,to_jsonb(p),transfer,obs,auth.uid(),auth.uid()),
 (second_id,id,date_now,hour_now,'AJUSTE_POSITIVO',product,destination,qty,0,0,to_jsonb(p),transfer,obs,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'transfer-out',null,after_data);
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=second_id;perform marathon.ortho_audit(p_request_id,'ortho',second_id,'transfer-in',null,after_data);
 reply=jsonb_build_object('ids',jsonb_build_array(id,second_id),'message','Traslado registrado en ambas sedes. No se movió dinero.');
 else
 kind=case p_action when 'sale'then 'VENTA'when 'rent'then 'ALQUILER'when 'purchase'then 'COMPRA'when 'adjust_in'then 'AJUSTE_POSITIVO'else 'AJUSTE_NEGATIVO'end;
 if p_action in('sale','rent')then dni=nullif(marathon.master_text(p_data,'dni',12,p_action='rent'),'');if dni is not null and not exists(select 1 from marathon.pacientes where pacientes.dni=dni)then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;
 if strpos(p.modalidad,kind)=0 then raise sqlstate '22023' using message='El catálogo no habilita esta modalidad.';end if;end if;
 weeks=case when p_action='rent'then marathon.ortho_int(p_data,'semanas',1,520)else null end;
 price=case p_action when 'sale'then p.precio_venta when 'rent'then p.precio_alquiler when 'purchase'then p.costo else 0 end;
 if price is null then raise sqlstate '22023' using message='Falta el precio o costo en el catálogo.';end if;
 if p_action in('adjust_in','adjust_out')and obs=''then raise sqlstate '22023' using message='Indicá el motivo del ajuste.';end if;
 if p_data ? 'discount_rate' then
 if p_action not in('sale','rent') or jsonb_typeof(p_data->'discount_rate') is distinct from 'number' or coalesce(p_data->>'discount_rate','') !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Descuento inválido: usá un porcentaje entre 0 y 100, con hasta dos decimales.';end if;
 discount_rate=(p_data->>'discount_rate')::numeric;
 if discount_rate>100 then raise sqlstate '22023' using message='El descuento no puede superar el 100%.';end if;end if;
 subtotal=round(price*qty*coalesce(weeks,1),2);discount_amount=round(subtotal*discount_rate/100,2);total=subtotal-discount_amount;if total>9999999999999999.99 then raise sqlstate '22023' using message='El total supera el límite de esta operación.';end if;
 payment=coalesce(marathon.ortho_price(p_data,'pago'),0);medium=marathon.master_text(p_data,'medio',13);
 if payment>total or(p_action in('adjust_in','adjust_out')and payment<>0)then raise sqlstate '22023' using message='El pago supera el total o no corresponde a un ajuste.';end if;
 if payment>0 and medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,fecha,hora,tipo,producto_id,sede,cantidad,dni,semanas,devolucion_prevista,importe_total,precio_unitario,producto_snapshot,observaciones,subtotal,discount_rate,discount_amount,created_by,updated_by)values(id,date_now,hour_now,kind,product,site,qty,dni,weeks,case when weeks is not null then date_now+weeks*7 end,total,price,to_jsonb(p),obs,case when p_action in('sale','rent')then subtotal end,case when p_action in('sale','rent')then discount_rate end,case when p_action in('sale','rent')then discount_amount end,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,p_action,null,after_data);
 if payment>0 then mid='MOV-'||gen_random_uuid()::text;insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,operacion_id,concepto,observaciones_legacy,created_by,updated_by)values(mid,date_now,hour_now,'ORTOPEDIA',case when p_action='purchase'then 'EGRESO'else 'PAGO'end,dni,payment,medium,site,id,kind||' · '||p.descripcion,obs,auth.uid(),auth.uid());
 select to_jsonb(m)into after_data from marathon.movimientos m where m.id=mid;perform marathon.ortho_audit(p_request_id,'movement',mid,'initial-payment',null,after_data);end if;
 reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Operación guardada. Stock, cuenta y caja actualizados.');end if;
 else
 -- Devoluciones y cobros de operaciones antiguas siguen permitidos con catálogo inactivo.
 if p_action='reverse'then
 select * into move from marathon.movimientos m where m.id=marathon.master_text(p_data,'id',100,true)for update;
 if move.id is null or move.origen<>'ORTOPEDIA'or move.tipo<>'PAGO'or move.operacion_id is null then raise sqlstate '22023' using message='Elegí un cobro original de ortopedia.';end if;
 if move.version<>marathon.operation_version(p_data)or exists(select 1 from marathon.movimientos where compensacion_de=move.id)then raise sqlstate 'PT409' using message='El cobro cambió o ya tiene contrasiento.';end if;
 select * into old from marathon.ortopedia_operaciones where ortopedia_operaciones.id=move.operacion_id for update;
 else select * into old from marathon.ortopedia_operaciones where ortopedia_operaciones.id=marathon.master_text(p_data,'id',100,true)for update;
 if old.id is null then raise sqlstate 'PT404' using message='Operación no encontrada.';end if;
 if old.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='La operación cambió. Volvé a abrirla.';end if;end if;
 if not marathon.ortho_sede_allowed(old.sede) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;
 if p_action='return'then
 if old.tipo<>'ALQUILER'then raise sqlstate '22023' using message='Solo se devuelven unidades de un alquiler.';end if;
 qty=marathon.ortho_int(p_data,'cantidad',1,10000);if qty>old.cantidad-marathon.ortho_returned(old.id)then raise sqlstate 'PT409' using message='La cantidad supera las unidades pendientes de devolución.';end if;
 if not exists(select 1 from marathon.stock_config where producto_id=old.producto_id and sede=old.sede)then raise sqlstate '22023' using message='Revisá la habilitación del producto y la sede antes de devolver.';end if;
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,original_id,fecha,hora,tipo,producto_id,sede,cantidad,dni,importe_total,precio_unitario,producto_snapshot,observaciones,created_by,updated_by)values(id,old.id,date_now,hour_now,'DEVOLUCION',old.producto_id,old.sede,qty,old.dni,0,0,old.producto_snapshot,obs,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'return',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Devolución registrada. La deuda conserva su saldo.');
 elsif p_action='void'then
 if old.tipo<>'VENTA'then raise sqlstate '22023' using message='Solo se anulan ventas.';end if;
 if exists(select 1 from marathon.ortopedia_operaciones v where v.original_id=old.id and v.tipo='AJUSTE_POSITIVO')then raise sqlstate '22023' using message='Esta venta ya fue anulada.';end if;
 if marathon.ortho_paid(old.id)>0 then raise sqlstate '22023' using message='Esta venta ya tiene un cobro registrado. Primero usá «Registrar reintegro» para devolver el pago completo, y después pedile a un administrador que ajuste el stock.';end if;
 reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,original_id,fecha,hora,tipo,producto_id,sede,cantidad,importe_total,precio_unitario,producto_snapshot,observaciones,created_by,updated_by)values(id,old.id,date_now,hour_now,'AJUSTE_POSITIVO',old.producto_id,old.sede,old.cantidad,0,0,old.producto_snapshot,reason,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'void',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Venta anulada. El stock quedó restituido.');
 else
 paid=marathon.ortho_paid(old.id);
 if p_action='reverse'then
 reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
 if paid<move.monto then raise sqlstate '22023' using message='Hay reintegros previos. Reintegrá solo el saldo correspondiente.';end if;payment=move.monto;medium=move.medio;comp=move.id;obs=reason;
 else payment=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);end if;
 if medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
 if p_action='purchase_pay'then if old.tipo<>'COMPRA'or payment>old.importe_total-paid then raise sqlstate '22023' using message='El pago supera el saldo de la compra.';end if;kind='EGRESO';
 elsif p_action='pay'then if old.tipo not in('VENTA','ALQUILER')or payment>old.importe_total-paid then raise sqlstate '22023' using message='El cobro supera el saldo de la venta o alquiler.';end if;kind='PAGO';
 else if old.tipo not in('VENTA','ALQUILER')or payment>paid then raise sqlstate '22023' using message='El reintegro supera lo cobrado en la venta o alquiler.';end if;kind='REINTEGRO';end if;
 mid='MOV-'||gen_random_uuid()::text;insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,operacion_id,concepto,observaciones_legacy,compensacion_de,motivo,created_by,updated_by)values(mid,date_now,hour_now,'ORTOPEDIA',kind,old.dni,payment,medium,old.sede,old.id,case when p_action='reverse'then 'Contrasiento de '||move.id else kind||' de ortopedia'end,obs,comp,reason,auth.uid(),auth.uid());
 select to_jsonb(m)into after_data from marathon.movimientos m where m.id=mid;perform marathon.ortho_audit(p_request_id,'movement',mid,p_action,case when move.id is not null then to_jsonb(move)end,after_data);
 reply=jsonb_build_object('ids',jsonb_build_array(mid),'message',case when p_action='reverse'then 'Contrasiento registrado. El cobro original se conserva.'when kind='REINTEGRO'then 'Reintegro registrado.'when kind='EGRESO'then 'Pago de compra registrado.'else 'Cobro de ortopedia registrado.'end);end if;
 end if;
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $function$;
