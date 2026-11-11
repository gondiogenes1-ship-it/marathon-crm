--
-- PostgreSQL database dump
--

\restrict F9TtlFLhugykBDIvL3TnVwpChZBGpyQFXGOQfJEfDTqdbg9hYPf6dXCINAecte8

-- Dumped from database version 17.11
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: active_user(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.active_user() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select exists(select 1 from marathon.app_users where user_id=(select auth.uid()) and active) $$;


--
-- Name: advance_apply(text, text, boolean); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.advance_apply(p_request text, p_turn text, p_release boolean DEFAULT false) RETURNS numeric
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
#variable_conflict use_variable
declare t marathon.turnos%rowtype;a record;need numeric;amount numeric;total numeric:=0;
begin
 select * into t from marathon.turnos where id=p_turn for update;
 if not found then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
 if p_release then
  for a in select anticipo_id,sum(case when tipo='APLICACION'then monto else -monto end) available from marathon.anticipo_eventos where turno_id=t.id group by anticipo_id having sum(case when tipo='APLICACION'then monto else -monto end)>0 order by anticipo_id loop
   insert into marathon.anticipo_eventos(anticipo_id,turno_id,tipo,monto,request_id,actor)values(a.anticipo_id,t.id,'REVERSO',a.available,p_request,auth.uid());
   update marathon.anticipos set observaciones=observaciones where id=a.anticipo_id;total=total+a.available;
  end loop;
 else
  if t.estado<>'PRESENTE' then return 0;end if;
  need=greatest(0,t.importe-marathon.turn_paid(t.id));
  for a in select * from marathon.daily_advance where dni=t.dni and sede=t.sede and(terapia_id is null or terapia_id=t.terapia_id)and(profesional_id is null or profesional_id=t.profesional_id)and available>0 order by fecha,hora,id loop
   exit when need<=0;amount=least(need,a.available);
   insert into marathon.anticipo_eventos(anticipo_id,turno_id,tipo,monto,request_id,actor)values(a.id,t.id,'APLICACION',amount,p_request,auth.uid());
   update marathon.anticipos set observaciones=observaciones where id=a.id;total=total+amount;need=need-amount;
  end loop;
 end if;
 if total>0 then update marathon.turnos set observaciones=observaciones where id=t.id;end if;
 return total;
end $$;


--
-- Name: advance_change(text, text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.advance_change(p_request text, p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
#variable_conflict use_variable
declare a marathon.anticipos%rowtype;aid text;mid text;dni text;site text;therapy text;prof text;obs text;medium text;amount numeric;available numeric;applied numeric:=0;t record;d date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;h time:=(now() at time zone 'America/Argentina/Buenos_Aires')::time;
begin
 obs=marathon.master_text(p_data,'observaciones',1000);
 if p_action in('advance_deposit','advance_apply')then
  dni=marathon.master_text(p_data,'dni',12,true);
  if dni !~ '^[0-9]{1,12}$' or not exists(select 1 from marathon.pacientes p where p.dni=dni)then raise sqlstate '22023' using message='Seleccioná un paciente registrado.';end if;
 end if;
 if p_action='advance_deposit'then
  site=marathon.master_text(p_data,'sede',40,true);therapy=nullif(marathon.master_text(p_data,'therapy',100),'');prof=nullif(marathon.master_text(p_data,'prof',100),'');
  if not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')or(therapy is not null and not exists(select 1 from marathon.terapias where id=therapy and estado='ACTIVO'))or(prof is not null and not exists(select 1 from marathon.profesionales where id=prof and estado='ACTIVO'))or(prof is not null and therapy is not null and not exists(select 1 from marathon.profesional_terapias where profesional_id=prof and terapia_id=therapy))then raise sqlstate '22023' using message='Elegí sede, terapia y profesional compatibles y activos.';end if;
  if p_data?'apply_existing' and jsonb_typeof(p_data->'apply_existing') is distinct from 'boolean'then raise sqlstate '22023' using message='Opción de aplicación inválida.';end if;
  amount=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);
  if medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  aid='ANT-'||gen_random_uuid()::text;mid='MOV-'||gen_random_uuid()::text;
  insert into marathon.anticipos(id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,observaciones,created_by,updated_by)values(aid,dni,site,therapy,prof,amount,d,h,obs,auth.uid(),auth.uid());
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,anticipo_id,concepto,categoria,observaciones_legacy,created_by,updated_by)values(mid,d,h,'ANTICIPO','INGRESO',dni,amount,medium,site,aid,'Anticipo clínico','Anticipos',obs,auth.uid(),auth.uid());
  insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,movimiento_id,request_id,actor)values(aid,'DEPOSITO',amount,mid,p_request,auth.uid());
 elsif p_action='advance_refund'then
  select * into a from marathon.anticipos where id=marathon.master_text(p_data,'id',100,true) for update;
  if not found then raise sqlstate 'PT404' using message='Anticipo no encontrado.';end if;
  if a.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='El anticipo cambió. Volvé a abrirlo.';end if;
  if length(btrim(obs))<3 then raise sqlstate '22023' using message='Indicá el motivo del reintegro (mínimo 3 caracteres).';end if;
  select x.available into available from marathon.daily_advance x where x.id=a.id;
  amount=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);
  if amount>available then raise sqlstate '22023' using message='Solo podés reintegrar el saldo del anticipo que todavía no se aplicó.';end if;
  if medium not in('EFECTIVO','TRANSFERENCIA')then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  aid=a.id;mid='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,anticipo_id,concepto,categoria,observaciones_legacy,motivo,created_by,updated_by)values(mid,d,h,'ANTICIPO','EGRESO',a.dni,amount,medium,a.sede,aid,'Reintegro de anticipo','Anticipos',obs,obs,auth.uid(),auth.uid());
  insert into marathon.anticipo_eventos(anticipo_id,tipo,monto,movimiento_id,request_id,actor)values(aid,'DEVOLUCION',amount,mid,p_request,auth.uid());
  update marathon.anticipos set observaciones=observaciones where id=aid;
 end if;
 if p_action='advance_apply' or(p_action='advance_deposit'and coalesce((p_data->>'apply_existing')::boolean,false))then
  for t in select id from marathon.turnos where turnos.dni=dni and estado='PRESENTE' and importe>marathon.turn_paid(id) order by fecha,hora,id loop
   applied=applied+marathon.advance_apply(p_request,t.id);
  end loop;
 end if;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request,auth.uid(),'advance',coalesce(aid,dni),p_action,jsonb_build_object('id',aid,'applied',applied,'movement',mid));
 return jsonb_build_object('id',aid,'applied',applied,'message',case p_action when 'advance_deposit'then 'Anticipo recibido. Ingreso registrado en Caja.'when 'advance_refund'then 'Saldo disponible reintegrado. Egreso registrado en Caja.'else 'Anticipos aplicados a las sesiones presentes compatibles con deuda.'end);
end $_$;


--
-- Name: advance_paid(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.advance_paid(p_id text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select coalesce(sum(case when tipo='APLICACION'then monto when tipo='REVERSO'then -monto else 0 end),0) from marathon.anticipo_eventos where turno_id=p_id
$$;


--
-- Name: agenda_completar(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_completar() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
 if new.plan_id is not null and pg_trigger_depth()=1 then
  update marathon.agenda_planes set updated_at=now() where id=new.plan_id;
  if exists(select 1 from marathon.agenda_planes p where p.id=new.plan_id and p.modalidad='sessions' and marathon.agenda_presentes(p.id)>=marathon.agenda_total(p.id))then
   update marathon.turnos set estado='CANCELADO',agenda_motivo='SESIONES_COMPLETAS' where plan_id=new.plan_id and id<>new.id and estado='PENDIENTE' and fecha>=new.fecha;
  end if;
 end if;return new;
end$$;


--
-- Name: agenda_cuota_pagado(uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_cuota_pagado(q uuid) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select coalesce(sum(case when m.tipo in('PAGO','INGRESO') then m.monto else -m.monto end),0)
 from marathon.movimientos m left join marathon.movimientos original on original.id=m.compensacion_de
 where m.cuota_id=q or original.cuota_id=q
$$;


--
-- Name: agenda_cuota_saldo(uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_cuota_saldo(q uuid) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select greatest(0,c.importe-marathon.agenda_cuota_pagado(c.id)-coalesce((select sum(a.importe) from marathon.agenda_ajustes a where a.cuota_id=c.id),0)) from marathon.agenda_cuotas c where c.id=q
$$;


--
-- Name: agenda_hoy(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_hoy() RETURNS date
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$select (now() at time zone 'America/Argentina/Buenos_Aires')::date$$;


--
-- Name: agenda_cuotas_generar(date); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_cuotas_generar(p_hoy date DEFAULT marathon.agenda_hoy()) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare n int;begin
 if p_hoy>marathon.agenda_hoy() then raise sqlstate '22023' using message='No se generan cuotas anticipadas.';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 insert into marathon.agenda_cuotas(plan_id,periodo_id,fecha,hasta,importe,sede)
 select p.id,s.id,(s.inicio+make_interval(months=>g.n))::date,(s.inicio+make_interval(months=>g.n+1))::date,p.importe,h.sede
 from marathon.agenda_periodos s join marathon.agenda_planes p on p.id=s.plan_id
 cross join lateral(select x.sede from marathon.agenda_horarios x where x.plan_id=p.id order by x.dia,x.hora limit 1)h
 cross join lateral generate_series(0,greatest(0,(extract(year from p_hoy)::int-extract(year from s.inicio)::int)*12+extract(month from p_hoy)::int-extract(month from s.inicio)::int))g(n)
 where p.facturacion='monthly' and not s.anulado and s.inicio<=p_hoy
 and (s.inicio+make_interval(months=>g.n))::date<=p_hoy
 and(s.fin is null or (s.inicio+make_interval(months=>g.n))::date<s.fin)
 and(p.baja is null or (s.inicio+make_interval(months=>g.n))::date<p.baja)
 on conflict(periodo_id,fecha) do nothing;
 get diagnostics n=row_count;return n;
end$$;


--
-- Name: agenda_cupo(date, text, text, text, time without time zone, uuid, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, exclude_plan uuid DEFAULT NULL::uuid, exclude_turn text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
#variable_conflict use_variable
declare cap int;shared_cap int;dur int;spec text;left_over int;no boolean;people int;own int;begin
 select t.capacidad,t.duracion_min,marathon.master_norm(t.especialidad) into cap,dur,spec from marathon.terapias t
 join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
 join marathon.profesionales p on p.id=prof and p.estado='ACTIVO'
 join marathon.sedes s on s.nombre=site and s.estado='ACTIVO' where t.id=therapy and t.estado='ACTIVO';
 if cap is null or not exists(select 1 from marathon.horarios h where h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int and at_hour>=h.inicio and at_hour+interval '15 minutes'<=h.fin and (extract(epoch from(at_hour-h.inicio))/60)::int%marathon.professional_step(prof)=0)then return jsonb_build_object('remaining',0,'capacity',coalesce(cap,0),'blocked',true);end if;
 dur=marathon.session_minutes(d,site,prof,at_hour,dur);
 select greatest(cap,coalesce(max(t.capacidad),cap)) into shared_cap from marathon.terapias t join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof where t.estado='ACTIVO' and spec<>'' and marathon.master_norm(t.especialidad)=spec;
 with pool as materialized(select a.*,marathon.master_norm(t.especialidad) spec from marathon.agenda_pool(d)a join marathon.terapias t on t.id=a.terapia_id where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select exists(select 1 from pool a where a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min) and(a.sede<>site or not(a.terapia_id=therapy or(spec<>'' and a.spec=spec)))),
 coalesce(min(least(cap-(select count(*)::int from pool a where a.terapia_id=therapy and a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min)),shared_cap-(select count(*)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min)))),cap)
 into no,left_over from (select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 select count(*)::int into own from marathon.agenda_pool(d)a where a.profesional_id=prof and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn) and a.hora<at_hour+make_interval(mins=>dur) and at_hour<a.hora+make_interval(mins=>a.duracion_min);
 with pool as materialized(select a.* from marathon.agenda_pool(d)a join marathon.shared_space_therapies g on g.therapy_id=a.terapia_id where a.sede=site and a.estado in('PENDIENTE','PRESENTE') and not a.pausado and (exclude_plan is null or a.plan_id is distinct from exclude_plan) and(exclude_turn is null or a.id<>exclude_turn))
 select coalesce(max((select count(distinct a.dni)::int from pool a where a.hora<=cut.at and cut.at<a.hora+make_interval(mins=>a.duracion_min))),0) into people from(select at_hour at union select a.hora from pool a where a.hora>at_hour and a.hora<at_hour+make_interval(mins=>dur))cut;
 return jsonb_build_object('hora',to_char(at_hour,'HH24:MI'),'remaining',case when no then 0 else greatest(0,left_over) end,'capacity',cap,'shared_capacity',shared_cap,'blocked',no,'professional_count',own,'shared_space_count',people,'duration_min',dur,'end_hour',to_char(at_hour+make_interval(mins=>dur),'HH24:MI'));
end$$;


--
-- Name: agenda_date(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_date(value text) RETURNS date
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare d date;begin
 if value is null or value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise sqlstate '22023' using message='Fecha inválida.';end if;
 begin d=value::date;exception when datetime_field_overflow or invalid_datetime_format then raise sqlstate '22023' using message='Fecha inválida.';end;
 if d not between date '2000-01-01' and date '2100-12-31' then raise sqlstate '22023' using message='La fecha debe estar entre 2000 y 2100.';end if;return d;
end $_$;


--
-- Name: agenda_materializar(date, date); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_materializar(d date, e date) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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
 perform marathon.agenda_cuotas_generar();return n;
end$$;


--
-- Name: agenda_movimiento_guard(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_movimiento_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare q marathon.agenda_cuotas%rowtype;begin
 if new.cuota_id is null and new.compensacion_de is not null then select cuota_id into new.cuota_id from marathon.movimientos where id=new.compensacion_de;end if;
 if new.cuota_id is null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 select * into strict q from marathon.agenda_cuotas where id=new.cuota_id for update;
 if new.tipo='INGRESO'and new.monto>marathon.agenda_cuota_saldo(q.id)or new.tipo='EGRESO'and new.monto>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El movimiento supera el saldo de la cuota. Revisá los pagos y reintegros previos.';end if;
 update marathon.agenda_planes set updated_at=now()where id=q.plan_id;return new;
end$$;


--
-- Name: agenda_pausado(uuid, date); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_pausado(p uuid, d date) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select exists(select 1 from marathon.agenda_pausas x where x.plan_id=p and x.desde<=d and(x.hasta is null or d<x.hasta))
$$;


--
-- Name: agenda_plan_info(uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_plan_info(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare p marathon.agenda_planes%rowtype;r jsonb;streak int:=0;s text;begin
 select * into p from marathon.agenda_planes where id=p_id;if not found then return null;end if;
 for s in select t.estado from marathon.turnos t where t.plan_id=p.id and t.fecha<=marathon.agenda_hoy() and t.estado in('PRESENTE','AUSENTE') and not marathon.agenda_pausado(p.id,t.fecha) order by t.fecha desc,t.hora desc,t.id desc loop
  exit when s='PRESENTE';streak=streak+1;
 end loop;
 r=to_jsonb(p)||jsonb_build_object('total',marathon.agenda_total(p.id),'done',marathon.agenda_presentes(p.id),'absences',streak,
 'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id)) from marathon.agenda_cuotas q where q.plan_id=p.id),0),
 'renewed_today',exists(select 1 from marathon.agenda_periodos ps where ps.plan_id=p.id and not ps.anulado and ps.inicio<=marathon.agenda_hoy()and(ps.fin is null or marathon.agenda_hoy()<ps.fin)and(ps.inicio+make_interval(months=>(extract(year from marathon.agenda_hoy())::int-extract(year from ps.inicio)::int)*12+extract(month from marathon.agenda_hoy())::int-extract(month from ps.inicio)::int))::date=marathon.agenda_hoy()),
 'next_due',(select min((s.inicio+make_interval(months=>g.n))::date)from marathon.agenda_periodos s cross join lateral generate_series(greatest(0,(extract(year from marathon.agenda_hoy())::int-extract(year from s.inicio)::int)*12+extract(month from marathon.agenda_hoy())::int-extract(month from s.inicio)::int),greatest(0,(extract(year from marathon.agenda_hoy())::int-extract(year from s.inicio)::int)*12+extract(month from marathon.agenda_hoy())::int-extract(month from s.inicio)::int)+1)g(n)where s.plan_id=p.id and not s.anulado and (s.inicio+make_interval(months=>g.n))::date>marathon.agenda_hoy()and(s.fin is null or(s.inicio+make_interval(months=>g.n))::date<s.fin)and(p.baja is null or(s.inicio+make_interval(months=>g.n))::date<p.baja)),
 'paused',marathon.agenda_pausado(p.id,marathon.agenda_hoy()),
 'pauses',coalesce((select jsonb_agg(to_jsonb(x)order by x.desde)from marathon.agenda_pausas x where x.plan_id=p.id),'[]'::jsonb),
 'schedules',coalesce((select jsonb_agg(to_jsonb(x)order by x.dia,x.hora)from marathon.agenda_horarios x where x.plan_id=p.id),'[]'::jsonb),
 'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('done',(select count(*)from marathon.turnos t where t.autorizacion_id=a.id and t.estado='PRESENTE'))order by a.fecha,a.created_at)from marathon.agenda_autorizaciones a where a.plan_id=p.id),'[]'::jsonb),
 'quotas',coalesce((select jsonb_agg(to_jsonb(q)||jsonb_build_object('paid',marathon.agenda_cuota_pagado(q.id),'debt',marathon.agenda_cuota_saldo(q.id))order by q.fecha desc)from marathon.agenda_cuotas q where q.plan_id=p.id),'[]'::jsonb));return r;
end$$;


--
-- Name: agenda_pool(date); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_pool(d date) RETURNS TABLE(id text, plan_id uuid, dni text, sede text, profesional_id text, terapia_id text, hora time without time zone, duracion_min integer, estado text, pausado boolean, fecha date)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select x.id,x.plan_id,x.dni,x.sede,x.profesional_id,x.terapia_id,x.hora,x.duracion_min,x.estado,(x.estado<>'PRESENTE'and marathon.agenda_pausado(x.plan_id,d)),x.fecha
 from marathon.turnos x where x.fecha=d and x.estado<>'CANCELADO'
 union all select v.id,v.plan_id,v.dni,v.sede,v.profesional_id,v.terapia_id,v.hora,v.duracion_min,'PENDIENTE',v.pausado,d from marathon.agenda_virtual(d)v
$$;


--
-- Name: agenda_presentes(uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_presentes(p uuid) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$select count(*)::int from marathon.turnos where plan_id=p and estado='PRESENTE'$$;


--
-- Name: agenda_slots(date, text, text, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_slots(d date, site text, prof text, therapy text) RETURNS TABLE(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 with target as (
  select t.*,marathon.master_norm(t.especialidad) spec from marathon.terapias t
  join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
  join marathon.profesionales p on p.id=pt.profesional_id and p.estado='ACTIVO'
  join marathon.sedes s on s.nombre=site and s.estado='ACTIVO'
  where t.id=therapy and t.estado='ACTIVO'
 ), config as (
  select t.*,greatest(t.capacidad,coalesce((select max(a.capacidad) from marathon.terapias a
   join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=prof
   where a.estado='ACTIVO' and t.spec<>'' and marathon.master_norm(a.especialidad)=t.spec),t.capacidad)) shared
  from target t
 ), candidates as (
  select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(d,site,prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
  join marathon.horarios h on h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int
  cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(prof)) g(n)
 ), active as (
  select x.id,x.sede,x.terapia_id,(extract(epoch from x.hora)/60)::int m,marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min) duracion_min,
   marathon.master_norm(t.especialidad) spec from marathon.agenda_pool(d) x join marathon.terapias t on t.id=x.terapia_id
  where x.profesional_id=prof and x.fecha=d and x.estado<>'CANCELADO'
 )
 select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI'),
  case when b.no then 0 else greatest(0,coalesce(r.left_over,c.capacidad)) end,
  c.capacidad,c.shared,b.no
 from candidates c
 cross join lateral (select exists(select 1 from active a where a.m<c.m+c.actual_duration and c.m<a.m+a.duracion_min
  and (a.sede<>site or not(a.terapia_id=therapy or(c.spec<>'' and a.spec=c.spec)))) no) b
 cross join lateral (
  select min(least(c.capacidad-(select count(*)::int from active a where a.terapia_id=therapy and a.m<=cuts.at and cuts.at<a.m+a.duracion_min),
   c.shared-(select count(*)::int from active a where a.m<=cuts.at and cuts.at<a.m+a.duracion_min))) left_over
  from (select c.m at union select a.m from active a where a.m>c.m and a.m<c.m+c.actual_duration
   union select a.m+a.duracion_min from active a where a.m+a.duracion_min>c.m and a.m+a.duracion_min<c.m+c.actual_duration) cuts
 ) r order by c.m;
$$;


--
-- Name: agenda_slots_excluding(date, text, text, text, text[]); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_slots_excluding(d date, site text, prof text, therapy text, excluded text[]) RETURNS TABLE(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 with target as (
  select t.*,marathon.master_norm(t.especialidad) spec from marathon.terapias t
  join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
  join marathon.profesionales p on p.id=pt.profesional_id and p.estado='ACTIVO'
  join marathon.sedes s on s.nombre=site and s.estado='ACTIVO'
  where t.id=therapy and t.estado='ACTIVO'
 ), config as (
  select t.*,greatest(t.capacidad,coalesce((select max(a.capacidad) from marathon.terapias a
   join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=prof
   where a.estado='ACTIVO' and t.spec<>'' and marathon.master_norm(a.especialidad)=t.spec),t.capacidad)) shared
  from target t
 ), candidates as (
  select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(d,site,prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
  join marathon.horarios h on h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int
  cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(prof)) g(n)
 ), active as (
  select x.id,x.sede,x.terapia_id,(extract(epoch from x.hora)/60)::int m,marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min) duracion_min,
   marathon.master_norm(t.especialidad) spec from marathon.agenda_pool(d) x join marathon.terapias t on t.id=x.terapia_id
  where x.profesional_id=prof and x.fecha=d and x.estado<>'CANCELADO' and not(x.id=any(excluded))
 )
 select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI'),
  case when b.no then 0 else greatest(0,coalesce(r.left_over,c.capacidad)) end,
  c.capacidad,c.shared,b.no
 from candidates c
 cross join lateral (select exists(select 1 from active a where a.m<c.m+c.actual_duration and c.m<a.m+a.duracion_min
  and (a.sede<>site or not(a.terapia_id=therapy or(c.spec<>'' and a.spec=c.spec)))) no) b
 cross join lateral (
  select min(least(c.capacidad-(select count(*)::int from active a where a.terapia_id=therapy and a.m<=cuts.at and cuts.at<a.m+a.duracion_min),
   c.shared-(select count(*)::int from active a where a.m<=cuts.at and cuts.at<a.m+a.duracion_min))) left_over
  from (select c.m at union select a.m from active a where a.m>c.m and a.m<c.m+c.actual_duration
   union select a.m+a.duracion_min from active a where a.m+a.duracion_min>c.m and a.m+a.duracion_min<c.m+c.actual_duration) cuts
 ) r order by c.m;
$$;


--
-- Name: agenda_total(uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_total(p uuid) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$select coalesce(sum(cantidad),0)::int from marathon.agenda_autorizaciones where plan_id=p$$;


--
-- Name: agenda_turno_guard(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_turno_guard() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare p marathon.agenda_planes%rowtype;q jsonb;a uuid;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if tg_op='INSERT' and new.recovered_from is not null and new.plan_id is null then
  select t.plan_id into new.plan_id from marathon.turnos t where t.id=new.recovered_from;
  if new.plan_id is not null then new.fecha_habitual=new.fecha;end if;
 end if;
 if new.plan_id is not null then
  select * into strict p from marathon.agenda_planes where id=new.plan_id for update;
  if new.dni<>p.dni or new.terapia_id<>p.terapia_id then raise sqlstate '22023' using message='El turno no corresponde al tratamiento.';end if;
  if new.estado in('PRESENTE','AUSENTE') and marathon.agenda_pausado(p.id,new.fecha) then raise sqlstate '22023' using message='El tratamiento está pausado; conserva su lugar y no registra faltas.';end if;
  if new.estado='PRESENTE' and p.baja is not null and new.fecha>=p.baja then raise sqlstate '22023' using message='El tratamiento está dado de baja.';end if;
  if new.estado='PENDIENTE'and p.modalidad='sessions'and marathon.agenda_presentes(p.id)-(case when tg_op='UPDATE'and old.estado='PRESENTE'then 1 else 0 end)>=marathon.agenda_total(p.id)then raise sqlstate '22023'using message='Las sesiones están completas. Registrá una nueva cantidad.';end if;
  if new.estado='PRESENTE' and p.modalidad='sessions' then
   select x.id into a from marathon.agenda_autorizaciones x where x.plan_id=p.id and (select count(*) from marathon.turnos t where t.autorizacion_id=x.id and t.estado='PRESENTE' and t.id<>new.id)<x.cantidad order by x.fecha,x.created_at,x.id limit 1;
   if a is null then raise sqlstate '22023' using message='Se completaron las sesiones autorizadas. Registrá una nueva cantidad.';end if;new.autorizacion_id=a;
  elsif new.estado<>'PRESENTE' then new.autorizacion_id=null;end if;
 end if;
 if new.estado<>'CANCELADO' and (tg_op='INSERT' or old.estado='CANCELADO' or (old.fecha,old.hora,old.sede,old.profesional_id,old.terapia_id) is distinct from(new.fecha,new.hora,new.sede,new.profesional_id,new.terapia_id)) then
  if exists(select 1 from marathon.agenda_pool(new.fecha)x where x.dni=new.dni and x.id<>new.id and not(x.plan_id is not distinct from new.plan_id and new.horario_id is not null and x.id='H-'||new.horario_id::text||'-'||new.fecha_habitual::text) and x.hora<new.hora+make_interval(mins=>new.duracion_min) and new.hora<x.hora+make_interval(mins=>x.duracion_min)) then raise sqlstate '22023' using message='El paciente ya tiene atención o un lugar reservado en ese horario.';end if;
  q=marathon.agenda_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.plan_id,new.id);
  if coalesce((q->>'remaining')::int,0)<1 or coalesce((q->>'blocked')::boolean,true) then raise sqlstate '22023' using message='El horario no tiene cupo o dejó de estar habilitado.';end if;
 end if;return new;
end$$;


--
-- Name: agenda_virtual(date); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.agenda_virtual(d date) RETURNS TABLE(id text, plan_id uuid, horario_id uuid, dni text, sede text, profesional_id text, terapia_id text, hora time without time zone, duracion_min integer, pausado boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select 'H-'||h.id::text||'-'||d::text,p.id,h.id,p.dni,h.sede,h.profesional_id,p.terapia_id,h.hora,h.duracion_min,marathon.agenda_pausado(p.id,d)
 from marathon.agenda_horarios h join marathon.agenda_planes p on p.id=h.plan_id
 where h.dia=extract(dow from d)::int and d>=greatest(h.desde,p.inicio) and(h.hasta is null or d<h.hasta) and(p.baja is null or d<p.baja)
 and(p.modalidad<>'sessions' or marathon.agenda_presentes(p.id)<marathon.agenda_total(p.id))
 and not exists(select 1 from marathon.turnos t where t.horario_id=h.id and t.fecha_habitual=d)
$$;


--
-- Name: attendance_rollover(date, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.attendance_rollover(p_day date DEFAULT ((now() AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))::date, p_prof text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare t marathon.turnos%rowtype;n integer:=0;after_row jsonb;cfg marathon.attendance_settings%rowtype;
begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 select * into cfg from marathon.attendance_settings where id=true;
 if not coalesce(cfg.enabled,false)then return 0;end if;
 for t in select x.* from marathon.turnos x where estado='PENDIENTE'and fecha>=cfg.start_date and fecha<p_day and(p_prof is null or profesional_id=p_prof)
 and not marathon.agenda_pausado(x.plan_id,x.fecha) and attendance_manual_date is distinct from fecha
 and marathon.turn_cash_paid(x.id)<=0 and marathon.advance_paid(x.id)<=0
 and not coalesce((select m.parts[1]=x.fecha::text and m.parts[2]='Pendiente' from regexp_matches(coalesce(x.observaciones,''),'\[ESTADO_MANUAL\|([0-9]{4}-[0-9]{2}-[0-9]{2})\|(Pendiente|Presente|Ausente|Cancelado)\]','g')with ordinality as m(parts,n)order by m.n desc limit 1),false)
 and not coalesce((select a.after_data->>'estado'='PENDIENTE'and a.after_data->>'fecha'=x.fecha::text from marathon.turn_audit a where a.turn_id=x.id and a.action='status'order by a.created_at desc,a.id desc limit 1),false)
 order by fecha,hora,id limit 500 for update loop
  update marathon.turnos set estado='AUSENTE',attendance_auto=true,attendance_auto_at=now()where id=t.id;
  select to_jsonb(x)into after_row from marathon.turnos x where id=t.id;
  insert into marathon.attendance_system_audit(turn_id,run_day,before_data,after_data)values(t.id,p_day,to_jsonb(t),after_row);n=n+1;
 end loop;
 return n;
end $$;


--
-- Name: bonus_change(text, text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.bonus_change(request_id text, action text, data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
#variable_conflict use_variable
declare old marathon.bonos_serie%rowtype;paid numeric;amount numeric;medium text;obs text;mov text;after_row jsonb;
begin
 select * into old from marathon.bonos_serie b where b.id=marathon.master_text(data,'id',100,true) for update;
 if old.id is null then raise sqlstate 'PT404' using message='Bono no encontrado.';end if;
 if old.version<>marathon.operation_version(data) then raise sqlstate 'PT409' using message='El bono cambió. Volvé a abrirlo antes de guardar.';end if;
 if old.estado='ANULADO' then raise sqlstate '22023' using message='El bono está anulado.';end if;
 select coalesce(sum(case when m.tipo='EGRESO' then -m.monto else m.monto end),0) into paid from marathon.movimientos m where m.bono_id=old.id and m.origen='BONO';
 if action='bonus_cancel' then
  obs=marathon.master_text(data,'motivo',1000,true);if length(obs)<3 then raise sqlstate '22023' using message='Indicá un motivo de al menos 3 caracteres.';end if;
  if paid<>0 then raise sqlstate '22023' using message='Reintegrá lo cobrado antes de anular el bono.';end if;
  update marathon.bonos_serie b set estado='ANULADO',observaciones=concat_ws(E'\n',b.observaciones,obs) where b.id=old.id;
 elsif action in('bonus_pay','bonus_refund') then
  amount=marathon.operation_amount(data);medium=marathon.master_text(data,'medio',13,true);obs=marathon.master_text(data,'observaciones',1000);
  if medium not in('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
  if action='bonus_pay' and amount>old.importe-paid then raise sqlstate '22023' using message='El cobro supera el saldo del bono.';end if;
  if action='bonus_refund' and amount>paid then raise sqlstate '22023' using message='El reintegro supera lo cobrado del bono.';end if;
  if action='bonus_refund' and length(btrim(coalesce(obs,'')))<3 then raise sqlstate '22023' using message='Indicá el motivo del reintegro.';end if;
  mov='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,bono_id,concepto,observaciones_legacy,categoria,profesional_asociado_id,created_by,updated_by)
  values(mov,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,'BONO',case when action='bonus_pay' then 'INGRESO' else 'EGRESO' end,old.dni,amount,medium,old.sede,old.id,
  case when action='bonus_pay' then 'Cobro de bono inicial' else 'Reintegro de bono inicial' end,obs,'Bono inicial',old.profesional_id,auth.uid(),auth.uid());
  update marathon.bonos_serie b set updated_at=now() where b.id=old.id;
  insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select request_id,auth.uid(),'movement',mov,action,to_jsonb(m) from marathon.movimientos m where m.id=mov;
 else raise sqlstate '22023' using message='Operación de bono inválida.';end if;
 select to_jsonb(b) into after_row from marathon.daily_bonus b where b.id=old.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(request_id,auth.uid(),'bonus',old.id,action,to_jsonb(old),after_row);
 return jsonb_build_object('id',old.id,'message',case action when 'bonus_pay' then 'Cobro del bono registrado. Las sesiones se mantienen separadas.' when 'bonus_refund' then 'Reintegro registrado. El saldo del bono queda pendiente.' else 'Bono anulado. Se conservaron movimientos y sesiones.' end);
end $$;


--
-- Name: bonus_create(text, text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.bonus_create(request_id text, root_id text, data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
#variable_conflict use_variable
declare amount numeric:=0;paid boolean:=false;medium text;root marathon.turnos%rowtype;id text;mov text;reply jsonb;
begin
 if data?'bonus_amount' then
  if jsonb_typeof(data->'bonus_amount') is distinct from 'number' or coalesce(data->>'bonus_amount','') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Importe de bono inválido (hasta dos decimales).';end if;
  amount=(data->>'bonus_amount')::numeric;
 end if;
 if data?'bonus_paid' then if jsonb_typeof(data->'bonus_paid') is distinct from 'boolean' then raise sqlstate '22023' using message='Indicá si el bono se cobra al reservar.';end if;paid=(data->>'bonus_paid')::boolean;end if;
 if paid and amount<=0 then raise sqlstate '22023' using message='Ingresá el importe del bono antes de registrar su pago.';end if;
 if amount=0 then return null;end if;
 if paid then medium=marathon.master_text(data,'bonus_medium',13,true);if medium not in('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago del bono.';end if;end if;
 select * into root from marathon.turnos t where t.id=root_id;
 if root.id is null then raise sqlstate '22023' using message='No se encontró la serie del bono.';end if;
 id='BON-'||gen_random_uuid()::text;
 insert into marathon.bonos_serie(id,serie_id,dni,sede,terapia_id,profesional_id,importe,fecha,hora,primera_fecha,sesiones,observaciones,created_by,updated_by)
 values(id,root_id,root.dni,root.sede,root.terapia_id,root.profesional_id,amount,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,root.fecha,
 (select count(*) from marathon.turnos t where coalesce(t.original_id,t.id)=root_id),'Bono inicial único de la reserva',auth.uid(),auth.uid());
 if paid then
  mov='MOV-'||gen_random_uuid()::text;
  insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,bono_id,concepto,categoria,profesional_asociado_id,created_by,updated_by)
  values(mov,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,'BONO','INGRESO',root.dni,amount,medium,root.sede,id,'Cobro de bono inicial','Bono inicial',root.profesional_id,auth.uid(),auth.uid());
  insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select request_id,auth.uid(),'movement',mov,'bonus_pay',to_jsonb(m) from marathon.movimientos m where m.id=mov;
 end if;
 select to_jsonb(b) into reply from marathon.daily_bonus b where b.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(request_id,auth.uid(),'bonus',id,'create',reply);
 return reply;
end $_$;


--
-- Name: daily_validate(jsonb, text[], integer, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.daily_validate(f jsonb, keys text[], lim integer, cur jsonb) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$begin
 if f is null or jsonb_typeof(f)<>'object' or length(f::text)>4000 or exists(select 1 from jsonb_object_keys(f)k where k<>all(keys))or lim is null or lim not between 1 and 100 or(cur is not null and(jsonb_typeof(cur)<>'object'or length(cur::text)>500))or length(coalesce(f->>'query',''))>100 then raise sqlstate '22023' using message='Filtros o página inválidos.';end if;
end $$;


--
-- Name: document_access(text, boolean); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.document_access(p_path text, p_upload boolean) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
 select marathon.active_user() and exists(select 1 from marathon.documentos where storage_path=p_path and case when p_upload then estado='PENDIENTE' and created_by=(select auth.uid()) and upload_expires>now() else estado in ('LISTO','ELIMINANDO') or (estado='PENDIENTE' and created_by=(select auth.uid()) and upload_expires>now()) end)
$$;


--
-- Name: document_delete_access(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.document_delete_access(p_path text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
 select marathon.active_user() and exists(select 1 from marathon.documentos where storage_path=p_path and estado='ELIMINANDO')
$$;


--
-- Name: fixed_dates(text, text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.fixed_dates(first_value text, until_value text, days_value jsonb) RETURNS date[]
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare first_day date:=marathon.agenda_date(first_value);until_day date:=marathon.agenda_date(until_value);days integer[];dates date[];
begin
 if until_day<first_day or until_day>first_day+366 then raise sqlstate '22023' using message='La revisión debe estar entre la primera fecha y un año después.';end if;
 if jsonb_typeof(days_value) is distinct from 'array' then raise sqlstate '22023' using message='Elegí los días del horario fijo.';end if;
 if jsonb_array_length(days_value) not between 1 and 7 or exists(select 1 from jsonb_array_elements(days_value)x where jsonb_typeof(x)<>'number' or x::text!~'^[0-6]$') then raise sqlstate '22023' using message='Días inválidos.';end if;
 select array_agg(distinct x::int order by x::int) into days from jsonb_array_elements_text(days_value)x;
 if cardinality(days)<>jsonb_array_length(days_value) then raise sqlstate '22023' using message='No repitas días del horario fijo.';end if;
 select array_agg(first_day+n order by n) into dates from generate_series(0,until_day-first_day)n where extract(dow from first_day+n)::int=any(days);
 if coalesce(cardinality(dates),0) not between 1 and 60 then raise sqlstate '22023' using message='El horario fijo debe incluir entre 1 y 60 turnos. Ajustá la fecha de revisión.';end if;
 return dates;
end $_$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ select exists(select 1 from marathon.app_users where user_id=(select auth.uid()) and active and role='ADMIN') $$;


--
-- Name: master_impact(text, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.master_impact(p_entity text, p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare turns jsonb; waits jsonb; token text; begin
 select coalesce(jsonb_agg(to_jsonb(t) order by t.id),'[]'::jsonb) into turns from marathon.turnos t
 where fecha>=(now() at time zone 'America/Argentina/Buenos_Aires')::date and estado='PENDIENTE' and
 ((p_entity='professional' and profesional_id=p_id) or (p_entity='therapy' and terapia_id=p_id) or (p_entity='sede' and sede=p_id));
 select coalesce(jsonb_agg(to_jsonb(e) order by e.id),'[]'::jsonb) into waits from marathon.espera e
 where estado in ('PENDIENTE','CONTACTADO') and
 ((p_entity='professional' and profesional_id=p_id) or (p_entity='therapy' and terapia_id=p_id) or (p_entity='sede' and sede=p_id));
 if jsonb_array_length(turns)+jsonb_array_length(waits)>0 then
  token=encode(sha256(convert_to(jsonb_build_object('entity',p_entity,'id',p_id,'turns',turns,'waits',waits)::text,'UTF8')),'hex');end if;
 return jsonb_build_object('token',token,'turn_count',jsonb_array_length(turns),'wait_count',jsonb_array_length(waits));
end $$;


--
-- Name: master_norm(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.master_norm(value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select regexp_replace(normalize(lower(regexp_replace(btrim(coalesce(value,'')),'\s+',' ','g')),NFD),U&'[\0300-\036f]','','g')
$$;


--
-- Name: master_text(jsonb, text, integer, boolean); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.master_text(data jsonb, key text, maxlen integer, required boolean DEFAULT false) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$ declare result text; begin
 if data ? key and jsonb_typeof(data->key) not in ('string','null') then
  raise sqlstate '22023' using message='Formato de campo inválido: '||key; end if;
 result=regexp_replace(btrim(coalesce(data->>key,'')),'\s+',' ','g');
 if length(result)>maxlen or (required and result='') then
  raise sqlstate '22023' using message='Completá un valor válido para '||key||' (máximo '||maxlen||' caracteres).'; end if;
 return result;
end $$;


--
-- Name: normalize_turn_coverage(text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.normalize_turn_coverage(p_dni text, p_raw jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare p marathon.pacientes%rowtype;os text;label text;affiliate text;kind text;item jsonb;covers jsonb;
begin
 if p_raw is null or jsonb_typeof(p_raw)<>'object' then raise sqlstate '22023' using message='Elegí la modalidad de atención.';end if;
 if octet_length(p_raw::text)>3000 or exists(select 1 from jsonb_object_keys(p_raw) k where k<>all(array['type','obra_social_id','name','affiliate'])) then raise sqlstate '22023' using message='Cobertura de turno inválida.';end if;
 if exists(select 1 from jsonb_each(p_raw) e where jsonb_typeof(e.value)<>'string') then raise sqlstate '22023' using message='Los campos de cobertura deben ser textos.';end if;
 kind=p_raw->>'type';
 if kind is null or kind not in ('PARTICULAR','OBRA_SOCIAL','ART','CLUB') then raise sqlstate '22023' using message='Elegí obra social, Particular, ART o Club.';end if;
 select * into p from marathon.pacientes where dni=p_dni for share;
 if not found then raise sqlstate 'PT404' using message='Paciente no encontrado.';end if;
 if kind='OBRA_SOCIAL' then
  os=btrim(coalesce(p_raw->>'obra_social_id',''));
  covers=coalesce(p.coberturas,case when p.obra_social_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('obra_social_id',p.obra_social_id,'afiliado',coalesce(p.afiliado,''))) end);
  select x into item from jsonb_array_elements(covers) x where x->>'obra_social_id'=os;
  select nombre into label from marathon.obras_sociales where id=os and estado='ACTIVO';
  if item is null or label is null then raise sqlstate '22023' using message='Elegí una obra social activa de la ficha del paciente.';end if;
  return jsonb_build_object('type',kind,'obra_social_id',os,'name',label,'affiliate',coalesce(item->>'afiliado',''));
 end if;
 label=btrim(coalesce(p_raw->>'name',''));affiliate=btrim(coalesce(p_raw->>'affiliate',''));
 if length(label)>120 or length(affiliate)>120 then raise sqlstate '22023' using message='La entidad y la referencia admiten hasta 120 caracteres.';end if;
 return jsonb_build_object('type',kind,'name',case when kind='PARTICULAR' then '' else label end,'affiliate',case when kind='PARTICULAR' then '' else affiliate end);
end $$;


--
-- Name: operation_amount(jsonb, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.operation_amount(data jsonb, key text DEFAULT 'monto'::text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$ begin
 if jsonb_typeof(data->key) is distinct from 'number' or coalesce(data->>key,'') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' or (data->>key)::numeric<=0 then raise sqlstate '22023' using message='Ingresá un importe mayor a cero, con hasta dos decimales.';end if;return (data->>key)::numeric;
end $_$;


--
-- Name: operation_begin(text, text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.operation_begin(p_id text, p_kind text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $_$
declare uid uuid:=auth.uid();h text;r marathon.solicitudes%rowtype;begin
 perform 1 from marathon.app_users where user_id=uid and active for share;
 if not found then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or p_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise sqlstate '22023' using message='Solicitud inválida.';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '22023' using message='La operación requiere transacciones READ COMMITTED.';end if;
 h=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_id,uid,p_kind,h) on conflict on constraint solicitudes_pkey do nothing;
 select * into r from marathon.solicitudes s where s.id=p_id for update;
 if r.id is null or r.usuario_id<>uid or r.tipo<>p_kind or r.payload_hash<>h then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if r.resultado is not null then return r.resultado;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));return null;
end $_$;


--
-- Name: operation_version(jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.operation_version(data jsonb) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$ begin
 if jsonb_typeof(data->'version') is distinct from 'number' or coalesce(data->>'version','') !~ '^[1-9][0-9]{0,17}$' then raise sqlstate '22023' using message='Versión inválida. Actualizá el registro.';end if;return (data->>'version')::bigint;
end $_$;


--
-- Name: ortho_audit(text, text, text, text, jsonb, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_audit(req text, entity text, id text, action text, before_data jsonb, after_data jsonb) RETURNS void
    LANGUAGE sql
    SET search_path TO ''
    AS $$
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(req,auth.uid(),entity,id,action,before_data,after_data)
$$;


--
-- Name: ortho_int(jsonb, text, bigint, bigint); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_int(data jsonb, k text, min_value bigint, max_value bigint) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$ declare n bigint;begin
 if jsonb_typeof(data->k) is distinct from 'number' or coalesce(data->>k,'') !~ '^[0-9]{1,18}$' then raise sqlstate '22023' using message='Cantidad o versión inválida: '||k;end if;n=(data->>k)::bigint;
 if n not between min_value and max_value then raise sqlstate '22023' using message='Cantidad fuera del límite: '||k;end if;return n;
end $_$;


--
-- Name: ortho_paid(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_paid(op text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select coalesce(sum(case when tipo='REINTEGRO' then -monto else monto end),0) from marathon.movimientos where operacion_id=op and origen='ORTOPEDIA'
$$;


--
-- Name: ortho_price(jsonb, text, boolean); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_price(data jsonb, k text, required boolean DEFAULT false) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$ begin
 if data->k is null or data->k='null'::jsonb then if required then raise sqlstate '22023' using message='Falta el precio: '||k;end if;return null;end if;
 if jsonb_typeof(data->k)<>'number' or coalesce(data->>k,'') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Precio inválido: '||k;end if;return(data->>k)::numeric;
end $_$;


--
-- Name: ortho_returned(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_returned(op text) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$select coalesce(sum(cantidad),0)::bigint from marathon.ortopedia_operaciones where original_id=op and tipo='DEVOLUCION'$$;


--
-- Name: ortho_stock(text, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.ortho_stock(product text, site text) RETURNS bigint
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select coalesce(sum(case when tipo in ('STOCK_INICIAL','COMPRA','AJUSTE_POSITIVO','DEVOLUCION') then cantidad else -cantidad end),0)::bigint from marathon.ortopedia_operaciones where producto_id=product and sede=site
$$;


--
-- Name: patient_phone(jsonb, text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.patient_phone(data jsonb, old_phone text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $_$
declare raw text:=btrim(coalesce(data->>'telefono',''));area_raw text:=btrim(coalesce(data->>'telefono_area',''));local_raw text:=btrim(coalesce(data->>'telefono_local',''));area text;local_number text;digits text;positions integer[];pos integer;
begin
 if data?'telefono_area' or data?'telefono_local' then
  if not(data?'telefono_area' and data?'telefono_local') then raise sqlstate '22023' using message='Completá característica y número, o dejá ambos vacíos.';end if;
  if area_raw='' and local_raw='' then return '';end if;
  if area_raw='' and local_raw=btrim(coalesce(old_phone,'')) then return local_raw;end if;
  if area_raw='' or local_raw='' then raise sqlstate '22023' using message='Completá característica y número, o dejá ambos vacíos.';end if;
  if (area_raw||local_raw) ~ '[^0-9[:space:]()+.\-]' then raise sqlstate '22023' using message='El teléfono solo admite números, espacios, paréntesis y guiones.';end if;
  area=regexp_replace(regexp_replace(area_raw,'[^0-9]','','g'),'^0+','');local_number=regexp_replace(local_raw,'[^0-9]','','g');
  if length(local_number)+length(area)=12 and left(local_number,2)='15' then local_number=substr(local_number,3);end if;
  if area !~ '^[1-9][0-9]{1,3}$' or local_number !~ '^[0-9]{6,8}$' or length(area)+length(local_number)<>10 then raise sqlstate '22023' using message='La característica y el número deben sumar 10 dígitos, sin 0 ni 15.';end if;
  return '+54 9 '||area||' '||local_number;
 end if;
 -- Cliente anterior: conservar el mismo texto o normalizar un teléfono nuevo completo.
 if raw='' or raw=btrim(coalesce(old_phone,'')) then return raw;end if;
 if raw ~ '[^0-9[:space:]()+.\-]' then raise sqlstate '22023' using message='Revisá el teléfono: incluí característica de ciudad y número.';end if;
 digits=regexp_replace(regexp_replace(raw,'[^0-9]','','g'),'^00','');
 if length(digits)>=12 and left(digits,2)='54' then digits=regexp_replace(substr(digits,3),'^9','');end if;
 digits=regexp_replace(digits,'^0+','');
 if length(digits)=12 then
  select array_agg(n) into positions from generate_series(2,4)n where substr(digits,n+1,2)='15';
  if coalesce(cardinality(positions),0)<>1 then raise sqlstate '22023' using message='Revisá el teléfono: incluí característica de ciudad y número.';end if;
  pos=positions[1];digits=left(digits,pos)||substr(digits,pos+3);
 end if;
 if digits !~ '^[1-9][0-9]{9}$' then raise sqlstate '22023' using message='Revisá el teléfono: incluí característica de ciudad y número.';end if;
 return '+549'||digits;
end $_$;


--
-- Name: professional_step(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.professional_step(p_prof text) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select min(t.duracion_min) from marathon.terapias t join marathon.profesional_terapias pt on pt.terapia_id=t.id join marathon.profesionales p on p.id=pt.profesional_id and p.estado='ACTIVO' where pt.profesional_id=p_prof and t.estado='ACTIVO'
$$;


--
-- Name: recovery_free(date, text, text, text, time without time zone, integer, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.recovery_free(d date, site text, prof text, therapy text, h time without time zone, duration integer, planned jsonb) RETURNS boolean
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 with config as (select s.*,marathon.master_norm(t.especialidad) spec from marathon.agenda_slots(d,site,prof,therapy)s join marathon.terapias t on t.id=therapy where s.hora=to_char(h,'HH24:MI')),
 active as (
 select x.sede,x.terapia_id,x.hora st,x.hora+marathon.session_minutes(x.fecha,x.sede,x.profesional_id,x.hora,x.duracion_min)*interval '1 minute' en,marathon.master_norm(t.especialidad) spec
 from marathon.turnos x join marathon.terapias t on t.id=x.terapia_id where x.fecha=d and x.profesional_id=prof and x.estado<>'CANCELADO'
 union all
 select p->>'sede',p->>'therapy',(p->>'hora')::time,(p->>'hora')::time+(p->>'duration_min')::int*interval '1 minute',marathon.master_norm(t.especialidad)
 from jsonb_array_elements(planned)p join marathon.terapias t on t.id=p->>'therapy' where p->>'prof'=prof and p->>'fecha'=d::text
 ), cuts as (select h cut_time union select st from active where st>h and st<h+duration*interval '1 minute' union select en from active where en>h and en<h+duration*interval '1 minute')
 select coalesce((select not c.blocked
 and not exists(select 1 from active a where a.st<h+duration*interval '1 minute' and h<a.en and(a.sede<>site or not(a.terapia_id=therapy or(c.spec<>'' and a.spec=c.spec))))
 and not exists(select 1 from cuts z where (select count(*) from active a where a.st<=z.cut_time and z.cut_time<a.en and a.terapia_id=therapy)>=c.capacity or(select count(*)from active a where a.st<=z.cut_time and z.cut_time<a.en)>=c.shared_capacity)
 from config c),false);
$$;


--
-- Name: reservation_notes(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.reservation_notes(value text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
 select coalesce(string_agg(line,E'\n' order by ord),'') from regexp_split_to_table(coalesce(value,''),E'\n') with ordinality l(line,ord)
 where line !~* '^\s*(\[(estado|cobertura|reprogram|recuper|fijo|auditor|sistema|auto|id)[^]]*\]|(estado (actualizado|cambiado)|cobertura (actualizada|modificada)|recuperaci[oó]n (de|creada)|horario fijo|fijo hasta|original_id|request_id|turno_id)\s*[:·-])';
$$;


--
-- Name: session_minutes(date, text, text, time without time zone, integer); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.session_minutes(d date, site text, prof text, start_time time without time zone, requested integer) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select least(requested,coalesce((select (extract(epoch from (max(h.fin)-start_time))/60)::integer
 from marathon.horarios h where h.profesional_id=prof and h.sede=site and h.dia=extract(dow from d)::int and h.inicio<=start_time and start_time<h.fin),requested));
$$;


--
-- Name: shared_space_save(jsonb, bigint); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.shared_space_save(p_therapy_ids jsonb, p_version bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare wanted text[];existing text[];v bigint;
begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede configurar el espacio compartido.';end if;
 if p_therapy_ids is null or jsonb_typeof(p_therapy_ids)<>'array' or jsonb_array_length(p_therapy_ids)>200
  or exists(select 1 from jsonb_array_elements(p_therapy_ids)x where jsonb_typeof(x)<>'string') then
  raise sqlstate '22023' using message='Elegí las terapias que comparten lugar.';
 end if;
 select coalesce(array_agg(distinct x order by x),'{}'::text[]) into wanted from jsonb_array_elements_text(p_therapy_ids)x;
 if exists(select 1 from unnest(wanted)x where not exists(select 1 from marathon.terapias t where t.id=x)) then
  raise sqlstate '22023' using message='La selección incluye una terapia inexistente. Volvé a cargar el catálogo.';
 end if;
 select version into v from marathon.shared_space_config where singleton for update;
 select coalesce(array_agg(therapy_id order by therapy_id),'{}'::text[]) into existing from marathon.shared_space_therapies;
 -- Repetir una petición ya aplicada no vuelve a escribirla.
 if wanted=existing then return public.marathon_shared_space_get();end if;
 if p_version is null or p_version<>v then raise sqlstate '40001' using message='Otra persona cambió la configuración. Volvé a cargarla antes de guardar.';end if;
 delete from marathon.shared_space_therapies;
 insert into marathon.shared_space_therapies(therapy_id) select unnest(wanted);
 update marathon.shared_space_config set version=version+1,updated_at=statement_timestamp(),updated_by=auth.uid() where singleton;
 return public.marathon_shared_space_get();
end $$;


--
-- Name: touch_row(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.touch_row() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$ begin
 new.updated_at=now(); new.updated_by=auth.uid(); new.version=old.version+1; return new;
end $$;


--
-- Name: turn_cash_paid(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.turn_cash_paid(p_id text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select coalesce(sum(case when tipo in ('REINTEGRO','EGRESO') then -monto else monto end),0) from marathon.movimientos where turno_id=p_id
$$;


--
-- Name: turn_paid(text); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.turn_paid(p_id text) RETURNS numeric
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
 select marathon.turn_cash_paid(p_id)+marathon.advance_paid(p_id)
$$;


--
-- Name: wa_begin(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.wa_begin() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare s jsonb;aid uuid;begin
 s=marathon.wa_status();if not(s->>'ready')::boolean then raise sqlstate '22023' using message='Completá la preparación de Meta antes de vincular el número.';end if;
 if (select count(*) from marathon.whatsapp_attempts where user_id=auth.uid() and expires_at>statement_timestamp() and status in('pending','processing','choose_phone'))>=8 then raise sqlstate '22023' using message='Hay varios intentos abiertos. Esperá unos minutos antes de volver a iniciar.';end if;
 insert into marathon.whatsapp_attempts(user_id,config_version)values(auth.uid(),(s->>'version')::bigint)returning id into aid;
 return jsonb_build_object('attempt_id',aid);
end $$;


--
-- Name: wa_configure(jsonb, bigint, uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.wa_configure(p_data jsonb, p_version bigint, p_request_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare c marathon.whatsapp_config;s text;sid uuid;begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede vincular WhatsApp.';end if;
 if p_request_id is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise sqlstate '22023' using message='Configuración inválida.';end if;
 select * into c from marathon.whatsapp_config where singleton for update;
 if c.last_request_id=p_request_id then return marathon.wa_status();end if;
 if c.version is distinct from p_version then raise sqlstate '40001' using message='La configuración cambió. Volvé a cargarla antes de guardar.';end if;
 if c.connected then raise sqlstate '22023' using message='El número está vinculado. Conservá esta configuración mientras esté conectado.';end if;
 if coalesce(p_data->>'app_id','') !~ '^[0-9]{5,30}$' or coalesce(p_data->>'config_id','') !~ '^[0-9]{5,30}$' then raise sqlstate '22023' using message='Revisá el ID de aplicación y el ID de configuración de Meta.';end if;
 s=coalesce(p_data->>'app_secret','');sid=c.app_secret_id;
 if s<>'' then
  if s !~ '^[0-9a-fA-F]{32}$' then raise sqlstate '22023' using message='La clave de aplicación debe ser la clave secreta de Meta de 32 caracteres.';end if;
  sid=vault.create_secret(s,null,'Marathon WhatsApp Meta app secret');
 elsif sid is null or c.app_id<>p_data->>'app_id' then raise sqlstate '22023' using message='Ingresá la clave secreta de esta aplicación de Meta.';
 end if;
 update marathon.whatsapp_config set app_id=p_data->>'app_id',config_id=p_data->>'config_id',app_secret_id=sid,
 coexistence_enabled=coalesce((p_data->>'coexistence_enabled')::boolean,false),
 webhook_verified_at=case when c.app_id=p_data->>'app_id' and s='' then c.webhook_verified_at else null end,
 version=version+1,last_request_id=p_request_id,updated_at=statement_timestamp() where singleton;
 return marathon.wa_status();
end $_$;


--
-- Name: wa_status(); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.wa_status() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c marathon.whatsapp_config;begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede vincular WhatsApp.';end if;
 select * into c from marathon.whatsapp_config where singleton;
 return jsonb_build_object('version',c.version,'app_id',c.app_id,'config_id',c.config_id,'graph_version',c.graph_version,
 'secret_set',c.app_secret_id is not null,'coexistence_enabled',c.coexistence_enabled,'webhook_verified',c.webhook_verified_at is not null,
 'verify_token',c.verify_token,'ready',c.app_id<>'' and c.config_id<>'' and c.app_secret_id is not null and c.coexistence_enabled and c.webhook_verified_at is not null,
 'connected',c.connected,'phone_display',c.phone_display,'phone_name',c.phone_name,'linked_at',c.linked_at,'last_event_at',c.last_event_at);
end $$;


--
-- Name: wa_worker(text, jsonb); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.wa_worker(p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare c marathon.whatsapp_config;a marathon.whatsapp_attempts;sid uuid;phone jsonb;begin
 select * into c from marathon.whatsapp_config where singleton;
 if p_action='config' then
  return jsonb_build_object('app_id',c.app_id,'graph_version',c.graph_version,'verify_token',c.verify_token,'webhook_verified',c.webhook_verified_at is not null,
   'app_secret',(select decrypted_secret from vault.decrypted_secrets where id=c.app_secret_id),'waba_id',c.waba_id,'connected',c.connected);
 elsif p_action='webhook_verified' then
  update marathon.whatsapp_config set webhook_verified_at=statement_timestamp() where singleton;return '{}'::jsonb;
 elsif p_action='event' then
  if p_data->'payload'->>'object'<>'whatsapp_business_account' then raise sqlstate '22023' using message='Evento inválido.';end if;
  insert into marathon.whatsapp_events(event_hash,payload)values(p_data->>'event_hash',p_data->'payload')on conflict do nothing;
  update marathon.whatsapp_config set last_event_at=statement_timestamp() where singleton;
  if c.waba_id is not null and exists(select 1 from jsonb_array_elements(p_data->'payload'->'entry')e cross join lateral jsonb_array_elements(e->'changes')x where e->>'id'=c.waba_id and x->>'field'='account_update' and x->'value'->>'event' in('PARTNER_REMOVED','ACCOUNT_OFFBOARDED')) then
   update marathon.whatsapp_config set connected=false where singleton;
  end if;
  return '{}'::jsonb;
 end if;
 select * into a from marathon.whatsapp_attempts where id=(p_data->>'attempt_id')::uuid and user_id=(p_data->>'user_id')::uuid for update;
 if a.id is null or a.expires_at<statement_timestamp() then raise sqlstate '22023' using message='El intento de vinculación venció. Volvé a iniciarlo.';end if;
 if c.version<>a.config_version then raise sqlstate '40001' using message='Cambió la configuración. Volvé a iniciar la vinculación.';end if;
 if p_action='claim' then
  if a.status='pending' then update marathon.whatsapp_attempts set status='processing' where id=a.id;return jsonb_build_object('claimed',true);end if;
  return jsonb_build_object('claimed',false,'status',a.status,'phones',a.phones);
 elsif p_action='stage' then
  if a.status<>'processing' then raise sqlstate '22023' using message='Intento no disponible.';end if;
  sid=vault.create_secret(p_data->>'token',null,'Marathon WhatsApp business token');
  update marathon.whatsapp_attempts set token_id=sid,waba_id=p_data->>'waba_id',phones=p_data->'phones',status='choose_phone' where id=a.id;
  return jsonb_build_object('status','choose_phone','phones',p_data->'phones');
 elsif p_action='credentials' then
  if a.status<>'choose_phone' then raise sqlstate '22023' using message='Volvé a iniciar la vinculación.';end if;
  select x into phone from jsonb_array_elements(a.phones)x where x->>'id'=p_data->>'phone_id';
  if phone is null then raise sqlstate '22023' using message='Seleccioná uno de los números autorizados.';end if;
  return jsonb_build_object('token',(select decrypted_secret from vault.decrypted_secrets where id=a.token_id),'waba_id',a.waba_id,'phone',phone);
 elsif p_action='complete' then
  if a.status='linked' then return jsonb_build_object('status','linked');end if;
  if a.status<>'choose_phone' then raise sqlstate '22023' using message='Intento no disponible.';end if;
  select x into phone from jsonb_array_elements(a.phones)x where x->>'id'=p_data->>'phone_id';
  if phone is null then raise sqlstate '22023' using message='Número inválido.';end if;
  update marathon.whatsapp_config set connected=true,phone_id=phone->>'id',waba_id=a.waba_id,phone_display=phone->>'display_phone_number',phone_name=phone->>'verified_name',access_token_id=a.token_id,linked_at=statement_timestamp() where singleton;
  update marathon.whatsapp_attempts set status='linked' where id=a.id;return jsonb_build_object('status','linked');
 elsif p_action='fail' then
  if a.status='processing' then update marathon.whatsapp_attempts set status='failed' where id=a.id;end if;return '{}'::jsonb;
 end if;
 raise sqlstate '22023' using message='Acción no disponible.';
end $$;


--
-- Name: whatsapp_template_save(text, text, bigint, uuid); Type: FUNCTION; Schema: marathon; Owner: -
--

CREATE FUNCTION marathon.whatsapp_template_save(p_id text, p_body text, p_version bigint, p_request_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare t marathon.whatsapp_message_templates;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_request_id is null or p_body is null or length(trim(p_body)) not between 1 and 1000 then raise sqlstate '22023' using message='Escribí un mensaje de 1 a 1.000 caracteres.';end if;
 if exists(select 1 from regexp_matches(p_body,'\{([^{}]*)\}','g') m where m[1] not in('paciente','fecha','hora','sede','terapia','profesional')) or regexp_replace(p_body,'\{(paciente|fecha|hora|sede|terapia|profesional)\}','','g')~'[{}]' then raise sqlstate '22023' using message='Usá los datos disponibles: {paciente}, {fecha}, {hora}, {sede}, {terapia} y {profesional}.';end if;
 select * into t from marathon.whatsapp_message_templates where id=p_id for update;
 if t.id is null then raise sqlstate 'P0002' using message='Mensaje no disponible. Volvé a abrir WhatsApp.';end if;
 if t.last_request_id is distinct from p_request_id then
  if t.version is distinct from p_version then raise sqlstate '40001' using message='Otra persona cambió este mensaje. Conservá tu texto y volvé a abrir WhatsApp para revisar la versión guardada.';end if;
  update marathon.whatsapp_message_templates set body=trim(p_body),version=version+1,last_request_id=p_request_id,updated_at=statement_timestamp(),updated_by=auth.uid()where id=p_id;
 end if;
 return(select x from jsonb_array_elements(public.marathon_whatsapp_templates())x where x->>'id'=p_id);
end $$;


--
-- Name: marathon_advance_get(text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_advance_get(p_id text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare a jsonb;rows jsonb;nxt jsonb;
begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 50 or length(coalesce(p_id,''))>100 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 if p_after is not null and(jsonb_typeof(p_after)<>'object'or not(p_after?&array['at','id'])or length(p_after::text)>200)then raise sqlstate '22023' using message='Cursor inválido.';end if;
 select to_jsonb(x)into a from marathon.daily_advance x where id=p_id;
 if a is null then raise sqlstate 'PT404' using message='Anticipo no encontrado.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by created_at desc,id desc),'[]')into rows from(
 select e.*,m.medio,t.fecha turn_date,t.hora turn_hour,coalesce(u.display_name,'Sin registro') actor_name
 from marathon.anticipo_eventos e left join marathon.movimientos m on m.id=e.movimiento_id left join marathon.turnos t on t.id=e.turno_id left join marathon.app_users u on u.user_id=e.actor
 where e.anticipo_id=p_id and(p_after is null or(e.created_at,e.id)<((p_after->>'at')::timestamptz,(p_after->>'id')::uuid))order by e.created_at desc,e.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('at',rows->(p_limit-1)->>'created_at','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('advance',a,'rows',rows,'next',nxt);
end $$;


--
-- Name: marathon_agenda_command(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_command(p_request_id text, p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare uid uuid:=auth.uid();req marathon.solicitudes%rowtype;hashed text;reply jsonb;old marathon.turnos%rowtype;after_row jsonb;
 dates date[];d date;site text;prof text;therapy text;dni text;hour_text text;obs text;cost numeric;duration integer;base_duration integer;
 ids text[]:=array[]::text[];id text;root_id text;state text;slot record;paid numeric;ver bigint;coverage jsonb;reason text;bonus jsonb;fixed_dates date[];fixed_until date;fixed_days integer[];member marathon.turnos%rowtype;series_days integer[];series_pattern jsonb;
begin
 perform 1 from marathon.app_users where user_id=uid and active for share;
 if not found then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_action is null or p_action not in ('book','status','coverage','fixed_end','bonus_pay','bonus_refund','bonus_cancel','advance_deposit','advance_apply','advance_refund') or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise sqlstate '22023' using message='Solicitud inválida.';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '22023' using message='La agenda requiere transacciones READ COMMITTED.';end if;
 hashed=encode(sha256(convert_to(jsonb_build_object('action',p_action,'data',p_data)::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_request_id,uid,'agenda:'||p_action,hashed) on conflict on constraint solicitudes_pkey do nothing;
 select * into req from marathon.solicitudes s where s.id=p_request_id for update;
 if req.id is null or req.usuario_id<>uid or req.tipo<>'agenda:'||p_action or req.payload_hash<>hashed then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if req.resultado is not null then return req.resultado;end if;
 -- Mismo orden y mismo candado que el mantenimiento de maestros. Tres usuarios: prima la integridad.
 -- VOLATILE (valor predeterminado) permite leer el estado confirmado después de esperar el candado.
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_action when 'book' then array['dates','sede','prof','therapy','dni','hora','importe','observaciones','coverage','fixed_from','fixed_until','fixed_days','series_days','bonus_amount','bonus_paid','bonus_medium'] when 'coverage' then array['id','version','coverage','motivo'] when 'bonus_pay' then array['id','version','monto','medio','observaciones'] when 'bonus_refund' then array['id','version','monto','medio','observaciones'] when 'bonus_cancel' then array['id','version','motivo'] when 'advance_deposit' then array['dni','sede','therapy','prof','monto','medio','observaciones','apply_existing'] when 'advance_apply' then array['dni'] when 'advance_refund' then array['id','version','monto','medio','observaciones'] when 'fixed_end' then array['id','version'] else array['id','version','estado'] end)) then raise sqlstate '22023' using message='La solicitud contiene campos no admitidos.';end if;
 if p_action='book' then
  site=marathon.master_text(p_data,'sede',40,true);prof=marathon.master_text(p_data,'prof',100,true);therapy=marathon.master_text(p_data,'therapy',100,true);
  dni=marathon.master_text(p_data,'dni',12,true);hour_text=marathon.master_text(p_data,'hora',5,true);obs=marathon.master_text(p_data,'observaciones',1000);
  if dni !~ '^[0-9]{1,12}$' or not exists(select 1 from marathon.pacientes p where p.dni=dni) then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;
  if hour_text !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or jsonb_typeof(p_data->'importe') is distinct from 'number' or coalesce(p_data->>'importe','') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise sqlstate '22023' using message='Hora o importe inválidos (hasta dos decimales).';end if;
  cost=(p_data->>'importe')::numeric;
  if p_data?'coverage' then coverage=marathon.normalize_turn_coverage(dni,p_data->'coverage');end if;
  if jsonb_typeof(p_data->'dates') is distinct from 'array' or jsonb_array_length(p_data->'dates') not between 1 and 60 then raise sqlstate '22023' using message='Seleccioná entre 1 y 60 fechas.';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'dates') x where jsonb_typeof(x)<>'string') then raise sqlstate '22023' using message='Fecha inválida.';end if;
  select array_agg(marathon.agenda_date(value) order by value) into dates from jsonb_array_elements_text(p_data->'dates');
  if cardinality(dates)<>(select count(distinct x) from unnest(dates) x) then raise sqlstate '22023' using message='Hay fechas repetidas en la reserva.';end if;
  if p_data ?| array['fixed_until','fixed_from','fixed_days'] then
   fixed_dates=marathon.fixed_dates(p_data->>'fixed_from',p_data->>'fixed_until',p_data->'fixed_days');
   if dates<>fixed_dates then raise sqlstate '22023' using message='El horario fijo debe incluir todas las fechas hasta la revisión.';end if;
   fixed_until=marathon.agenda_date(p_data->>'fixed_until');
   select array_agg(x::int order by x::int) into fixed_days from jsonb_array_elements_text(p_data->'fixed_days')x;
  end if;
     if p_data?'series_days' then
    if jsonb_typeof(p_data->'series_days') is distinct from 'array' or jsonb_array_length(p_data->'series_days') not between 1 and 7 or exists(select 1 from jsonb_array_elements_text(p_data->'series_days') x where x !~ '^[0-6]$') then raise sqlstate '22023' using message='Días semanales inválidos.';end if;
    select array_agg(distinct x::int order by x::int) into series_days from jsonb_array_elements_text(p_data->'series_days') x;
    if cardinality(series_days)<>jsonb_array_length(p_data->'series_days') or exists(select 1 from unnest(dates) x where extract(dow from x)::int<>all(series_days)) then raise sqlstate '22023' using message='Los días de la serie no coinciden con las fechas elegidas.';end if;
    if fixed_days is not null and fixed_days<>series_days then raise sqlstate '22023' using message='Los días del horario fijo no coinciden con la serie.';end if;
   else
    select array_agg(distinct extract(dow from x)::int order by extract(dow from x)::int) into series_days from unnest(dates) x;
   end if;
   series_pattern=jsonb_build_object('days',series_days,'hora',hour_text,'source',case when p_data?'series_days' then 'selected' else 'inferred' end);
select t.duracion_min into duration from marathon.terapias t where t.id=therapy and t.estado='ACTIVO';
  if duration is null then raise sqlstate '22023' using message='La terapia ya no está activa. Actualizá los datos de agenda.';end if;
  base_duration=duration;
  foreach d in array dates loop
   duration=marathon.session_minutes(d,site,prof,hour_text::time,base_duration);
   select * into slot from marathon.agenda_slots(d,site,prof,therapy) s where s.hora=hour_text;
   if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='Sin cupo el '||d||' a las '||hour_text||'. No se guardó ningún turno de la reserva.';end if;
   if exists(select 1 from marathon.turnos t where t.dni=dni and t.fecha=d and t.estado<>'CANCELADO' and t.hora<(hour_text::time+duration*interval '1 minute') and hour_text::time<(t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute')) then raise sqlstate 'PT409' using message='El paciente ya tiene un turno que se superpone el '||d||'. No se guardó la reserva.';end if;
   id='TUR-'||gen_random_uuid()::text;if root_id is null then root_id=id;end if;
   insert into marathon.turnos(id,original_id,fecha,sede,hora,duracion_min,terapia_id,profesional_id,dni,importe,estado,observaciones,booking_notes,series_pattern,coverage,fixed_until,fixed_days,created_by,updated_by)
    values(id,case when id=root_id then null else root_id end,d,site,hour_text::time,duration,therapy,prof,dni,cost,'PENDIENTE',obs,obs,series_pattern,coverage,fixed_until,fixed_days,uid,uid);
   select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,after_data) values(p_request_id,uid,id,p_action,after_row);ids=array_append(ids,id);
  end loop;
  bonus=marathon.bonus_create(p_request_id,root_id,p_data);
  reply=jsonb_build_object('ids',ids,'coverage',coverage,'bonus',bonus,'sessions',(select jsonb_agg(jsonb_build_object('fecha',t.fecha,'hora',to_char(t.hora,'HH24:MI'),'end_hour',to_char(t.hora+t.duracion_min*interval '1 minute','HH24:MI'),'duration_min',t.duracion_min) order by t.fecha,t.hora,t.id) from marathon.turnos t where t.id=any(ids)),'message',case when cardinality(ids)=1 then 'Turno reservado.' else cardinality(ids)||' turnos reservados.' end);
 elsif p_action='fixed_end' then
  id=marathon.master_text(p_data,'id',100,true);ver=marathon.operation_version(p_data);
  select * into old from marathon.turnos t where t.id=id for update;
  if not found or old.fixed_until is null then raise sqlstate '22023' using message='No se encontró un horario fijo.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda.';end if;
  for member in select t.* from marathon.turnos t where coalesce(t.original_id,t.id)=coalesce(old.original_id,old.id)
   and t.fecha>=old.fecha and t.fecha>=(now() at time zone 'America/Argentina/Buenos_Aires')::date and t.estado='PENDIENTE' order by t.fecha,t.hora,t.id for update loop
   if marathon.turn_paid(member.id)>0 then raise sqlstate 'PT409' using message='Hay un turno con cobros. Reintegrá antes de finalizar el fijo.';end if;
   update marathon.turnos t set estado='CANCELADO' where t.id=member.id;
   select to_jsonb(t) into after_row from marathon.turnos t where t.id=member.id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,uid,member.id,'fixed_end',to_jsonb(member),after_row);
   ids=array_append(ids,member.id);
  end loop;
  if cardinality(ids)=0 then raise sqlstate '22023' using message='No quedan turnos futuros pendientes para finalizar.';end if;
  reply=jsonb_build_object('ids',ids,'message',cardinality(ids)||' turnos futuros cancelados. Se conservaron asistencia y cobros anteriores.');
 elsif p_action in('bonus_pay','bonus_refund','bonus_cancel') then
  reply=marathon.bonus_change(p_request_id,p_action,p_data);
 elsif p_action in('advance_deposit','advance_apply','advance_refund')then
 reply=marathon.advance_change(p_request_id,p_action,p_data);
 elsif p_action='coverage' then
  id=marathon.master_text(p_data,'id',100,true);reason=marathon.master_text(p_data,'motivo',500,true);
  if length(btrim(reason))<3 then raise sqlstate '22023' using message='Indicá el motivo de la corrección (mínimo 3 caracteres).';end if;
  ver=marathon.operation_version(p_data);
  select * into old from marathon.turnos t where t.id=id for update;
  if not found then raise sqlstate 'PT404' using message='El turno ya no existe.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda.';end if;
  if coalesce(old.coverage->>'type','')<>'' and old.estado<>'PENDIENTE' and not exists(select 1 from marathon.app_users u where u.user_id=uid and u.active and u.role='ADMIN') then raise sqlstate '42501' using message='Solo administración puede corregir la cobertura de un turno que no está pendiente.';end if;
  coverage=marathon.normalize_turn_coverage(old.dni,p_data->'coverage');
  update marathon.turnos t set coverage=coverage where t.id=id;
  select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,uid,id,'coverage',to_jsonb(old),after_row||jsonb_build_object('motivo_cobertura',reason));
  reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Cobertura del turno actualizada. Se conservaron importe, estado y pagos.');
 else
  id=marathon.master_text(p_data,'id',100,true);state=marathon.master_text(p_data,'estado',10,true);
  if state not in ('PENDIENTE','PRESENTE','AUSENTE','CANCELADO') or jsonb_typeof(p_data->'version') is distinct from 'number' or coalesce(p_data->>'version','') !~ '^[0-9]{1,18}$' then raise sqlstate '22023' using message='Estado o versión inválidos.';end if;
  ver=(p_data->>'version')::bigint;
  select * into old from marathon.turnos t where t.id=id for update;
  if not found then raise sqlstate 'PT404' using message='El turno ya no existe.';end if;
  if old.version<>ver then raise sqlstate 'PT409' using message='El turno cambió. Actualizá la agenda antes de modificarlo.';end if;
  select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) into paid from marathon.movimientos m where m.turno_id=id;
  if state<>'PRESENTE' and paid>0 then raise sqlstate '22023' using message='El turno tiene cobros. Registrá el reintegro antes de cambiar su estado.';end if;
     if old.estado='CANCELADO' and state<>'CANCELADO' and exists(select 1 from marathon.turnos r where r.recovered_from=old.id) then raise sqlstate 'PT409' using message='Esta cancelación ya fue recuperada. Consultá la nueva sesión.';end if;
if old.estado='CANCELADO' and state<>'CANCELADO' then
   select * into slot from marathon.agenda_slots(old.fecha,old.sede,old.profesional_id,old.terapia_id) s where s.hora=to_char(old.hora,'HH24:MI');
   -- No restaurar con una duración distinta de la que se comprobó.
   if marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)<>(select marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,t.duracion_min) from marathon.terapias t where t.id=old.terapia_id) then raise sqlstate 'PT409' using message='Cambió la duración de la terapia. Creá una nueva reserva para este turno cancelado.';end if;
   if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='El horario ya no tiene cupo. El turno sigue cancelado.';end if;
   if exists(select 1 from marathon.turnos t where t.dni=old.dni and t.fecha=old.fecha and t.estado<>'CANCELADO' and t.hora<old.hora+marathon.session_minutes(old.fecha,old.sede,old.profesional_id,old.hora,old.duracion_min)*interval '1 minute' and old.hora<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute') then raise sqlstate 'PT409' using message='El paciente tiene otro turno que se superpone.';end if;
  end if;
  if state<>'PRESENTE' then perform marathon.advance_apply(p_request_id,id,true);end if;
 update marathon.turnos t set estado=state,attendance_manual_date=t.fecha,attendance_auto=false,attendance_auto_at=null where t.id=id;
 if state='PRESENTE'then perform marathon.advance_apply(p_request_id,id);end if;
  select to_jsonb(t) into after_row from marathon.turnos t where t.id=id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,uid,id,p_action,to_jsonb(old),after_row);
  reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Estado del turno actualizado.');
 end if;
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $_$;


--
-- Name: marathon_agenda_flexible(jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_flexible(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
declare r jsonb;d date;e date;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 perform marathon.agenda_materializar(d,e);
 r=public.marathon_agenda_search(p_filters,p_after,p_limit);
 r=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(x||jsonb_build_object('plan',marathon.agenda_plan_info(t.plan_id),'paused',t.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(t.plan_id,t.fecha),'end_hour',to_char(t.hora+make_interval(mins=>t.duracion_min),'HH24:MI')) order by n)from jsonb_array_elements(r->'rows')with ordinality a(x,n)join marathon.turnos t on t.id=x->>'id'),'[]'::jsonb));return r;
end$$;


--
-- Name: marathon_agenda_grilla(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_grilla(p_from text, p_sede text, p_prof text, p_therapy text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
declare d date;e date;rows jsonb;plans jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_from);e=d+6;
 if not exists(select 1 from marathon.horarios where sede=p_sede and profesional_id=p_prof)then return jsonb_build_object('slots','[]'::jsonb,'plans','[]'::jsonb);end if;
 perform marathon.agenda_cuotas_generar();
 select coalesce(jsonb_agg(jsonb_build_object('fecha',dt::date,'hora',to_char(h.inicio+make_interval(mins=>g.m),'HH24:MI'),'therapy',t.id,'meta',marathon.agenda_cupo(dt::date,p_sede,p_prof,t.id,h.inicio+make_interval(mins=>g.m)),
 'patients',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'plan_id',a.plan_id,'dni',a.dni,'paciente',concat_ws(' ',p.apellido,p.nombre,p.segundo_nombre),'telefono',p.telefono,'hora',to_char(a.hora,'HH24:MI'),'end_hour',to_char(a.hora+make_interval(mins=>a.duracion_min),'HH24:MI'),'estado',a.estado,'paused',a.pausado,'therapy',a.terapia_id,'plan',marathon.agenda_plan_info(a.plan_id)) order by p.apellido,p.nombre)from marathon.agenda_pool(dt::date)a join marathon.pacientes p on p.dni=a.dni where a.sede=p_sede and a.profesional_id=p_prof and a.hora=h.inicio+make_interval(mins=>g.m) and(p_therapy=''or a.terapia_id=p_therapy)),'[]'::jsonb))order by dt,g.m),'[]'::jsonb)into rows
 from generate_series(d,e,interval '1 day')dt join marathon.horarios h on h.dia=extract(dow from dt)::int and h.profesional_id=p_prof and h.sede=p_sede
 join lateral(select x.id from marathon.terapias x join marathon.profesional_terapias pt on pt.terapia_id=x.id and pt.profesional_id=p_prof where x.estado='ACTIVO' and(p_therapy=''or x.id=p_therapy) order by x.capacidad desc,x.id limit 1)t on true
 cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(p_prof))g(m);
 select coalesce(jsonb_agg(marathon.agenda_plan_info(p.id)||jsonb_build_object('paciente',concat_ws(' ',x.apellido,x.nombre,x.segundo_nombre),'telefono',x.telefono)order by x.apellido,x.nombre),'[]'::jsonb) into plans from marathon.agenda_planes p join marathon.pacientes x on x.dni=p.dni where exists(select 1 from marathon.agenda_horarios h where h.plan_id=p.id and h.sede=p_sede and h.profesional_id=p_prof)and(p_therapy=''or p.terapia_id=p_therapy);
 return jsonb_build_object('slots',rows,'plans',plans);
end$$;


--
-- Name: marathon_agenda_list(text, text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_list(p_fecha text, p_sede text DEFAULT ''::text, p_prof text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$ declare d date;rows jsonb;nxt jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_fecha);
 if p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_sede,''))>40 or length(coalesce(p_prof,''))>100 or
 (p_after is not null and (jsonb_typeof(p_after)<>'object' or not(p_after ?& array['hora','id']) or coalesce(p_after->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.hora,x.id),'[]'::jsonb) into rows from (
  select t.id,t.original_id,t.fecha,t.sede,to_char(t.hora,'HH24:MI') hora,t.duracion_min,t.terapia_id,th.nombre terapia,t.profesional_id,
  concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido) profesional,t.dni,concat_ws(' ',p.apellido,p.nombre,nullif(p.segundo_nombre,'')) paciente,
  t.importe,t.estado,t.observaciones,t.version from marathon.turnos t join marathon.pacientes p on p.dni=t.dni
  join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales pr on pr.id=t.profesional_id
  where t.fecha=d and (coalesce(p_sede,'')='' or t.sede=p_sede) and(coalesce(p_prof,'')='' or t.profesional_id=p_prof)
   and(p_after is null or(t.hora,t.id)>((p_after->>'hora')::time,p_after->>'id')) order by t.hora,t.id limit p_limit+1
 ) x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt);
end $_$;


--
-- Name: marathon_agenda_options(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_options() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if (select count(*) from marathon.sedes where estado='ACTIVO')>500 or (select count(*) from marathon.terapias where estado='ACTIVO')>500 or (select count(*) from marathon.profesionales where estado='ACTIVO')>500 then
  raise sqlstate '22023' using message='El catálogo supera el límite del selector. Se requiere búsqueda paginada.';end if;
 return jsonb_build_object('sedes',coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre) order by nombre) from marathon.sedes where estado='ACTIVO'),'[]'::jsonb),
 'therapies',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',nombre,'duration',duracion_min,'capacity',capacidad) order by nombre,id) from marathon.terapias where estado='ACTIVO'),'[]'::jsonb),
 'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'label',concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido),'start_step',marathon.professional_step(p.id),'therapy_ids',coalesce((select jsonb_agg(terapia_id order by terapia_id) from marathon.profesional_terapias where profesional_id=p.id),'[]'::jsonb)) order by p.apellido,p.nombre,p.id) from marathon.profesionales p where estado='ACTIVO'),'[]'::jsonb)) || jsonb_build_object('hours',coalesce((select jsonb_agg(jsonb_build_object('prof',h.profesional_id,'sede',h.sede,'day',h.dia,'start',to_char(h.inicio,'HH24:MI'),'end',to_char(h.fin,'HH24:MI')) order by h.profesional_id,h.dia,h.inicio,h.id) from marathon.horarios h join marathon.profesionales p on p.id=h.profesional_id and p.estado='ACTIVO' join marathon.sedes s on s.nombre=h.sede and s.estado='ACTIVO'),'[]'::jsonb));
end $$;


--
-- Name: marathon_agenda_patient_account(text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
declare r jsonb;plans jsonb;debt numeric;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.agenda_cuotas_generar();r=public.marathon_patient_account(p_dni,p_after,p_limit);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'terapia',t.nombre,'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id=p.id),0))order by p.inicio),'[]'::jsonb)into plans from marathon.agenda_planes p join marathon.terapias t on t.id=p.terapia_id where p.dni=p_dni and p.facturacion='monthly';
 select coalesce(sum((x->>'debt')::numeric),0)into debt from jsonb_array_elements(plans)x;
 return r||jsonb_build_object('plans',plans,'debt',coalesce((r->>'debt')::numeric,0)+debt);
end$$;


--
-- Name: marathon_agenda_plan(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_plan(p_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;perform marathon.agenda_cuotas_generar();return marathon.agenda_plan_info(p_id);end$$;


--
-- Name: marathon_agenda_plan_command(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_plan_command(p_request_id text, p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare reply jsonb;p marathon.agenda_planes%rowtype;h marathon.agenda_horarios%rowtype;pause marathon.agenda_pausas%rowtype;q marathon.agenda_cuotas%rowtype;
 raw jsonb;cov jsonb;slot jsonb;dt date;dt2 date;kind text;fee numeric;quantity int;pid uuid;sid uuid;root text;mid text;amount numeric;reason text;medium text;before_data jsonb;w marathon.espera%rowtype;bonus jsonb;
begin
 reply=marathon.operation_begin(p_request_id,'agenda-plan:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action not in('create','pause','resume','end','authorize','quota_pay','quota_waive','quota_refund')or p_action is null then raise sqlstate '22023' using message='Acción inválida.';end if;
 if p_action='create' then
  if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['dni','therapy','mode','billing','amount','start','total','coverage','notes','schedules','bonus_amount','bonus_paid','bonus_medium','wait_id','wait_version']))then raise sqlstate '22023'using message='Campos de reserva inválidos.';end if;
  dt=marathon.agenda_date(p_data->>'start');kind=p_data->>'mode';fee=(p_data->>'amount')::numeric;quantity=coalesce((p_data->>'total')::int,0);
  if dt<marathon.agenda_hoy() or dt>marathon.agenda_hoy()+366 or kind not in('sessions','monthly','fixed')or kind is null or p_data->>'billing' not in('class','bonus_class','monthly','none')or p_data->>'billing' is null or fee is null or fee<0 or fee>9999999999.99 or fee<>round(fee,2)or(kind='sessions'and quantity not between 1 and 1000)or(p_data->>'billing'='none'and fee<>0)or(p_data->>'billing'='monthly'and fee<=0)then raise sqlstate '22023'using message='Revisá inicio, modalidad, cantidad e importe.';end if;
  cov=marathon.normalize_turn_coverage(p_data->>'dni',p_data->'coverage');
  if jsonb_typeof(p_data->'schedules')is distinct from'array'or jsonb_array_length(p_data->'schedules')not between 1 and 5 then raise sqlstate '22023'using message='Elegí uno o más días hábiles.';end if;
  if p_data->>'billing'='bonus_class' and coalesce((p_data->>'bonus_amount')::numeric,0)<=0 then raise sqlstate '22023'using message='Indicá el importe del bono inicial.';end if;
  if p_data->>'billing'<>'bonus_class'and coalesce((p_data->>'bonus_amount')::numeric,0)<>0 then raise sqlstate '22023'using message='El bono solo corresponde a bono inicial más clase.';end if;
  insert into marathon.agenda_planes(dni,terapia_id,modalidad,facturacion,importe,inicio,coverage,observaciones,created_by,updated_by)values(p_data->>'dni',p_data->>'therapy',kind,p_data->>'billing',fee,dt,cov,coalesce(p_data->>'notes',''),auth.uid(),auth.uid())returning id into pid;
  if kind='sessions'then insert into marathon.agenda_autorizaciones(plan_id,cantidad,fecha,created_by)values(pid,quantity,dt,auth.uid());end if;
  for raw in select * from jsonb_array_elements(p_data->'schedules')loop
   if exists(select 1 from jsonb_object_keys(raw)k where k<>all(array['day','site','prof','time']))or(raw->>'day')::int not between 1 and 5 then raise sqlstate '22023'using message='Día u horario inválido.';end if;
   dt2=dt+(((raw->>'day')::int-extract(dow from dt)::int+7)%7);
   slot=marathon.agenda_cupo(dt2,raw->>'site',raw->>'prof',p_data->>'therapy',(raw->>'time')::time,pid);
   if coalesce((slot->>'remaining')::int,0)<1 or coalesce((slot->>'blocked')::boolean,true)then raise sqlstate '22023'using message='Uno de los horarios no está habilitado o no tiene cupo.';end if;
   insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde)values(pid,raw->>'site',raw->>'prof',(raw->>'day')::int,(raw->>'time')::time,(slot->>'duration_min')::int,dt);
  end loop;
  -- Comprobar todos los cambios futuros de reglas y todos los turnos ya cargados, además de las próximas semanas.
  for h in select * from marathon.agenda_horarios where plan_id=pid loop
   for dt2 in select distinct candidate_date from(
    select g::date candidate_date from generate_series(dt,dt+41,interval '1 day')g
    union select t.fecha from marathon.turnos t where t.fecha>=dt and(t.dni=p_data->>'dni'or t.profesional_id=h.profesional_id)and t.estado<>'CANCELADO'
    union select greatest(dt,x.desde)+((h.dia-extract(dow from greatest(dt,x.desde))::int+7)%7)from marathon.agenda_horarios x where x.profesional_id=h.profesional_id or x.plan_id in(select p.id from marathon.agenda_planes p where p.dni=p_data->>'dni')
   )c where candidate_date>=dt and extract(dow from candidate_date)::int=h.dia loop
    slot=marathon.agenda_cupo(dt2,h.sede,h.profesional_id,p_data->>'therapy',h.hora,pid);
    if coalesce((slot->>'remaining')::int,0)<1 then raise sqlstate '22023'using message='La reserva entra en conflicto con la ocupación del '||dt2::text||'.';end if;
    if exists(select 1 from marathon.agenda_pool(dt2)x where x.dni=p_data->>'dni'and x.plan_id is distinct from pid and x.hora<h.hora+make_interval(mins=>h.duracion_min)and h.hora<x.hora+make_interval(mins=>x.duracion_min))then raise sqlstate '22023'using message='El paciente ya tiene un turno o lugar reservado en uno de los horarios.';end if;
   end loop;
  end loop;
  if p_data->>'billing'='monthly'or kind='monthly'then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt);end if;
  perform marathon.agenda_materializar(dt,dt+case when kind='fixed'then 6 else 27 end);
  select id into root from marathon.turnos t where t.plan_id=pid order by t.fecha,t.hora,t.id limit 1;
  bonus=marathon.bonus_create(p_request_id,root,p_data);
  if nullif(p_data->>'wait_id','')is not null then
   select * into w from marathon.espera where id=p_data->>'wait_id'for update;
   if w.id is null or w.estado not in('PENDIENTE','CONTACTADO')or w.version<>(p_data->>'wait_version')::bigint or w.dni<>p_data->>'dni'or w.terapia_id<>p_data->>'therapy'or not exists(select 1 from marathon.agenda_horarios h where h.plan_id=pid and h.sede=w.sede and(w.profesional_id is null or h.profesional_id=w.profesional_id))then raise sqlstate 'PT409'using message='El pedido de espera cambió o la reserva no corresponde.';end if;
   update marathon.espera set estado='RESUELTO',reserved_turn_id=root where id=w.id;
  end if;
 else
  if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','date','until','reason','total','quota','amount','medium']))then raise sqlstate '22023'using message='Campos de operación inválidos.';end if;
  pid=(p_data->>'id')::uuid;select * into p from marathon.agenda_planes where id=pid for update;
  if not found then raise sqlstate 'PT404'using message='Tratamiento no encontrado.';end if;
  if p.version<>(p_data->>'version')::bigint or p_data->>'version'is null then raise sqlstate 'PT409'using message='El tratamiento cambió. Volvé a abrirlo.';end if;before_data=to_jsonb(p);
  dt=coalesce(nullif(p_data->>'date','')::date,marathon.agenda_hoy());reason=btrim(coalesce(p_data->>'reason',''));
  if p_action in('pause','resume','end','quota_waive','quota_refund')and length(reason)not between 3 and 1000 then raise sqlstate '22023'using message='Indicá un motivo de al menos tres caracteres.';end if;
  if p_action='pause'then
   dt2=nullif(p_data->>'until','')::date;
   if p.baja is not null or dt<greatest(p.inicio,marathon.agenda_hoy())or(dt2 is not null and dt2<=dt)or exists(select 1 from marathon.agenda_pausas x where x.plan_id=pid and coalesce(x.hasta,'infinity'::date)>dt and coalesce(dt2,'infinity'::date)>x.desde)then raise sqlstate '22023'using message='Fechas de pausa inválidas o superpuestas.';end if;
   insert into marathon.agenda_pausas(plan_id,desde,hasta,motivo,created_by)values(pid,dt,dt2,reason,auth.uid());
   update marathon.agenda_periodos set fin=dt where plan_id=pid and not anulado and inicio<=dt and(fin is null or fin>dt);
   if dt2 is not null and(p.facturacion='monthly'or p.modalidad='monthly')then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt2);end if;
  elsif p_action='resume'then
   select * into pause from marathon.agenda_pausas x where x.plan_id=pid and x.desde<=dt and(x.hasta is null or dt<x.hasta)order by x.desde desc limit 1 for update;
   if pause.id is null or dt<>marathon.agenda_hoy()or p.baja is not null then raise sqlstate '22023'using message='No hay una pausa activa para reanudar hoy.';end if;
   update marathon.agenda_pausas set hasta=dt where id=pause.id;
   update marathon.agenda_periodos set anulado=true where plan_id=pid and inicio>dt;
   if p.facturacion='monthly'or p.modalidad='monthly'then
    if dt=pause.desde then update marathon.agenda_periodos set fin=null where plan_id=pid and fin=dt and not anulado;
    else insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt);end if;
   end if;
  elsif p_action='end'then
   if dt<greatest(p.inicio,marathon.agenda_hoy())or p.baja is not null then raise sqlstate '22023'using message='La baja no puede modificar períodos anteriores.';end if;
   if exists(select 1 from marathon.turnos t where t.plan_id=pid and t.fecha>=dt and t.estado='PRESENTE')then raise sqlstate '22023'using message='Hay atenciones presentes posteriores a esa baja. Revisá su fecha antes de continuar.';end if;
   update marathon.agenda_planes set baja=dt where id=pid;
   update marathon.turnos set estado='CANCELADO',agenda_motivo='BAJA'where plan_id=pid and fecha>=dt and estado='PENDIENTE';
  elsif p_action='authorize'then
   quantity=(p_data->>'total')::int;if p.modalidad<>'sessions'or quantity is null or quantity not between 1 and 1000 or p.baja is not null then raise sqlstate '22023'using message='Indicá de 1 a 1000 sesiones para una nueva autorización.';end if;
   insert into marathon.agenda_autorizaciones(plan_id,cantidad,fecha,created_by)values(pid,quantity,marathon.agenda_hoy(),auth.uid());
  else
   perform marathon.agenda_cuotas_generar();select * into q from marathon.agenda_cuotas c where c.id=(p_data->>'quota')::uuid and c.plan_id=pid for update;
   if q.id is null then raise sqlstate 'PT404'using message='Cuota no encontrada.';end if;
   amount=(p_data->>'amount')::numeric;medium=p_data->>'medium';
   if amount is null or amount<=0 or amount<>round(amount,2)then raise sqlstate '22023'using message='Importe inválido.';end if;
   if p_action='quota_waive'then
    if amount>marathon.agenda_cuota_saldo(q.id)then raise sqlstate '22023'using message='La cancelación supera el saldo pendiente.';end if;
    insert into marathon.agenda_ajustes(cuota_id,importe,motivo,created_by)values(q.id,amount,reason,auth.uid());
   else
    if medium not in('EFECTIVO','TRANSFERENCIA')or medium is null then raise sqlstate '22023'using message='Elegí un medio de pago.';end if;
    if p_action='quota_pay'and amount>marathon.agenda_cuota_saldo(q.id)or p_action='quota_refund'and amount>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El importe supera el saldo disponible.';end if;
    mid='MOV-'||gen_random_uuid()::text;
    insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,concepto,observaciones_legacy,motivo,categoria,profesional_asociado_id,cuota_id,created_by,updated_by)
    values(mid,marathon.agenda_hoy(),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA',case when p_action='quota_pay'then'INGRESO'else'EGRESO'end,p.dni,amount,medium,q.sede,'Cuota mensual '||q.fecha::text,reason,nullif(reason,''),'Cuota mensual',(select quota_schedule.profesional_id from marathon.agenda_horarios quota_schedule where quota_schedule.plan_id=pid order by quota_schedule.dia,quota_schedule.hora limit 1),q.id,auth.uid(),auth.uid());
   end if;
  end if;
  update marathon.agenda_planes set updated_at=now()where id=pid;
 end if;
 if mid is not null then insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)select p_request_id,auth.uid(),'movement',m.id,p_action,to_jsonb(m)from marathon.movimientos m where m.id=mid;end if;
 perform marathon.agenda_cuotas_generar();
 reply=jsonb_build_object('id',pid,'ids',jsonb_build_array(root),'bonus',bonus,'plan',marathon.agenda_plan_info(pid),'message','Operación guardada en la agenda.');
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'agenda_plan',pid::text,p_action,before_data,reply->'plan');
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end$$;


--
-- Name: marathon_agenda_search(jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d date;e date;rows jsonb;nxt jsonb;summary jsonb;state text;layout text;groups jsonb;show_cancelled boolean;
begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','prof','therapy','query','state','layout'],least(p_limit,100),p_after);
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');state=coalesce(p_filters->>'state','');
 if p_limit is null or p_limit not between 1 and 10000 or e<d or e-d>31 or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Elegí un período de hasta 32 días y una página válida.';end if;
 if state not in('','PENDIENTE','PRESENTE','AUSENTE','CANCELADO','PAUSADO')then raise sqlstate '22023'using message='Estado de turno inválido.';end if;

 show_cancelled=marathon.is_admin();
 layout=coalesce(p_filters->>'layout','');
 if layout not in('','blocks')or(layout='blocks'and p_limit>50)then raise sqlstate '22023'using message='Vista o cantidad de bloques inválida.';end if;
 if layout='blocks'then
  with base as(
  select jsonb_build_array(t.sede,t.profesional_id,t.terapia_id)::text group_id,t.*,b.plan_id,(b.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(b.plan_id,b.fecha))paused,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where (show_cancelled or t.estado<>'CANCELADO') and t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)

 ), chosen as(select * from base where state=''or(state='PAUSADO'and paused)or(estado=state and not paused)),
 keys as(
  select fecha,hora,group_id from chosen where p_after is null or(fecha,hora,group_id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')
  group by fecha,hora,group_id order by fecha,hora,group_id limit p_limit+1
 ), wanted as(select * from keys order by fecha,hora,group_id limit p_limit),
 paged as(select c.* from chosen c join wanted k using(fecha,hora,group_id)),
 metadata as(
  select fecha,hora,group_id,min(sede) sede,min(profesional_id) profesional_id,min(terapia_id) terapia_id,min(profesional) profesional,min(terapia) terapia,count(*) listed
  from paged group by fecha,hora,group_id
 )
 select coalesce((select jsonb_agg(to_jsonb(x)-'group_id'order by fecha,hora,group_id,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PAUSADO',count(*)filter(where paused),'PENDIENTE',count(*)filter(where estado='PENDIENTE'and not paused),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'and not paused),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0)+coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id in(select plan_id from base)),0))from base),
 coalesce((select jsonb_agg(jsonb_build_object('fecha',m.fecha,'hora',m.hora,'key',m.group_id,'sede',m.sede,'profesional_id',m.profesional_id,'terapia_id',m.terapia_id,'profesional',m.profesional,'terapia',m.terapia,'listed',m.listed,'availability_known',s.hora is not null,'capacity',s.capacity,'remaining',s.remaining,'blocked',s.blocked)order by m.fecha,m.hora,m.group_id)
 from metadata m left join lateral(select * from marathon.agenda_slots(m.fecha,m.sede,m.profesional_id,m.terapia_id)s where s.hora=to_char(m.hora,'HH24:MI'))s on true),'[]'::jsonb),
 (select case when(select count(*)from keys)>p_limit then jsonb_build_object('fecha',fecha,'hora',hora,'id',group_id)end from wanted order by fecha desc,hora desc,group_id desc limit 1)
 into rows,summary,groups,nxt;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'blocks',groups,'generated_at',statement_timestamp(),'layout','blocks');
 end if;
 with base as(
  select t.*,b.plan_id,(b.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(b.plan_id,b.fecha))paused,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where (show_cancelled or t.estado<>'CANCELADO') and t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
  and(coalesce(p_filters->>'prof','')=''or t.profesional_id=p_filters->>'prof')
  and(coalesce(p_filters->>'therapy','')=''or t.terapia_id=p_filters->>'therapy')
  and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(t.paciente||' '||t.dni),marathon.master_norm(p_filters->>'query'))>0)
 ), paged as(
  select * from base where(state=''or(state='PAUSADO'and paused)or(estado=state and not paused))and(p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id'))
  order by fecha,hora,id limit p_limit+1
 )
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,hora,id)from paged x),'[]'::jsonb),
 (select jsonb_build_object('total',count(*),'patients',count(distinct dni),'PAUSADO',count(*)filter(where paused),'PENDIENTE',count(*)filter(where estado='PENDIENTE'and not paused),'PRESENTE',count(*)filter(where estado='PRESENTE'),'AUSENTE',count(*)filter(where estado='AUSENTE'and not paused),'CANCELADO',count(*)filter(where estado='CANCELADO'),'debt',coalesce(sum(debt),0)+coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id in(select plan_id from base)),0))from base)
 into rows,summary;
 if p_limit=10000 and jsonb_array_length(rows)>10000 then raise sqlstate '22023'using message='Hay más de 10.000 turnos. Reducí el período o los filtros para exportar el listado completo.';end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'summary',summary,'generated_at',statement_timestamp());
end $$;


--
-- Name: marathon_agenda_slots(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_agenda_slots(p_fecha text, p_sede text, p_prof text, p_therapy text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d date;r jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;d=marathon.agenda_date(p_fecha);
 select coalesce(jsonb_agg(marathon.agenda_cupo(d,p_sede,p_prof,p_therapy,at_hour)||jsonb_build_object('shared_space',exists(select 1 from marathon.shared_space_therapies where therapy_id=p_therapy))order by at_hour),'[]'::jsonb)into r from(
 select distinct h.inicio+make_interval(mins=>g.m)at_hour from marathon.horarios h cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(p_prof))g(m) where h.profesional_id=p_prof and h.sede=p_sede and h.dia=extract(dow from d)::int
 )c;return r;
end$$;


--
-- Name: marathon_bonus_get(text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_bonus_get(p_id text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare bonus jsonb;rows jsonb;nxt jsonb;after_date date;after_time time;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or length(p_id)>100 or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta de bono inválida.';end if;
 select to_jsonb(b) into bonus from marathon.daily_bonus b where b.id=p_id;
 if bonus is null then raise sqlstate 'PT404' using message='Bono no encontrado.';end if;
 if p_after is not null then
  if jsonb_typeof(p_after)<>'object' or not(p_after?&array['fecha','hora','id']) or exists(select 1 from jsonb_object_keys(p_after)k where k<>all(array['fecha','hora','id'])) or exists(select 1 from jsonb_each(p_after)e where jsonb_typeof(e.value)<>'string') or coalesce(p_after->>'fecha','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or length(p_after->>'hora')>16 or length(p_after->>'id')>100 then raise sqlstate '22023' using message='Cursor inválido.';end if;
  begin after_date=(p_after->>'fecha')::date;after_time=(p_after->>'hora')::time;exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023' using message='Cursor inválido.';end;
 end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
 select m.id,m.fecha,m.hora,m.tipo,m.monto,m.medio,m.concepto,m.observaciones_legacy,coalesce(u.display_name,m.secretaria_legacy,'Sin registro') actor from marathon.movimientos m left join marathon.app_users u on u.user_id=m.created_by
 where m.bono_id=p_id and m.origen='BONO' and(p_after is null or(m.fecha,m.hora,m.id)<(after_date,after_time,p_after->>'id')) order by m.fecha desc,m.hora desc,m.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('bonus',bonus,'rows',rows,'next',nxt);
end $_$;


--
-- Name: marathon_booking_dates(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_booking_dates(p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare first_day date;last_day date;d date;site text;prof text;therapy text;hour_text text;patient text;
 fixed_dates date[];is_fixed boolean:=p_data?'fixed_until';wanted integer;days integer[];working integer[];duration integer;actual_duration integer;minute_of_day integer;slot record;
 available boolean;reason text;free integer;rows jsonb='[]'::jsonb;selected jsonb='[]'::jsonb;ok_count integer=0;row_count integer=0;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>4000 then raise sqlstate '22023' using message='Solicitud de fechas inválida.';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['from','sede','prof','therapy','hora','dni','count','days','fixed_until'])) then raise sqlstate '22023' using message='Campos no admitidos.';end if;
 first_day=marathon.agenda_date(p_data->>'from');last_day=least(first_day+729,date '2100-12-31');
 site=marathon.master_text(p_data,'sede',40,true);prof=marathon.master_text(p_data,'prof',100,true);therapy=marathon.master_text(p_data,'therapy',100,true);
 hour_text=marathon.master_text(p_data,'hora',5,true);patient=marathon.master_text(p_data,'dni',12,true);wanted=marathon.ortho_int(p_data,'count',1,60);
 if hour_text!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or patient!~'^[0-9]{1,12}$' or not exists(select 1 from marathon.pacientes where dni=patient) then raise sqlstate '22023' using message='Elegí un paciente y un horario válidos.';end if;
 if jsonb_typeof(p_data->'days') is distinct from 'array' then raise sqlstate '22023' using message='Elegí los días de atención.';end if;
 if jsonb_array_length(p_data->'days') not between 1 and 7 or exists(select 1 from jsonb_array_elements(p_data->'days') x where jsonb_typeof(x)<>'number' or x::text!~'^[0-6]$') then raise sqlstate '22023' using message='Días inválidos.';end if;
 select array_agg(distinct x::integer order by x::integer) into days from jsonb_array_elements_text(p_data->'days') x;
 if is_fixed then
  fixed_dates=marathon.fixed_dates(p_data->>'from',p_data->>'fixed_until',p_data->'days');last_day=marathon.agenda_date(p_data->>'fixed_until');wanted=cardinality(fixed_dates);
 end if;
 select t.duracion_min into duration from marathon.terapias t
 join marathon.profesional_terapias pt on pt.terapia_id=t.id and pt.profesional_id=prof
 join marathon.profesionales p on p.id=prof and p.estado='ACTIVO'
 join marathon.sedes s on s.nombre=site and s.estado='ACTIVO'
 where t.id=therapy and t.estado='ACTIVO';
 if duration is null then raise sqlstate '22023' using message='La terapia o el profesional ya no está disponible en esa sede.';end if;
 minute_of_day=(extract(epoch from hour_text::time)/60)::integer;
 select array_agg(distinct h.dia::integer order by h.dia::integer) into working from marathon.horarios h
 where h.profesional_id=prof and h.sede=site and h.inicio<=hour_text::time
 and minute_of_day+15<=(extract(epoch from h.fin)/60)::integer
 and (minute_of_day-(extract(epoch from h.inicio)/60)::integer)%15=0;
 if working is null or exists(select 1 from unnest(days) n where not n=any(working)) then raise sqlstate '22023' using message='El profesional no atiende ese horario en alguno de los días elegidos.';end if;
 for d in select first_day+n from generate_series(0,last_day-first_day) n where extract(dow from first_day+n)::integer=any(days) order by n loop
  actual_duration=marathon.session_minutes(d,site,prof,hour_text::time,duration);
  select * into slot from marathon.agenda_slots(d,site,prof,therapy) s where s.hora=hour_text;
  free=coalesce(slot.remaining,0);available=slot.hora is not null and free>0 and not coalesce(slot.blocked,true);
  reason=case when slot.hora is null then 'Fuera del horario de atención' when not available then 'Sin cupo' else free||' cupos libres' end;
  if exists(select 1 from marathon.turnos t where t.dni=patient and t.fecha=d and t.estado<>'CANCELADO'
   and (extract(epoch from t.hora)/60)::integer<minute_of_day+actual_duration
   and minute_of_day<(extract(epoch from t.hora)/60)::integer+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)) then
   available=false;reason='El paciente tiene un turno superpuesto';
  end if;
  rows=rows||jsonb_build_array(jsonb_build_object('fecha',d::text,'ok',available,'reason',reason,'remaining',free,'duration_min',actual_duration,'end_hour',to_char(hour_text::time+actual_duration*interval '1 minute','HH24:MI'),'shortened',actual_duration<duration));row_count=row_count+1;
  if available then ok_count=ok_count+1;if jsonb_array_length(selected)<wanted then selected=selected||jsonb_build_array(d::text);end if;end if;
  exit when not is_fixed and (ok_count>=wanted+4 or row_count>=200);
 end loop;
 return jsonb_build_object('rows',rows,'selected',selected,'working_days',to_jsonb(working),'complete',jsonb_array_length(selected)=wanted,'limited',row_count>=200,'count',wanted);
end $_$;


--
-- Name: marathon_cash_command(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_cash_command(p_request_id text, p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare reply jsonb;t marathon.turnos%rowtype;old marathon.movimientos%rowtype;m numeric;paid numeric;medium text;site text;dni text;concept text;obs text;reason text;kind text;origin text;id text;tid text;comp text;d date;after_data jsonb;category text;associated_prof text;associated_sec text;
begin
 reply=marathon.operation_begin(p_request_id,'cash:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action is null or p_action not in ('pay','refund','cash','reverse') or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case p_action when 'cash' then array['tipo','sede','dni','monto','medio','concepto','observaciones','fecha','categoria','profesional_asociado_id','secretaria_asociada'] when 'reverse' then array['id','version','motivo','fecha'] else array['id','version','monto','medio','observaciones','fecha'] end)) then raise sqlstate '22023' using message='Operación de caja inválida.';end if;
 d=case when coalesce(p_data->>'fecha','')='' then(now() at time zone 'America/Argentina/Buenos_Aires')::date else marathon.agenda_date(marathon.master_text(p_data,'fecha',10,true)) end;
 if p_action='reverse' then
  if not marathon.is_admin() then raise sqlstate '42501' using message='Solo ADMIN puede aprobar un contrasiento.';end if;
  reason=marathon.master_text(p_data,'motivo',1000,true);if length(reason)<3 then raise sqlstate '22023' using message='Indicá el motivo (3 a 1000 caracteres).';end if;
  select * into old from marathon.movimientos x where x.id=marathon.master_text(p_data,'id',100,true) for update;
  if old.id is null or old.compensacion_de is not null or not((old.tipo='PAGO' and old.origen='CLINICA' and old.turno_id is not null)or(old.origen='CAJA' and old.tipo in('INGRESO','EGRESO')))then raise sqlstate '22023' using message='Solo se corrigen cobros clínicos o movimientos manuales originales mediante contrasiento.';end if;
  if old.version<>marathon.operation_version(p_data) or exists(select 1 from marathon.movimientos where compensacion_de=old.id) then raise sqlstate 'PT409' using message='El cobro cambió o ya tiene contrasiento.';end if;
  if old.origen='CAJA'then
   m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;comp=old.id;kind=case when old.tipo='EGRESO'then'INGRESO'else'EGRESO'end;origin='CAJA';concept='Contrasiento de '||old.id;obs=reason;category=old.categoria;associated_prof=old.profesional_asociado_id;associated_sec=old.secretaria_asociada;
  else
  select * into t from marathon.turnos where turnos.id=old.turno_id for update;paid=marathon.turn_cash_paid(t.id);
  if paid<old.monto then raise sqlstate '22023' using message='Hay reintegros previos. El cobro completo no puede anularse; registrá el reintegro del saldo correspondiente.';end if;
  m=old.monto;medium=old.medio;site=old.sede;dni=old.dni;tid=old.turno_id;comp=old.id;kind='REINTEGRO';origin='CLINICA';concept='Contrasiento de '||old.id;obs=reason;
 end if;
 elsif p_action in ('pay','refund') then
  select * into t from marathon.turnos where turnos.id=marathon.master_text(p_data,'id',100,true) for update;
  if t.id is null then raise sqlstate 'PT404' using message='Turno no encontrado.';end if;
  if t.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir su cuenta.';end if;
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);paid=marathon.turn_paid(t.id);
  if p_action='pay' and(t.estado<>'PRESENTE' or m>t.importe-paid) then raise sqlstate '22023' using message='Solo se cobran turnos presentes y hasta su saldo pendiente.';end if;
  if p_action='refund' and m>marathon.turn_cash_paid(t.id) then raise sqlstate '22023' using message='El reintegro supera lo cobrado.';end if;
  site=t.sede;dni=t.dni;tid=t.id;kind=case when p_action='pay' then 'PAGO' else 'REINTEGRO' end;origin='CLINICA';concept=case when p_action='pay' then 'Cobro de turno' else 'Reintegro de turno' end;
 else
  m=marathon.operation_amount(p_data);medium=marathon.master_text(p_data,'medio',13,true);obs=marathon.master_text(p_data,'observaciones',1000);site=marathon.master_text(p_data,'sede',40,true);dni=nullif(marathon.master_text(p_data,'dni',12),'');concept=marathon.master_text(p_data,'concepto',200,true);kind=marathon.master_text(p_data,'tipo',7,true);origin='CAJA';
  if kind not in ('INGRESO','EGRESO') or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO') or(dni is not null and not exists(select 1 from marathon.pacientes p where p.dni=dni)) then raise sqlstate '22023' using message='Tipo, sede o paciente inválidos.';end if;
 end if;
 if p_action='cash'then
 category=nullif(marathon.master_text(p_data,'categoria',100),'');associated_prof=nullif(marathon.master_text(p_data,'profesional_asociado_id',100),'');associated_sec=nullif(marathon.master_text(p_data,'secretaria_asociada',100),'');
 if(associated_prof is not null and associated_sec is not null)or(associated_prof is not null and not exists(select 1 from marathon.profesionales pr where pr.id=associated_prof and pr.estado='ACTIVO'))or(associated_sec is not null and not exists(select 1 from marathon.secretarias where nombre=associated_sec and estado='ACTIVO'))then raise sqlstate '22023'using message='Elegí un profesional o una secretaria activos para asociar.';end if;
 end if;
 if medium not in ('EFECTIVO','TRANSFERENCIA') then raise sqlstate '22023' using message='Elegí el medio de pago.';end if;
 id='MOV-'||gen_random_uuid()::text;
 insert into marathon.movimientos(id,fecha,hora,origen,tipo,dni,monto,medio,sede,turno_id,concepto,observaciones_legacy,compensacion_de,motivo,created_by,updated_by,categoria,profesional_asociado_id,secretaria_asociada)
 values(id,d,(now() at time zone 'America/Argentina/Buenos_Aires')::time,origin,kind,dni,m,medium,site,tid,concept,obs,comp,reason,auth.uid(),auth.uid(),category,associated_prof,associated_sec);
 select to_jsonb(x) into after_data from marathon.movimientos x where x.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'movement',id,p_action,case when old.id is not null then to_jsonb(old) end,after_data);
 reply=jsonb_build_object('id',id,'message',case p_action when 'pay' then 'Cobro registrado.' when 'refund' then 'Reintegro registrado.' when 'reverse' then 'Contrasiento registrado. El cobro original se conserva.' else 'Movimiento de caja registrado.' end);
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $$;


--
-- Name: marathon_cash_list(text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_cash_list(p_fecha text, p_sede text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$
declare d date;rows jsonb;nxt jsonb;totals jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;d=marathon.agenda_date(p_fecha);
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['hora','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 if p_after is not null and coalesce(p_after->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9](\:[0-5][0-9](\.[0-9]{1,6})?)?$' then raise sqlstate '22023' using message='Cursor inválido.';end if;
 select coalesce(jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense)),'{}'::jsonb) into totals from(
 select medio,sum(case when tipo in ('PAGO','INGRESO') then monto else 0 end) income,sum(case when tipo in ('REINTEGRO','EGRESO') then monto else 0 end) expense from marathon.movimientos where fecha=d and origen in ('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO') and(coalesce(p_sede,'')='' or sede=p_sede) group by medio)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.hora,x.id),'[]'::jsonb) into rows from(
 select m.*,concat_ws(' ',p.apellido,p.nombre) paciente,u.display_name actor,exists(select 1 from marathon.movimientos r where r.compensacion_de=m.id) reversed from marathon.movimientos m left join marathon.pacientes p on p.dni=m.dni left join marathon.app_users u on u.user_id=m.created_by
 where m.fecha=d and m.origen in ('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO') and(coalesce(p_sede,'')='' or m.sede=p_sede) and(p_after is null or(m.hora,m.id)>((p_after->>'hora')::time,p_after->>'id')) order by m.hora,m.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $_$;


--
-- Name: marathon_cash_search(jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_cash_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d date;e date;rows jsonb;nxt jsonb;totals jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','medium','category','prof','actor'],p_limit,p_after);d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 if e<d or e-d>3660 or coalesce(p_filters->>'medium','')not in('','EFECTIVO','TRANSFERENCIA')or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Período o filtros de caja inválidos.';end if;
 with filtered as(select * from marathon.daily_cash where fecha between d and e and origen in('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO')and(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'medium','')=''or medio=p_filters->>'medium')and(coalesce(p_filters->>'category','')=''or category_key=p_filters->>'category')and(coalesce(p_filters->>'prof','')=''or professional_key=p_filters->>'prof')and(coalesce(p_filters->>'actor','')=''or actor_key=p_filters->>'actor')),
 page as(select * from filtered where p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')order by fecha,hora,id limit p_limit+1),
 sums as(select medio,coalesce(sum(monto)filter(where tipo in('PAGO','INGRESO')),0)income,coalesce(sum(monto)filter(where tipo in('EGRESO','REINTEGRO')),0)expense from filtered group by medio)
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,hora,id)from page x),'[]'::jsonb),coalesce((select jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense))from sums),'{}'::jsonb)into rows,totals;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $$;


--
-- Name: marathon_catalog_get(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_catalog_get(p_entity text, p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare r jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_entity='insurance' then select to_jsonb(t) into r from marathon.obras_sociales t where id=p_id;
 elsif p_entity='secretary' then select to_jsonb(t)||jsonb_build_object('id',nombre) into r from marathon.secretarias t where nombre=p_id;
 elsif p_entity='info' then select to_jsonb(t) into r from marathon.informacion_terapias t where id=p_id;
 else raise sqlstate '22023' using message='Catálogo inválido.';end if;
 if r is null then raise sqlstate 'PT404' using message='El registro ya no existe.';end if;return r;
end $$;


--
-- Name: marathon_catalog_list(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_catalog_list(p_entity text, p_query text DEFAULT ''::text, p_after text DEFAULT NULL::text, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare rows jsonb;next_id text;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_entity is null or p_entity not in ('insurance','secretary','info') or p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_query,''))>100 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by id),'[]'::jsonb) into rows from (
 select * from (
 select id,nombre label,estado,version from marathon.obras_sociales where p_entity='insurance'
 union all select nombre,nombre,estado,version from marathon.secretarias where p_entity='secretary'
 union all select i.id,t.nombre||' · '||coalesce(o.nombre,'Particular')||' · '||left(i.mensaje,80),i.estado,i.version from marathon.informacion_terapias i join marathon.terapias t on t.id=i.terapia_id left join marathon.obras_sociales o on o.id=i.obra_social_id where p_entity='info'
 ) q where (p_after is null or id>p_after) and (coalesce(p_query,'')='' or strpos(marathon.master_norm(label||' '||id),marathon.master_norm(p_query))>0) order by id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_id=rows->(p_limit-1)->>'id';end if;
 return jsonb_build_object('rows',rows,'next',next_id);
end $$;


--
-- Name: marathon_catalog_options(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_catalog_options() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if (select count(*) from marathon.obras_sociales)>500 then raise sqlstate '22023' using message='Hay más de 500 obras sociales; se requiere un selector con búsqueda.';end if;
 return public.marathon_master_options()||jsonb_build_object('insurances',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',nombre,'estado',estado) order by nombre,id) from marathon.obras_sociales),'[]'::jsonb));
end $$;


--
-- Name: marathon_catalog_save(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_catalog_save(p_request_id text, p_entity text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare r jsonb;old jsonb;saved jsonb;id text;name text;state text;therapy text;insurance text;message text;mail text;begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo el administrador puede mantener estos datos.';end if;
 r=marathon.operation_begin(p_request_id,'catalog:'||coalesce(p_entity,''),p_data);if not marathon.is_admin() then raise sqlstate '42501' using message='Solo administración.';end if;if r is not null then return r;end if;
 if p_entity is null or p_entity not in ('insurance','secretary','info') or exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_entity when 'insurance' then array['id','version','nombre','domicilio','localidad','cuit','observaciones','estado'] when 'secretary' then array['id','version','nombre','email','estado'] else array['id','version','terapia_id','obra_social_id','mensaje','estado'] end)) then raise sqlstate '22023' using message='Catálogo o campos inválidos.';end if;
 id=marathon.master_text(p_data,'id',150);state=marathon.master_text(p_data,'estado',8,true);
 if state not in ('ACTIVO','INACTIVO') then raise sqlstate '22023' using message='Estado inválido.';end if;
 if id<>'' then old=public.marathon_catalog_get(p_entity,id);if (old->>'version')::bigint<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El registro cambió. Volvé a abrirlo antes de guardar.';end if;
 elsif p_data ? 'version' then raise sqlstate '22023' using message='Un registro nuevo no admite versión.';end if;
 if p_entity in ('insurance','secretary') then
 name=marathon.master_text(p_data,'nombre',150,true);
 if p_entity='insurance' then
 if exists(select 1 from marathon.obras_sociales t where t.id<>id and marathon.master_norm(t.nombre)=marathon.master_norm(name)) then raise sqlstate '22023' using message='Ya existe una obra social con ese nombre.';end if;
 if old is null then id='OS-'||gen_random_uuid()::text;end if;
 if marathon.master_text(p_data,'cuit',20)<>'' and regexp_replace(p_data->>'cuit','[- ]','','g') !~ '^[0-9]{11}$' then raise sqlstate '22023' using message='El CUIT debe tener 11 dígitos.';end if;
 insert into marathon.obras_sociales(id,nombre,domicilio,localidad,cuit,observaciones,estado,created_by,updated_by) values(id,name,marathon.master_text(p_data,'domicilio',200),marathon.master_text(p_data,'localidad',100),marathon.master_text(p_data,'cuit',20),marathon.master_text(p_data,'observaciones',2000),state,auth.uid(),auth.uid()) on conflict on constraint obras_sociales_pkey do update set nombre=excluded.nombre,domicilio=excluded.domicilio,localidad=excluded.localidad,cuit=excluded.cuit,observaciones=excluded.observaciones,estado=excluded.estado;
 else
 if old is not null and name<>id then raise sqlstate '22023' using message='El nombre de un registro existente no se puede cambiar.';end if;
 if old is null and exists(select 1 from marathon.secretarias t where marathon.master_norm(t.nombre)=marathon.master_norm(name)) then raise sqlstate '22023' using message='Ya existe una secretaria con ese nombre.';end if;
 id=name;mail=marathon.master_text(p_data,'email',254);
 if mail<>'' and mail !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise sqlstate '22023' using message='Correo inválido.';end if;
 insert into marathon.secretarias(nombre,email,estado,created_by,updated_by) values(id,mail,state,auth.uid(),auth.uid()) on conflict on constraint secretarias_pkey do update set email=excluded.email,estado=excluded.estado;
 end if;
 else
 therapy=marathon.master_text(p_data,'terapia_id',100,true);insurance=nullif(marathon.master_text(p_data,'obra_social_id',100),'');message=marathon.master_text(p_data,'mensaje',4000,true);
 if not exists(select 1 from marathon.terapias t where t.id=therapy and (t.estado='ACTIVO' or old->>'terapia_id'=therapy)) or (insurance is not null and not exists(select 1 from marathon.obras_sociales o where o.id=insurance and (o.estado='ACTIVO' or old->>'obra_social_id'=insurance))) then raise sqlstate '22023' using message='Elegí una terapia y obra social válidas.';end if;
 if state='ACTIVO' and exists(select 1 from marathon.informacion_terapias i where i.id<>id and i.terapia_id=therapy and i.obra_social_id is not distinct from insurance and i.estado='ACTIVO') then raise sqlstate '22023' using message='Ya hay indicaciones activas para esa terapia y obra social.';end if;
 if old is null then id='INFO-'||gen_random_uuid()::text;end if;
 insert into marathon.informacion_terapias(id,terapia_id,obra_social_id,mensaje,estado,created_by,updated_by) values(id,therapy,insurance,message,state,auth.uid(),auth.uid()) on conflict on constraint informacion_terapias_pkey do update set terapia_id=excluded.terapia_id,obra_social_id=excluded.obra_social_id,mensaje=excluded.mensaje,estado=excluded.estado;
 end if;
 saved=public.marathon_catalog_get(p_entity,id);
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'catalog:'||p_entity,id,'save',old,saved);
 r=jsonb_build_object('id',id,'message','Datos guardados correctamente.');update marathon.solicitudes set resultado=r where solicitudes.id=p_request_id;return r;
end $_$;


--
-- Name: marathon_daily_options(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_daily_options() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 return public.marathon_catalog_options()||jsonb_build_object(
 'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',pr.id,'label',concat_ws(' ',pr.nombre,pr.apellido),'estado',pr.estado,'therapy_ids',coalesce((select jsonb_agg(pt.terapia_id order by pt.terapia_id)from marathon.profesional_terapias pt where pt.profesional_id=pr.id),'[]'::jsonb))order by pr.apellido,pr.nombre,pr.id)from marathon.profesionales pr),'[]'::jsonb),
 'actors',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',label)order by label,id)from(select user_id::text id,display_name label from marathon.app_users union select 'legacy:'||secretaria_legacy,secretaria_legacy from marathon.movimientos where created_by is null and secretaria_legacy is not null union select 'legacy:'||secretaria_legacy,secretaria_legacy from marathon.ortopedia_operaciones where created_by is null and secretaria_legacy is not null union select 'unknown','Sin registro')q),'[]'::jsonb),
 'secretaries',coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre,'estado',estado)order by nombre)from marathon.secretarias),'[]'::jsonb),
 'categories',coalesce((select jsonb_agg(jsonb_build_object('id','C:'||name,'label',name)order by name)from(select distinct coalesce(categoria,case when origen='ORTOPEDIA'then'Ortopedia'else'Otros'end)name from marathon.movimientos where origen<>'BONO' union select 'Otros' union select 'Ortopedia')q),'[]'::jsonb));
end $$;


--
-- Name: marathon_document_delete_begin(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_document_delete_begin(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
declare r jsonb;doc marathon.documentos%rowtype;begin
 r=marathon.operation_begin(p_request_id,'document:delete_begin',p_data);if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version'])) or coalesce(p_data->>'id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise sqlstate '22023' using message='Documento inválido.';end if;
 select * into doc from marathon.documentos where id=(p_data->>'id')::uuid for update;
 if not found then raise sqlstate 'PT404' using message='El documento ya no existe.';end if;
 if doc.estado<>'ELIMINADO' and doc.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El documento cambió. Volvé a abrir Documentos antes de eliminarlo.';end if;
 if doc.estado not in ('ELIMINADO','ELIMINANDO') then
 update marathon.documentos set estado='ELIMINANDO' where id=doc.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'document',doc.id::text,'delete_begin',jsonb_build_object('estado',doc.estado,'nombre',doc.nombre,'dni',doc.dni),jsonb_build_object('estado','ELIMINANDO'));
 end if;
 r=jsonb_build_object('id',doc.id,'path',doc.storage_path,'deleted',doc.estado='ELIMINADO');update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $_$;


--
-- Name: marathon_document_delete_finish(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_document_delete_finish(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
declare r jsonb;doc marathon.documentos%rowtype;begin
 r=marathon.operation_begin(p_request_id,'document:delete_finish',p_data);if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>'id') or coalesce(p_data->>'id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise sqlstate '22023' using message='Documento inválido.';end if;
 select * into doc from marathon.documentos where id=(p_data->>'id')::uuid for update;
 if not found then raise sqlstate 'PT404' using message='El documento ya no existe.';end if;
 if doc.estado not in ('ELIMINANDO','ELIMINADO') then raise sqlstate '22023' using message='Primero confirmá la eliminación desde la ficha.';end if;
 if doc.estado='ELIMINANDO' then
 if doc.storage_path is not null and exists(select 1 from storage.objects where bucket_id='marathon-patient-docs' and name=doc.storage_path) then raise sqlstate 'PT409' using message='El archivo todavía está almacenado. Volvé a verificar la eliminación.';end if;
 update marathon.documentos set estado='ELIMINADO',deleted_at=now(),deleted_by=auth.uid() where id=doc.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'document',doc.id::text,'delete',jsonb_build_object('estado','ELIMINANDO'),jsonb_build_object('estado','ELIMINADO','nombre',doc.nombre,'dni',doc.dni));
 end if;
 r=jsonb_build_object('id',doc.id,'message','Documento eliminado.');update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $_$;


--
-- Name: marathon_document_finish(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_document_finish(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
declare r jsonb;doc marathon.documentos%rowtype;meta jsonb;begin
 r=marathon.operation_begin(p_request_id,'document:finish',p_data);if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>'id') or coalesce(p_data->>'id','')!~'^[0-9a-f-]{36}$' then raise sqlstate '22023' using message='Documento inválido.';end if;
 select * into doc from marathon.documentos where id=(p_data->>'id')::uuid for update;
 if not found or (doc.estado='PENDIENTE' and doc.created_by<>auth.uid()) then raise sqlstate '42501' using message='Documento no habilitado.';end if;
 if doc.estado not in ('PENDIENTE','LISTO') then raise sqlstate 'PT409' using message='El documento se eliminó o está siendo eliminado.';end if;
 if doc.estado='PENDIENTE' then
 select metadata into meta from storage.objects where bucket_id='marathon-patient-docs' and name=doc.storage_path;
 if meta is null then raise sqlstate 'PT409' using message='Todavía no se confirmó la subida. Volvé a verificar el documento.';end if;
 if coalesce(meta->>'size','')!~'^[0-9]+$' or (meta->>'size')::bigint<>doc.bytes or meta->>'mimetype' is distinct from doc.mime then raise sqlstate '22023' using message='El archivo recibido no coincide con el tamaño y formato declarados.';end if;
 update marathon.documentos set estado='LISTO' where id=doc.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data) values(p_request_id,auth.uid(),'document',doc.id::text,'upload',jsonb_build_object('dni',doc.dni,'nombre',doc.nombre,'bytes',doc.bytes,'sha256_cliente',doc.sha256));
 end if;
 r=jsonb_build_object('id',doc.id,'message','Documento guardado.');update marathon.solicitudes set resultado=r where solicitudes.id=p_request_id;return r;
end $_$;


--
-- Name: marathon_document_list(text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_document_list(p_dni text, p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare rows jsonb;next_id uuid;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 then raise sqlstate '22023' using message='Límite inválido.';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]'::jsonb) into rows from(select id,nombre,storage_path,legacy_url,mime,bytes,created_at,estado,upload_expires,version from marathon.documentos where dni=p_dni and (estado in ('LISTO','ELIMINANDO') or (estado='PENDIENTE' and created_by=(select auth.uid()))) and (p_after is null or id>p_after) order by id limit p_limit+1)q;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_id=(rows->(p_limit-1)->>'id')::uuid;end if;
 return jsonb_build_object('rows',rows,'next',next_id);
end $$;


--
-- Name: marathon_document_prepare(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_document_prepare(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare r jsonb;doc marathon.documentos%rowtype;dni text;name text;mime text;hash text;size bigint;ext text;begin
 r=marathon.operation_begin(p_request_id,'document:prepare',p_data);if r is not null then if exists(select 1 from marathon.documentos where id=(r->>'id')::uuid and estado in ('ELIMINANDO','ELIMINADO')) then raise sqlstate 'PT409' using message='Este documento fue eliminado o está siendo eliminado. Elegí nuevamente el archivo para cargarlo otra vez.';end if;return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['dni','nombre','mime','sha256','bytes'])) then raise sqlstate '22023' using message='Campos de documento inválidos.';end if;
 dni=marathon.master_text(p_data,'dni',12,true);name=marathon.master_text(p_data,'nombre',180,true);mime=marathon.master_text(p_data,'mime',150,true);hash=marathon.master_text(p_data,'sha256',64,true);ext=lower(substring(name from '\.([^.]+)$'));
 if not exists(select 1 from marathon.pacientes p where p.dni=dni) or name ~ '[/\\[:cntrl:]]' or hash !~ '^[0-9a-f]{64}$' or jsonb_typeof(p_data->'bytes') is distinct from 'number' or coalesce(p_data->>'bytes','') !~ '^[0-9]{1,8}$' then raise sqlstate '22023' using message='Documento o paciente inválido.';end if;
 size=(p_data->>'bytes')::bigint;
 if size not between 1 and 5242880 or ext is null or not ((ext='pdf' and mime='application/pdf') or (ext='doc' and mime='application/msword') or (ext='docx' and mime='application/vnd.openxmlformats-officedocument.wordprocessingml.document')) then raise sqlstate '22023' using message='Solo PDF, DOC y DOCX, de hasta 5 MB.';end if;
 select * into doc from marathon.documentos t where t.dni=dni and t.sha256=hash and t.bytes=size and (t.estado='LISTO' or (t.estado='PENDIENTE' and t.created_by=auth.uid() and t.upload_expires>now())) order by (t.estado='LISTO') desc,t.created_at limit 1;
 if not found then
 doc.id=gen_random_uuid();doc.storage_path='patients/'||doc.id::text||'/attachment.'||ext;
 insert into marathon.documentos(id,dni,nombre,storage_path,mime,sha256,bytes,estado,upload_expires,created_by,updated_by) values(doc.id,dni,name,doc.storage_path,mime,hash,size,'PENDIENTE',now()+interval '24 hours',auth.uid(),auth.uid()) returning * into doc;
 end if;
 r=jsonb_build_object('id',doc.id,'path',doc.storage_path,'ready',doc.estado='LISTO');update marathon.solicitudes set resultado=r where solicitudes.id=p_request_id;return r;
end $_$;


--
-- Name: marathon_extension_context(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_extension_context(p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare t marathon.turnos;last_date date;local_now timestamp:=(statement_timestamp() at time zone 'America/Argentina/Buenos_Aires');begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or length(p_id) not between 1 and 200 then raise sqlstate '22023' using message='Seleccioná un turno válido.';end if;
 select * into t from marathon.turnos where id=p_id;
 if t.id is null then raise sqlstate 'P0002' using message='El turno ya no está disponible. Actualizá la planilla.';end if;
 select max(fecha) into last_date from marathon.turnos where dni=t.dni and terapia_id=t.terapia_id and estado in('PENDIENTE','PRESENTE');
 return jsonb_build_object('dni',t.dni,'sede',t.sede,'prof',t.profesional_id,'therapy',t.terapia_id,
  'hora',to_char(t.hora,'HH24:MI'),'source_date',t.fecha,'after_date',greatest(local_now::date+case when t.hora<=local_now::time then 1 else 0 end,coalesce(last_date+1,local_now::date)),
  'last_date',last_date,'days',case when jsonb_typeof(t.series_pattern->'days')='array' and t.series_pattern->'days'<>'[]'::jsonb then t.series_pattern->'days' when cardinality(t.fixed_days)>0 then to_jsonb(t.fixed_days) else jsonb_build_array(extract(dow from t.fecha)::int) end,
  'importe',t.importe,'coverage',t.coverage,'booking_notes',coalesce(t.booking_notes,''));
end $$;


--
-- Name: marathon_management(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_management(p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare
  cut timestamp := statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
  d date; e date; w date; site text; therapy text; professional text;
  activity jsonb; activity_rows jsonb; professional_rows jsonb; cash jsonb;
  balances jsonb; inventory jsonb; capacity jsonb;
begin
  if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
  if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000
    or exists(select 1 from jsonb_object_keys(p_filters) k where k<>all(array['month','sede','therapy','professional','week_start']))
    or coalesce(p_filters->>'month','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$'
  then raise sqlstate '22023' using message='Elegí un mes válido y filtros de Gestión.'; end if;
  d := (p_filters->>'month'||'-01')::date; e := (d+interval '1 month')::date;
  site := coalesce(p_filters->>'sede',''); therapy := coalesce(p_filters->>'therapy','');
  professional := coalesce(p_filters->>'professional','');
  w := coalesce(nullif(p_filters->>'week_start','')::date, date_trunc('week',cut)::date-7);
  if extract(isodow from w)<>1 or w+7>cut::date or w<date '2000-01-01' then
    raise sqlstate '22023' using message='Para tiempo profesional elegí un lunes de una semana completa ya terminada.';
  end if;
  with finished as (
    select t.* from marathon.turnos t where t.fecha>=d and t.fecha<e
      and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy)
      and (professional='' or t.profesional_id=professional)
  ), grouped as (
    select t.terapia_id,th.nombre terapia,count(*) total,
      count(*) filter(where t.estado='PRESENTE') present,
      count(distinct t.dni) filter(where t.estado='PRESENTE') patients,
      count(*) filter(where t.estado='AUSENTE') absent,
      count(*) filter(where t.estado='AUSENTE' and t.attendance_auto) auto_absent,
      count(*) filter(where t.estado='PENDIENTE') pending,
      count(*) filter(where t.estado='CANCELADO') cancelled
    from finished t join marathon.terapias th on th.id=t.terapia_id group by t.terapia_id,th.nombre
  ) select jsonb_build_object('total',count(*),'present',count(*) filter(where estado='PRESENTE'),
      'patients',count(distinct dni) filter(where estado='PRESENTE'),
      'absent',count(*) filter(where estado='AUSENTE'),
      'auto_absent',count(*) filter(where estado='AUSENTE' and attendance_auto),
      'pending',count(*) filter(where estado='PENDIENTE'),'cancelled',count(*) filter(where estado='CANCELADO'),
      'attendance',round(100.0*count(*) filter(where estado='PRESENTE')/nullif(count(*) filter(where estado in ('PRESENTE','AUSENTE')),0),2),
      'coverage',round(100.0*count(*) filter(where estado in ('PRESENTE','AUSENTE'))/nullif(count(*) filter(where estado in ('PRESENTE','AUSENTE','PENDIENTE')),0),2)),
    (select coalesce(jsonb_agg(to_jsonb(g) order by terapia),'[]'::jsonb) from grouped g)
    into activity,activity_rows from finished;
  with finished as (
    select t.* from marathon.turnos t where t.fecha>=d and t.fecha<e
      and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy)
      and (professional='' or t.profesional_id=professional)
  ) select coalesce(jsonb_agg(to_jsonb(q) order by profesional),'[]'::jsonb) into professional_rows from (
    select p.id,concat_ws(' ',p.nombre,p.apellido) profesional,t.sede,
      count(*) filter(where t.estado='PRESENTE') atenciones,
      count(distinct t.dni) filter(where t.estado='PRESENTE') personas
    from finished t join marathon.profesionales p on p.id=t.profesional_id group by p.id,t.sede
  )q;
  with m as (
    select m.* from marathon.movimientos m
    left join marathon.turnos t on t.id=m.turno_id
    left join marathon.bonos_serie b on b.id=m.bono_id
    left join marathon.anticipos a on a.id=m.anticipo_id
    where m.fecha>=d and m.fecha<e and m.fecha+m.hora<=cut
      and (site='' or m.sede=site) and (therapy='' or coalesce(t.terapia_id,b.terapia_id,a.terapia_id)=therapy)
      and (professional='' or coalesce(t.profesional_id,b.profesional_id,a.profesional_id,m.profesional_asociado_id)=professional)
  ), grouped as (
    select medio,origen,count(*) movimientos,
      coalesce(sum(monto) filter(where tipo in ('INGRESO','PAGO')),0) entradas,
      coalesce(sum(monto) filter(where tipo in ('EGRESO','REINTEGRO')),0) salidas
    from m group by medio,origen
  ) select jsonb_build_object('count',count(*),
    'income',coalesce(sum(monto) filter(where tipo in ('INGRESO','PAGO')),0),
    'expense',coalesce(sum(monto) filter(where tipo in ('EGRESO','REINTEGRO')),0),
    'net',coalesce(sum(case when tipo in ('INGRESO','PAGO') then monto when tipo in ('EGRESO','REINTEGRO') then -monto else 0 end),0),
    'compensations',count(*) filter(where compensacion_de is not null),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by origen,medio),'[]'::jsonb) from grouped g)) into cash from m;
  with payments as (
    select turno_id,bono_id,operacion_id,origen,
      sum(case when tipo in ('REINTEGRO','EGRESO') then -monto when tipo in ('PAGO','INGRESO') then monto else 0 end) paid
    from marathon.movimientos where fecha+hora<=cut group by turno_id,bono_id,operacion_id,origen
  ), turnpayments as (select turno_id,sum(paid) paid from payments where turno_id is not null group by turno_id),
  bonuspayments as (select bono_id,sum(paid) paid from payments where bono_id is not null and origen='BONO' group by bono_id),
  orthopayments as (select operacion_id,sum(paid) paid from payments where operacion_id is not null and origen='ORTOPEDIA' group by operacion_id),
  advances as (
    select turno_id,sum(case when tipo='APLICACION' then monto when tipo='REVERSO' then -monto else 0 end) paid
    from marathon.anticipo_eventos where created_at<=statement_timestamp() group by turno_id
  ), charges as (
    select 'Sesiones' origen,t.fecha, t.importe amount,coalesce(p.paid,0)+coalesce(a.paid,0) paid
    from marathon.turnos t left join turnpayments p on p.turno_id=t.id left join advances a on a.turno_id=t.id
    where t.estado='PRESENTE' and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
      and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy) and (professional='' or t.profesional_id=professional)
    union all
    select 'Bonos',b.fecha,b.importe,coalesce(p.paid,0) from marathon.bonos_serie b left join bonuspayments p on p.bono_id=b.id
    where b.estado='ACTIVO' and b.fecha+b.hora<=cut and (site='' or b.sede=site)
      and (therapy='' or b.terapia_id=therapy) and (professional='' or b.profesional_id=professional)
    union all
    select 'Ortopedia',o.fecha,o.importe_total,coalesce(p.paid,0) from marathon.ortopedia_operaciones o left join orthopayments p on p.operacion_id=o.id
    where o.tipo in ('VENTA','ALQUILER') and o.fecha+o.hora<=cut and (site='' or o.sede=site) and therapy='' and professional=''
  ), debts as (
    select *,greatest(0,amount-paid) balance,case when cut::date-fecha<=30 then '0–30 días' when cut::date-fecha<=60 then '31–60 días' when cut::date-fecha<=90 then '61–90 días' else 'Más de 90 días' end age from charges
  ), grouped as (select origen,age,count(*) cantidad,sum(balance) saldo from debts where balance>0 group by origen,age)
  select jsonb_build_object('total',coalesce(sum(balance),0),'count',count(*) filter(where balance>0),
    'charges',count(*),'overpaid',count(*) filter(where paid>amount),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by origen,age),'[]'::jsonb) from grouped g)) into balances from debts;
  with stock as (
    select producto_id,sede,sum(case when tipo in ('STOCK_INICIAL','COMPRA','AJUSTE_POSITIVO','DEVOLUCION') then cantidad else -cantidad end) stock
    from marathon.ortopedia_operaciones where fecha+hora<=cut group by producto_id,sede
  ), pairs as (
    select c.producto_id,concat_ws(' · ',p.pieza,nullif(p.descripcion,''),nullif(p.codigo,'')) producto,p.modalidad,c.sede,c.minimo,c.initial_loaded,coalesce(s.stock,0) stock
    from marathon.stock_config c join marathon.productos p on p.id=c.producto_id
    join marathon.sedes sd on sd.nombre=c.sede left join stock s on s.producto_id=c.producto_id and s.sede=c.sede
    where p.estado='ACTIVO' and sd.estado='ACTIVO' and (site='' or c.sede=site)
  ), grouped as (
    select sede,count(*) total,count(*) filter(where initial_loaded) initialized,
      count(*) filter(where not initial_loaded) unknown,
      count(*) filter(where initial_loaded and stock<=minimo) alerts,
      count(*) filter(where initial_loaded and stock<=0) empty,
      count(*) filter(where initial_loaded and stock<0) negative from pairs group by sede
  ) select jsonb_build_object('total',count(*),'initialized',count(*) filter(where initial_loaded),
    'unknown',count(*) filter(where not initial_loaded),'alerts',count(*) filter(where initial_loaded and stock<=minimo),
    'empty',count(*) filter(where initial_loaded and stock<=0),'negative',count(*) filter(where initial_loaded and stock<0),
    'percentage',round(100.0*count(*) filter(where initial_loaded and stock<=minimo)/nullif(count(*) filter(where initial_loaded),0),2),
    'rows',(select coalesce(jsonb_agg(to_jsonb(g) order by sede),'[]'::jsonb) from grouped g),
    'details',(select coalesce(jsonb_agg(to_jsonb(x) order by sede,producto),'[]'::jsonb) from pairs x)) into inventory from pairs;
  -- Union of professional minutes, including overlapping/group appointments only once.
  with days as (select w+i as work_date from generate_series(0,6)i),
  offered as (
    select h.profesional_id,h.sede,days.work_date,range_agg(tsrange(days.work_date+h.inicio,days.work_date+h.fin,'[)')) ranges
    from days join marathon.horarios h on h.dia=extract(isodow from days.work_date)
    join marathon.profesionales p on p.id=h.profesional_id join marathon.sedes s on s.nombre=h.sede
    where h.fin>h.inicio and p.estado='ACTIVO' and s.estado='ACTIVO'
      and (site='' or h.sede=site) and (professional='' or h.profesional_id=professional)
    group by h.profesional_id,h.sede,days.work_date
  ), booked as (
    select t.profesional_id,t.sede,t.fecha,
      range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)')) filter(where estado in ('PENDIENTE','PRESENTE')) ranges,
      range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)')) filter(where estado='PRESENTE') attended
    from marathon.turnos t where t.fecha>=w and t.fecha<w+7 and t.estado in ('PENDIENTE','PRESENTE')
      and (site='' or t.sede=site) and (professional='' or t.profesional_id=professional) group by t.profesional_id,t.sede,t.fecha
  ), intersections as (
    select o.*,o.ranges*coalesce(b.ranges,'{}'::tsmultirange) used,o.ranges*coalesce(b.attended,'{}'::tsmultirange) attended
    from offered o left join booked b on b.profesional_id=o.profesional_id and b.sede=o.sede and b.fecha=o.work_date
  ), per_professional as (
    select profesional_id,range_agg(r) offered from offered cross join lateral unnest(ranges)r group by profesional_id
  ), per_used as (
    select profesional_id,range_agg(r) used from intersections cross join lateral unnest(used)r group by profesional_id
  ), per_attended as (
    select profesional_id,range_agg(r) attended from intersections cross join lateral unnest(attended)r group by profesional_id
  ), mins as (
    select p.profesional_id,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(p.offered)r) available,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(u.used)r) used,
      (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0) from unnest(a.attended)r) attended
    from per_professional p left join per_used u using(profesional_id) left join per_attended a using(profesional_id)
  ), rows as (
    select m.*,concat_ws(' ',p.nombre,p.apellido) profesional,round(100*used/nullif(available,0),2) usage
    from mins m join marathon.profesionales p on p.id=m.profesional_id
  ) select jsonb_build_object('week_start',w,'week_end',w+6,'available',coalesce(sum(available),0),
    'used',coalesce(sum(used),0),'attended',coalesce(sum(attended),0),'professionals',count(*),
    'usage',round(100*sum(used)/nullif(sum(available),0),2),
    'attendance',round(100*sum(attended)/nullif(sum(available),0),2),
    'rows',coalesce(jsonb_agg(to_jsonb(rows) order by profesional),'[]'::jsonb),
    'outside', (select count(*) from marathon.turnos t where t.fecha>=w and t.fecha<w+7 and t.estado in ('PENDIENTE','PRESENTE')
      and (site='' or t.sede=site) and (professional='' or t.profesional_id=professional)
      and not exists(select 1 from offered o where o.profesional_id=t.profesional_id and o.sede=t.sede and o.work_date=t.fecha
        and o.ranges @> tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)'))),
    'site_conflicts',(select count(*) from offered a join offered b on a.profesional_id=b.profesional_id and a.work_date=b.work_date and a.sede<b.sede and a.ranges&&b.ranges)
    ) into capacity from rows;
  return jsonb_build_object('generated_at',statement_timestamp(),'cut_local',cut,'month',to_char(d,'YYYY-MM'),
    'activity',activity,'therapies',activity_rows,'professionals',professional_rows,'cash',cash,'balances',balances,'inventory',inventory,'capacity',capacity);
end;
$_$;


--
-- Name: marathon_master_get(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_master_get(p_entity text, p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare result jsonb; begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
 if p_entity='sede' then select to_jsonb(s) into result from marathon.sedes s where nombre=p_id;
 elsif p_entity='therapy' then select to_jsonb(t) into result from marathon.terapias t where id=p_id;
 elsif p_entity='professional' then
  select to_jsonb(p)||jsonb_build_object('therapy_ids',coalesce((select jsonb_agg(terapia_id order by terapia_id) from marathon.profesional_terapias where profesional_id=p.id),'[]'::jsonb),
   'hours',coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'sede',h.sede,'day',h.dia,'start',to_char(h.inicio,'HH24:MI'),'end',to_char(h.fin,'HH24:MI')) order by h.dia,h.inicio,h.id) from marathon.horarios h where h.profesional_id=p.id),'[]'::jsonb))
   into result from marathon.profesionales p where id=p_id;
 else raise sqlstate '22023' using message='Entidad inválida.'; end if;
 if result is null then raise sqlstate 'PT404' using message='El registro ya no existe.';end if;return result;
end $$;


--
-- Name: marathon_master_list(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_master_list(p_entity text, p_query text DEFAULT ''::text, p_after text DEFAULT NULL::text, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare rows jsonb; next_id text; begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.'; end if;
 if p_entity is null or p_entity not in ('sede','therapy','professional') or p_limit is null or p_limit<1 or p_limit>100 or length(coalesce(p_query,''))>100 then
  raise sqlstate '22023' using message='Consulta inválida.'; end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into rows from (
  select * from (
   select nombre id,nombre label,estado,version from marathon.sedes where p_entity='sede'
   union all select id,nombre,estado,version from marathon.terapias where p_entity='therapy'
   union all select id,concat_ws(' ',nombre,nullif(segundo_nombre,''),apellido),estado,version from marathon.profesionales where p_entity='professional'
  ) all_rows where (p_after is null or id>p_after) and
   (coalesce(p_query,'')='' or strpos(marathon.master_norm(label||' '||id),marathon.master_norm(p_query))>0)
  order by id limit p_limit+1
 ) x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_id=rows->(p_limit-1)->>'id';end if;
 return jsonb_build_object('rows',rows,'next',next_id);
end $$;


--
-- Name: marathon_master_options(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_master_options() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if (select count(*) from marathon.terapias)>500 or (select count(*) from marathon.sedes)>500 then
  raise sqlstate '22023' using message='El catálogo supera el límite de este selector. Se requiere búsqueda paginada para seleccionar relaciones.';end if;
 return jsonb_build_object('sedes',coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre,'estado',estado) order by nombre) from marathon.sedes),'[]'::jsonb),
 'therapies',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',nombre,'estado',estado) order by nombre,id) from marathon.terapias),'[]'::jsonb));
end $$;


--
-- Name: marathon_master_preview(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_master_preview(p_entity text, p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo el administrador puede mantener los datos maestros.';end if;
 if p_entity is null or p_entity not in ('sede','therapy','professional') then raise sqlstate '22023' using message='Entidad inválida.';end if;
 return marathon.master_impact(p_entity,p_id);
end $$;


--
-- Name: marathon_master_save(text, text, jsonb, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_master_save(p_request_id text, p_entity text, p_data jsonb, p_version bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare uid uuid:=auth.uid();req marathon.solicitudes%rowtype;body_hash text;old jsonb;saved jsonb;reply jsonb;impact jsonb;
 id text;name text;second_name text;surname text;spec text;mat text;status text;addr text;phone text;obs text;prefix text;
 n bigint;duration integer;capacity integer;h jsonb;item jsonb;wanted text[];seen text[]:=array[]::text[];hid text;
 day_num integer;start_at time;end_at time;site text;hours_data jsonb;links_data jsonb;
begin
 perform 1 from marathon.app_users where user_id=uid and active and role='ADMIN' for share;
 if not found then raise sqlstate '42501' using message='Solo el administrador puede mantener los datos maestros.';end if;
 if p_entity is null or p_entity not in ('sede','therapy','professional') or p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then
  raise sqlstate '22023' using message='Solicitud inválida.';end if;
 body_hash=encode(sha256(convert_to(jsonb_build_object('entity',p_entity,'data',p_data,'version',p_version)::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_request_id,uid,'master:'||p_entity,body_hash) on conflict on constraint solicitudes_pkey do nothing;
 select * into req from marathon.solicitudes requests where requests.id=p_request_id for update;
 if req.id is null or req.usuario_id<>uid or req.tipo<>'master:'||p_entity or req.payload_hash<>body_hash then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if req.resultado is not null then return req.resultado;end if;
 -- Tres usuarios y catálogos pequeños: serialización administrativa simple, evita carreras de IDs y duplicados.
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(case p_entity
  when 'sede' then array['id','nombre','direccion','telefono','estado','observaciones','inactive_token']
  when 'therapy' then array['id','nombre','especialidad','duracion_min','capacidad','estado','inactive_token']
  else array['id','nombre','segundo_nombre','apellido','matricula','especialidad','estado','therapy_ids','hours','inactive_token'] end)) then
  raise sqlstate '22023' using message='La solicitud contiene campos no admitidos.';end if;
 id=marathon.master_text(p_data,'id',100);status=marathon.master_text(p_data,'estado',8,true);
 if status not in ('ACTIVO','INACTIVO') or (p_version is not null and p_version<1) then raise sqlstate '22023' using message='Estado o versión inválidos.';end if;
 if p_version is not null then
  if id='' then raise sqlstate '22023' using message='Falta el identificador.';end if;
  if p_entity='sede' then perform 1 from marathon.sedes s where s.nombre=id for update;
  elsif p_entity='therapy' then perform 1 from marathon.terapias t where t.id=id for update;
  else perform 1 from marathon.profesionales p where p.id=id for update;end if;
  old=public.marathon_master_get(p_entity,id);
  if (old->>'version')::bigint<>p_version then raise sqlstate 'PT409' using message='El registro cambió. Volvé a abrirlo antes de guardar.';end if;
 else
  if id<>'' then raise sqlstate '22023' using message='Los IDs nuevos se generan automáticamente.';end if;
 end if;
 if p_version is not null and old->>'estado'='ACTIVO' and status='INACTIVO' then
  impact=marathon.master_impact(p_entity,id);
  if impact->>'token' is not null and coalesce(p_data->>'inactive_token','')<>impact->>'token' then
   raise sqlstate 'PT409' using message='Cambió el impacto de la inactivación. Revisá nuevamente los turnos futuros y la lista de espera.';end if;
 end if;
 if p_entity='sede' then
  name=case when old is null then upper(marathon.master_text(p_data,'nombre',40,true)) else old->>'nombre' end;
  if old is not null and marathon.master_text(p_data,'nombre',40,true)<>name then raise sqlstate '22023' using message='El nombre de una sede existente no se puede cambiar.';end if;
  if old is null and (length(regexp_replace(name,'\s','','g'))<3 or exists(select 1 from marathon.sedes where marathon.master_norm(nombre)=marathon.master_norm(name) or left(regexp_replace(nombre,'\s','','g'),3)=left(regexp_replace(name,'\s','','g'),3))) then
   raise sqlstate '22023' using message='La sede ya existe o comparte sus primeras tres letras con otra sede.';end if;
  if status='INACTIVO' and not exists(select 1 from marathon.sedes where nombre<>name and estado='ACTIVO') then raise sqlstate '22023' using message='Tiene que quedar al menos una sede activa.';end if;
  addr=marathon.master_text(p_data,'direccion',160);phone=marathon.master_text(p_data,'telefono',30);obs=marathon.master_text(p_data,'observaciones',300);
  if phone<>'' and phone !~ '^[0-9[:space:]()+-]{6,30}$' then raise sqlstate '22023' using message='El teléfono de la sede no es válido.';end if;
  id=name;
  insert into marathon.sedes(nombre,direccion,telefono,estado,observaciones,created_by,updated_by) values(id,addr,phone,status,obs,uid,uid)
  on conflict(nombre) do update set direccion=excluded.direccion,telefono=excluded.telefono,estado=excluded.estado,observaciones=excluded.observaciones;
 elsif p_entity='therapy' then
  name=marathon.master_text(p_data,'nombre',100,true);spec=marathon.master_text(p_data,'especialidad',100);
  if exists(select 1 from marathon.terapias t where (old is null or t.id<>id) and marathon.master_norm(t.nombre)=marathon.master_norm(name)) then raise sqlstate '22023' using message='Ya existe una terapia con ese nombre.';end if;
  if jsonb_typeof(p_data->'duracion_min') is distinct from 'number' or jsonb_typeof(p_data->'capacidad') is distinct from 'number' or (p_data->>'duracion_min') !~ '^[0-9]{1,3}$' or (p_data->>'capacidad') !~ '^[0-9]{1,3}$' then raise sqlstate '22023' using message='Duración y capacidad deben ser números enteros.';end if;
  duration=(p_data->>'duracion_min')::integer;capacity=(p_data->>'capacidad')::integer;
  if duration not between 5 and 480 or capacity not between 1 and 200 then raise sqlstate '22023' using message='Duración: 5 a 480 minutos. Capacidad: 1 a 200 pacientes.';end if;
  if old is null then select coalesce(max(substring(t.id from '^TER([0-9]+)$')::bigint),0)+1 into n from marathon.terapias t;id='TER'||lpad(n::text,greatest(5,length(n::text)),'0');end if;
  insert into marathon.terapias(id,especialidad,nombre,duracion_min,capacidad,estado,created_by,updated_by) values(id,spec,name,duration,capacity,status,uid,uid)
  on conflict on constraint terapias_pkey do update set especialidad=excluded.especialidad,nombre=excluded.nombre,duracion_min=excluded.duracion_min,capacidad=excluded.capacidad,estado=excluded.estado;
 else
  name=marathon.master_text(p_data,'nombre',60,true);second_name=marathon.master_text(p_data,'segundo_nombre',60);surname=marathon.master_text(p_data,'apellido',60,true);spec=marathon.master_text(p_data,'especialidad',80,true);mat=marathon.master_text(p_data,'matricula',40);
  if exists(select 1 from marathon.profesionales p where (old is null or p.id<>id) and marathon.master_norm(concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido))=marathon.master_norm(concat_ws(' ',name,nullif(second_name,''),surname))) then raise sqlstate '22023' using message='Ya existe un profesional con ese nombre y apellido.';end if;
  if jsonb_typeof(p_data->'therapy_ids') is distinct from 'array' or jsonb_typeof(p_data->'hours') is distinct from 'array' or jsonb_array_length(p_data->'hours')>40 then raise sqlstate '22023' using message='Seleccioná terapias y hasta 40 horarios.';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'therapy_ids') x where jsonb_typeof(x)<>'string') then raise sqlstate '22023' using message='Identificador de terapia inválido.';end if;
  select coalesce(array_agg(distinct value),array[]::text[]) into wanted from jsonb_array_elements_text(p_data->'therapy_ids');
  if exists(select 1 from unnest(wanted) t where not exists(select 1 from marathon.terapias where terapias.id=t)) then raise sqlstate '22023' using message='Una terapia elegida ya no existe.';end if;
  if old is null then
   prefix=upper(coalesce(nullif(left(regexp_replace(marathon.master_norm(name),'[^a-z]','','g'),1),''),'x')||coalesce(nullif(left(regexp_replace(marathon.master_norm(surname),'[^a-z]','','g'),1),''),'x')||coalesce(nullif(left(regexp_replace(marathon.master_norm(spec),'[^a-z]','','g'),1),''),'x'));
   n=1;while exists(select 1 from marathon.profesionales p where upper(p.id)=prefix||lpad(n::text,greatest(2,length(n::text)),'0')) loop n=n+1;end loop;
   id=prefix||lpad(n::text,greatest(2,length(n::text)),'0');
  end if;
  -- Validar todos los horarios ANTES de escribir. Los tramos contiguos son válidos.
  for h in select value from jsonb_array_elements(p_data->'hours') loop
   if jsonb_typeof(h)<>'object' or exists(select 1 from jsonb_object_keys(h) k where k<>all(array['id','sede','day','start','end'])) then raise sqlstate '22023' using message='Formato de horario inválido.';end if;
   site=marathon.master_text(h,'sede',40,true);
   if not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO') then raise sqlstate '22023' using message='Elegí una sede activa en cada horario.';end if;
   if jsonb_typeof(h->'day') is distinct from 'number' or (h->>'day') !~ '^[0-6]$' or coalesce(h->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(h->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise sqlstate '22023' using message='Día u hora inválidos.';end if;
   start_at=(h->>'start')::time;end_at=(h->>'end')::time;
   if end_at<=start_at then raise sqlstate '22023' using message='La hora de fin debe ser posterior a la de inicio.';end if;
   hid=marathon.master_text(h,'id',100);
   if hid<>'' then
    if old is null or hid=any(seen) or not exists(select 1 from marathon.horarios where horarios.id=hid and profesional_id=id) then raise sqlstate '22023' using message='El horario cambió o pertenece a otro profesional.';end if;seen=array_append(seen,hid);
   end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_data->'hours') with ordinality a(h,i) cross join jsonb_array_elements(p_data->'hours') with ordinality b(h,i)
   where a.i<b.i and a.h->>'day'=b.h->>'day' and (a.h->>'start')::time<(b.h->>'end')::time and (b.h->>'start')::time<(a.h->>'end')::time) then
   raise sqlstate '22023' using message='Los horarios se superponen, aunque sean sedes diferentes.';end if;
  insert into marathon.profesionales(id,nombre,segundo_nombre,apellido,matricula,especialidad,estado,created_by,updated_by) values(id,name,second_name,surname,mat,spec,status,uid,uid)
  on conflict on constraint profesionales_pkey do update set nombre=excluded.nombre,segundo_nombre=excluded.segundo_nombre,apellido=excluded.apellido,matricula=excluded.matricula,especialidad=excluded.especialidad,estado=excluded.estado;
  delete from marathon.profesional_terapias where profesional_id=id and not (terapia_id=any(wanted));
  insert into marathon.profesional_terapias(profesional_id,terapia_id,created_by,updated_by) select id,t,uid,uid from unnest(wanted) t on conflict do nothing;
  -- El estado anterior de relaciones/horarios se conserva en auditoría, aun al retirar un tramo.
  select coalesce(max(substring(hh.id from '^HOR([0-9]+)$')::bigint),0) into n from marathon.horarios hh;
  delete from marathon.horarios where profesional_id=id and not (horarios.id=any(seen));
  for h in select value from jsonb_array_elements(p_data->'hours') loop
   hid=coalesce(nullif(h->>'id',''),'');if hid='' then n=n+1;hid='HOR'||lpad(n::text,greatest(5,length(n::text)),'0');end if;
   insert into marathon.horarios(id,profesional_id,sede,dia,inicio,fin,created_by,updated_by) values(hid,id,h->>'sede',(h->>'day')::integer,(h->>'start')::time,(h->>'end')::time,uid,uid)
   on conflict on constraint horarios_pkey do update set sede=excluded.sede,dia=excluded.dia,inicio=excluded.inicio,fin=excluded.fin;
  end loop;
 end if;
 saved=public.marathon_master_get(p_entity,id);
 insert into marathon.master_audit(request_id,actor,entity,entity_id,before_data,after_data) values(p_request_id,uid,p_entity,id,old,saved);
 reply=jsonb_build_object('id',id,'entity',p_entity,'version',saved->'version','message','Datos guardados correctamente.');
 update marathon.solicitudes set resultado=reply where solicitudes.id=p_request_id;return reply;
end $_$;


--
-- Name: marathon_ortho_catalog(text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_catalog(p_query text DEFAULT ''::text, p_state text DEFAULT ''::text, p_after text DEFAULT NULL::text, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$declare rows jsonb;nxt text;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or p_state is null or p_state not in ('','ACTIVO','INACTIVO') or length(coalesce(p_query,''))>100 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) into rows from(select * from marathon.productos p where(p_state='' or p.estado=p_state) and(p_after is null or p.id>p_after) and(coalesce(p_query,'')='' or strpos(marathon.master_norm(concat_ws(' ',p.id,p.pieza,p.marca,p.talle,p.descripcion,p.codigo)),marathon.master_norm(p_query))>0) order by p.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=rows->(p_limit-1)->>'id';end if;return jsonb_build_object('rows',rows,'next',nxt);
end $$;


--
-- Name: marathon_ortho_command(text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_command(p_request_id text, p_action text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare reply jsonb;p marathon.productos%rowtype;old marathon.ortopedia_operaciones%rowtype;move marathon.movimientos%rowtype;
 product text;site text;destination text;dni text;obs text;medium text;reason text;kind text;id text;second_id text;mid text;comp text;
 qty integer;weeks integer;price numeric;total numeric;subtotal numeric;discount_rate numeric:=0;discount_amount numeric:=0;payment numeric;paid numeric;date_now date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;hour_now time:=(now() at time zone 'America/Argentina/Buenos_Aires')::time;transfer uuid;after_data jsonb;ids text[]:=array[]::text[];
begin
 reply=marathon.operation_begin(p_request_id,'ortho:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;
 if p_action is null or p_action not in('sale','rent','purchase','adjust_in','adjust_out','transfer','return','pay','refund','purchase_pay','reverse')or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(case
 when p_action in('sale','rent','purchase','adjust_in','adjust_out')then array['product','product_version','sede','cantidad','semanas','dni','pago','medio','observaciones','discount_rate']
 when p_action='transfer'then array['product','product_version','sede','destino','cantidad','observaciones']
 when p_action='return'then array['id','version','cantidad','observaciones']
 when p_action='reverse'then array['id','version','motivo']else array['id','version','monto','medio','observaciones']end))then raise sqlstate '22023' using message='Operación de ortopedia inválida.';end if;
 if p_action in('purchase','adjust_in','adjust_out','purchase_pay','reverse')and not marathon.is_admin()then raise sqlstate '42501' using message='Solo ADMIN puede comprar, ajustar stock o aprobar contrasientos.';end if;
 obs=marathon.master_text(p_data,'observaciones',2000);
 if p_action in('sale','rent','purchase','adjust_in','adjust_out','transfer')then
 product=marathon.master_text(p_data,'product',100,true);site=marathon.master_text(p_data,'sede',40,true);qty=marathon.ortho_int(p_data,'cantidad',1,10000);
 select * into p from marathon.productos where productos.id=product for update;
 if p.id is null or p.estado<>'ACTIVO'or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')then raise sqlstate '22023' using message='Elegí un producto y una sede activos.';end if;
 if p.version<>marathon.ortho_int(p_data,'product_version',1,999999999999999999)then raise sqlstate 'PT409' using message='El producto o sus precios cambiaron. Volvé a abrir la operación.';end if;
 if not exists(select 1 from marathon.stock_config where producto_id=product and sede=site)then raise sqlstate '22023' using message='Habilitá el producto por sede antes de operar.';end if;
 if p_action in('sale','rent','adjust_out','transfer')and qty>marathon.ortho_stock(product,site)then raise sqlstate 'PT409' using message='Stock insuficiente. Actualizá el inventario.';end if;
 if p_action='transfer'then
 destination=marathon.master_text(p_data,'destino',40,true);
 if destination=site or not exists(select 1 from marathon.sedes where nombre=destination and estado='ACTIVO')or not exists(select 1 from marathon.stock_config where producto_id=product and sede=destination)then raise sqlstate '22023' using message='Elegí otra sede activa y habilitá allí el producto.';end if;
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
 if p_action in('sale','rent')then dni=marathon.master_text(p_data,'dni',12,true);if not exists(select 1 from marathon.pacientes where pacientes.dni=dni)then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;
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
 if p_action='return'then
 if old.tipo<>'ALQUILER'then raise sqlstate '22023' using message='Solo se devuelven unidades de un alquiler.';end if;
 qty=marathon.ortho_int(p_data,'cantidad',1,10000);if qty>old.cantidad-marathon.ortho_returned(old.id)then raise sqlstate 'PT409' using message='La cantidad supera las unidades pendientes de devolución.';end if;
 if not exists(select 1 from marathon.stock_config where producto_id=old.producto_id and sede=old.sede)then raise sqlstate '22023' using message='Revisá la habilitación del producto y la sede antes de devolver.';end if;
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,original_id,fecha,hora,tipo,producto_id,sede,cantidad,dni,importe_total,precio_unitario,producto_snapshot,observaciones,created_by,updated_by)values(id,old.id,date_now,hour_now,'DEVOLUCION',old.producto_id,old.sede,qty,old.dni,0,0,old.producto_snapshot,obs,auth.uid(),auth.uid());
 select to_jsonb(o)into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'return',null,after_data);reply=jsonb_build_object('ids',jsonb_build_array(id),'message','Devolución registrada. La deuda conserva su saldo.');
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
end $_$;


--
-- Name: marathon_ortho_config(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_config(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare reply jsonb;old marathon.stock_config%rowtype;p marathon.productos%rowtype;product text;site text;minimum integer;initial integer;id text;after_data jsonb;
begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo ADMIN puede habilitar stock por sede.';end if;
 reply=marathon.operation_begin(p_request_id,'ortho-config',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['product','sede','minimo','inicial','version'])) then raise sqlstate '22023' using message='Configuración inválida.';end if;
 product=marathon.master_text(p_data,'product',100,true);site=marathon.master_text(p_data,'sede',40,true);minimum=marathon.ortho_int(p_data,'minimo',0,1000000);
 select * into p from marathon.productos where productos.id=product and estado='ACTIVO';
 if p.id is null or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO') then raise sqlstate '22023' using message='Elegí producto y sede activos.';end if;
 select * into old from marathon.stock_config c where c.producto_id=product and c.sede=site for update;
 if old.producto_id is not null then if old.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='La configuración cambió. Volvé a abrir el producto.';end if;
 elsif p_data ? 'version' then raise sqlstate 'PT409' using message='La configuración cambió. Volvé a abrir el producto.';end if;
 if p_data ? 'inicial' and p_data->'inicial'<>'null'::jsonb then
 initial=marathon.ortho_int(p_data,'inicial',0,1000000);
 if coalesce(old.initial_loaded,false) or exists(select 1 from marathon.ortopedia_operaciones o where o.producto_id=product and o.sede=site) then raise sqlstate '22023' using message='La sede ya tiene carga inicial o movimientos. Usá compra o ajuste.';end if;end if;
 insert into marathon.stock_config(producto_id,sede,minimo,initial_loaded,created_by,updated_by)values(product,site,minimum,initial is not null,auth.uid(),auth.uid()) on conflict on constraint stock_config_pkey do update set minimo=excluded.minimo,initial_loaded=stock_config.initial_loaded or excluded.initial_loaded;
 if initial>0 then
 id='ORT-'||gen_random_uuid()::text;insert into marathon.ortopedia_operaciones(id,fecha,hora,tipo,producto_id,sede,cantidad,importe_total,precio_unitario,producto_snapshot,observaciones,created_by,updated_by)values(id,(now() at time zone 'America/Argentina/Buenos_Aires')::date,(now() at time zone 'America/Argentina/Buenos_Aires')::time,'STOCK_INICIAL',product,site,initial,0,0,to_jsonb(p),'Carga inicial por ADMIN',auth.uid(),auth.uid());
 select to_jsonb(o) into after_data from marathon.ortopedia_operaciones o where o.id=id;perform marathon.ortho_audit(p_request_id,'ortho',id,'initial',null,after_data);end if;
 select to_jsonb(c) into after_data from marathon.stock_config c where c.producto_id=product and c.sede=site;perform marathon.ortho_audit(p_request_id,'stock-config',product||'|'||site,'save',case when old.producto_id is not null then to_jsonb(old)end,after_data);
 reply=jsonb_build_object('message','Stock por sede configurado.');update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $$;


--
-- Name: marathon_ortho_get(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_get(p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$declare r jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 select to_jsonb(o)||jsonb_build_object('producto',coalesce(o.producto_snapshot->>'descripcion',p.descripcion),'paid',marathon.ortho_paid(o.id),'debt',case when o.tipo in('VENTA','ALQUILER','COMPRA')then greatest(0,o.importe_total-marathon.ortho_paid(o.id))else 0 end,'returned',marathon.ortho_returned(o.id),'pending',case when o.tipo='ALQUILER'then o.cantidad-marathon.ortho_returned(o.id)else 0 end)into r from marathon.ortopedia_operaciones o join marathon.productos p on p.id=o.producto_id where o.id=p_id;
 if r is null then raise sqlstate 'PT404' using message='Operación no encontrada.';end if;return r;
end $$;


--
-- Name: marathon_ortho_history(text, text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_history(p_dni text DEFAULT ''::text, p_sede text DEFAULT ''::text, p_filter text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $_$declare rows jsonb;nxt jsonb;debt numeric;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or p_filter is null or p_filter not in('','open_rentals','debts','VENTA','ALQUILER','COMPRA','DEVOLUCION','STOCK_INICIAL','AJUSTE_POSITIVO','AJUSTE_NEGATIVO')or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['fecha','hora','id'])))then raise sqlstate '22023' using message='Consulta inválida.';end if;
 if p_after is not null and coalesce(p_after->>'hora','')!~'^([01][0-9]|2[0-3]):[0-5][0-9](\:[0-5][0-9](\.[0-9]{1,6})?)?$'then raise sqlstate '22023' using message='Cursor inválido.';end if;
 select coalesce(sum(greatest(0,o.importe_total-marathon.ortho_paid(o.id))),0)into debt from marathon.ortopedia_operaciones o where o.tipo in('VENTA','ALQUILER')and(coalesce(p_dni,'')=''or o.dni=p_dni)and(coalesce(p_sede,'')=''or o.sede=p_sede);
 select coalesce(jsonb_agg(to_jsonb(x)order by x.fecha desc,x.hora desc,x.id desc),'[]'::jsonb)into rows from(
 select o.*,coalesce(o.producto_snapshot->>'descripcion',p.descripcion)producto,concat_ws(' ',pac.apellido,pac.nombre)paciente,marathon.ortho_paid(o.id)paid,case when o.tipo in('VENTA','ALQUILER','COMPRA')then greatest(0,o.importe_total-marathon.ortho_paid(o.id))else 0 end debt,marathon.ortho_returned(o.id)returned,case when o.tipo='ALQUILER'then o.cantidad-marathon.ortho_returned(o.id)else 0 end pending,u.display_name actor from marathon.ortopedia_operaciones o join marathon.productos p on p.id=o.producto_id left join marathon.pacientes pac on pac.dni=o.dni left join marathon.app_users u on u.user_id=o.created_by
 where(coalesce(p_dni,'')=''or o.dni=p_dni)and(coalesce(p_sede,'')=''or o.sede=p_sede)and(case p_filter when ''then true when 'open_rentals'then o.tipo='ALQUILER'and o.cantidad>marathon.ortho_returned(o.id)when 'debts'then o.tipo in('VENTA','ALQUILER')and o.importe_total>marathon.ortho_paid(o.id)else o.tipo=p_filter end)
 and(p_after is null or(o.fecha,o.hora,o.id)<(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id'))order by o.fecha desc,o.hora desc,o.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;return jsonb_build_object('rows',rows,'next',nxt,'patient_debt',debt);
end $_$;


--
-- Name: marathon_ortho_product(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_product(p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$declare r jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 select to_jsonb(p)||jsonb_build_object('sites',coalesce((select jsonb_agg(to_jsonb(x) order by x.sede) from(select c.*,marathon.ortho_stock(c.producto_id,c.sede) stock from marathon.stock_config c where c.producto_id=p.id)x),'[]'::jsonb)) into r from marathon.productos p where id=p_id;
 if r is null then raise sqlstate 'PT404' using message='Producto no encontrado.';end if;return r;
end $$;


--
-- Name: marathon_ortho_product_save(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_product_save(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare reply jsonb;old marathon.productos%rowtype;id text;piece text;size text;brand text;description text;code text;mode text;status text;obs text;cost numeric;sale numeric;rent numeric;prefix text;n bigint;after_data jsonb;
begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo ADMIN puede administrar productos.';end if;
 reply=marathon.operation_begin(p_request_id,'ortho-product',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','pieza','talle','marca','descripcion','codigo','modalidad','costo','precio_venta','precio_alquiler','estado','observaciones'])) then raise sqlstate '22023' using message='Campos de producto inválidos.';end if;
 id=marathon.master_text(p_data,'id',100);piece=marathon.master_text(p_data,'pieza',100,true);size=marathon.master_text(p_data,'talle',60);brand=marathon.master_text(p_data,'marca',100);description=marathon.master_text(p_data,'descripcion',300,true);code=marathon.master_text(p_data,'codigo',80);mode=marathon.master_text(p_data,'modalidad',16,true);status=marathon.master_text(p_data,'estado',8,true);obs=marathon.master_text(p_data,'observaciones',1000);
 if mode not in ('VENTA','ALQUILER','VENTA Y ALQUILER') or status not in ('ACTIVO','INACTIVO') then raise sqlstate '22023' using message='Modalidad o estado inválidos.';end if;
 cost=marathon.ortho_price(p_data,'costo');sale=marathon.ortho_price(p_data,'precio_venta',strpos(mode,'VENTA')>0);rent=marathon.ortho_price(p_data,'precio_alquiler',strpos(mode,'ALQUILER')>0);
 if id<>'' then select * into old from marathon.productos p where p.id=id for update;if old.id is null then raise sqlstate 'PT404' using message='Producto no encontrado.';end if;
 if old.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El producto cambió. Volvé a abrirlo.';end if;
 else
 if p_data ? 'version' then raise sqlstate '22023' using message='Un producto nuevo no debe tener versión.';end if;
 select string_agg(coalesce(nullif(left(trim(both '-' from regexp_replace(upper(marathon.master_norm(v)),'[^A-Z0-9]+','-','g')),len),''),'SIN'),'-' order by ord) into prefix from(values(piece,3,1),(brand,3,2),(size,3,3),(code,8,4))parts(v,len,ord);
 n=1;while exists(select 1 from marathon.productos p where p.id=prefix||'-'||lpad(n::text,greatest(4,length(n::text)),'0'))loop n=n+1;end loop;id=prefix||'-'||lpad(n::text,greatest(4,length(n::text)),'0');end if;
 insert into marathon.productos(id,pieza,talle,marca,descripcion,codigo,modalidad,costo,precio_venta,precio_alquiler,estado,observaciones,created_by,updated_by) values(id,piece,size,brand,description,code,mode,cost,sale,rent,status,obs,auth.uid(),auth.uid()) on conflict on constraint productos_pkey do update set pieza=excluded.pieza,talle=excluded.talle,marca=excluded.marca,descripcion=excluded.descripcion,codigo=excluded.codigo,modalidad=excluded.modalidad,costo=excluded.costo,precio_venta=excluded.precio_venta,precio_alquiler=excluded.precio_alquiler,estado=excluded.estado,observaciones=excluded.observaciones;
 select to_jsonb(p) into after_data from marathon.productos p where p.id=id;perform marathon.ortho_audit(p_request_id,'product',id,'save',case when old.id is not null then to_jsonb(old) end,after_data);
 reply=jsonb_build_object('id',id,'message','Producto guardado.');update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $$;


--
-- Name: marathon_ortho_search(text, jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_search(p_kind text, p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare d date;e date;rows jsonb;nxt jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','query','actor','stock_state','operation'],p_limit,p_after);
 if p_kind is null or p_kind not in('stock','returns','debts','history')or coalesce(p_filters->>'stock_state','')not in('','AGOTADO','BAJO','DISPONIBLE')or coalesce(p_filters->>'operation','')not in('','VENTA','ALQUILER','COMPRA','DEVOLUCION','STOCK_INICIAL','AJUSTE_POSITIVO','AJUSTE_NEGATIVO')then raise sqlstate '22023'using message='Filtros de ortopedia inválidos.';end if;
 if p_kind='stock'then
 if p_after is not null and not(p_after?&array['product','sede'])then raise sqlstate '22023'using message='Cursor inválido.';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by id,sede),'[]'::jsonb)into rows from(select * from(select p.*,c.sede,c.minimo,marathon.ortho_stock(p.id,c.sede)stock from marathon.productos p join marathon.stock_config c on c.producto_id=p.id)q
 where(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(concat_ws(' ',id,descripcion,pieza,marca,codigo,talle)),marathon.master_norm(p_filters->>'query'))>0)and(case coalesce(p_filters->>'stock_state','')when'AGOTADO'then stock<=0 when'BAJO'then stock>0 and stock<=minimo when'DISPONIBLE'then stock>minimo else true end)and(p_after is null or(id,sede)>(p_after->>'product',p_after->>'sede'))order by id,sede limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('product',rows->(p_limit-1)->>'id','sede',rows->(p_limit-1)->>'sede');end if;
 else
 if p_after is not null and not(p_after?&array['fecha','hora','id'])then raise sqlstate '22023'using message='Cursor inválido.';end if;
 if p_kind='history'then d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');if e<d or e-d>3660 then raise sqlstate '22023'using message='Período inválido.';end if;end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by fecha desc,hora desc,id desc),'[]'::jsonb)into rows from(select * from marathon.daily_ortho o where(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(paciente||' '||coalesce(dni,'')),marathon.master_norm(p_filters->>'query'))>0)and(case p_kind when'returns'then tipo='ALQUILER'and pending>0 when'debts'then tipo in('VENTA','ALQUILER')and debt>0 else fecha between d and e and(coalesce(p_filters->>'actor','')=''or actor_key=p_filters->>'actor')and(coalesce(p_filters->>'operation','')=''or tipo=p_filters->>'operation')end)
 and(p_after is null or(fecha,hora,id)<(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id'))order by fecha desc,hora desc,id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 end if;return jsonb_build_object('rows',rows,'next',nxt);
end $$;


--
-- Name: marathon_ortho_sites(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_sites() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if(select count(*)from marathon.sedes where estado='ACTIVO')>500 then raise sqlstate '22023' using message='El catálogo de sedes requiere búsqueda paginada.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre) order by nombre)from marathon.sedes where estado='ACTIVO'),'[]'::jsonb);
end $$;


--
-- Name: marathon_ortho_stock(text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_ortho_stock(p_sede text DEFAULT ''::text, p_query text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$declare rows jsonb;nxt jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_query,''))>100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['product','sede'])))then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.id,x.sede),'[]'::jsonb)into rows from(
 select p.*,c.sede,c.minimo,marathon.ortho_stock(p.id,c.sede) stock from marathon.stock_config c join marathon.productos p on p.id=c.producto_id where(coalesce(p_sede,'')='' or c.sede=p_sede)and(coalesce(p_query,'')='' or strpos(marathon.master_norm(concat_ws(' ',p.id,p.descripcion,p.pieza,p.marca,p.talle,p.codigo)),marathon.master_norm(p_query))>0)and(p_after is null or(p.id,c.sede)>(p_after->>'product',p_after->>'sede'))order by p.id,c.sede limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('product',rows->(p_limit-1)->>'id','sede',rows->(p_limit-1)->>'sede');end if;return jsonb_build_object('rows',rows,'next',nxt);
end $$;


--
-- Name: marathon_patient_account(text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_account(p_dni text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare rows jsonb;nxt jsonb;total numeric;name text;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(jsonb_typeof(p_after)<>'object' or not(p_after ?& array['fecha','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select concat_ws(' ',apellido,nombre,nullif(segundo_nombre,'')) into name from marathon.pacientes where dni=p_dni;if name is null then raise sqlstate 'PT404' using message='Paciente no encontrado.';end if;
 select coalesce(sum(greatest(0,t.importe-marathon.turn_paid(t.id))),0) into total from marathon.turnos t where t.dni=p_dni and t.estado='PRESENTE';
 select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into rows from(
 select t.id,t.fecha,to_char(t.hora,'HH24:MI') hora,t.sede,t.estado,t.version,t.importe,th.nombre terapia,marathon.turn_paid(t.id) paid,greatest(0,t.importe-marathon.turn_paid(t.id)) debt from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.dni=p_dni and t.estado='PRESENTE' and t.importe>marathon.turn_paid(t.id) and(p_after is null or(t.fecha,t.id)>(marathon.agenda_date(p_after->>'fecha'),p_after->>'id')) order by t.fecha,t.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'debt',total,'name',name);
end $$;


--
-- Name: marathon_patient_catalog(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_catalog() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ begin
 if not marathon.active_user() then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nombre,'status',estado) order by nombre,id)
 from marathon.obras_sociales),'[]'::jsonb);
end $$;


--
-- Name: marathon_patient_dashboard(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_dashboard(p_filters jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare
 cut timestamp:=statement_timestamp() at time zone 'America/Argentina/Buenos_Aires';
 d date; e date; n_days int; prev date; finish timestamp; prev_finish timestamp;
 v_site text; v_therapy text; v_professional text; v_specialty text;
 summary jsonb; previous jsonb; groups jsonb; trend jsonb; coverage_json jsonb;
 firsts jsonb; waiting jsonb; capacity jsonb; quality jsonb; flow jsonb; catalog jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>3000
 or exists(select 1 from jsonb_object_keys(p_filters)k where k<>all(array['from','to','sede','therapy','professional','specialty'])) then
 raise sqlstate '22023' using message='Filtros de pacientes invalidos.';end if;
 if coalesce(p_filters->>'from','')!~'^\d{4}-\d{2}-\d{2}$'or coalesce(p_filters->>'to','')!~'^\d{4}-\d{2}-\d{2}$'then
 raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end if;
 begin d:=(p_filters->>'from')::date;e:=(p_filters->>'to')::date+1;
 exception when invalid_datetime_format or datetime_field_overflow then raise sqlstate '22023'using message='Elegi fechas validas para el informe.';end;
 n_days:=e-d;prev:=d-n_days;
 if n_days<1 or n_days>93 or e-1>cut::date or e-1>date '2100-12-31'or prev<date '2000-01-01' then
 raise sqlstate '22023' using message='Elegi hasta 93 dias, sin fechas futuras y con periodo anterior desde 2000.';end if;
 v_site:=coalesce(p_filters->>'sede','');v_therapy:=coalesce(p_filters->>'therapy','');
 v_professional:=coalesce(p_filters->>'professional','');v_specialty:=coalesce(p_filters->>'specialty','');
 finish:=least(e::timestamp,cut);prev_finish:=finish-make_interval(days=>n_days);
 -- Todas las filas de pacientes quedan dentro del servidor. Solo se devuelven agregados.
 with scoped as materialized (
 select t.*,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=prev and t.fecha<e and(v_site=''or t.sede=v_site)
 and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), marked as (
 select *,fecha+hora+make_interval(mins=>duracion_min) ended,
 case when fecha>=d then 'current' else 'previous' end period from scoped
 ), stats as (
 select period,count(*) total,count(*)filter(where estado='PRESENTE') present,
 count(distinct dni)filter(where estado='PRESENTE') patients,
 count(*)filter(where estado='AUSENTE') absent,count(*)filter(where estado='AUSENTE'and attendance_auto) auto_absent,
 count(*)filter(where estado='PENDIENTE') pending,count(*)filter(where estado='CANCELADO') cancelled
 from marked where (period='current'and ended<=finish)or(period='previous'and ended<=prev_finish)group by period
 ), comparisons as (
 select k.period,coalesce(s.total,0) total,coalesce(s.present,0) present,coalesce(s.patients,0) patients,
 coalesce(s.absent,0) absent,coalesce(s.pending,0) pending,coalesce(s.cancelled,0) cancelled,coalesce(s.auto_absent,0) auto_absent,
 round(100.0*s.present/nullif(s.present+s.absent,0),2) attendance,
 round(100.0*(s.present+s.absent)/nullif(s.present+s.absent+s.pending,0),2) completeness,
 round(s.present::numeric/nullif(s.patients,0),2) frequency
 from(values('current'),('previous'))k(period)left join stats s using(period)
 )select(select to_jsonb(b)-'period'from comparisons b where period='current'),
 (select to_jsonb(b)-'period'from comparisons b where period='previous')into summary,previous;
 with finished as materialized (
 select t.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad') specialty,
 concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)professional
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales pr on pr.id=t.profesional_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), grouped as (
 select g.kind,g.id,g.label,count(*)total,count(*)filter(where estado='PRESENTE')present,
 count(distinct dni)filter(where estado='PRESENTE')patients,count(*)filter(where estado='AUSENTE')absent,
 count(*)filter(where estado='PENDIENTE')pending,count(*)filter(where estado='CANCELADO')cancelled,
 round(100.0*count(*)filter(where estado='PRESENTE')/nullif(count(*)filter(where estado in('PRESENTE','AUSENTE')),0),2)attendance
 from finished f cross join lateral(values('specialty',f.specialty,f.specialty),('therapy',f.terapia_id,f.therapy),
 ('site',f.sede,f.sede),('professional',f.profesional_id,f.professional))g(kind,id,label)group by g.kind,g.id,g.label
 ), series as (
 select fecha date,count(*)filter(where estado='PRESENTE')present,count(*)filter(where estado='AUSENTE')absent,
 count(distinct dni)filter(where estado='PRESENTE')patients from finished group by fecha
 ), types as (
 select case when coverage->>'type'in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')then coverage->>'type'else 'SIN_REGISTRO'end type,
 count(*)attentions,count(distinct dni)patients from finished where estado='PRESENTE'group by 1
 )select(select coalesce(jsonb_agg(to_jsonb(g)order by kind,patients desc,label),'[]'::jsonb)from grouped g),
 (select coalesce(jsonb_agg(jsonb_build_object('date',g::date,'present',coalesce(s.present,0),'absent',coalesce(s.absent,0),'patients',coalesce(s.patients,0))order by g),'[]'::jsonb)
 from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g left join series s on s.date=g::date),
 (select jsonb_agg(jsonb_build_object('type',k.type,'label',k.label,'attentions',coalesce(t.attentions,0),'patients',coalesce(t.patients,0),
 'percent',round(100.0*coalesce(t.attentions,0)/nullif((summary->>'present')::numeric,0),2))order by k.ord)
 from(values('PARTICULAR','Particular',1),('OBRA_SOCIAL','Obra social',2),('ART','ART',3),('CLUB','Club',4),('SIN_REGISTRO','Sin registrar',5))k(type,label,ord)left join types t using(type))
 into groups,trend,coverage_json;
 -- Primera observada: minima atencion real registrada; no usa alta de ficha ni bonos.
 with attended as materialized (
 select t.dni,t.sede,t.terapia_id,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 t.fecha+t.hora started,t.fecha+t.hora+make_interval(mins=>t.duracion_min)ended,t.profesional_id
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=cut
 ), first_global as(select dni,min(started)first_at from attended group by dni),
 first_site as(select dni,sede,min(started)first_at from attended group by dni,sede),
 first_specialty as(select dni,specialty,min(started)first_at from attended group by dni,specialty),
 current_people as(select distinct dni from attended where started>=d and started<finish and ended<=finish and(v_site=''or sede=v_site)
 and(v_therapy=''or terapia_id=v_therapy)and(v_professional=''or profesional_id=v_professional)and(v_specialty=''or attended.specialty=v_specialty))
 select jsonb_build_object('observed',count(*)filter(where g.first_at>=d and g.first_at<finish),'returning',count(*)filter(where g.first_at<d),
 'first_site',case when v_site=''then null else(select count(*)from current_people c join first_site fs on fs.dni=c.dni and fs.sede=v_site where fs.first_at>=d and fs.first_at<finish)end,
 'first_specialty',case when v_specialty=''then null else(select count(*)from current_people c join first_specialty fs on fs.dni=c.dni and fs.specialty=v_specialty where fs.first_at>=d and fs.first_at<finish)end,
 'confirmed',null,'history_complete',false)into firsts from current_people c join first_global g using(dni);
 with filtered as materialized (
 select w.*,th.nombre therapy,coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')specialty,
 cut::date-w.fecha age from marathon.espera w join marathon.terapias th on th.id=w.terapia_id
 where(v_site=''or w.sede=v_site)and(v_therapy=''or w.terapia_id=v_therapy)and(v_professional=''or w.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), active as(select * from filtered where estado in('PENDIENTE','CONTACTADO')),
 wg as(select specialty label,count(*)requests,count(distinct dni)patients,min(fecha)oldest,
 percentile_cont(0.5)within group(order by age)filter(where age>=0)median_days from active group by specialty),
 assigned as(
 select w.id,t.fecha-w.fecha days from filtered w join marathon.turnos t on t.id=w.reserved_turn_id
 where w.fecha>=d and w.fecha<e and w.fecha<=cut::date and w.estado='RESUELTO'and t.estado<>'CANCELADO'and t.fecha>=w.fecha
 )select jsonb_build_object('requests',(select count(*)from active),'patients',(select count(distinct dni)from active),
 'median_days',(select percentile_cont(0.5)within group(order by age)filter(where age>=0)from active),
 'invalid_dates',(select count(*)from active where age<0),'rows',(select coalesce(jsonb_agg(to_jsonb(wg)order by requests desc,label),'[]'::jsonb)from wg),
 'linked_count',(select count(*)from assigned),'linked_median_days',(select percentile_cont(0.5)within group(order by days)from assigned),
 'complete_demand',false,'first_offer_days',null)into waiting;
 -- Tiempo profesional, no cupos fisicos. Dia de horarios: 0 domingo ... 6 sabado.
 with dates as(select g::date date from generate_series(d::timestamp,(e-1)::timestamp,interval '1 day')g),
 offered as(
 select h.profesional_id,h.sede,dt.date,range_agg(tsrange(dt.date+h.inicio,least(dt.date+h.fin,finish),'[)'))ranges
 from dates dt join marathon.horarios h on h.dia=extract(dow from dt.date)
 join marathon.profesionales pr on pr.id=h.profesional_id and pr.estado='ACTIVO'
 join marathon.sedes sd on sd.nombre=h.sede and sd.estado='ACTIVO'
 where dt.date+h.inicio<finish and h.fin>h.inicio and(v_site=''or h.sede=v_site)and(v_professional=''or h.profesional_id=v_professional)
 and(v_therapy=''or exists(select 1 from marathon.profesional_terapias pt where pt.profesional_id=h.profesional_id and pt.terapia_id=v_therapy))
 and(v_specialty=''or exists(select 1 from marathon.profesional_terapias pt join marathon.terapias th on th.id=pt.terapia_id where pt.profesional_id=h.profesional_id and coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty))
 group by h.profesional_id,h.sede,dt.date
 ), booked as(
 select t.profesional_id,t.sede,t.fecha,
 range_agg(tsrange(t.fecha+t.hora,least(t.fecha+t.hora+make_interval(mins=>t.duracion_min),finish),'[)'))reserved,
 range_agg(tsrange(t.fecha+t.hora,t.fecha+t.hora+make_interval(mins=>t.duracion_min),'[)'))filter(where t.estado='PRESENTE'and t.fecha+t.hora+make_interval(mins=>t.duracion_min)<=finish)effective
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id
 where t.fecha>=d and t.fecha<e and t.fecha+t.hora<finish and t.estado in('PENDIENTE','PRESENTE')
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 group by t.profesional_id,t.sede,t.fecha
 ), inter as(
 select o.*,o.ranges*coalesce(b.reserved,'{}'::tsmultirange)reserved,o.ranges*coalesce(b.effective,'{}'::tsmultirange)effective
 from offered o left join booked b on b.profesional_id=o.profesional_id and b.sede=o.sede and b.fecha=o.date
 ), op as(select profesional_id,range_agg(r)ranges from offered cross join lateral unnest(ranges)r group by profesional_id),
 rp as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(reserved)r group by profesional_id),
 ep as(select profesional_id,range_agg(r)ranges from inter cross join lateral unnest(effective)r group by profesional_id),
 mins as(
 select op.profesional_id,concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)label,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(op.ranges)r)available,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(rp.ranges)r)reserved,
 (select coalesce(sum(extract(epoch from upper(r)-lower(r))/60),0)from unnest(ep.ranges)r)effective
 from op left join rp using(profesional_id)left join ep using(profesional_id)join marathon.profesionales pr on pr.id=op.profesional_id
 ), rows as(select *,round(100*reserved/nullif(available,0),2)reserved_pct,round(100*effective/nullif(available,0),2)effective_pct from mins)
 select jsonb_build_object('available',coalesce(sum(available),0),'reserved',coalesce(sum(reserved),0),'effective',coalesce(sum(effective),0),
 'reserved_pct',round(100*sum(reserved)/nullif(sum(available),0),2),'effective_pct',round(100*sum(effective)/nullif(sum(available),0),2),
 'rows',coalesce(jsonb_agg(to_jsonb(rows)order by reserved desc,label),'[]'::jsonb),'physical_capacity',null,'current_schedules',true)
 into capacity from rows;
 with current_turns as(
 select t.*from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id where t.fecha>=d and t.fecha<e
 and(v_site=''or t.sede=v_site)and(v_therapy=''or t.terapia_id=v_therapy)and(v_professional=''or t.profesional_id=v_professional)
 and(v_specialty=''or coalesce(nullif(btrim(th.especialidad),''),'Sin especialidad')=v_specialty)
 ), heat as(
 select extract(isodow from fecha)::int as weekday,extract(hour from hora)::int as hour_bucket,count(*) as count
 from current_turns where estado in('PENDIENTE','PRESENTE')and fecha+hora<finish group by 1,2
 )select jsonb_build_object('future',(select count(*)from current_turns where fecha+hora>=finish),
 'missing_coverage',(select count(*)from current_turns where estado='PRESENTE'and fecha+hora+make_interval(mins=>duracion_min)<=finish and coalesce(coverage->>'type','')not in('PARTICULAR','OBRA_SOCIAL','ART','CLUB')),
 'scope_turns',(select count(*)from current_turns),'clinical_diagnoses',false,'experience',false),
 (select coalesce(jsonb_agg((to_jsonb(h)-'hour_bucket')||jsonb_build_object('hour',h.hour_bucket)order by h.hour_bucket,h.weekday),'[]'::jsonb)from heat h)into quality,flow;
 select jsonb_build_object(
 'specialties',(select coalesce(jsonb_agg(x.specialty order by x.specialty),'[]'::jsonb)from(select distinct coalesce(nullif(btrim(especialidad),''),'Sin especialidad')specialty from marathon.terapias)x),
 'therapies',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',nombre,'specialty',coalesce(nullif(btrim(especialidad),''),'Sin especialidad'))order by nombre),'[]'::jsonb)from marathon.terapias),
 'professionals',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'label',concat_ws(' ',nombre,nullif(segundo_nombre,''),apellido)||case when estado='INACTIVO'then ' (inactivo)'else ''end)order by apellido,nombre),'[]'::jsonb)from marathon.profesionales))into catalog;
 return jsonb_build_object('generated_at',statement_timestamp(),'today',cut::date,'filters',p_filters,
 'period',jsonb_build_object('from',d,'to',e-1,'days',n_days,'previous_from',prev,'previous_to',d-1,'cut',finish,'previous_cut',prev_finish,'partial_day',e::timestamp>cut),
 'summary',summary,'previous',previous,'groups',groups,'trend',trend,'coverage',coverage_json,'firsts',firsts,'waiting',waiting,'capacity',capacity,'quality',quality,'flow',flow,'catalog',catalog);
end;
$_$;


--
-- Name: marathon_patient_get(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_get(p_dni text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare r jsonb; begin
 if not marathon.active_user() then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 select to_jsonb(p) into r from marathon.pacientes p where dni=p_dni;
 if r is null then raise exception using errcode='P0002',message='Paciente no encontrado.'; end if;
 return r;
end $$;


--
-- Name: marathon_patient_history(text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_history(p_dni text, p_kind text DEFAULT 'clinic'::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
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
  select coalesce(sum(case when t.estado='PRESENTE' then greatest(0,t.importe-pay.paid) else 0 end),0) debt,count(*) filter(where t.estado='PRESENTE') present,count(*) filter(where t.estado='PENDIENTE' and t.fecha>=first_day) upcoming,count(*) total
  from marathon.turnos t cross join lateral(select marathon.turn_paid(t.id) paid)pay where t.dni=p_dni
 )c cross join(
  select coalesce(sum(case when o.tipo in ('VENTA','ALQUILER') then greatest(0,o.importe_total-pay.paid) else 0 end),0) debt,coalesce(sum(case when o.tipo='ALQUILER' then greatest(0,o.cantidad-ret.qty) else 0 end),0) units,count(*) total
  from marathon.ortopedia_operaciones o cross join lateral(select coalesce(sum(case when m.tipo='REINTEGRO' then -m.monto else m.monto end),0) paid from marathon.movimientos m where m.operacion_id=o.id and m.origen='ORTOPEDIA')pay
  cross join lateral(select coalesce(sum(d.cantidad),0) qty from marathon.ortopedia_operaciones d where d.original_id=o.id and d.tipo='DEVOLUCION')ret where o.dni=p_dni
 )o cross join(select coalesce(sum(debt),0) debt from marathon.daily_bonus where dni=p_dni)b;
 if p_kind='clinic' then
  select coalesce(jsonb_agg(to_jsonb(x) order by fecha desc,hora desc,id desc),'[]'::jsonb) into rows from(
   select t.id,t.fecha,t.hora,t.sede,t.estado,t.importe,t.coverage,t.observaciones,t.version,t.attendance_auto,t.attendance_auto_at,th.nombre terapia,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido) profesional,pay.paid,case when t.estado='PRESENTE' then greatest(0,t.importe-pay.paid) else 0 end debt
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
end $_$;


--
-- Name: marathon_patient_save(text, jsonb, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_save(p_request_id text, p_data jsonb, p_version bigint DEFAULT NULL::bigint) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
declare uid uuid:=auth.uid(); old marathon.pacientes%rowtype; req marathon.solicitudes%rowtype;
 saved marathon.pacientes%rowtype; body_hash text; response jsonb; d text; birth date; os text; k text; covers jsonb; item jsonb; ids text[]:=array[]::text[]; affiliate text;
begin
 -- Bloquea perfil durante operación: revocación de acceso no se intercala con esta escritura.
 perform 1 from marathon.app_users where user_id=uid and active for share;
 if not found then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 if p_request_id is null or p_request_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' then
  raise exception using errcode='22023',message='Solicitud inválida.'; end if;
 -- Hash incluye modo/versión. Mismo ID + payload diferente es un error, no un nuevo guardado.
 body_hash=encode(sha256(convert_to(jsonb_build_object('data',p_data,'version',p_version)::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash)
 values(p_request_id,uid,'patient',body_hash) on conflict(id) do nothing;
 select * into req from marathon.solicitudes where id=p_request_id for update;
 if req.usuario_id<>uid or req.payload_hash<>body_hash or req.tipo<>'patient' then
  raise exception using errcode='22023',message='Identificador de solicitud utilizado con otros datos.'; end if;
 if req.resultado is not null then return req.resultado; end if;
 if exists(select 1 from jsonb_object_keys(p_data) key where key<>all(array[
 'dni','nombre','segundo_nombre','apellido','obra_social_id','afiliado','nacimiento','domicilio','localidad',
 'provincia','telefono','telefono_area','telefono_local','email','sexo','medico','observaciones','coberturas'])) then
  raise exception using errcode='22023',message='La solicitud contiene campos no admitidos.'; end if;
 for k in select jsonb_object_keys(p_data) loop
  if k<>'coberturas' and (jsonb_typeof(p_data->k) not in ('string','null') or length(p_data->>k)>10000) then
   raise exception using errcode='22023',message='Formato o longitud de campo inválido.'; end if;
 end loop;
 d=trim(p_data->>'dni');
 if d is null or d !~ '^[0-9]{1,12}$' or coalesce(trim(p_data->>'nombre'),'')='' or coalesce(trim(p_data->>'apellido'),'')='' then
  raise exception using errcode='22023',message='Completá DNI, nombre y apellido válidos.'; end if;
 if p_version is not null and p_version<1 then raise exception using errcode='22023',message='Versión inválida.'; end if;
 -- Bloqueo también para altas concurrentes del mismo DNI; colisión de hash solo serializa, nunca autoriza.
 perform pg_advisory_xact_lock(hashtextextended('patient:'||d,0));
 select * into old from marathon.pacientes where dni=d for update;
 if p_version is null and found then raise exception using errcode='23505',message='Ese DNI ya está registrado.'; end if;
 if p_version is not null and (old.dni is null or old.version<>p_version) then
  raise exception using errcode='PT409',message='La ficha cambió. Volvé a abrirla antes de guardar.'; end if;
 -- El primer elemento mantiene la compatibilidad con los clientes anteriores.
 if p_data ? 'coberturas' then
  if jsonb_typeof(p_data->'coberturas') is distinct from 'array' then raise sqlstate '22023' using message='Las coberturas deben ser una lista.';end if;
  if jsonb_array_length(p_data->'coberturas')>20 then raise sqlstate '22023' using message='Se admiten hasta 20 obras sociales.';end if;
  covers='[]'::jsonb;
  for item in select value from jsonb_array_elements(p_data->'coberturas') loop
   if jsonb_typeof(item)<>'object' then raise sqlstate '22023' using message='Cobertura inválida.';end if;
   if exists(select 1 from jsonb_object_keys(item) as j(field) where j.field<>all(array['obra_social_id','afiliado'])) or jsonb_typeof(item->'obra_social_id') is distinct from 'string' or (item?'afiliado' and jsonb_typeof(item->'afiliado') is distinct from 'string') then raise sqlstate '22023' using message='Campos de cobertura inválidos.';end if;
   os=nullif(btrim(item->>'obra_social_id'),'');affiliate=btrim(coalesce(item->>'afiliado',''));
   if os is null or length(os)>100 or length(affiliate)>500 or os=any(ids) then raise sqlstate '22023' using message='Elegí obras sociales sin repetir y afiliados de hasta 500 caracteres.';end if;
   if not exists(select 1 from marathon.obras_sociales o where o.id=os and (o.estado='ACTIVO' or os=old.obra_social_id or coalesce(old.coberturas,'[]'::jsonb) @> jsonb_build_array(jsonb_build_object('obra_social_id',os)))) then raise sqlstate '22023' using message='Obra social inválida o inactiva.';end if;
   ids=array_append(ids,os);covers=covers||jsonb_build_array(jsonb_build_object('obra_social_id',os,'afiliado',affiliate));
  end loop;
 else
  os=nullif(btrim(p_data->>'obra_social_id'),'');affiliate=coalesce(p_data->>'afiliado','');
  if os is not null and not exists(select 1 from marathon.obras_sociales where id=os and (estado='ACTIVO' or os=old.obra_social_id)) then raise sqlstate '22023' using message='Obra social inválida o inactiva.';end if;
  covers=old.coberturas;
  -- Un cliente anterior puede cambiar la primera obra social, pero no borrar las adicionales.
  if covers is not null then
   select coalesce(jsonb_agg(x order by ord),'[]'::jsonb) into covers from jsonb_array_elements(covers) with ordinality e(x,ord)
   where (x->>'obra_social_id') is distinct from old.obra_social_id and (x->>'obra_social_id') is distinct from os;
   if os is not null then covers=jsonb_build_array(jsonb_build_object('obra_social_id',os,'afiliado',affiliate))||covers;end if;
  end if;
 end if;
 if covers is not null then os=covers->0->>'obra_social_id';affiliate=coalesce(covers->0->>'afiliado','');end if;
 if nullif(p_data->>'nacimiento','') is not null then
  if (p_data->>'nacimiento') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception using errcode='22023',message='Fecha inválida.'; end if;
  begin birth=(p_data->>'nacimiento')::date;
  exception when datetime_field_overflow or invalid_datetime_format then raise exception using errcode='22023',message='Fecha inválida.'; end;
 end if;
 insert into marathon.pacientes(dni,nombre,segundo_nombre,apellido,obra_social_id,afiliado,coberturas,nacimiento,domicilio,
 localidad,provincia,telefono,email,sexo,medico,observaciones,created_by,updated_by)
 values(d,trim(p_data->>'nombre'),trim(p_data->>'segundo_nombre'),trim(p_data->>'apellido'),os,affiliate,covers,birth,
 p_data->>'domicilio',p_data->>'localidad',p_data->>'provincia',marathon.patient_phone(p_data,old.telefono),p_data->>'email',
 p_data->>'sexo',p_data->>'medico',p_data->>'observaciones',uid,uid)
 on conflict(dni) do update set nombre=excluded.nombre,segundo_nombre=excluded.segundo_nombre,apellido=excluded.apellido,
 obra_social_id=excluded.obra_social_id,afiliado=excluded.afiliado,coberturas=excluded.coberturas,nacimiento=excluded.nacimiento,domicilio=excluded.domicilio,
 localidad=excluded.localidad,provincia=excluded.provincia,telefono=excluded.telefono,email=excluded.email,
 sexo=excluded.sexo,medico=excluded.medico,observaciones=excluded.observaciones
 returning * into saved;
 -- Referencias documentales y sesiones autorizadas nunca se sobrescriben desde este formulario.
 response=jsonb_build_object('dni',saved.dni,'version',saved.version,'message','Paciente guardado.');
 update marathon.solicitudes set resultado=response where id=p_request_id;
 return response;
end $_$;


--
-- Name: marathon_patient_search(text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_search(p_query text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 25) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
declare q text:=lower(trim(coalesce(p_query,''))); rows jsonb; next_cursor jsonb;
begin
 if not marathon.active_user() then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 if p_limit is null or p_limit<1 or p_limit>50 or length(q)>100 then
  raise exception using errcode='22023',message='Búsqueda o tamaño de página inválido.'; end if;
 if p_after is not null and (jsonb_typeof(p_after)<>'object' or not p_after ?& array['apellido','nombre','dni']) then
  raise exception using errcode='22023',message='Cursor inválido.'; end if;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.apellido,t.nombre,t.dni),'[]'::jsonb) into rows from (
  select p.dni,p.nombre,p.segundo_nombre,p.apellido,p.telefono,p.obra_social_id
  from marathon.pacientes p
  where (q='' or starts_with(p.dni,q) or starts_with(lower(coalesce(p.telefono,'')),q)
   or not exists(select 1 from regexp_split_to_table(q,'\s+') token
    where not (starts_with(lower(p.nombre),token) or starts_with(lower(p.apellido),token)
     or starts_with(lower(coalesce(p.segundo_nombre,'')),token))))
  and (p_after is null or (p.apellido,p.nombre,p.dni)>(p_after->>'apellido',p_after->>'nombre',p_after->>'dni'))
  order by p.apellido,p.nombre,p.dni limit p_limit+1
 ) t;
 if jsonb_array_length(rows)>p_limit then
  rows=rows-(jsonb_array_length(rows)-1);
  next_cursor=jsonb_build_object('apellido',rows->(p_limit-1)->>'apellido','nombre',rows->(p_limit-1)->>'nombre','dni',rows->(p_limit-1)->>'dni');
 end if;
 return jsonb_build_object('rows',rows,'next',next_cursor);
end $$;


--
-- Name: marathon_patient_sessions(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_sessions(p_pairs jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare cut date := (statement_timestamp() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_pairs is null or jsonb_typeof(p_pairs)<>'array' then raise sqlstate '22023' using message='La consulta de sesiones requiere una lista de pacientes y terapias.';end if;
 if jsonb_array_length(p_pairs)>500 then raise sqlstate '22023' using message='Consultá hasta 500 pacientes y terapias por vez.';end if;
 if exists(select 1 from jsonb_array_elements(p_pairs) x where jsonb_typeof(x) is distinct from 'object'
  or jsonb_typeof(x->'dni') is distinct from 'string' or coalesce(x->>'dni','') !~ '^[0-9]{1,12}$'
  or jsonb_typeof(x->'therapy_id') is distinct from 'string' or length(coalesce(x->>'therapy_id','')) not between 1 and 100)
 then raise sqlstate '22023' using message='Paciente o terapia inválidos para consultar sesiones.';end if;
 return (
  with wanted as(select distinct x->>'dni' dni,x->>'therapy_id' therapy_id from jsonb_array_elements(p_pairs)x),
  counts as(
   select w.dni,w.therapy_id,
    count(t.id) filter(where t.estado='PRESENTE' and t.fecha<=cut) completed,
    count(t.id) filter(where t.estado='PENDIENTE' and t.fecha>=cut) remaining
   from wanted w left join marathon.turnos t on t.dni=w.dni and t.terapia_id=w.therapy_id
   group by w.dni,w.therapy_id
  ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('as_of',cut) order by c.dni,c.therapy_id),'[]'::jsonb) from counts c
 );
end $_$;


--
-- Name: marathon_patient_upcoming(text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_patient_upcoming(p_dni text, p_therapy text, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare rows jsonb;total bigint;first_day date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_dni is null or p_dni!~'^[0-9]{1,12}$' or p_therapy is null or length(p_therapy)>100 or p_limit is null or p_limit not between 1 and 50 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select count(*) into total from marathon.turnos where dni=p_dni and terapia_id=p_therapy and estado='PENDIENTE' and fecha>=first_day;
 select coalesce(jsonb_agg(to_jsonb(x) order by fecha,hora,id),'[]'::jsonb) into rows from(
  select t.id,t.fecha,to_char(t.hora,'HH24:MI') hora,t.sede,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,''),p.apellido) profesional,t.coverage
  from marathon.turnos t join marathon.profesionales p on p.id=t.profesional_id
  where t.dni=p_dni and t.terapia_id=p_therapy and t.estado='PENDIENTE' and t.fecha>=first_day
  order by t.fecha,t.hora,t.id limit p_limit
 )x;
 return jsonb_build_object('rows',rows,'total',total,'limited',total>p_limit);
end $_$;


--
-- Name: marathon_report(text, jsonb, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_report(p_kind text, p_filters jsonb, p_after text DEFAULT NULL::text, p_limit integer DEFAULT 100) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
#variable_conflict use_variable
declare d date;e date;n date;site text;therapy text;insurance text;rows jsonb;summary jsonb;next_id text;total bigint;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_kind is null or p_kind not in ('billing','cash','indicators') or p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000 or exists(select 1 from jsonb_object_keys(p_filters) k where k<>all(array['month','sede','therapy','insurance'])) or p_limit is null or p_limit not between 1 and 10000 or coalesce(p_filters->>'month','') !~ '^(20[0-9]{2}|2100)-(0[1-9]|1[0-2])$' then raise sqlstate '22023' using message='Filtros inválidos. Elegí un mes de 2000 a 2100.';end if;
 d=(p_filters->>'month'||'-01')::date;e=(d+interval '1 month')::date;n=(d+interval '2 months')::date;site=coalesce(p_filters->>'sede','');therapy=coalesce(p_filters->>'therapy','');insurance=coalesce(p_filters->>'insurance','');
 if p_kind='billing' then

 with counts as(select p.dni,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,'')) name,p.apellido surname,coalesce(p.afiliado,'') affiliate,coalesce((select nombre from marathon.obras_sociales where id=p.obra_social_id),'Particular') insurance,
 count(*) filter(where t.fecha>=d and t.fecha<e and t.estado='PRESENTE') done,count(*) filter(where t.fecha>=e and t.fecha<n and t.estado='PENDIENTE') next
 from marathon.turnos t join marathon.pacientes p on p.dni=t.dni where t.fecha>=d and t.fecha<n and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy) and(insurance='' or coalesce(p.obra_social_id,'__PARTICULAR__')=insurance) group by p.dni)
 select jsonb_build_object('patients',count(*),'done',coalesce(sum(done),0),'next',coalesce(sum(next),0),'missing_affiliate',count(*)filter(where affiliate=''),'insurance',case when insurance=''then'Todas las obras sociales'when insurance='__PARTICULAR__'then'Particular'else coalesce((select nombre from marathon.obras_sociales where id=insurance),insurance)end) into summary from counts where done+next>0;
 total=(summary->>'patients')::bigint;
 select coalesce(jsonb_agg(to_jsonb(q) order by dni),'[]'::jsonb) into rows from (
 select p.dni,concat_ws(' ',p.nombre,nullif(p.segundo_nombre,'')) name,p.apellido surname,coalesce(p.afiliado,'') affiliate,coalesce((select nombre from marathon.obras_sociales where id=p.obra_social_id),'Particular') insurance,
 count(*) filter(where t.fecha>=d and t.fecha<e and t.estado='PRESENTE') done,count(*) filter(where t.fecha>=e and t.fecha<n and t.estado='PENDIENTE') next
 from marathon.turnos t join marathon.pacientes p on p.dni=t.dni where t.fecha>=d and t.fecha<n and (site='' or t.sede=site) and (therapy='' or t.terapia_id=therapy) and(insurance='' or coalesce(p.obra_social_id,'__PARTICULAR__')=insurance) and (p_after is null or p.dni>p_after) group by p.dni
 having count(*)filter(where (t.fecha<e and t.estado='PRESENTE') or (t.fecha>=e and t.estado='PENDIENTE'))>0 order by p.dni limit p_limit+1)q;
 elsif p_kind='cash' then
 -- Terapia filtra movimientos clínicos y bonos vinculados a esa terapia. Sin filtro incluye todos los orígenes.
 select count(*),jsonb_build_object('income',coalesce(sum(m.monto)filter(where m.tipo in ('INGRESO','PAGO')),0),'expense',coalesce(sum(m.monto)filter(where m.tipo in ('EGRESO','REINTEGRO')),0),'net',coalesce(sum(case when m.tipo in ('INGRESO','PAGO')then m.monto else -m.monto end),0)) into total,summary from marathon.movimientos m left join marathon.turnos t on t.id=m.turno_id left join marathon.bonos_serie b on b.id=m.bono_id left join marathon.anticipos a on a.id=m.anticipo_id where m.fecha>=d and m.fecha<e and (site='' or m.sede=site) and (therapy='' or coalesce(t.terapia_id,b.terapia_id,a.terapia_id)=therapy);
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]'::jsonb) into rows from(select m.id,m.fecha,m.hora,m.sede,m.origen,m.tipo,m.dni,m.monto,m.medio,m.concepto,coalesce(u.display_name,m.secretaria_legacy,'') actor from marathon.movimientos m left join marathon.turnos t on t.id=m.turno_id left join marathon.bonos_serie b on b.id=m.bono_id left join marathon.anticipos a on a.id=m.anticipo_id left join marathon.app_users u on u.user_id=m.created_by where m.fecha>=d and m.fecha<e and (site='' or m.sede=site) and (therapy='' or coalesce(t.terapia_id,b.terapia_id,a.terapia_id)=therapy) and (p_after is null or m.id>p_after) order by m.id limit p_limit+1)q;
 else
 select jsonb_build_object('total',count(*),'present',count(*)filter(where estado='PRESENTE'),'absent',count(*)filter(where estado='AUSENTE'),'pending',count(*)filter(where estado='PENDIENTE'),'cancelled',count(*)filter(where estado='CANCELADO'),'patients',count(distinct dni)) into summary from marathon.turnos where fecha>=d and fecha<e and (site='' or sede=site) and (therapy='' or terapia_id=therapy);
 rows='[]'::jsonb;total=0;
 end if;
 if p_limit=10000 and jsonb_array_length(rows)>10000 then raise sqlstate '22023' using message='El informe supera 10.000 filas. Reducí los filtros antes de exportar.';end if;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_id=case when p_kind='billing' then rows->(p_limit-1)->>'dni' else rows->(p_limit-1)->>'id' end;end if;
 return jsonb_build_object('rows',rows,'summary',summary,'total',total,'next',next_id,'generated_at',statement_timestamp(),'month',to_char(d,'YYYY-MM'),'next_month',to_char(e,'YYYY-MM'));
end $_$;


--
-- Name: marathon_reschedule_get(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_reschedule_get(p_id text, p_scope text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare target marathon.turnos%rowtype;rows jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 select * into target from marathon.turnos where id=p_id;
 if target.id is null or target.estado<>'PENDIENTE' then raise sqlstate '22023' using message='Solo se pueden reprogramar turnos pendientes.';end if;
 if p_scope is null or p_scope not in ('single','series') then raise sqlstate '22023' using message='Alcance inválido.';end if;
 select jsonb_agg(to_jsonb(x) order by x.fecha,x.hora,x.id) into rows from(
 select t.id,t.fecha,to_char(t.hora,'HH24:MI') hora,t.sede,t.profesional_id prof,t.terapia_id therapy,t.dni,t.version,t.importe from marathon.turnos t
 where t.estado='PENDIENTE' and(case when p_scope='single' then t.id=p_id else coalesce(t.original_id,t.id)=coalesce(target.original_id,target.id) and (target.fixed_until is null or t.fecha>=target.fecha) end)
 order by t.fecha,t.hora,t.id limit 61)x;
 if coalesce(jsonb_array_length(rows),0) not between 1 and 60 then raise sqlstate '22023' using message='La serie supera 60 turnos o cambió. Abrí un turno individual.';end if;
 return rows;
end $$;


--
-- Name: marathon_reschedule_preview(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_reschedule_preview(p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $_$
declare selected jsonb; ids text[]; c jsonb; d date; result jsonb;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000
 or exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['id','scope','changes']))
 or jsonb_typeof(p_data->'changes') is distinct from 'array' then raise sqlstate '22023' using message='Vista previa inválida.';end if;
 selected=public.marathon_reschedule_get(p_data->>'id',p_data->>'scope');
 select array_agg(x->>'id') into ids from jsonb_array_elements(selected)x;
 if jsonb_array_length(p_data->'changes')<>cardinality(ids)
 or exists(select 1 from jsonb_array_elements(p_data->'changes') x where jsonb_typeof(x)<>'object' or not(coalesce(x->>'id','')=any(ids)))
 or (select count(distinct x->>'id') from jsonb_array_elements(p_data->'changes')x)<>cardinality(ids)
 then raise sqlstate 'PT409' using message='La serie cambió. Volvé a abrir la reprogramación.';end if;
 for c in select value from jsonb_array_elements(p_data->'changes') loop
  if exists(select 1 from jsonb_object_keys(c) k where k<>all(array['id','version','fecha','hora','sede','prof']))
  or jsonb_typeof(c->'version') is distinct from 'number' or coalesce(c->>'version','') !~ '^[1-9][0-9]{0,17}$'
  or coalesce(c->>'fecha','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(c->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  or coalesce(length(c->>'sede'),0) not between 1 and 40 or coalesce(length(c->>'prof'),0) not between 1 and 100
  then raise sqlstate '22023' using message='Completá fecha, hora, sede y profesional de todos los turnos.';end if;
  begin d=(c->>'fecha')::date;exception when datetime_field_overflow or invalid_datetime_format then raise sqlstate '22023' using message='Fecha inválida.';end;
  if d not between date '2000-01-01' and date '2100-12-31' then raise sqlstate '22023' using message='La fecha debe estar entre 2000 y 2100.';end if;
  if not exists(select 1 from jsonb_array_elements(selected)x where x->>'id'=c->>'id' and (x->>'version')::bigint=(c->>'version')::bigint)
  then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir la reprogramación.';end if;
 end loop;
 with proposed as materialized (
  select x->>'id' id,(x->>'fecha')::date fecha,(x->>'hora')::time hora,x->>'sede' sede,x->>'prof' prof,
   t.terapia_id therapy,t.dni,marathon.session_minutes((x->>'fecha')::date,x->>'sede',x->>'prof',(x->>'hora')::time,a.duracion_min) duration,marathon.master_norm(a.especialidad) spec,x->>'hora' selected_hour
  from jsonb_array_elements(p_data->'changes')x join marathon.turnos t on t.id=x->>'id' join marathon.terapias a on a.id=t.terapia_id
 ), per_turn as (
  select q.id,q.selected_hour,coalesce(jsonb_agg(jsonb_build_object('hora',s.hora,'remaining',s.remaining,'available',s.available,'reason',s.reason,'duration_min',s.duration_min,'end_hour',s.end_hour) order by s.hora) filter(where s.hora is not null),'[]'::jsonb) slots
  from proposed q
  left join lateral (
   with config as (
    select a.*,greatest(a.capacidad,coalesce((select max(b.capacidad) from marathon.terapias b join marathon.profesional_terapias pt on pt.terapia_id=b.id and pt.profesional_id=q.prof
     where b.estado='ACTIVO' and q.spec<>'' and marathon.master_norm(b.especialidad)=q.spec),a.capacidad)) shared
    from marathon.terapias a join marathon.profesional_terapias pt on pt.terapia_id=a.id and pt.profesional_id=q.prof
    join marathon.profesionales p on p.id=q.prof and p.estado='ACTIVO' join marathon.sedes se on se.nombre=q.sede and se.estado='ACTIVO'
    where a.id=q.therapy and a.estado='ACTIVO'
   ), candidates as (
    select distinct (extract(epoch from h.inicio)/60)::int+g.n m,marathon.session_minutes(q.fecha,q.sede,q.prof,time '00:00'+((extract(epoch from h.inicio)/60)::int+g.n)*interval '1 minute',c.duracion_min) actual_duration,c.* from config c
    join marathon.horarios h on h.profesional_id=q.prof and h.sede=q.sede and h.dia=extract(dow from q.fecha)::int
    cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(q.prof))g(n)
   ), busy as materialized (
    select t.dni,t.profesional_id prof,t.sede,t.terapia_id therapy,(extract(epoch from t.hora)/60)::int m,marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min) duration,marathon.master_norm(a.especialidad) spec
    from marathon.turnos t join marathon.terapias a on a.id=t.terapia_id
    where t.fecha=q.fecha and t.estado<>'CANCELADO' and not(t.id=any(ids)) and (t.profesional_id=q.prof or t.dni=q.dni)
    union all
    select p.dni,p.prof,p.sede,p.therapy,(extract(epoch from p.hora)/60)::int,p.duration,p.spec from proposed p
    where p.id<>q.id and p.fecha=q.fecha and (p.prof=q.prof or p.dni=q.dni)
   )
   select to_char(time '00:00'+c.m*interval '1 minute','HH24:MI') hora,c.actual_duration duration_min,to_char(time '00:00'+(c.m+c.actual_duration)*interval '1 minute','HH24:MI') end_hour,
    case when conflict.blocked then 0 else greatest(0,r.remaining) end remaining,
    not conflict.patient_overlap and not conflict.blocked and r.remaining>0 available,
    case when conflict.patient_overlap then 'El paciente tiene otro turno superpuesto.' when conflict.blocked then 'El profesional tiene una sesión incompatible o en otra sede.' when r.remaining<1 then 'Sin cupo.' else '' end reason
   from candidates c
   cross join lateral (select
    exists(select 1 from busy b where b.dni=q.dni and b.m<c.m+c.actual_duration and c.m<b.m+b.duration) patient_overlap,
    exists(select 1 from busy b where b.prof=q.prof and b.m<c.m+c.actual_duration and c.m<b.m+b.duration and (b.sede<>q.sede or not(b.therapy=q.therapy or(q.spec<>'' and b.spec=q.spec)))) blocked
   ) conflict
   cross join lateral (
    select min(least(c.capacidad-(select count(*)::int from busy b where b.prof=q.prof and b.therapy=q.therapy and b.m<=cuts.at and cuts.at<b.m+b.duration),
     c.shared-(select count(*)::int from busy b where b.prof=q.prof and b.m<=cuts.at and cuts.at<b.m+b.duration))) remaining
    from (select c.m at union select b.m from busy b where b.prof=q.prof and b.m>c.m and b.m<c.m+c.actual_duration
     union select b.m+b.duration from busy b where b.prof=q.prof and b.m+b.duration>c.m and b.m+b.duration<c.m+c.actual_duration) cuts
   )r
  )s on true group by q.id,q.selected_hour
 ), evaluated as (
  select id,slots,coalesce((select (x->>'available')::boolean from jsonb_array_elements(slots)x where x->>'hora'=selected_hour),false) ok,
   coalesce((select nullif(x->>'reason','') from jsonb_array_elements(slots)x where x->>'hora'=selected_hour),'Fuera del horario de atención o combinación no habilitada.') reason from per_turn
 )
 select jsonb_build_object('ok',bool_and(ok),'rows',jsonb_agg(jsonb_build_object('id',id,'slots',slots,'ok',ok,'reason',case when ok then '' else reason end) order by id)) into result from evaluated;
 return result;
end $_$;


--
-- Name: FUNCTION marathon_reschedule_preview(p_data jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.marathon_reschedule_preview(p_data jsonb) IS 'Solo lectura: cupos y superposiciones de la propuesta completa, con selección de serie y versiones verificadas. El guardado vuelve a validar bajo bloqueo.';


--
-- Name: marathon_reschedule_save(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_reschedule_save(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare reply jsonb;selected jsonb;ids text[];remaining_ids text[];change jsonb;old marathon.turnos%rowtype;after_data jsonb;d date;h text;site text;prof text;duration integer;slot record;
begin
 reply=marathon.operation_begin(p_request_id,'reschedule',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['id','scope','changes'])) or jsonb_typeof(p_data->'changes') is distinct from 'array' then raise sqlstate '22023' using message='Reprogramación inválida.';end if;
 selected=public.marathon_reschedule_get(marathon.master_text(p_data,'id',100,true),marathon.master_text(p_data,'scope',6,true));
 select array_agg(x->>'id') into ids from jsonb_array_elements(selected)x;remaining_ids=ids;
 if jsonb_array_length(p_data->'changes')<>cardinality(ids) or exists(select 1 from jsonb_array_elements(p_data->'changes')c where jsonb_typeof(c)<>'object' or not(coalesce(c->>'id','')=any(ids))) or
 (select count(distinct c->>'id') from jsonb_array_elements(p_data->'changes')c)<>cardinality(ids) then raise sqlstate 'PT409' using message='La serie cambió. Volvé a abrir la reprogramación.';end if;
 -- Todas las versiones se comprueban antes de modificar; no se borra ningún turno ni pago.
 for change in select value from jsonb_array_elements(p_data->'changes') loop
  if exists(select 1 from jsonb_object_keys(change) k where k<>all(array['id','version','fecha','hora','sede','prof'])) then raise sqlstate '22023' using message='Campos de reprogramación inválidos.';end if;
  select * into old from marathon.turnos t where t.id=change->>'id' for update;
  if old.version<>marathon.operation_version(change) then raise sqlstate 'PT409' using message='El turno cambió. Volvé a abrir la reprogramación.';end if;
 end loop;
 for change in select value from jsonb_array_elements(p_data->'changes') loop
  select * into old from marathon.turnos t where t.id=change->>'id';
  d=marathon.agenda_date(marathon.master_text(change,'fecha',10,true));h=marathon.master_text(change,'hora',5,true);
  site=marathon.master_text(change,'sede',40,true);prof=marathon.master_text(change,'prof',100,true);
  if h !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise sqlstate '22023' using message='Hora inválida.';end if;
  select t.duracion_min into duration from marathon.terapias t where t.id=old.terapia_id and t.estado='ACTIVO';
  duration=marathon.session_minutes(d,site,prof,h::time,duration);
  select * into slot from marathon.agenda_slots_excluding(d,site,prof,old.terapia_id,remaining_ids) s where s.hora=h;
  if slot.hora is null or slot.remaining<1 or slot.blocked then raise sqlstate 'PT409' using message='Sin cupo el '||d||' a las '||h||'. No se reprogramó ningún turno.';end if;
  if exists(select 1 from marathon.turnos t where t.dni=old.dni and t.fecha=d and t.estado<>'CANCELADO' and not(t.id=any(remaining_ids)) and t.hora<h::time+duration*interval '1 minute' and h::time<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute') then raise sqlstate 'PT409' using message='El paciente tiene un turno superpuesto. No se reprogramó ningún turno.';end if;
  update marathon.turnos t set fecha=d,hora=h::time,sede=site,profesional_id=prof,duracion_min=duration where t.id=old.id;
  select to_jsonb(t) into after_data from marathon.turnos t where t.id=old.id;
  insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data) values(p_request_id,auth.uid(),old.id,'reschedule',to_jsonb(old),after_data);
  remaining_ids=array_remove(remaining_ids,old.id);
 end loop;
 reply=jsonb_build_object('ids',ids,'message',case when cardinality(ids)=1 then 'Turno reprogramado. Se conservaron sus pagos.' else cardinality(ids)||' turnos reprogramados. Se conservaron sus pagos.' end);
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end $_$;


--
-- Name: marathon_session(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_session() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ declare r jsonb; begin
 if not marathon.active_user() then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 select jsonb_build_object('user_id',user_id,'name',display_name,'role',role,'all_sites',true)
 into r from marathon.app_users where user_id=auth.uid(); return r;
end $$;


--
-- Name: marathon_shared_space_get(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_shared_space_get() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 return jsonb_build_object('version',(select version from marathon.shared_space_config where singleton),
  'therapy_ids',coalesce((select jsonb_agg(therapy_id order by therapy_id) from marathon.shared_space_therapies),'[]'::jsonb),
  'therapies',coalesce((select jsonb_agg(jsonb_build_object('id',id,'label',nombre,'estado',estado) order by nombre) from marathon.terapias),'[]'::jsonb));
end $$;


--
-- Name: marathon_shared_space_save(jsonb, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_shared_space_save(p_therapy_ids jsonb, p_version bigint) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$
 select marathon.shared_space_save(p_therapy_ids,p_version)
$$;


--
-- Name: marathon_therapy_info(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_therapy_info(p_therapy text, p_insurance text DEFAULT ''::text) RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$ begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('mensaje',mensaje,'particular',obra_social_id is null) order by id) from marathon.informacion_terapias where terapia_id=p_therapy and obra_social_id is not distinct from nullif(p_insurance,'') and estado='ACTIVO'),'[]'::jsonb);
end $$;


--
-- Name: marathon_turn_account(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_turn_account(p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: marathon_turn_cancel_charge(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_turn_cancel_charge(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
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
end $_$;


--
-- Name: marathon_turns_commit(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_turns_commit(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    SET statement_timeout TO '30s'
    AS $$
#variable_conflict use_variable
declare reply jsonb;review jsonb;r jsonb;old marathon.turnos%rowtype;id text;ids jsonb:='[]';after_row jsonb;
begin
 reply=marathon.operation_begin(p_request_id,'agenda:bulk',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['action','turns','review_token']))then raise sqlstate '22023'using message='Solicitud inválida.';end if;
 perform 1 from marathon.turnos t join jsonb_array_elements(p_data->'turns')x on t.id=x->>'id' order by t.id for update of t;
 review=public.marathon_turns_preview(p_data->>'action',p_data->'turns');
 if coalesce(p_data->>'review_token','')<>review->>'review_token' then raise sqlstate 'PT409'using message='Los turnos, pagos o fechas disponibles cambiaron después de la revisión. Volvé a revisar antes de confirmar. No se guardó ningún cambio.';end if;
 for r in select value from jsonb_array_elements(review->'rows')loop
  if p_data->>'action'='recover' then
   select * into old from marathon.turnos t where t.id=r->>'id';id='TUR-'||gen_random_uuid()::text;
   insert into marathon.turnos(id,original_id,recovered_from,fecha,hora,sede,profesional_id,terapia_id,duracion_min,dni,importe,coverage,estado,observaciones,booking_notes,series_pattern,created_by,updated_by)
   values(id,r->>'root',old.id,(r->>'proposed_fecha')::date,(r->>'proposed_hora')::time,old.sede,old.profesional_id,old.terapia_id,(r->>'duration_min')::int,old.dni,old.importe,old.coverage,'PENDIENTE',coalesce(old.booking_notes,marathon.reservation_notes(old.observaciones)),coalesce(old.booking_notes,marathon.reservation_notes(old.observaciones)),r->'pattern',auth.uid(),auth.uid());
   select to_jsonb(t)into after_row from marathon.turnos t where t.id=id;
   insert into marathon.turn_audit(request_id,actor,turn_id,action,before_data,after_data)values(p_request_id,auth.uid(),id,'recover',to_jsonb(old),after_row);
  else
   id=r->>'id';perform public.marathon_agenda_command('BULK-'||md5(p_request_id||':'||id),'status',jsonb_build_object('id',id,'version',(r->>'version')::bigint,'estado',case when p_data->>'action'='present'then 'PRESENTE'else 'CANCELADO'end));
  end if;
  ids=ids||jsonb_build_array(id);
 end loop;
 reply=jsonb_build_object('ids',ids,'message',jsonb_array_length(ids)||case when p_data->>'action'='recover'then ' sesiones recuperadas al final de sus series. Se conservaron los cancelados; no se crearon cobros ni bonos.'else ' turnos actualizados. No se generaron cobros automáticos.'end);
 update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $$;


--
-- Name: marathon_turns_preview(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_turns_preview(p_action text, p_turns jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET statement_timeout TO '25s'
    AS $_$
#variable_conflict use_variable
declare item jsonb;old marathon.turnos%rowtype;root text;days integer[];pattern jsonb;inferred boolean;tail date;d date;start_day date;last_day date;duration integer;chosen date;series_snapshot text;
 rows jsonb:='[]';planned jsonb:='[]';row_data jsonb;today date:=(now() at time zone 'America/Argentina/Buenos_Aires')::date;now_local timestamp:=now() at time zone 'America/Argentina/Buenos_Aires';
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_action is null or p_action not in('present','cancel','recover') or jsonb_typeof(p_turns) is distinct from 'array' then raise sqlstate '22023' using message='Operación múltiple inválida.';end if;
 if jsonb_array_length(p_turns) not between 1 and 30 or octet_length(p_turns::text)>12000 then raise sqlstate '22023' using message='Seleccioná entre 1 y 30 turnos.';end if;
 if exists(select 1 from jsonb_array_elements(p_turns)x where jsonb_typeof(x)<>'object' or coalesce(x->>'id','')='' or jsonb_typeof(x->'version') is distinct from 'number' or coalesce(x->>'version','')!~'^[0-9]{1,18}$') or (select count(distinct x->>'id')from jsonb_array_elements(p_turns)x)<>jsonb_array_length(p_turns) then raise sqlstate '22023' using message='La selección tiene turnos repetidos o inválidos.';end if;
 for item in select value from jsonb_array_elements(p_turns) order by value->>'id' loop
  select * into old from marathon.turnos t where t.id=item->>'id';
  if not found or old.version<>(item->>'version')::bigint then raise sqlstate 'PT409' using message='Uno de los turnos cambió. Actualizá la lista y revisá la selección.';end if;
  if (p_action='present' and old.estado<>'PENDIENTE') or(p_action='cancel' and old.estado='CANCELADO') or(p_action='recover' and old.estado<>'CANCELADO') then raise sqlstate '22023' using message='Hay un turno cuyo estado no permite esta acción. No se modificó ninguno.';end if;
  if p_action in('cancel','recover') and marathon.turn_cash_paid(old.id)>0 then raise sqlstate '22023' using message='Hay un turno con cobros. Registrá el reintegro antes de continuar. No se modificó ninguno.';end if;
  if p_action='recover' and exists(select 1 from marathon.turnos t where t.recovered_from=old.id) then raise sqlstate '22023' using message='Esta cancelación ya tiene una recuperación. Si esa nueva sesión se canceló, seleccioná la nueva cancelación.';end if;
  row_data=jsonb_build_object('id',old.id,'version',old.version,'estado',old.estado,'fecha',old.fecha,'hora',to_char(old.hora,'HH24:MI'),'dni',old.dni,'paciente',(select concat_ws(' ',p.apellido,p.nombre,p.segundo_nombre)from marathon.pacientes p where p.dni=old.dni),'prof',old.profesional_id,'profesional',(select concat_ws(' ',p.nombre,p.apellido)from marathon.profesionales p where p.id=old.profesional_id),'therapy',old.terapia_id,'terapia',(select t.nombre from marathon.terapias t where t.id=old.terapia_id),'sede',old.sede,'importe',old.importe,'paid',marathon.turn_paid(old.id),'coverage',old.coverage,'source_fingerprint',encode(sha256(convert_to(to_jsonb(old)::text,'UTF8')),'hex'));
  if p_action='recover' then
   root=coalesce(old.original_id,old.id);inferred=old.series_pattern is null;
   if not inferred then select array_agg(x::int order by x::int)into days from jsonb_array_elements_text(old.series_pattern->'days')x;
   else select array_agg(distinct extract(dow from t.fecha)::int order by extract(dow from t.fecha)::int)into days from marathon.turnos t where coalesce(t.original_id,t.id)=root and t.dni=old.dni and t.profesional_id=old.profesional_id and t.terapia_id=old.terapia_id and t.sede=old.sede and t.hora=old.hora and t.recovered_from is null;end if;
   if coalesce(cardinality(days),0)not between 1 and 7 or not(days<@array[0,1,2,3,4,5,6])then raise sqlstate '22023' using message='No se pudo identificar el patrón semanal de la serie. Revisá sus turnos originales.';end if;
   pattern=jsonb_build_object('days',days,'hora',to_char(old.hora,'HH24:MI'),'source',case when inferred then 'inferred' else coalesce(old.series_pattern->>'source','saved')end);
   select max(t.fecha),encode(sha256(convert_to(coalesce(jsonb_agg(jsonb_build_array(t.id,t.version,t.fecha,t.hora,t.estado)order by t.id)::text,''),'UTF8')),'hex')into tail,series_snapshot from marathon.turnos t where coalesce(t.original_id,t.id)=root;
   select greatest(tail,coalesce(max((p->>'fecha')::date),tail))into tail from jsonb_array_elements(planned)p where p->>'root'=root;
   select t.duracion_min into duration from marathon.terapias t where t.id=old.terapia_id and t.estado='ACTIVO';
   if duration is null then raise sqlstate '22023' using message='La terapia ya no está activa.';end if;
   start_day=greatest(tail+1,today);last_day=least(start_day+365,date '2100-12-31');chosen=null;
   for d in select start_day+n from generate_series(0,last_day-start_day)n where extract(dow from start_day+n)::int=any(days)order by n loop
    if d+old.hora<=now_local then continue;end if;
    if not marathon.recovery_free(d,old.sede,old.profesional_id,old.terapia_id,old.hora,marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration),planned)then continue;end if;
    if exists(select 1 from marathon.turnos t where t.fecha=d and t.dni=old.dni and t.estado<>'CANCELADO' and t.hora<old.hora+marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration)*interval '1 minute' and old.hora<t.hora+marathon.session_minutes(t.fecha,t.sede,t.profesional_id,t.hora,t.duracion_min)*interval '1 minute')then continue;end if;
    if exists(select 1 from jsonb_array_elements(planned)p where p->>'dni'=old.dni and p->>'fecha'=d::text and(p->>'hora')::time<old.hora+marathon.session_minutes(d,old.sede,old.profesional_id,old.hora,duration)*interval '1 minute' and old.hora<(p->>'hora')::time+(p->>'duration_min')::int*interval '1 minute')then continue;end if;
    chosen=d;exit;
   end loop;
   if chosen is null then raise sqlstate '22023' using message='No se encontró una fecha compatible en los próximos 366 días de búsqueda. No se guardó ninguna recuperación.';end if;
   duration=marathon.session_minutes(chosen,old.sede,old.profesional_id,old.hora,duration);
   row_data=row_data||jsonb_build_object('proposed_fecha',chosen,'proposed_hora',to_char(old.hora,'HH24:MI'),'duration_min',duration,'root',root,'pattern',pattern,'pattern_inferred',inferred,'series_snapshot',series_snapshot);
   planned=planned||jsonb_build_array(jsonb_build_object('root',root,'fecha',chosen,'hora',to_char(old.hora,'HH24:MI'),'dni',old.dni,'prof',old.profesional_id,'therapy',old.terapia_id,'sede',old.sede,'duration_min',duration));
  end if;
  rows=rows||jsonb_build_array(row_data);
 end loop;
 return jsonb_build_object('action',p_action,'rows',rows,'review_token',encode(sha256(convert_to(jsonb_build_object('action',p_action,'rows',rows)::text,'UTF8')),'hex'));
end $_$;


--
-- Name: marathon_user_link(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_link(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare r jsonb;email text;name text;role text;u uuid;begin
 r=marathon.operation_begin(p_request_id,'user:link',p_data);
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede vincular cuentas.';end if;
 if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['email','display_name','role']))then raise sqlstate '22023' using message='Campos inválidos.';end if;
 email=lower(marathon.master_text(p_data,'email',254,true));name=marathon.master_text(p_data,'display_name',100,true);role=marathon.master_text(p_data,'role',10,true);
 if role not in('ADMIN','SECRETARIA')then raise sqlstate '22023' using message='Rol inválido.';end if;
 if exists(select 1 from marathon.user_provision p where p.email=email and p.finished_at is null)then raise sqlstate 'PT409' using message='Ese correo tiene un alta pendiente. Retomala desde el listado.';end if;
 select id into u from auth.users where lower(auth.users.email)=email and email_confirmed_at is not null;
 if u is null then raise sqlstate '22023' using message='No hay una cuenta confirmada con ese correo. Creala desde Nuevo usuario.';end if;
 if exists(select 1 from marathon.app_users where user_id=u)then raise sqlstate '22023' using message='La cuenta ya está en Usuarios. Editá su acceso desde el listado.';end if;
 insert into marathon.app_users(user_id,display_name,role,active,created_by,updated_by)values(u,name,role,true,auth.uid(),auth.uid());
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'user',u::text,'link',jsonb_build_object('email',email,'name',name,'role',role,'active',true));
 r=jsonb_build_object('id',u,'message','Cuenta vinculada y habilitada.');update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $$;


--
-- Name: marathon_user_list(text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_list(p_query text DEFAULT ''::text, p_after uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_variable
declare rows jsonb;nxt uuid;plans jsonb;begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo administración puede gestionar usuarios.';end if;
 if p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_query,''))>100 then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by user_id),'[]'::jsonb)into rows from(
 select a.user_id,a.display_name,a.role,a.active,a.version,coalesce(u.email,'')email,u.email_confirmed_at is not null confirmed,u.last_sign_in_at
 from marathon.app_users a join auth.users u on u.id=a.user_id where (p_after is null or a.user_id>p_after)and(coalesce(p_query,'')=''or strpos(marathon.master_norm(a.display_name||' '||coalesce(u.email,'')),marathon.master_norm(p_query))>0)order by a.user_id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=(rows->(p_limit-1)->>'user_id')::uuid;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'email',email,'display_name',display_name,'role',role,'created_at',created_at)order by created_at),'[]'::jsonb)into plans from marathon.user_provision where finished_at is null;
 return jsonb_build_object('rows',rows,'next',nxt,'pending',plans);
end $$;


--
-- Name: marathon_user_provision_begin(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_provision_begin(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare r jsonb;email text;name text;role text;begin
 r=marathon.operation_begin(p_request_id,'user:provision',p_data);
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede crear usuarios.';end if;
 if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['email','display_name','role']))then raise sqlstate '22023' using message='Campos de usuario inválidos.';end if;
 email=lower(marathon.master_text(p_data,'email',254,true));name=marathon.master_text(p_data,'display_name',100,true);role=marathon.master_text(p_data,'role',10,true);
 if email!~'^[a-z0-9.!#$%&*+/=?^_`{|}~-]+@[a-z0-9-]+(\.[a-z0-9-]+)+$'or role not in('ADMIN','SECRETARIA')then raise sqlstate '22023' using message='Correo o rol inválido.';end if;
 if exists(select 1 from marathon.user_provision p where p.email=email and p.finished_at is null)then raise sqlstate 'PT409' using message='Hay un alta pendiente para ese correo. Retomala desde Altas pendientes.';end if;
 if exists(select 1 from auth.users u where lower(u.email)=email)then raise sqlstate '22023' using message='Ya existe una cuenta con ese correo. Usá Vincular cuenta existente si todavía no tiene acceso a Marathon.';end if;
 if(select count(*)from marathon.user_provision where finished_at is null)>=50 then raise sqlstate '22023' using message='Hay 50 altas pendientes. Completalas antes de crear otra.';end if;
 insert into marathon.user_provision(id,email,display_name,role,created_by)values(p_request_id,email,name,role,auth.uid());
 r=jsonb_build_object('id',p_request_id);update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $_$;


--
-- Name: marathon_user_provision_finish(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_provision_finish(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
#variable_conflict use_variable
declare r jsonb;p marathon.user_provision%rowtype;u uuid;begin
 r=marathon.operation_begin(p_request_id,'user:provision_finish',p_data);
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede gestionar usuarios.';end if;
 if r is not null then return r;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>'plan_id')then raise sqlstate '22023' using message='Alta inválida.';end if;
 select * into p from marathon.user_provision where id=p_data->>'plan_id'for update;if not found then raise sqlstate 'PT404' using message='No se encontró el alta.';end if;
 if p.finished_at is null then
 select id into u from auth.users where lower(email)=p.email and email_confirmed_at is not null;
 if u is null then raise sqlstate 'PT409' using message='La cuenta de autenticación aún no está confirmada.';end if;
 if exists(select 1 from marathon.app_users where user_id=u)then raise sqlstate 'PT409' using message='La cuenta ya tiene un perfil. Revisá Usuarios antes de continuar.';end if;
 insert into marathon.app_users(user_id,display_name,role,active,created_by,updated_by)values(u,p.display_name,p.role,true,auth.uid(),auth.uid());
 update marathon.user_provision set auth_user_id=u,finished_at=now()where id=p.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)values(p_request_id,auth.uid(),'user',u::text,'create',jsonb_build_object('name',p.display_name,'role',p.role,'email',p.email,'active',true,'plan_id',p.id));
 else u=p.auth_user_id;end if;
 r=jsonb_build_object('id',u,'message','Usuario creado y habilitado.');update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $$;


--
-- Name: marathon_user_provision_status(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_provision_status(p_id text) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
#variable_conflict use_variable
declare p marathon.user_provision%rowtype;u uuid;confirmed boolean;begin
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede gestionar altas.';end if;
 select * into p from marathon.user_provision where id=p_id;if not found then raise sqlstate 'PT404' using message='No se encontró el alta.';end if;
 select id,email_confirmed_at is not null into u,confirmed from auth.users where lower(email)=p.email;
 return jsonb_build_object('id',p.id,'email',p.email,'display_name',p.display_name,'role',p.role,'auth_id',u,'confirmed',coalesce(confirmed,false),'finished',p.finished_at is not null);
end $$;


--
-- Name: marathon_user_save(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_user_save(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare r jsonb;a marathon.app_users%rowtype;target uuid;name text;role text;active boolean;begin
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede gestionar usuarios.';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['user_id','version','display_name','role','active']))or coalesce(p_data->>'user_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'then raise sqlstate '22023' using message='Datos de acceso inválidos.';end if;
 target=(p_data->>'user_id')::uuid;
 -- NOWAIT evita invertir el orden de candados con operaciones clínicas del usuario objetivo.
 perform 1 from marathon.app_users where user_id=target for update nowait;
 if not found then raise sqlstate 'PT404' using message='El perfil ya no existe.';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0))then raise sqlstate '55P03' using message='Hay una operación en curso. Volvé a intentar en unos segundos.';end if;
 r=marathon.operation_begin(p_request_id,'user:save',p_data);
 if not marathon.is_admin()then raise sqlstate '42501' using message='Solo administración puede gestionar usuarios.';end if;
 if r is not null then return r;end if;
 select * into a from marathon.app_users where user_id=target;
 if a.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='El acceso cambió. Volvé a abrirlo antes de guardar.';end if;
 name=marathon.master_text(p_data,'display_name',100,true);role=marathon.master_text(p_data,'role',10,true);
 if role not in('ADMIN','SECRETARIA')or jsonb_typeof(p_data->'active')is distinct from'boolean'then raise sqlstate '22023' using message='Rol o estado inválidos.';end if;active=(p_data->>'active')::boolean;
 if a.user_id=auth.uid()and(not active or role<>a.role)then raise sqlstate '22023' using message='No podés desactivar tu propia cuenta ni cambiar tu propio rol.';end if;
 if a.active and a.role='ADMIN'and(not active or role<>'ADMIN')and not exists(select 1 from marathon.app_users where user_id<>target and active and app_users.role='ADMIN')then raise sqlstate '22023' using message='Debe quedar al menos un administrador activo.';end if;
 update marathon.app_users set display_name=name,role=role,active=active where user_id=target;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'user',target::text,'save',jsonb_build_object('name',a.display_name,'role',a.role,'active',a.active),jsonb_build_object('name',name,'role',role,'active',active));
 r=jsonb_build_object('id',target,'message','Acceso actualizado.');update marathon.solicitudes set resultado=r where id=p_request_id;return r;
end $_$;


--
-- Name: marathon_wa_worker(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wa_worker(p_action text, p_data jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select marathon.wa_worker(p_action,p_data) $$;


--
-- Name: marathon_wait_book(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wait_book(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
declare reply jsonb;old marathon.espera%rowtype;booking jsonb;after_data jsonb;begin
 reply=marathon.operation_begin(p_request_id,'wait-book',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['wait_id','version','booking'])) or jsonb_typeof(p_data->'booking') is distinct from 'object' then raise sqlstate '22023' using message='Reserva desde espera inválida.';end if;
 booking=p_data->'booking';select * into old from marathon.espera where id=marathon.master_text(p_data,'wait_id',100,true) for update;
 if old.id is null or old.estado not in ('PENDIENTE','CONTACTADO') or old.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El pedido cambió o ya fue resuelto. Actualizá la lista.';end if;
 if booking->>'dni' is distinct from old.dni or booking->>'therapy' is distinct from old.terapia_id or booking->>'sede' is distinct from old.sede or(old.profesional_id is not null and booking->>'prof' is distinct from old.profesional_id) then raise sqlstate '22023' using message='La reserva no corresponde al paciente, terapia, sede o profesional del pedido.';end if;
 reply=public.marathon_agenda_command('WB-'||gen_random_uuid()::text,'book',booking);
 update marathon.espera set estado='RESUELTO',reserved_turn_id=reply->'ids'->>0 where id=old.id;select to_jsonb(e) into after_data from marathon.espera e where id=old.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'wait',old.id,'book',to_jsonb(old),after_data);
 reply=reply||jsonb_build_object('wait_id',old.id,'message',(reply->>'message')||' Pedido de espera resuelto.');update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end $$;


--
-- Name: marathon_wait_list(text, text, text, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wait_list(p_state text DEFAULT 'PENDIENTE'::text, p_sede text DEFAULT ''::text, p_query text DEFAULT ''::text, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$ declare rows jsonb;nxt jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_state is null or p_state not in ('','PENDIENTE','CONTACTADO','RESUELTO','CANCELADO') or p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_query,''))>100 or
 (p_after is not null and (jsonb_typeof(p_after)<>'object' or not(p_after ?& array['fecha','id']))) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into rows from(
 select e.*,concat_ws(' ',p.apellido,p.nombre,nullif(p.segundo_nombre,'')) paciente,t.nombre terapia,concat_ws(' ',pr.nombre,pr.apellido) profesional from marathon.espera e join marathon.pacientes p on p.dni=e.dni join marathon.terapias t on t.id=e.terapia_id left join marathon.profesionales pr on pr.id=e.profesional_id
 where(p_state='' or e.estado=p_state) and(coalesce(p_sede,'')='' or e.sede=p_sede) and(coalesce(p_query,'')='' or starts_with(e.dni,p_query) or strpos(marathon.master_norm(concat_ws(' ',p.apellido,p.nombre)),marathon.master_norm(p_query))>0)
 and(p_after is null or(e.fecha,e.id)>(marathon.agenda_date(p_after->>'fecha'),p_after->>'id')) order by e.fecha,e.id limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','id',rows->(p_limit-1)->>'id');end if;return jsonb_build_object('rows',rows,'next',nxt);
end $$;


--
-- Name: marathon_wait_save(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wait_save(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $_$
#variable_conflict use_variable
declare reply jsonb;id text;old marathon.espera%rowtype;dni text;therapy text;prof text;site text;obs text;pref jsonb;v jsonb;duration integer;day_num integer;m integer;after_data jsonb;state text;
begin
 reply=marathon.operation_begin(p_request_id,'wait-save',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k<>all(array['id','version','dni','therapy','prof','sede','observaciones','preferences'])) then raise sqlstate '22023' using message='Campos de espera inválidos.';end if;
 id=marathon.master_text(p_data,'id',100);
 if id<>'' then select * into old from marathon.espera e where e.id=id for update;if old.id is null then raise sqlstate 'PT404' using message='El pedido ya no existe.';end if;
  if old.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El pedido cambió. Actualizá la lista de espera.';end if;
  if old.estado not in ('PENDIENTE','CONTACTADO') then raise sqlstate '22023' using message='Solo se editan pedidos abiertos.';end if;
 else if p_data ? 'version' then raise sqlstate '22023' using message='Versión inválida para un pedido nuevo.';end if;id='ESP-'||gen_random_uuid()::text;end if;
 dni=marathon.master_text(p_data,'dni',12,true);therapy=marathon.master_text(p_data,'therapy',100,true);prof=nullif(marathon.master_text(p_data,'prof',100),'');site=marathon.master_text(p_data,'sede',40,true);obs=marathon.master_text(p_data,'observaciones',2000);pref=p_data->'preferences';
 if not exists(select 1 from marathon.pacientes p where p.dni=dni) or not exists(select 1 from marathon.sedes s where s.nombre=site and estado='ACTIVO') then raise sqlstate '22023' using message='Seleccioná un paciente registrado y una sede activa.';end if;
 state=coalesce(old.estado,'PENDIENTE');
 if state='PENDIENTE' and exists(select 1 from marathon.espera e where e.dni=dni and e.terapia_id=therapy and e.estado='PENDIENTE' and e.id<>id) then raise sqlstate 'PT409' using message='El paciente ya tiene un pedido pendiente para esta terapia.';end if;
 select duracion_min into duration from marathon.terapias t where t.id=therapy and t.estado='ACTIVO';
 if duration is null or not exists(select 1 from marathon.profesionales p join marathon.profesional_terapias pt on pt.profesional_id=p.id and pt.terapia_id=therapy join marathon.horarios h on h.profesional_id=p.id and h.sede=site where p.estado='ACTIVO' and(prof is null or p.id=prof) and h.fin-h.inicio>=duration*interval '1 minute') then raise sqlstate '22023' using message='La terapia o el profesional no tiene horarios en esa sede.';end if;
 if jsonb_typeof(pref) is distinct from 'object' or exists(select 1 from jsonb_object_keys(pref)k where k<>all(array['version','any','slots'])) or pref->'version' is distinct from '1'::jsonb or jsonb_typeof(pref->'any') is distinct from 'boolean' or jsonb_typeof(pref->'slots') is distinct from 'array' or jsonb_array_length(pref->'slots')>100 then raise sqlstate '22023' using message='Preferencias inválidas.';end if;
 if not(pref->>'any')::boolean and jsonb_array_length(pref->'slots')=0 then raise sqlstate '22023' using message='Seleccioná al menos un horario o Cualquier horario.';end if;
 for v in select value from jsonb_array_elements(pref->'slots') loop
  if jsonb_typeof(v)<>'object' or exists(select 1 from jsonb_object_keys(v) k where k<>all(array['day','m'])) or jsonb_typeof(v->'day') is distinct from 'number' or coalesce(v->>'day','') !~ '^[0-6]$' or jsonb_typeof(v->'m') is distinct from 'number' or coalesce(v->>'m','') !~ '^[0-9]{1,4}$' then raise sqlstate '22023' using message='Día u hora de preferencia inválidos.';end if;
  day_num=(v->>'day')::int;m=(v->>'m')::int;
  if m>1439 or not exists(select 1 from marathon.horarios h join marathon.profesionales p on p.id=h.profesional_id and p.estado='ACTIVO' join marathon.profesional_terapias pt on pt.profesional_id=p.id and pt.terapia_id=therapy where h.sede=site and(prof is null or p.id=prof) and h.dia=day_num and m>=(extract(epoch from h.inicio)/60)::int and m+duration<=(extract(epoch from h.fin)/60)::int and (m-(extract(epoch from h.inicio)/60)::int)%15=0) then raise sqlstate '22023' using message='Uno de los horarios preferidos no está admitido en esa sede.';end if;
 end loop;
 if(pref->>'any')::boolean then pref=jsonb_build_object('version',1,'any',true,'slots','[]'::jsonb);end if;
 if old.id is null then insert into marathon.espera(id,fecha,dni,terapia_id,profesional_id,sede,estado,preferencias_legacy,observaciones,created_by,updated_by) values(id,(now() at time zone 'America/Argentina/Buenos_Aires')::date,dni,therapy,prof,site,state,pref::text,obs,auth.uid(),auth.uid());
 else update marathon.espera e set dni=dni,terapia_id=therapy,profesional_id=prof,sede=site,preferencias_legacy=pref::text,observaciones=obs where e.id=id;end if;
 select to_jsonb(e) into after_data from marathon.espera e where e.id=id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'wait',id,'save',case when old.id is not null then to_jsonb(old) end,after_data);
 reply=jsonb_build_object('id',id,'message','Pedido de espera guardado.');update marathon.solicitudes s set resultado=reply where s.id=p_request_id;return reply;
end $_$;


--
-- Name: marathon_wait_search(jsonb, jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wait_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare rows jsonb;nxt jsonb;counts jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['sede','prof','therapy','query','insurance','state','show_cancelled'],p_limit,p_after);
 if coalesce(p_filters->>'state','')not in('','PENDIENTE','CONTACTADO','RESUELTO','CANCELADO')or(p_filters?'show_cancelled'and jsonb_typeof(p_filters->'show_cancelled')<>'boolean')or(p_after is not null and not(p_after?&array['fecha','id']))then raise sqlstate '22023'using message='Filtros de espera inválidos.';end if;
 with filtered as(select * from marathon.daily_wait where(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'prof','')=''or profesional_id=p_filters->>'prof')and(coalesce(p_filters->>'therapy','')=''or terapia_id=p_filters->>'therapy')and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(paciente||' '||dni),marathon.master_norm(p_filters->>'query'))>0)and(coalesce(p_filters->>'insurance','')=''or coalesce(obra_social_id,'__PARTICULAR__')=p_filters->>'insurance')and(coalesce(p_filters->>'state','')=''or estado=p_filters->>'state')and(coalesce((p_filters->>'show_cancelled')::boolean,false)or estado<>'CANCELADO')),
 page as(select * from filtered where p_after is null or(fecha,id)>(marathon.agenda_date(p_after->>'fecha'),p_after->>'id')order by fecha,id limit p_limit+1)
 select coalesce((select jsonb_agg(to_jsonb(x)order by fecha,id)from page x),'[]'::jsonb),(select jsonb_build_object('PENDIENTE',count(*)filter(where estado='PENDIENTE'),'CONTACTADO',count(*)filter(where estado='CONTACTADO'),'RESUELTO',count(*)filter(where estado='RESUELTO'),'CANCELADO',count(*)filter(where estado='CANCELADO'))from filtered)into rows,counts;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','id',rows->(p_limit-1)->>'id');end if;return jsonb_build_object('rows',rows,'next',nxt,'counts',counts);
end $$;


--
-- Name: marathon_wait_status(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_wait_status(p_request_id text, p_data jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET lock_timeout TO '3s'
    AS $$
declare reply jsonb;old marathon.espera%rowtype;s text;after_data jsonb;begin
 reply=marathon.operation_begin(p_request_id,'wait-status',p_data);if reply is not null then return reply;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','estado'])) then raise sqlstate '22023' using message='Campos inválidos.';end if;
 s=marathon.master_text(p_data,'estado',10,true);if s not in ('PENDIENTE','CONTACTADO','RESUELTO','CANCELADO') then raise sqlstate '22023' using message='Estado inválido.';end if;
 select * into old from marathon.espera where id=marathon.master_text(p_data,'id',100,true) for update;
 if old.id is null then raise sqlstate 'PT404' using message='Pedido no encontrado.';end if;
 if old.version<>marathon.operation_version(p_data) then raise sqlstate 'PT409' using message='El pedido cambió. Actualizá la lista.';end if;
 if s='PENDIENTE' and exists(select 1 from marathon.espera e where e.id<>old.id and e.dni=old.dni and e.terapia_id=old.terapia_id and estado='PENDIENTE') then raise sqlstate 'PT409' using message='El paciente ya tiene otro pedido pendiente para esta terapia.';end if;
 update marathon.espera set estado=s where id=old.id;select to_jsonb(e) into after_data from marathon.espera e where id=old.id;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data) values(p_request_id,auth.uid(),'wait',old.id,'status',to_jsonb(old),after_data);
 reply=jsonb_build_object('id',old.id,'message','Lista de espera actualizada.');update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end $$;


--
-- Name: marathon_whatsapp_begin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_whatsapp_begin() RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select marathon.wa_begin() $$;


--
-- Name: marathon_whatsapp_configure(jsonb, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_whatsapp_configure(p_data jsonb, p_version bigint, p_request_id uuid) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select marathon.wa_configure(p_data,p_version,p_request_id) $$;


--
-- Name: marathon_whatsapp_status(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_whatsapp_status() RETURNS jsonb
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$ select marathon.wa_status() $$;


--
-- Name: marathon_whatsapp_template_save(text, text, bigint, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_whatsapp_template_save(p_id text, p_body text, p_version bigint, p_request_id uuid) RETURNS jsonb
    LANGUAGE sql
    SET search_path TO ''
    AS $$ select marathon.whatsapp_template_save(p_id,p_body,p_version,p_request_id) $$;


--
-- Name: marathon_whatsapp_templates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.marathon_whatsapp_templates() RETURNS jsonb
    LANGUAGE plpgsql STABLE
    SET search_path TO ''
    AS $$
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'trigger_label',trigger_label,'body',body,'default_body',default_body,'version',version,'updated_at',updated_at,'status','DRAFT') order by case id when 'confirmation' then 1 when 'reminder' then 2 when 'cancellation' then 3 else 4 end),'[]'::jsonb)from marathon.whatsapp_message_templates);
end $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: agenda_ajustes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_ajustes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    cuota_id uuid NOT NULL,
    importe numeric(12,2) NOT NULL,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT agenda_ajustes_importe_check CHECK ((importe > (0)::numeric)),
    CONSTRAINT agenda_ajustes_motivo_check CHECK (((length(btrim(motivo)) >= 3) AND (length(btrim(motivo)) <= 1000)))
);


--
-- Name: agenda_autorizaciones; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_autorizaciones (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    cantidad integer NOT NULL,
    fecha date NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT agenda_autorizaciones_cantidad_check CHECK (((cantidad >= 1) AND (cantidad <= 1000)))
);


--
-- Name: agenda_cuotas; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_cuotas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    periodo_id uuid NOT NULL,
    fecha date NOT NULL,
    hasta date NOT NULL,
    importe numeric(12,2) NOT NULL,
    sede text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT agenda_cuotas_check CHECK ((hasta > fecha)),
    CONSTRAINT agenda_cuotas_importe_check CHECK ((importe >= (0)::numeric))
);


--
-- Name: agenda_horarios; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_horarios (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    sede text NOT NULL,
    profesional_id text NOT NULL,
    dia integer NOT NULL,
    hora time without time zone NOT NULL,
    duracion_min integer NOT NULL,
    desde date NOT NULL,
    hasta date,
    CONSTRAINT agenda_horarios_check CHECK (((hasta IS NULL) OR (hasta >= desde))),
    CONSTRAINT agenda_horarios_dia_check CHECK (((dia >= 1) AND (dia <= 5))),
    CONSTRAINT agenda_horarios_duracion_min_check CHECK ((duracion_min > 0))
);


--
-- Name: agenda_pausas; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_pausas (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    desde date NOT NULL,
    hasta date,
    motivo text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    CONSTRAINT agenda_pausas_check CHECK (((hasta IS NULL) OR (hasta >= desde))),
    CONSTRAINT agenda_pausas_motivo_check CHECK (((length(btrim(motivo)) >= 3) AND (length(btrim(motivo)) <= 1000)))
);


--
-- Name: agenda_periodos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_periodos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    plan_id uuid NOT NULL,
    inicio date NOT NULL,
    fin date,
    anulado boolean DEFAULT false NOT NULL,
    CONSTRAINT agenda_periodos_check CHECK (((fin IS NULL) OR (fin >= inicio)))
);


--
-- Name: agenda_planes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.agenda_planes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dni text NOT NULL,
    terapia_id text NOT NULL,
    modalidad text NOT NULL,
    facturacion text NOT NULL,
    importe numeric(12,2) NOT NULL,
    inicio date NOT NULL,
    baja date,
    coverage jsonb NOT NULL,
    observaciones text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT agenda_planes_check CHECK (((baja IS NULL) OR (baja >= inicio))),
    CONSTRAINT agenda_planes_check1 CHECK (((facturacion <> 'none'::text) OR (importe = (0)::numeric))),
    CONSTRAINT agenda_planes_facturacion_check CHECK ((facturacion = ANY (ARRAY['class'::text, 'bonus_class'::text, 'monthly'::text, 'none'::text]))),
    CONSTRAINT agenda_planes_importe_check CHECK ((importe >= (0)::numeric)),
    CONSTRAINT agenda_planes_modalidad_check CHECK ((modalidad = ANY (ARRAY['sessions'::text, 'monthly'::text, 'fixed'::text]))),
    CONSTRAINT agenda_planes_observaciones_check CHECK ((length(observaciones) <= 1000))
);


--
-- Name: anticipo_eventos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.anticipo_eventos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    anticipo_id text NOT NULL,
    turno_id text,
    tipo text NOT NULL,
    monto numeric(18,2) NOT NULL,
    movimiento_id text,
    request_id text NOT NULL,
    actor uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT anticipo_eventos_check CHECK ((((tipo = ANY (ARRAY['DEPOSITO'::text, 'DEVOLUCION'::text])) AND (turno_id IS NULL) AND (movimiento_id IS NOT NULL)) OR ((tipo = ANY (ARRAY['APLICACION'::text, 'REVERSO'::text])) AND (turno_id IS NOT NULL) AND (movimiento_id IS NULL)))),
    CONSTRAINT anticipo_eventos_monto_check CHECK ((monto > (0)::numeric)),
    CONSTRAINT anticipo_eventos_tipo_check CHECK ((tipo = ANY (ARRAY['DEPOSITO'::text, 'APLICACION'::text, 'REVERSO'::text, 'DEVOLUCION'::text])))
);


--
-- Name: anticipos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.anticipos (
    id text NOT NULL,
    dni text NOT NULL,
    sede text NOT NULL,
    terapia_id text,
    profesional_id text,
    importe numeric(18,2) NOT NULL,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    observaciones text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT anticipos_importe_check CHECK ((importe > (0)::numeric))
);


--
-- Name: app_users; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.app_users (
    user_id uuid NOT NULL,
    role text NOT NULL,
    active boolean DEFAULT false NOT NULL,
    display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT app_users_role_check CHECK ((role = ANY (ARRAY['ADMIN'::text, 'SECRETARIA'::text]))),
    CONSTRAINT app_users_version_check CHECK ((version > 0))
);


--
-- Name: attendance_settings; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.attendance_settings (
    id boolean DEFAULT true NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    start_date date NOT NULL,
    CONSTRAINT attendance_settings_id_check CHECK (id)
);


--
-- Name: attendance_system_audit; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.attendance_system_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    turn_id text NOT NULL,
    run_day date NOT NULL,
    before_data jsonb NOT NULL,
    after_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: bonos_serie; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.bonos_serie (
    id text NOT NULL,
    serie_id text NOT NULL,
    dni text NOT NULL,
    sede text NOT NULL,
    terapia_id text NOT NULL,
    profesional_id text NOT NULL,
    importe numeric NOT NULL,
    estado text DEFAULT 'ACTIVO'::text NOT NULL,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    primera_fecha date NOT NULL,
    sesiones integer NOT NULL,
    observaciones text,
    created_by uuid,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT bonos_serie_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'ANULADO'::text]))),
    CONSTRAINT bonos_serie_importe_check CHECK ((importe > (0)::numeric)),
    CONSTRAINT bonos_serie_sesiones_check CHECK (((sesiones >= 1) AND (sesiones <= 60))),
    CONSTRAINT bonos_serie_version_check CHECK ((version > 0))
);


--
-- Name: profesionales; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.profesionales (
    id text NOT NULL,
    nombre text NOT NULL,
    segundo_nombre text,
    apellido text NOT NULL,
    matricula text,
    especialidad text,
    estado text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT profesionales_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: terapias; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.terapias (
    id text NOT NULL,
    especialidad text,
    nombre text NOT NULL,
    duracion_min integer NOT NULL,
    capacidad integer NOT NULL,
    estado text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT terapias_capacidad_check CHECK (((capacidad >= 1) AND (capacidad <= 200))),
    CONSTRAINT terapias_duracion_min_check CHECK (((duracion_min >= 5) AND (duracion_min <= 480))),
    CONSTRAINT terapias_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: daily_advance; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_advance WITH (security_invoker='true') AS
 SELECT a.id,
    a.dni,
    a.sede,
    a.terapia_id,
    a.profesional_id,
    a.importe,
    a.fecha,
    a.hora,
    a.observaciones,
    a.created_at,
    a.updated_at,
    a.created_by,
    a.updated_by,
    a.version,
    COALESCE(th.nombre, 'Cualquier terapia'::text) AS terapia,
    COALESCE(NULLIF(concat_ws(' '::text, p.nombre, p.apellido), ''::text), 'Cualquier profesional'::text) AS profesional,
    COALESCE(( SELECT sum(
                CASE
                    WHEN (e.tipo = ANY (ARRAY['DEPOSITO'::text, 'REVERSO'::text])) THEN e.monto
                    ELSE (- e.monto)
                END) AS sum
           FROM marathon.anticipo_eventos e
          WHERE (e.anticipo_id = a.id)), (0)::numeric) AS available
   FROM ((marathon.anticipos a
     LEFT JOIN marathon.terapias th ON ((th.id = a.terapia_id)))
     LEFT JOIN marathon.profesionales p ON ((p.id = a.profesional_id)));


--
-- Name: movimientos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.movimientos (
    id text NOT NULL,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    origen text NOT NULL,
    tipo text NOT NULL,
    dni text,
    monto numeric(18,2) NOT NULL,
    medio text NOT NULL,
    sede text NOT NULL,
    secretaria_legacy text,
    turno_id text,
    operacion_id text,
    concepto text,
    observaciones_legacy text,
    compensacion_de text,
    motivo text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    categoria text,
    profesional_asociado_id text,
    secretaria_asociada text,
    bono_id text,
    anticipo_id text,
    cuota_id uuid,
    CONSTRAINT movimiento_cuota_shape CHECK (((cuota_id IS NULL) OR ((origen = 'CAJA'::text) AND (tipo = ANY (ARRAY['INGRESO'::text, 'EGRESO'::text])) AND (turno_id IS NULL) AND (bono_id IS NULL) AND (anticipo_id IS NULL) AND (operacion_id IS NULL)))),
    CONSTRAINT movimientos_anticipo_shape CHECK (((anticipo_id IS NULL) OR ((origen = 'ANTICIPO'::text) AND (tipo = ANY (ARRAY['INGRESO'::text, 'EGRESO'::text])) AND (turno_id IS NULL) AND (bono_id IS NULL) AND (operacion_id IS NULL)))),
    CONSTRAINT movimientos_bono_shape CHECK (((bono_id IS NULL) OR ((origen = 'BONO'::text) AND (turno_id IS NULL) AND (operacion_id IS NULL) AND (tipo = ANY (ARRAY['INGRESO'::text, 'EGRESO'::text]))))),
    CONSTRAINT movimientos_check CHECK (((compensacion_de IS NULL) OR ((compensacion_de <> id) AND (length(TRIM(BOTH FROM motivo)) >= 3)))),
    CONSTRAINT movimientos_medio_check CHECK ((medio = ANY (ARRAY['EFECTIVO'::text, 'TRANSFERENCIA'::text]))),
    CONSTRAINT movimientos_monto_check CHECK ((monto >= (0)::numeric)),
    CONSTRAINT movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['PAGO'::text, 'INGRESO'::text, 'EGRESO'::text, 'REINTEGRO'::text])))
);


--
-- Name: daily_bonus; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_bonus WITH (security_invoker='true') AS
 SELECT b.id,
    b.serie_id,
    b.dni,
    b.sede,
    b.terapia_id,
    b.profesional_id,
    b.importe,
    b.estado,
    b.fecha,
    b.hora,
    b.primera_fecha,
    b.sesiones,
    b.observaciones,
    b.created_by,
    b.updated_by,
    b.created_at,
    b.updated_at,
    b.version,
    th.nombre AS terapia,
    concat_ws(' '::text, p.nombre, NULLIF(p.segundo_nombre, ''::text), p.apellido) AS profesional,
    pay.paid,
        CASE
            WHEN (b.estado = 'ACTIVO'::text) THEN GREATEST((0)::numeric, (b.importe - pay.paid))
            ELSE (0)::numeric
        END AS debt
   FROM (((marathon.bonos_serie b
     JOIN marathon.terapias th ON ((th.id = b.terapia_id)))
     JOIN marathon.profesionales p ON ((p.id = b.profesional_id)))
     CROSS JOIN LATERAL ( SELECT COALESCE(sum(
                CASE
                    WHEN (m.tipo = 'EGRESO'::text) THEN (- m.monto)
                    ELSE m.monto
                END), (0)::numeric) AS paid
           FROM marathon.movimientos m
          WHERE ((m.bono_id = b.id) AND (m.origen = 'BONO'::text))) pay);


--
-- Name: pacientes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.pacientes (
    dni text NOT NULL,
    nombre text NOT NULL,
    segundo_nombre text,
    apellido text NOT NULL,
    obra_social_id text,
    afiliado text,
    nacimiento date,
    domicilio text,
    localidad text,
    provincia text,
    telefono text,
    email text,
    sexo text,
    medico text,
    observaciones text,
    documentos_legacy text,
    sesiones_autorizadas integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    coberturas jsonb,
    CONSTRAINT pacientes_apellido_check CHECK ((length(TRIM(BOTH FROM apellido)) > 0)),
    CONSTRAINT pacientes_coberturas_shape CHECK (((coberturas IS NULL) OR ((jsonb_typeof(coberturas) = 'array'::text) AND (jsonb_array_length(coberturas) <= 20)))),
    CONSTRAINT pacientes_dni_check CHECK ((dni ~ '^[0-9]{1,12}$'::text)),
    CONSTRAINT pacientes_nombre_check CHECK ((length(TRIM(BOTH FROM nombre)) > 0)),
    CONSTRAINT pacientes_sesiones_autorizadas_check CHECK ((sesiones_autorizadas >= 0))
);


--
-- Name: COLUMN pacientes.coberturas; Type: COMMENT; Schema: marathon; Owner: -
--

COMMENT ON COLUMN marathon.pacientes.coberturas IS 'Lista de obra_social_id y afiliado. NULL conserva la compatibilidad con la ficha anterior.';


--
-- Name: turnos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.turnos (
    id text NOT NULL,
    original_id text,
    fecha date NOT NULL,
    sede text NOT NULL,
    hora time without time zone NOT NULL,
    duracion_min integer NOT NULL,
    terapia_id text NOT NULL,
    profesional_id text NOT NULL,
    dni text NOT NULL,
    importe numeric(18,2) NOT NULL,
    estado text NOT NULL,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    coverage jsonb,
    fixed_until date,
    fixed_days integer[],
    attendance_manual_date date,
    attendance_auto boolean DEFAULT false NOT NULL,
    attendance_auto_at timestamp with time zone,
    series_pattern jsonb,
    recovered_from text,
    booking_notes text,
    plan_id uuid,
    horario_id uuid,
    fecha_habitual date,
    autorizacion_id uuid,
    agenda_motivo text,
    CONSTRAINT turnos_coverage_shape CHECK (((coverage IS NULL) OR ((jsonb_typeof(coverage) = 'object'::text) AND (coverage ? 'type'::text) AND ((coverage ->> 'type'::text) = ANY (ARRAY['PARTICULAR'::text, 'OBRA_SOCIAL'::text, 'ART'::text, 'CLUB'::text]))))),
    CONSTRAINT turnos_duracion_min_check CHECK ((duracion_min > 0)),
    CONSTRAINT turnos_estado_check CHECK ((estado = ANY (ARRAY['PENDIENTE'::text, 'PRESENTE'::text, 'AUSENTE'::text, 'CANCELADO'::text]))),
    CONSTRAINT turnos_fixed_shape CHECK ((((fixed_until IS NULL) AND (fixed_days IS NULL)) OR ((fixed_until IS NOT NULL) AND (fixed_days IS NOT NULL) AND ((cardinality(fixed_days) >= 1) AND (cardinality(fixed_days) <= 7)) AND (fixed_days <@ ARRAY[0, 1, 2, 3, 4, 5, 6])))),
    CONSTRAINT turnos_importe_check CHECK ((importe >= (0)::numeric))
);


--
-- Name: COLUMN turnos.coverage; Type: COMMENT; Schema: marathon; Owner: -
--

COMMENT ON COLUMN marathon.turnos.coverage IS 'Cobertura histórica elegida para este turno. NULL significa sin definir en el cliente anterior.';


--
-- Name: daily_cash; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_cash AS
 SELECT m.id,
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
    COALESCE((m.created_by)::text, ('legacy:'::text || m.secretaria_legacy), 'unknown'::text) AS actor_key,
        CASE
            WHEN (COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id) IS NOT NULL) THEN ('T:'::text || COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id))
            ELSE ('C:'::text || COALESCE(m.categoria,
            CASE
                WHEN (m.origen = 'ORTOPEDIA'::text) THEN 'Ortopedia'::text
                ELSE 'Otros'::text
            END))
        END AS category_key,
    COALESCE(th.nombre, m.categoria,
        CASE
            WHEN (m.origen = 'ORTOPEDIA'::text) THEN 'Ortopedia'::text
            ELSE 'Otros'::text
        END) AS category_label,
    COALESCE(t.profesional_id, b.profesional_id, a.profesional_id, m.profesional_asociado_id) AS professional_key,
    NULLIF(concat_ws(' '::text, pr.nombre, pr.apellido), ''::text) AS profesional,
    COALESCE(NULLIF(concat_ws(' '::text, pr.nombre, pr.apellido), ''::text), m.secretaria_asociada, ''::text) AS associated,
    (EXISTS ( SELECT 1
           FROM marathon.movimientos r
          WHERE (r.compensacion_de = m.id))) AS reversed
   FROM (((((((((marathon.movimientos m
     LEFT JOIN marathon.agenda_cuotas aq ON ((aq.id = m.cuota_id)))
     LEFT JOIN marathon.agenda_planes ap ON ((ap.id = aq.plan_id)))
     LEFT JOIN marathon.turnos t ON ((t.id = m.turno_id)))
     LEFT JOIN marathon.bonos_serie b ON ((b.id = m.bono_id)))
     LEFT JOIN marathon.anticipos a ON ((a.id = m.anticipo_id)))
     LEFT JOIN marathon.terapias th ON ((th.id = COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id))))
     LEFT JOIN marathon.profesionales pr ON ((pr.id = COALESCE(t.profesional_id, b.profesional_id, a.profesional_id, m.profesional_asociado_id))))
     LEFT JOIN marathon.pacientes p ON ((p.dni = m.dni)))
     LEFT JOIN marathon.app_users u ON ((u.user_id = m.created_by)));


--
-- Name: ortopedia_operaciones; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.ortopedia_operaciones (
    id text NOT NULL,
    original_id text,
    fecha date NOT NULL,
    hora time without time zone NOT NULL,
    tipo text NOT NULL,
    producto_id text NOT NULL,
    sede text NOT NULL,
    cantidad integer NOT NULL,
    dni text,
    semanas integer,
    devolucion_prevista date,
    importe_total numeric(18,2) NOT NULL,
    secretaria_legacy text,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    precio_unitario numeric(18,2),
    producto_snapshot jsonb,
    transfer_id uuid,
    subtotal numeric,
    discount_rate numeric,
    discount_amount numeric,
    CONSTRAINT ortho_discount_valid CHECK (((num_nonnulls(subtotal, discount_rate, discount_amount) = 0) OR ((num_nonnulls(subtotal, discount_rate, discount_amount) = 3) AND (tipo = ANY (ARRAY['VENTA'::text, 'ALQUILER'::text])) AND (subtotal >= (0)::numeric) AND ((discount_rate >= (0)::numeric) AND (discount_rate <= (100)::numeric)) AND (discount_amount = round(((subtotal * discount_rate) / (100)::numeric), 2)) AND (importe_total = (subtotal - discount_amount))))),
    CONSTRAINT ortopedia_operaciones_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT ortopedia_operaciones_importe_total_check CHECK ((importe_total >= (0)::numeric)),
    CONSTRAINT ortopedia_operaciones_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric)),
    CONSTRAINT ortopedia_operaciones_semanas_check CHECK (((semanas >= 1) AND (semanas <= 520))),
    CONSTRAINT ortopedia_operaciones_tipo_check CHECK ((tipo = ANY (ARRAY['STOCK_INICIAL'::text, 'VENTA'::text, 'ALQUILER'::text, 'COMPRA'::text, 'AJUSTE_POSITIVO'::text, 'AJUSTE_NEGATIVO'::text, 'DEVOLUCION'::text])))
);


--
-- Name: productos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.productos (
    id text NOT NULL,
    pieza text NOT NULL,
    talle text,
    marca text,
    descripcion text NOT NULL,
    codigo text,
    modalidad text NOT NULL,
    costo numeric(18,2),
    precio_venta numeric(18,2),
    precio_alquiler numeric(18,2),
    estado text NOT NULL,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT productos_costo_check CHECK ((costo >= (0)::numeric)),
    CONSTRAINT productos_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text]))),
    CONSTRAINT productos_modalidad_check CHECK ((modalidad = ANY (ARRAY['VENTA'::text, 'ALQUILER'::text, 'VENTA Y ALQUILER'::text]))),
    CONSTRAINT productos_precio_alquiler_check CHECK ((precio_alquiler >= (0)::numeric)),
    CONSTRAINT productos_precio_venta_check CHECK ((precio_venta >= (0)::numeric))
);


--
-- Name: daily_ortho; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_ortho WITH (security_invoker='true') AS
 SELECT o.id,
    o.original_id,
    o.fecha,
    o.hora,
    o.tipo,
    o.producto_id,
    o.sede,
    o.cantidad,
    o.dni,
    o.semanas,
    o.devolucion_prevista,
    o.importe_total,
    o.secretaria_legacy,
    o.observaciones,
    o.created_at,
    o.updated_at,
    o.created_by,
    o.updated_by,
    o.version,
    o.precio_unitario,
    o.producto_snapshot,
    o.transfer_id,
    COALESCE((o.producto_snapshot ->> 'descripcion'::text), p.descripcion) AS producto,
    p.marca,
    p.codigo,
    concat_ws(' '::text, pac.apellido, pac.nombre, NULLIF(pac.segundo_nombre, ''::text)) AS paciente,
    COALESCE(u.display_name, o.secretaria_legacy, 'Sin registro'::text) AS actor,
    COALESCE((o.created_by)::text, ('legacy:'::text || o.secretaria_legacy), 'unknown'::text) AS actor_key,
    marathon.ortho_paid(o.id) AS paid,
        CASE
            WHEN (o.tipo = ANY (ARRAY['VENTA'::text, 'ALQUILER'::text, 'COMPRA'::text])) THEN GREATEST((0)::numeric, (o.importe_total - marathon.ortho_paid(o.id)))
            ELSE (0)::numeric
        END AS debt,
        CASE
            WHEN (o.tipo = 'ALQUILER'::text) THEN (o.cantidad - marathon.ortho_returned(o.id))
            ELSE (0)::bigint
        END AS pending,
    COALESCE(( SELECT sum(
                CASE
                    WHEN (m.tipo = ANY (ARRAY['INGRESO'::text, 'PAGO'::text])) THEN m.monto
                    WHEN (m.tipo = 'REINTEGRO'::text) THEN (- m.monto)
                    ELSE (0)::numeric
                END) AS sum
           FROM marathon.movimientos m
          WHERE (m.operacion_id = o.id)), (0)::numeric) AS income,
    o.subtotal,
    o.discount_rate,
    o.discount_amount
   FROM (((marathon.ortopedia_operaciones o
     JOIN marathon.productos p ON ((p.id = o.producto_id)))
     LEFT JOIN marathon.pacientes pac ON ((pac.dni = o.dni)))
     LEFT JOIN marathon.app_users u ON ((u.user_id = o.created_by)));


--
-- Name: daily_turns; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_turns WITH (security_invoker='true') AS
 SELECT t.id,
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
            WHEN (t.estado = 'PRESENTE'::text) THEN GREATEST((0)::numeric, (t.importe - marathon.turn_paid(t.id)))
            ELSE (0)::numeric
        END AS debt
   FROM (((marathon.turnos t
     JOIN marathon.terapias th ON ((th.id = t.terapia_id)))
     JOIN marathon.profesionales pr ON ((pr.id = t.profesional_id)))
     JOIN marathon.pacientes p ON ((p.dni = t.dni)));


--
-- Name: espera; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.espera (
    id text NOT NULL,
    fecha date NOT NULL,
    dni text NOT NULL,
    terapia_id text NOT NULL,
    profesional_id text,
    sede text NOT NULL,
    estado text NOT NULL,
    preferencias_legacy text,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    reserved_turn_id text,
    CONSTRAINT espera_estado_check CHECK ((estado = ANY (ARRAY['PENDIENTE'::text, 'CONTACTADO'::text, 'RESUELTO'::text, 'CANCELADO'::text])))
);


--
-- Name: obras_sociales; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.obras_sociales (
    id text NOT NULL,
    nombre text NOT NULL,
    domicilio text,
    localidad text,
    cuit text,
    estado text NOT NULL,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT obras_sociales_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: daily_wait; Type: VIEW; Schema: marathon; Owner: -
--

CREATE VIEW marathon.daily_wait WITH (security_invoker='true') AS
 SELECT e.id,
    e.fecha,
    e.dni,
    e.terapia_id,
    e.profesional_id,
    e.sede,
    e.estado,
    e.preferencias_legacy,
    e.observaciones,
    e.created_at,
    e.updated_at,
    e.created_by,
    e.updated_by,
    e.version,
    e.reserved_turn_id,
    concat_ws(' '::text, p.apellido, p.nombre, NULLIF(p.segundo_nombre, ''::text)) AS paciente,
    th.nombre AS terapia,
    concat_ws(' '::text, pr.nombre, pr.apellido) AS profesional,
    p.obra_social_id,
    COALESCE(os.nombre, 'Particular'::text) AS obra_social
   FROM ((((marathon.espera e
     JOIN marathon.pacientes p ON ((p.dni = e.dni)))
     JOIN marathon.terapias th ON ((th.id = e.terapia_id)))
     LEFT JOIN marathon.profesionales pr ON ((pr.id = e.profesional_id)))
     LEFT JOIN marathon.obras_sociales os ON ((os.id = p.obra_social_id)));


--
-- Name: documentos; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.documentos (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dni text NOT NULL,
    nombre text NOT NULL,
    storage_path text,
    legacy_url text,
    mime text,
    sha256 text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    estado text DEFAULT 'LISTO'::text NOT NULL,
    bytes bigint,
    upload_expires timestamp with time zone,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    CONSTRAINT documentos_bytes_check CHECK (((bytes >= 1) AND (bytes <= 5242880))),
    CONSTRAINT documentos_check CHECK (((storage_path IS NOT NULL) OR (legacy_url IS NOT NULL))),
    CONSTRAINT documentos_estado_check CHECK ((estado = ANY (ARRAY['PENDIENTE'::text, 'LISTO'::text, 'ELIMINANDO'::text, 'ELIMINADO'::text])))
);


--
-- Name: horarios; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.horarios (
    id text NOT NULL,
    profesional_id text NOT NULL,
    sede text NOT NULL,
    dia smallint NOT NULL,
    inicio time without time zone NOT NULL,
    fin time without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT horarios_check CHECK ((fin > inicio)),
    CONSTRAINT horarios_dia_check CHECK (((dia >= 0) AND (dia <= 6)))
);


--
-- Name: informacion_terapias; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.informacion_terapias (
    id text NOT NULL,
    terapia_id text NOT NULL,
    obra_social_id text,
    mensaje text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    estado text DEFAULT 'ACTIVO'::text NOT NULL,
    CONSTRAINT informacion_terapias_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: master_audit; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.master_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_id text NOT NULL,
    actor uuid NOT NULL,
    entity text NOT NULL,
    entity_id text NOT NULL,
    before_data jsonb,
    after_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: operation_audit; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.operation_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_id text NOT NULL,
    actor uuid NOT NULL,
    entity text NOT NULL,
    entity_id text NOT NULL,
    action text NOT NULL,
    before_data jsonb,
    after_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: profesional_terapias; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.profesional_terapias (
    profesional_id text NOT NULL,
    terapia_id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL
);


--
-- Name: secretarias; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.secretarias (
    nombre text NOT NULL,
    email text,
    estado text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT secretarias_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: sedes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.sedes (
    nombre text NOT NULL,
    direccion text,
    telefono text,
    estado text NOT NULL,
    observaciones text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    CONSTRAINT sedes_estado_check CHECK ((estado = ANY (ARRAY['ACTIVO'::text, 'INACTIVO'::text])))
);


--
-- Name: shared_space_config; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.shared_space_config (
    singleton boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 1 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT shared_space_config_singleton_check CHECK (singleton),
    CONSTRAINT shared_space_config_version_check CHECK ((version > 0))
);


--
-- Name: shared_space_therapies; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.shared_space_therapies (
    therapy_id text NOT NULL
);


--
-- Name: solicitudes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.solicitudes (
    id text NOT NULL,
    usuario_id uuid NOT NULL,
    tipo text NOT NULL,
    payload_hash text NOT NULL,
    resultado jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stock_config; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.stock_config (
    producto_id text NOT NULL,
    sede text NOT NULL,
    minimo integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL,
    initial_loaded boolean DEFAULT false NOT NULL,
    CONSTRAINT stock_config_minimo_check CHECK ((minimo >= 0))
);


--
-- Name: turn_audit; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.turn_audit (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    request_id text NOT NULL,
    actor uuid NOT NULL,
    turn_id text NOT NULL,
    action text NOT NULL,
    before_data jsonb,
    after_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: user_provision; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.user_provision (
    id text NOT NULL,
    email text NOT NULL,
    display_name text NOT NULL,
    role text NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    auth_user_id uuid,
    CONSTRAINT user_provision_role_check CHECK ((role = ANY (ARRAY['ADMIN'::text, 'SECRETARIA'::text])))
);


--
-- Name: user_sedes; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.user_sedes (
    user_id uuid NOT NULL,
    sede text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by uuid,
    updated_by uuid,
    version bigint DEFAULT 1 NOT NULL
);


--
-- Name: whatsapp_attempts; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.whatsapp_attempts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    config_version bigint NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:10:00'::interval) NOT NULL,
    token_id uuid,
    waba_id text,
    phones jsonb DEFAULT '[]'::jsonb NOT NULL,
    CONSTRAINT whatsapp_attempts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'choose_phone'::text, 'linked'::text, 'failed'::text])))
);


--
-- Name: whatsapp_config; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.whatsapp_config (
    singleton boolean DEFAULT true NOT NULL,
    version bigint DEFAULT 1 NOT NULL,
    app_id text DEFAULT ''::text NOT NULL,
    config_id text DEFAULT ''::text NOT NULL,
    graph_version text DEFAULT 'v26.0'::text NOT NULL,
    app_secret_id uuid,
    verify_token text DEFAULT (gen_random_uuid())::text NOT NULL,
    coexistence_enabled boolean DEFAULT false NOT NULL,
    webhook_verified_at timestamp with time zone,
    connected boolean DEFAULT false NOT NULL,
    phone_id text,
    waba_id text,
    phone_display text,
    phone_name text,
    access_token_id uuid,
    linked_at timestamp with time zone,
    last_event_at timestamp with time zone,
    last_request_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT whatsapp_config_singleton_check CHECK (singleton)
);


--
-- Name: whatsapp_events; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.whatsapp_events (
    event_hash text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    payload jsonb NOT NULL
);


--
-- Name: whatsapp_message_templates; Type: TABLE; Schema: marathon; Owner: -
--

CREATE TABLE marathon.whatsapp_message_templates (
    id text NOT NULL,
    title text NOT NULL,
    trigger_label text NOT NULL,
    body text NOT NULL,
    default_body text NOT NULL,
    version bigint DEFAULT 1 NOT NULL,
    last_request_id uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT whatsapp_message_templates_body_check CHECK (((length(body) >= 1) AND (length(body) <= 1000))),
    CONSTRAINT whatsapp_message_templates_id_check CHECK ((id = ANY (ARRAY['confirmation'::text, 'reminder'::text, 'cancellation'::text, 'reschedule'::text])))
);


--
-- Name: p_activo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.p_activo (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    num numeric
);


--
-- Name: p_activo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.p_activo ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.p_activo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- PostgreSQL database dump complete
--

\unrestrict F9TtlFLhugykBDIvL3TnVwpChZBGpyQFXGOQfJEfDTqdbg9hYPf6dXCINAecte8

