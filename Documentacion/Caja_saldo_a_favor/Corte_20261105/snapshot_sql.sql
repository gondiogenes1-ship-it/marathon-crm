select jsonb_build_object('cuentas',(select count(*)from marathon.pacientes),'movimientos',(select count(*)from marathon.movimientos),'tables',coalesce(jsonb_object_agg(name,jsonb_build_object('count',n,'hash',h)),'{}'))from(
 select 'movimientos'name,count(*)n,md5(coalesce(jsonb_agg(to_jsonb(t)-'subtipo'-'terapia_asociada_id'order by id),'[]')::text)h from marathon.movimientos t
 union all select 'turnos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.turnos t
 union all select 'anticipos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.anticipos t
 union all select 'anticipo_eventos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.anticipo_eventos t
 union all select 'bonos_serie',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.bonos_serie t
 union all select 'agenda_cuotas',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.agenda_cuotas t
 union all select 'agenda_ajustes',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.agenda_ajustes t)x;