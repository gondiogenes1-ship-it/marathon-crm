begin;

create function marathon.saldo_cargo_sesion(p_id text)returns numeric language sql stable set search_path=''as $$
 select greatest(0,t.importe-case when exists(select 1 from marathon.saldo_config where activo)then coalesce((select sum(monto)from marathon.saldo_ajustes_sesion where turno_id=t.id),0)else 0 end)from marathon.turnos t where t.id=p_id
$$;
revoke all on function marathon.saldo_cargo_sesion(text)from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.marathon_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rows jsonb;nxt jsonb;total numeric;name text;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['fecha','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select concat_ws(' ',apellido,nombre,nullif(segundo_nombre,'')) into name from marathon.pacientes where dni=p_dni;if name is null then raise sqlstate 'PT404' using message='Paciente no encontrado.';end if;
 select coalesce(sum(greatest(0,marathon.saldo_cargo_sesion(t.id)-marathon.turn_paid(t.id))),0) into total from marathon.turnos t where t.dni=p_dni and t.estado='PRESENTE';
 select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into rows from(
 select t.id,t.fecha,to_char(t.hora,'HH24:MI') hora,t.sede,t.estado,t.version,t.importe,th.nombre terapia,marathon.turn_paid(t.id) paid,greatest(0,marathon.saldo_cargo_sesion(t.id)-marathon.turn_paid(t.id)) debt from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.dni=p_dni and t.estado='PRESENTE' and marathon.saldo_cargo_sesion(t.id)>marathon.turn_paid(t.id) and(p_after is null or(t.fecha,t.id)>(marathon.agenda_date(p_after->>'fecha'),p_after->>'id')) order by t.fecha,t.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'debt',total,'name',name);
end $function$
;
CREATE OR REPLACE FUNCTION public.marathon_turn_account(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  'advance_paid',marathon.advance_paid(t.id),'debt',case when t.estado='PRESENTE' then greatest(0,marathon.saldo_cargo_sesion(t.id)-paid) else 0 end,'charge_cancellations',history);
end $function$
;
CREATE OR REPLACE FUNCTION public.marathon_patient_history(p_dni text, p_kind text DEFAULT 'clinic'::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare rows jsonb;nxt jsonb;summary jsonb;after_date date;after_time time;first_day date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_dni is null or p_dni!~'^[0-9]{1,12}$' or p_kind is null or p_kind not in ('clinic','ortho','bonus','advance') or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de historial inválida.';end if;
 if not exists(select 1 from marathon.pacientes where dni=p_dni) then raise sqlstate 'P0002' using message='Paciente no encontrado.';end if;
 if p_after is not null then
  if jsonb_typeof(p_after)<>'object' then raise sqlstate '22023' using message='Cursor inválido.';end if;
  if not(p_after?&array['fecha','hora','id']) or exists(select 1 from jsonb_each(p_after)e where jsonb_typeof(e.value)<>'string') or exists(select 1 from jsonb_object_keys(p_after)k where k<>all(array['fecha','hora','id'])) or length(p_after->>'id')>100 or p_after->>'fecha'!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p_after->>'hora')>16 then raise sqlstate '22023' using message='Cursor inválido.';end if;
  begin after_date=(p_after->>'fecha')::date;after_time=(p_after->>'hora')::time;
  exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023' using message='Cursor inválido.';end;
 end if;
 select jsonb_build_object('clinical_debt',c.debt,'ortho_debt',o.debt,'bonus_debt',b.debt,'debt',c.debt+o.debt+b.debt,'present',c.present,'upcoming',c.upcoming,'clinic_total',c.total,'ortho_total',o.total,'rental_units',o.units,'advance_available',(select coalesce(sum(available),0)from marathon.daily_advance where dni=p_dni)) into summary from(
  select coalesce(sum(case when t.estado='PRESENTE' then greatest(0,marathon.saldo_cargo_sesion(t.id)-pay.paid) else 0 end),0) debt,count(*) filter(where t.estado='PRESENTE') present,count(*) filter(where t.estado='PENDIENTE' and t.fecha>=first_day) upcoming,count(*) total
  from marathon.turnos t cross join lateral(select marathon.turn_paid(t.id) paid)pay where t.dni=p_dni
 )c cross join(
  select coalesce(sum(case when o.tipo in ('VENTA','ALQUILER') then greatest(0,o.importe_total-pay.paid) else 0 end),0) debt,coalesce(sum(case when o.tipo='ALQUILER' then greatest(0,o.cantidad-ret.qty) else 0 end),0) units,count(*) total
  from marathon.ortopedia_operaciones o cross join lateral(select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) paid from marathon.movimientos m where m.operacion_id=o.id and m.origen='ORTOPEDIA')pay
  cross join lateral(select coalesce(sum(d.cantidad),0) qty from marathon.ortopedia_operaciones d where d.original_id=o.id and d.tipo='DEVOLUCION')ret where o.dni=p_dni
 )o cross join(select coalesce(sum(debt),0) debt from marathon.daily_bonus where dni=p_dni)b;
 if exists(select 1 from marathon.saldo_config where activo)then
   summary=summary||jsonb_build_object('saldo_disponible',marathon.saldo_disponible(p_dni),'advance_available',marathon.saldo_disponible(p_dni),
   'clinical_debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)where tipo<>'bono'),0),
   'debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)),0)+(summary->>'ortho_debt')::numeric);
  end if;
 if p_kind='clinic' then
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select t.id,t.fecha,t.hora,t.sede,t.estado,t.importe,t.coverage,t.observaciones,t.version,t.attendance_auto,t.attendance_auto_at,th.nombre terapia,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido) profesional,pay.paid,case when t.estado='PRESENTE' then greatest(0,marathon.saldo_cargo_sesion(t.id)-pay.paid) else 0 end debt
   from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales p on p.id=t.profesional_id
   cross join lateral(select marathon.turn_paid(t.id) paid)pay
   where t.dni=p_dni and(p_after is null or(t.fecha,t.hora,t.id)<(after_date,after_time,p_after->>'id')) order by t.fecha desc,t.hora desc,t.id desc limit p_limit+1
  )x;
 elsif p_kind='ortho' then
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select o.id,o.fecha,o.hora,o.sede,o.tipo,o.cantidad,o.devolucion_prevista,o.importe_total,o.subtotal,o.discount_rate,o.discount_amount,o.observaciones,coalesce(nullif(o.producto_snapshot->>'descripcion',''),nullif(o.producto_snapshot->>'description',''),p.descripcion,o.producto_id) producto,pay.paid,case when o.tipo in ('VENTA','ALQUILER') then greatest(0,o.importe_total-pay.paid) else 0 end debt,case when o.tipo='ALQUILER' then greatest(0,o.cantidad-ret.qty) else 0 end pending
   from marathon.ortopedia_operaciones o left join marathon.productos p on p.id=o.producto_id
   cross join lateral(select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) paid from marathon.movimientos m where m.operacion_id=o.id and m.origen='ORTOPEDIA')pay
   cross join lateral(select coalesce(sum(d.cantidad),0) qty from marathon.ortopedia_operaciones d where d.original_id=o.id and d.tipo='DEVOLUCION')ret
   where o.dni=p_dni and(p_after is null or(o.fecha,o.hora,o.id)<(after_date,after_time,p_after->>'id')) order by o.fecha desc,o.hora desc,o.id desc limit p_limit+1
  )x;
 elsif p_kind='advance'then
 select coalesce(jsonb_agg(to_jsonb(x)order by fecha desc,hora desc,id desc),'[]'::jsonb)into rows from(
 select a.* from marathon.daily_advance a where dni=p_dni and(p_after is null or(a.fecha,a.hora,a.id)<(after_date,after_time,p_after->>'id'))order by fecha desc,hora desc,id desc limit p_limit+1)x;
 else
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select b.* from marathon.daily_bonus b where b.dni=p_dni and(p_after is null or(b.fecha,b.hora,b.id)<(after_date,after_time,p_after->>'id')) order by b.fecha desc,b.hora desc,b.id desc limit p_limit+1
  )x;
 end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary);
end $function$
;
CREATE OR REPLACE FUNCTION public.marathon_agenda_plan(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;if not exists(select 1 from marathon.saldo_config where activo)then perform marathon.agenda_cuotas_generar();end if;return marathon.agenda_plan_info(p_id);end$function$
;
CREATE OR REPLACE FUNCTION public.marathon_agenda_grilla(p_from text, p_sede text, p_prof text, p_therapy text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare d date;e date;rows jsonb;plans jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_from);e=d+6;
 if not exists(select 1 from marathon.horarios where sede=p_sede and profesional_id=p_prof)then return jsonb_build_object('slots','[]'::jsonb,'plans','[]'::jsonb);end if;
 if not exists(select 1 from marathon.saldo_config where activo)then perform marathon.agenda_cuotas_generar();end if;
 select coalesce(jsonb_agg(jsonb_build_object('fecha',dt::date,'hora',to_char(h.inicio+make_interval(mins=>g.m),'HH24:MI'),'therapy',t.id,'meta',marathon.agenda_cupo(dt::date,p_sede,p_prof,t.id,h.inicio+make_interval(mins=>g.m)),
 'patients',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'plan_id',a.plan_id,'dni',a.dni,'paciente',concat_ws(' ',p.apellido,p.nombre,p.segundo_nombre),'telefono',p.telefono,'hora',to_char(a.hora,'HH24:MI'),'end_hour',to_char(a.hora+make_interval(mins=>a.duracion_min),'HH24:MI'),'estado',a.estado,'paused',a.pausado,'therapy',a.terapia_id,'plan',marathon.agenda_plan_info(a.plan_id)) order by p.apellido,p.nombre)from marathon.agenda_pool(dt::date)a join marathon.pacientes p on p.dni=a.dni where a.sede=p_sede and a.profesional_id=p_prof and a.hora=h.inicio+make_interval(mins=>g.m) and(p_therapy=''or a.terapia_id=p_therapy)),'[]'::jsonb))order by dt,g.m),'[]'::jsonb)into rows
 from generate_series(d,e,interval '1 day')dt join marathon.horarios h on h.dia=extract(dow from dt)::int and h.profesional_id=p_prof and h.sede=p_sede
 join lateral(select x.id from marathon.terapias x join marathon.profesional_terapias pt on pt.terapia_id=x.id and pt.profesional_id=p_prof where x.estado='ACTIVO' and(p_therapy=''or x.id=p_therapy) order by x.capacidad desc,x.id limit 1)t on true
 cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(p_prof))g(m);
 select coalesce(jsonb_agg(marathon.agenda_plan_info(p.id)||jsonb_build_object('paciente',concat_ws(' ',x.apellido,x.nombre,x.segundo_nombre),'telefono',x.telefono)order by x.apellido,x.nombre),'[]'::jsonb) into plans from marathon.agenda_planes p join marathon.pacientes x on x.dni=p.dni where exists(select 1 from marathon.agenda_horarios h where h.plan_id=p.id and h.sede=p_sede and h.profesional_id=p_prof)and(p_therapy=''or p.terapia_id=p_therapy);
 return jsonb_build_object('slots',rows,'plans',plans);
end$function$
;
CREATE OR REPLACE FUNCTION public.marathon_agenda_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare r jsonb;plans jsonb;debt numeric;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then perform marathon.agenda_cuotas_generar();end if;r=public.marathon_patient_account(p_dni,p_after,p_limit);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'terapia',t.nombre,'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id=p.id),0))order by p.inicio),'[]'::jsonb)into plans from marathon.agenda_planes p join marathon.terapias t on t.id=p.terapia_id where p.dni=p_dni and p.facturacion='monthly';
 select coalesce(sum((x->>'debt')::numeric),0)into debt from jsonb_array_elements(plans)x;
 return r||jsonb_build_object('plans',plans,'debt',coalesce((r->>'debt')::numeric,0)+debt);
end$function$
;
create or replace view marathon.daily_cash as  SELECT m.id,
    m.fecha,
    m.hora,
    m.origen,
    m.tipo,
    m.dni,
    m.monto,
    m.medio,
    m.sede,
    m.secretaria_legacy,
    m.turno_id,
    m.operacion_id,
    m.concepto,
    m.observaciones_legacy,
    m.compensacion_de,
    m.motivo,
    m.created_at,
    m.updated_at,
    m.created_by,
    m.updated_by,
    m.version,
    m.categoria,
    m.profesional_asociado_id,
    m.secretaria_asociada,
    concat_ws(' '::text, p.apellido, p.nombre, NULLIF(p.segundo_nombre, ''::text)) AS paciente,
    COALESCE(u.display_name, m.secretaria_legacy, 'Sin registro'::text) AS actor,
    COALESCE(m.created_by::text, 'legacy:'::text || m.secretaria_legacy, 'unknown'::text) AS actor_key,
        CASE
            WHEN COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id, m.terapia_asociada_id) IS NOT NULL THEN 'T:'::text || COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id, m.terapia_asociada_id)
            ELSE 'C:'::text || COALESCE(m.categoria,
            CASE
                WHEN m.origen = 'ORTOPEDIA'::text THEN 'Ortopedia'::text
                ELSE 'Otros'::text
            END)
        END AS category_key,
    COALESCE(th.nombre, m.categoria,
        CASE
            WHEN m.origen = 'ORTOPEDIA'::text THEN 'Ortopedia'::text
            ELSE 'Otros'::text
        END) AS category_label,
    COALESCE(t.profesional_id, b.profesional_id, a.profesional_id, m.profesional_asociado_id) AS professional_key,
    NULLIF(concat_ws(' '::text, pr.nombre, pr.apellido), ''::text) AS profesional,
    COALESCE(NULLIF(concat_ws(' '::text, pr.nombre, pr.apellido), ''::text), m.secretaria_asociada, ''::text) AS associated,
    (EXISTS ( SELECT 1
           FROM marathon.movimientos r
          WHERE r.compensacion_de = m.id)) AS reversed
   FROM marathon.movimientos m
     LEFT JOIN marathon.agenda_cuotas aq ON aq.id = m.cuota_id
     LEFT JOIN marathon.agenda_planes ap ON ap.id = aq.plan_id
     LEFT JOIN marathon.turnos t ON t.id = m.turno_id
     LEFT JOIN marathon.bonos_serie b ON b.id = m.bono_id
     LEFT JOIN marathon.anticipos a ON a.id = m.anticipo_id
     LEFT JOIN marathon.terapias th ON th.id = COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id, m.terapia_asociada_id)
     LEFT JOIN marathon.profesionales pr ON pr.id = COALESCE(t.profesional_id, b.profesional_id, a.profesional_id, m.profesional_asociado_id)
     LEFT JOIN marathon.pacientes p ON p.dni = m.dni
     LEFT JOIN marathon.app_users u ON u.user_id = m.created_by;
create or replace view marathon.daily_turns as  SELECT t.id,
    t.original_id,
    t.fecha,
    t.sede,
    t.hora,
    t.duracion_min,
    t.terapia_id,
    t.profesional_id,
    t.dni,
    t.importe,
    t.estado,
    t.observaciones,
    t.created_at,
    t.updated_at,
    t.created_by,
    t.updated_by,
    t.version,
    th.nombre AS terapia,
    concat_ws(' '::text, pr.nombre, NULLIF(pr.segundo_nombre, ''::text), pr.apellido) AS profesional,
    concat_ws(' '::text, p.apellido, p.nombre, NULLIF(p.segundo_nombre, ''::text)) AS paciente,
    marathon.turn_paid(t.id) AS paid,
        CASE
            WHEN t.estado = 'PRESENTE'::text THEN GREATEST(0::numeric, marathon.saldo_cargo_sesion(t.id) - marathon.turn_paid(t.id))
            ELSE 0::numeric
        END AS debt
   FROM marathon.turnos t
     JOIN marathon.terapias th ON th.id = t.terapia_id
     JOIN marathon.profesionales pr ON pr.id = t.profesional_id
     JOIN marathon.pacientes p ON p.dni = t.dni;
create or replace function public.marathon_saldo_command(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$
declare previous jsonb;proposal jsonb;kind text:=p_data->>'subtipo';person text:=nullif(p_data->>'dni','');amount numeric;mid text;source uuid;f record;a record;available numeric;piece numeric;remaining numeric;turno marathon.turnos%rowtype;reply jsonb;begin
 previous=marathon.operation_begin(p_request_id,'saldo:'||coalesce(kind,''),p_data);if previous is not null then return previous;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['dni','subtipo','monto','medio','sede','fecha','observaciones','categoria','profesional','terapia','secretaria','turno_id','huella','version']))then raise exception 'La solicitud contiene campos no admitidos.'using errcode='22023';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'El nuevo circuito de saldo todavía no está habilitado.'using errcode='55000';end if;
 if person is not null and p_data->>'version'is distinct from marathon.saldo_version(person)::text then raise exception 'La cuenta cambió. Revisá la nueva vista previa antes de confirmar.'using errcode='PT409';end if;
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
 -- El pase automático de pendiente a ausente sin pagos no tiene efecto financiero.
 if release_payment and not exists(select 1 from marathon.saldo_aplicaciones a where a.dni=person and marathon.saldo_aplicado(a.id)>0 and((tg_table_name='turnos'and a.turno_id=new.id::text)or(tg_table_name='bonos_serie'and a.bono_id=new.id::text)))then return new;end if;
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



create function public.marathon_saldo_preparar()returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$declare n int;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'Circuito de saldo no habilitado.'using errcode='55000';end if;
 n=marathon.agenda_cuotas_generar();return jsonb_build_object('cuotas_generadas',n);
end$$;
revoke all on function public.marathon_saldo_preparar()from public,anon;
grant execute on function public.marathon_saldo_preparar()to authenticated;
commit;
