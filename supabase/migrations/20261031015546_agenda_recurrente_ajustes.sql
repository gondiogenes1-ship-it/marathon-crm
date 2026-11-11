-- Aviso de aniversario de la agenda mensual independiente de su modalidad de cobro.
create or replace function public.marathon_agenda_plan_command(p_request_id text,p_action text,p_data jsonb) returns jsonb
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
create or replace function marathon.agenda_plan_info(p_id uuid) returns jsonb language plpgsql stable set search_path='' as $$
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
insert into marathon.agenda_periodos(plan_id,inicio,fin)select p.id,p.inicio,p.baja from marathon.agenda_planes p where p.modalidad='monthly'and not exists(select 1 from marathon.agenda_periodos ps where ps.plan_id=p.id);
notify pgrst,'reload schema';
