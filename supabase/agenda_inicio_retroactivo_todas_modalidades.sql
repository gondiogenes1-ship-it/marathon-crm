-- Extiende a "Cantidad de sesiones" e "Indefinido" el mismo inicio retroactivo que ya
-- tenía "Mensual": la fecha de inicio de una serie nueva puede ser anterior a hoy.
-- Las sesiones de fechas pasadas se cargan como PENDIENTE con attendance_manual_date
-- fijo (no se les asigna asistencia automática ni se cobran solas) — mismo mecanismo
-- que ya usa el modo Mensual, vía la columna registro_retroactivo.
-- Correr en el SQL Editor de Supabase (una sola vez).

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_agenda_plan_command(text,text,jsonb)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if(kind<>'monthly'and dt<marathon.agenda_hoy()) or dt>marathon.agenda_hoy()+366$frag$,
  $frag$if dt>marathon.agenda_hoy()+366$frag$);
 if cur = prev then raise exception 'marathon_agenda_plan_command: no se encontró la validación de fechas.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$(kind='monthly'and dt<marathon.agenda_hoy())$frag$,
  $frag$(dt<marathon.agenda_hoy())$frag$);
 if cur = prev then raise exception 'marathon_agenda_plan_command: no se encontró el cálculo de registro_retroactivo.'; end if;

 execute cur;
end $$;

notify pgrst,'reload schema';
commit;
