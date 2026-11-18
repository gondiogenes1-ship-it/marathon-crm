-- Agenda: al abrir la agenda del dia, reintentar materializar los turnos
-- pendientes de ese dia antes de listarlos.
--
-- Antes: si al crear una serie un turno no se podia generar en el momento
-- (por ejemplo, un cruce pasajero con otro turno que luego se resolvia),
-- quedaba "virtual" para siempre: la grilla semanal de Modalidad de agenda
-- lo mostraba como pendiente (lee marathon.agenda_pool, que incluye los
-- virtuales), pero la pantalla principal de la agenda (marathon_agenda_list)
-- solo lee la tabla de turnos ya creados, asi que ese dia aparecia vacio
-- aunque el plan ya hubiera arrancado.
--
-- Ahora: marathon_agenda_list reintenta marathon.agenda_materializar para
-- el dia consultado antes de listar los turnos. Si el cruce que lo
-- bloqueaba ya no existe, el turno se crea y aparece; si sigue bloqueado,
-- queda igual que antes (virtual, visible solo en la grilla semanal).
create or replace function public.marathon_agenda_list(p_fecha text, p_sede text default ''::text, p_prof text default ''::text, p_after jsonb default null::jsonb, p_limit integer default 50)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$ declare d date;rows jsonb;nxt jsonb;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 d=marathon.agenda_date(p_fecha);
 if p_limit is null or p_limit not between 1 and 100 or length(coalesce(p_sede,''))>40 or length(coalesce(p_prof,''))>100 or
 (p_after is not null and (jsonb_typeof(p_after)<>'object' or not(p_after ?& array['hora','id']) or coalesce(p_after->>'hora','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')) then raise sqlstate '22023' using message='Consulta inválida.';end if;
 perform marathon.agenda_materializar(d,d);
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
end $function$;
