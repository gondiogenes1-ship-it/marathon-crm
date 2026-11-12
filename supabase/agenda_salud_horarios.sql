-- CHEQUEO DE SALUD: horarios de planes que HOY no pueden materializarse.
--
-- Detecta agenda_horarios de planes activos cuyo próximo turno proyectado cae en un
-- slot que agenda_cupo rechaza (blocked=true) o sin cupo (remaining<1). Es decir,
-- horarios "huérfanos": el plan quedó agendado en un slot que el profesional ya no
-- ofrece (cambió su disponibilidad/step) o que está sobrevendido.
--
-- Este es el tipo de dato que, invisible, hacía fallar TODA reserva nueva. Con el fix
-- de agenda_materializar ya no rompe las reservas, pero esos turnos no se materializan
-- hasta corregir el horario. Esta función los expone para corregirlos a tiempo.
--
-- Uso:
--   select * from marathon.agenda_horarios_invalidos();
-- Ideal: mostrarlo en un panel admin, o agendarlo con pg_cron para alertar.

create or replace function marathon.agenda_horarios_invalidos()
returns table(
  profesional_id text,
  sede text,
  dia int,
  hora time,
  blocked boolean,
  remaining int,
  n_planes bigint,
  dnis text,
  proxima_fecha date
)
language sql
stable
security invoker
set search_path to ''
as $$
  with s as (
    select ah.id, ah.plan_id, ah.sede, ah.profesional_id, ah.dia, ah.hora,
           p.terapia_id, p.dni,
           (current_date + ((ah.dia - extract(dow from current_date)::int + 7) % 7))::date as nd
    from marathon.agenda_horarios ah
    join marathon.agenda_planes p on p.id = ah.plan_id
    where (p.baja is null or p.baja > current_date)
  ),
  c as (
    select s.*, marathon.agenda_cupo(s.nd, s.sede, s.profesional_id, s.terapia_id, s.hora, s.plan_id) q
    from s
  )
  select c.profesional_id, c.sede, c.dia, c.hora,
         (c.q->>'blocked')::boolean,
         (c.q->>'remaining')::int,
         count(*),
         string_agg(distinct c.dni, ', '),
         min(c.nd)
  from c
  where (c.q->>'blocked')::boolean is true
     or coalesce((c.q->>'remaining')::int, 0) < 1
  group by c.profesional_id, c.sede, c.dia, c.hora, (c.q->>'blocked')::boolean, (c.q->>'remaining')::int
  order by c.profesional_id, c.dia, c.hora;
$$;

revoke all on function marathon.agenda_horarios_invalidos() from public, anon;
grant execute on function marathon.agenda_horarios_invalidos() to authenticated;
