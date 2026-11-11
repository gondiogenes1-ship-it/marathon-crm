-- Agenda recurrente. Migración aditiva: no convierte ni elimina turnos anteriores.
create table marathon.agenda_planes (
 id uuid primary key default gen_random_uuid(), dni text not null references marathon.pacientes(dni),
 terapia_id text not null references marathon.terapias(id), modalidad text not null check(modalidad in('sessions','monthly','fixed')),
 facturacion text not null check(facturacion in('class','bonus_class','monthly','none')),
 importe numeric(12,2) not null check(importe>=0), inicio date not null, baja date, coverage jsonb not null,
 observaciones text not null default '' check(length(observaciones)<=1000),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 created_by uuid references auth.users(id),updated_by uuid references auth.users(id),version bigint not null default 1,
 check(baja is null or baja>=inicio),check(facturacion<>'none' or importe=0)
);
create index agenda_planes_paciente on marathon.agenda_planes(dni,inicio);
create table marathon.agenda_horarios (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references marathon.agenda_planes(id),
 sede text not null references marathon.sedes(nombre),profesional_id text not null references marathon.profesionales(id),
 dia int not null check(dia between 1 and 5),hora time not null,duracion_min int not null check(duracion_min>0),
 desde date not null,hasta date,check(hasta is null or hasta>=desde),unique(plan_id,dia)
);
create index agenda_horarios_prof on marathon.agenda_horarios(profesional_id,dia,desde);
create table marathon.agenda_autorizaciones (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references marathon.agenda_planes(id),
 cantidad int not null check(cantidad between 1 and 1000),fecha date not null,
 created_at timestamptz not null default now(),created_by uuid references auth.users(id)
);
create index agenda_autorizaciones_plan on marathon.agenda_autorizaciones(plan_id,fecha,created_at);
create table marathon.agenda_pausas (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references marathon.agenda_planes(id),
 desde date not null,hasta date,motivo text not null check(length(btrim(motivo)) between 3 and 1000),
 created_at timestamptz not null default now(),created_by uuid references auth.users(id),
 check(hasta is null or hasta>=desde)
);
create index agenda_pausas_plan on marathon.agenda_pausas(plan_id,desde,hasta);
create table marathon.agenda_periodos (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references marathon.agenda_planes(id),
 inicio date not null,fin date,anulado boolean not null default false,check(fin is null or fin>=inicio)
);
create index agenda_periodos_plan on marathon.agenda_periodos(plan_id,inicio);
create table marathon.agenda_cuotas (
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references marathon.agenda_planes(id),
 periodo_id uuid not null references marathon.agenda_periodos(id),fecha date not null,hasta date not null,
 importe numeric(12,2) not null check(importe>=0),sede text not null references marathon.sedes(nombre),
 created_at timestamptz not null default now(),unique(periodo_id,fecha),check(hasta>fecha)
);
create index agenda_cuotas_plan on marathon.agenda_cuotas(plan_id,fecha);
create table marathon.agenda_ajustes (
 id uuid primary key default gen_random_uuid(),cuota_id uuid not null references marathon.agenda_cuotas(id),
 importe numeric(12,2) not null check(importe>0),motivo text not null check(length(btrim(motivo)) between 3 and 1000),
 created_at timestamptz not null default now(),created_by uuid references auth.users(id)
);
create index agenda_ajustes_cuota on marathon.agenda_ajustes(cuota_id);
alter table marathon.turnos add column plan_id uuid references marathon.agenda_planes(id),
 add column horario_id uuid references marathon.agenda_horarios(id),add column fecha_habitual date,
 add column autorizacion_id uuid references marathon.agenda_autorizaciones(id),add column agenda_motivo text;
create unique index turnos_habitual_unico on marathon.turnos(horario_id,fecha_habitual) where horario_id is not null;
create index turnos_plan_fecha on marathon.turnos(plan_id,fecha,estado);
create index turnos_autorizacion on marathon.turnos(autorizacion_id) where autorizacion_id is not null;
alter table marathon.movimientos add column cuota_id uuid references marathon.agenda_cuotas(id);
create index movimientos_cuota on marathon.movimientos(cuota_id) where cuota_id is not null;
alter table marathon.movimientos add constraint movimiento_cuota_shape check(cuota_id is null or (origen='CAJA' and tipo in('INGRESO','EGRESO') and turno_id is null and bono_id is null and anticipo_id is null and operacion_id is null));
create trigger agenda_planes_touch before update on marathon.agenda_planes for each row execute function marathon.touch_row();

create function marathon.agenda_hoy() returns date language sql stable set search_path='' as $$select (now() at time zone 'America/Argentina/Buenos_Aires')::date$$;
create function marathon.agenda_pausado(p uuid,d date) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from marathon.agenda_pausas x where x.plan_id=p and x.desde<=d and(x.hasta is null or d<x.hasta))
$$;
create function marathon.agenda_total(p uuid) returns int language sql stable set search_path='' as $$select coalesce(sum(cantidad),0)::int from marathon.agenda_autorizaciones where plan_id=p$$;
create function marathon.agenda_presentes(p uuid) returns int language sql stable set search_path='' as $$select count(*)::int from marathon.turnos where plan_id=p and estado='PRESENTE'$$;
create function marathon.agenda_cuota_pagado(q uuid) returns numeric language sql stable set search_path='' as $$
 select coalesce(sum(case when m.tipo in('PAGO','INGRESO') then m.monto else -m.monto end),0)
 from marathon.movimientos m left join marathon.movimientos original on original.id=m.compensacion_de
 where m.cuota_id=q or original.cuota_id=q
$$;
create function marathon.agenda_cuota_saldo(q uuid) returns numeric language sql stable set search_path='' as $$
 select greatest(0,c.importe-marathon.agenda_cuota_pagado(c.id)-coalesce((select sum(a.importe) from marathon.agenda_ajustes a where a.cuota_id=c.id),0)) from marathon.agenda_cuotas c where c.id=q
$$;
create function marathon.agenda_movimiento_guard()returns trigger language plpgsql set search_path='' as $$
declare q marathon.agenda_cuotas%rowtype;begin
 if new.cuota_id is null and new.compensacion_de is not null then select cuota_id into new.cuota_id from marathon.movimientos where id=new.compensacion_de;end if;
 if new.cuota_id is null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 select * into strict q from marathon.agenda_cuotas where id=new.cuota_id for update;
 if new.tipo='INGRESO'and new.monto>marathon.agenda_cuota_saldo(q.id)or new.tipo='EGRESO'and new.monto>marathon.agenda_cuota_pagado(q.id)then raise sqlstate '22023'using message='El movimiento supera el saldo de la cuota. Revisá los pagos y reintegros previos.';end if;
 update marathon.agenda_planes set updated_at=now()where id=q.plan_id;return new;
end$$;
create trigger agenda_movimiento_guard before insert on marathon.movimientos for each row execute function marathon.agenda_movimiento_guard();
create function marathon.agenda_cuotas_generar(p_hoy date default marathon.agenda_hoy()) returns int
 language plpgsql set search_path='' as $$
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

-- Devuelve reglas sin materializar; una ocurrencia guardada (incluso cancelada) es su excepción.
create function marathon.agenda_virtual(d date) returns table(id text,plan_id uuid,horario_id uuid,dni text,sede text,profesional_id text,terapia_id text,hora time,duracion_min int,pausado boolean)
 language sql stable set search_path='' as $$
 select 'H-'||h.id::text||'-'||d::text,p.id,h.id,p.dni,h.sede,h.profesional_id,p.terapia_id,h.hora,h.duracion_min,marathon.agenda_pausado(p.id,d)
 from marathon.agenda_horarios h join marathon.agenda_planes p on p.id=h.plan_id
 where h.dia=extract(dow from d)::int and d>=greatest(h.desde,p.inicio) and(h.hasta is null or d<h.hasta) and(p.baja is null or d<p.baja)
 and(p.modalidad<>'sessions' or marathon.agenda_presentes(p.id)<marathon.agenda_total(p.id))
 and not exists(select 1 from marathon.turnos t where t.horario_id=h.id and t.fecha_habitual=d)
$$;
create function marathon.agenda_pool(d date) returns table(id text,plan_id uuid,dni text,sede text,profesional_id text,terapia_id text,hora time,duracion_min int,estado text,pausado boolean,fecha date)
 language sql stable set search_path='' as $$
 select x.id,x.plan_id,x.dni,x.sede,x.profesional_id,x.terapia_id,x.hora,x.duracion_min,x.estado,(x.estado<>'PRESENTE'and marathon.agenda_pausado(x.plan_id,d)),x.fecha
 from marathon.turnos x where x.fecha=d and x.estado<>'CANCELADO'
 union all select v.id,v.plan_id,v.dni,v.sede,v.profesional_id,v.terapia_id,v.hora,v.duracion_min,'PENDIENTE',v.pausado,d from marathon.agenda_virtual(d)v
$$;
create function marathon.agenda_cupo(d date,site text,prof text,therapy text,at_hour time,exclude_plan uuid default null,exclude_turn text default null) returns jsonb
 language plpgsql stable set search_path='' as $$
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

create function marathon.agenda_turno_guard() returns trigger language plpgsql set search_path='' as $$
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
create trigger agenda_turno_guard before insert or update of estado,fecha,hora,sede,profesional_id,terapia_id on marathon.turnos for each row execute function marathon.agenda_turno_guard();

create function marathon.agenda_completar() returns trigger language plpgsql set search_path='' as $$
begin
 if new.plan_id is not null and pg_trigger_depth()=1 then
  update marathon.agenda_planes set updated_at=now() where id=new.plan_id;
  if exists(select 1 from marathon.agenda_planes p where p.id=new.plan_id and p.modalidad='sessions' and marathon.agenda_presentes(p.id)>=marathon.agenda_total(p.id))then
   update marathon.turnos set estado='CANCELADO',agenda_motivo='SESIONES_COMPLETAS' where plan_id=new.plan_id and id<>new.id and estado='PENDIENTE' and fecha>=new.fecha;
  end if;
 end if;return new;
end$$;
create trigger agenda_completar after insert or update of estado on marathon.turnos for each row execute function marathon.agenda_completar();

create function marathon.agenda_materializar(d date,e date) returns int language plpgsql set search_path='' as $$
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

create function marathon.agenda_plan_info(p_id uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare p marathon.agenda_planes%rowtype;r jsonb;streak int:=0;s text;begin
 select * into p from marathon.agenda_planes where id=p_id;if not found then return null;end if;
 for s in select t.estado from marathon.turnos t where t.plan_id=p.id and t.fecha<=marathon.agenda_hoy() and t.estado in('PRESENTE','AUSENTE') and not marathon.agenda_pausado(p.id,t.fecha) order by t.fecha desc,t.hora desc,t.id desc loop
  exit when s='PRESENTE';streak=streak+1;
 end loop;
 r=to_jsonb(p)||jsonb_build_object('total',marathon.agenda_total(p.id),'done',marathon.agenda_presentes(p.id),'absences',streak,
 'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id)) from marathon.agenda_cuotas q where q.plan_id=p.id),0),
 'next_due',(select min((s.inicio+make_interval(months=>g.n))::date)from marathon.agenda_periodos s cross join lateral generate_series(greatest(0,(extract(year from marathon.agenda_hoy())::int-extract(year from s.inicio)::int)*12+extract(month from marathon.agenda_hoy())::int-extract(month from s.inicio)::int),greatest(0,(extract(year from marathon.agenda_hoy())::int-extract(year from s.inicio)::int)*12+extract(month from marathon.agenda_hoy())::int-extract(month from s.inicio)::int)+1)g(n)where s.plan_id=p.id and not s.anulado and (s.inicio+make_interval(months=>g.n))::date>marathon.agenda_hoy()and(s.fin is null or(s.inicio+make_interval(months=>g.n))::date<s.fin)and(p.baja is null or(s.inicio+make_interval(months=>g.n))::date<p.baja)),
 'paused',marathon.agenda_pausado(p.id,marathon.agenda_hoy()),
 'pauses',coalesce((select jsonb_agg(to_jsonb(x)order by x.desde)from marathon.agenda_pausas x where x.plan_id=p.id),'[]'::jsonb),
 'schedules',coalesce((select jsonb_agg(to_jsonb(x)order by x.dia,x.hora)from marathon.agenda_horarios x where x.plan_id=p.id),'[]'::jsonb),
 'authorizations',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('done',(select count(*)from marathon.turnos t where t.autorizacion_id=a.id and t.estado='PRESENTE'))order by a.fecha,a.created_at)from marathon.agenda_autorizaciones a where a.plan_id=p.id),'[]'::jsonb),
 'quotas',coalesce((select jsonb_agg(to_jsonb(q)||jsonb_build_object('paid',marathon.agenda_cuota_pagado(q.id),'debt',marathon.agenda_cuota_saldo(q.id))order by q.fecha desc)from marathon.agenda_cuotas q where q.plan_id=p.id),'[]'::jsonb));return r;
end$$;

create function public.marathon_agenda_plan(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;perform marathon.agenda_cuotas_generar();return marathon.agenda_plan_info(p_id);end$$;

create function public.marathon_agenda_flexible(p_filters jsonb,p_after jsonb default null,p_limit int default 50) returns jsonb
 language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare r jsonb;d date;e date;begin
 if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 perform marathon.agenda_materializar(d,e);
 r=public.marathon_agenda_search(p_filters,p_after,p_limit);
 r=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(x||jsonb_build_object('plan',marathon.agenda_plan_info(t.plan_id),'paused',t.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(t.plan_id,t.fecha),'end_hour',to_char(t.hora+make_interval(mins=>t.duracion_min),'HH24:MI')) order by n)from jsonb_array_elements(r->'rows')with ordinality a(x,n)join marathon.turnos t on t.id=x->>'id'),'[]'::jsonb));return r;
end$$;

create function public.marathon_agenda_grilla(p_from text,p_sede text,p_prof text,p_therapy text default '') returns jsonb
 language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
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

create function public.marathon_agenda_plan_command(p_request_id text,p_action text,p_data jsonb) returns jsonb
 language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
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
  if p_data->>'billing'='monthly'then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt);end if;
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
   if dt2 is not null and p.facturacion='monthly'then insert into marathon.agenda_periodos(plan_id,inicio)values(pid,dt2);end if;
  elsif p_action='resume'then
   select * into pause from marathon.agenda_pausas x where x.plan_id=pid and x.desde<=dt and(x.hasta is null or dt<x.hasta)order by x.desde desc limit 1 for update;
   if pause.id is null or dt<>marathon.agenda_hoy()or p.baja is not null then raise sqlstate '22023'using message='No hay una pausa activa para reanudar hoy.';end if;
   update marathon.agenda_pausas set hasta=dt where id=pause.id;
   update marathon.agenda_periodos set anulado=true where plan_id=pid and inicio>dt;
   if p.facturacion='monthly'then
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
    values(mid,marathon.agenda_hoy(),(now()at time zone'America/Argentina/Buenos_Aires')::time,'CAJA',case when p_action='quota_pay'then'INGRESO'else'EGRESO'end,p.dni,amount,medium,q.sede,'Cuota mensual '||q.fecha::text,reason,nullif(reason,''),'Cuota mensual',(select h.profesional_id from marathon.agenda_horarios h where h.plan_id=pid order by h.dia,h.hora limit 1),q.id,auth.uid(),auth.uid());
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

-- Tablas privadas: sin acceso directo desde el navegador. Se conserva el control de usuarios activos del CRM.
do $$declare n text;begin
 foreach n in array array['agenda_planes','agenda_horarios','agenda_autorizaciones','agenda_pausas','agenda_periodos','agenda_cuotas','agenda_ajustes']loop
  execute format('alter table marathon.%I enable row level security',n);
  execute format('revoke all on marathon.%I from public,anon,authenticated',n);
 end loop;
end$$;
revoke all on function public.marathon_agenda_plan(uuid),public.marathon_agenda_flexible(jsonb,jsonb,int),public.marathon_agenda_grilla(text,text,text,text),public.marathon_agenda_plan_command(text,text,jsonb)from public,anon;
grant execute on function public.marathon_agenda_plan(uuid),public.marathon_agenda_flexible(jsonb,jsonb,int),public.marathon_agenda_grilla(text,text,text,text),public.marathon_agenda_plan_command(text,text,jsonb)to authenticated;
do $$declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='marathon'and p.proname like 'agenda_%'and p.proname not in('agenda_slots','agenda_slots_excluding','agenda_date')loop
  execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 end loop;
end$$;
notify pgrst,'reload schema';

create or replace function public.marathon_agenda_slots(p_fecha text,p_sede text,p_prof text,p_therapy text)returns jsonb
 language plpgsql stable security definer set search_path='' as $$
declare d date;r jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;d=marathon.agenda_date(p_fecha);
 select coalesce(jsonb_agg(marathon.agenda_cupo(d,p_sede,p_prof,p_therapy,at_hour)||jsonb_build_object('shared_space',exists(select 1 from marathon.shared_space_therapies where therapy_id=p_therapy))order by at_hour),'[]'::jsonb)into r from(
 select distinct h.inicio+make_interval(mins=>g.m)at_hour from marathon.horarios h cross join lateral generate_series(0,(extract(epoch from(h.fin-h.inicio))/60)::int-15,marathon.professional_step(p_prof))g(m) where h.profesional_id=p_prof and h.sede=p_sede and h.dia=extract(dow from d)::int
 )c;return r;
end$$;

create function public.marathon_agenda_patient_account(p_dni text,p_after jsonb default null,p_limit int default 50)returns jsonb
 language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare r jsonb;plans jsonb;debt numeric;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.agenda_cuotas_generar();r=public.marathon_patient_account(p_dni,p_after,p_limit);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'terapia',t.nombre,'debt',coalesce((select sum(marathon.agenda_cuota_saldo(q.id))from marathon.agenda_cuotas q where q.plan_id=p.id),0))order by p.inicio),'[]'::jsonb)into plans from marathon.agenda_planes p join marathon.terapias t on t.id=p.terapia_id where p.dni=p_dni and p.facturacion='monthly';
 select coalesce(sum((x->>'debt')::numeric),0)into debt from jsonb_array_elements(plans)x;
 return r||jsonb_build_object('plans',plans,'debt',coalesce((r->>'debt')::numeric,0)+debt);
end$$;
revoke all on function public.marathon_agenda_patient_account(text,jsonb,int)from public,anon;
grant execute on function public.marathon_agenda_patient_account(text,jsonb,int)to authenticated;

-- El calendario de cuotas y las atenciones del día se actualizan incluso sin una pantalla abierta.
do $$begin
 if to_regnamespace('cron')is not null then
  perform cron.schedule('marathon_agenda_recurrente','5 3 * * *','select marathon.agenda_materializar(marathon.agenda_hoy(),marathon.agenda_hoy()); select marathon.attendance_rollover(marathon.agenda_hoy());');
 end if;
end$$;


-- Compatibilidad con las reservas y cierres diarios anteriores.
CREATE OR REPLACE FUNCTION marathon.agenda_slots(d date, site text, prof text, therapy text)
 RETURNS TABLE(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;


-- Compatibilidad con las reservas y cierres diarios anteriores.
CREATE OR REPLACE FUNCTION marathon.agenda_slots_excluding(d date, site text, prof text, therapy text, excluded text[])
 RETURNS TABLE(hora text, remaining integer, capacity integer, shared_capacity integer, blocked boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;


-- Compatibilidad con las reservas y cierres diarios anteriores.
CREATE OR REPLACE FUNCTION marathon.attendance_rollover(p_day date DEFAULT ((now() AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))::date, p_prof text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.marathon_agenda_search(p_filters jsonb, p_after jsonb DEFAULT NULL::jsonb, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d date;e date;rows jsonb;nxt jsonb;summary jsonb;state text;layout text;groups jsonb;
begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','prof','therapy','query','state','layout'],least(p_limit,100),p_after);
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');state=coalesce(p_filters->>'state','');
 if p_limit is null or p_limit not between 1 and 10000 or e<d or e-d>31 or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Elegí un período de hasta 32 días y una página válida.';end if;
 if state not in('','PENDIENTE','PRESENTE','AUSENTE','CANCELADO','PAUSADO')then raise sqlstate '22023'using message='Estado de turno inválido.';end if;

 layout=coalesce(p_filters->>'layout','');
 if layout not in('','blocks')or(layout='blocks'and p_limit>50)then raise sqlstate '22023'using message='Vista o cantidad de bloques inválida.';end if;
 if layout='blocks'then
  with base as(
  select jsonb_build_array(t.sede,t.profesional_id,t.terapia_id)::text group_id,t.*,b.plan_id,(b.estado in('PENDIENTE','AUSENTE')and marathon.agenda_pausado(b.plan_id,b.fecha))paused,b.coverage,b.fixed_until,b.attendance_auto,p.telefono,p.observaciones patient_notes,coalesce(b.booking_notes,marathon.reservation_notes(b.observaciones)) booking_notes,exists(select 1 from marathon.turnos r where r.recovered_from=b.id) has_recovery from marathon.daily_turns t
  join marathon.turnos b on b.id=t.id join marathon.pacientes p on p.dni=t.dni
  where t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
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
  where t.fecha between d and e and(coalesce(p_filters->>'sede','')=''or t.sede=p_filters->>'sede')
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
end $function$;
notify pgrst,'reload schema';

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
            WHEN COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id) IS NOT NULL THEN 'T:'::text || COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id)
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
   FROM marathon.movimientos m LEFT JOIN marathon.agenda_cuotas aq ON aq.id=m.cuota_id LEFT JOIN marathon.agenda_planes ap ON ap.id=aq.plan_id
     LEFT JOIN marathon.turnos t ON t.id = m.turno_id
     LEFT JOIN marathon.bonos_serie b ON b.id = m.bono_id
     LEFT JOIN marathon.anticipos a ON a.id = m.anticipo_id
     LEFT JOIN marathon.terapias th ON th.id = COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id)
     LEFT JOIN marathon.profesionales pr ON pr.id = COALESCE(t.profesional_id, b.profesional_id, a.profesional_id, m.profesional_asociado_id)
     LEFT JOIN marathon.pacientes p ON p.dni = m.dni
     LEFT JOIN marathon.app_users u ON u.user_id = m.created_by;
