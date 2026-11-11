CREATE OR REPLACE FUNCTION marathon.turn_series_context(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare t marathon.turnos%rowtype;p jsonb;members jsonb;rules jsonb;tarifas jsonb;quotas jsonb;begin
 select *into t from marathon.turnos where id=p_id;
 if t.id is null then raise exception 'El turno ya no existe. Actualizá la agenda.'using errcode='PT404';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.fecha,x.hora,x.id),'[]')into members from marathon.turnos x
 where (case when t.plan_id is not null then x.plan_id=t.plan_id else x.plan_id is null and coalesce(x.original_id,x.id)=coalesce(t.original_id,t.id)end)and x.fecha>=t.fecha;
 if t.plan_id is not null then
  select to_jsonb(x)||jsonb_build_object('importe',case when x.facturacion='monthly'then marathon.agenda_tarifa(x.id,t.fecha)else t.importe end)into p from marathon.agenda_planes x where x.id=t.plan_id;
  select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into tarifas from marathon.agenda_tarifas x where x.plan_id=t.plan_id;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('paid',marathon.agenda_cuota_pagado(x.id),'ajustes',coalesce((select sum(a.importe)from marathon.agenda_ajustes a where a.cuota_id=x.id),0))order by x.id),'[]')into quotas from marathon.agenda_cuotas x where x.plan_id=t.plan_id;
  select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into rules from marathon.agenda_horarios x where x.plan_id=t.plan_id;
 end if;
 return jsonb_build_object('target',to_jsonb(t),'plan',p,'schedules',coalesce(rules,'[]'),'series_days',(select jsonb_agg(num_day order by num_day)from(select distinct extract(dow from(x->>'fecha')::date)::int num_day from jsonb_array_elements(members)x where x->>'estado'='PENDIENTE')days),'series_count',(select count(*)from jsonb_array_elements(members)x where x->>'estado'='PENDIENTE'),
 'can_following',t.estado='PENDIENTE'and t.fecha>=marathon.agenda_hoy()and(t.plan_id is not null or jsonb_array_length(members)>1),
 'huella',encode(sha256(convert_to(jsonb_build_object('target',to_jsonb(t),'members',members,'plan',p,'rules',rules,'tarifas',tarifas,'quotas',quotas)::text,'UTF8')),'hex'));
end$function$
;