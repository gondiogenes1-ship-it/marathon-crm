-- Reubicar el plan huérfano restante del dni 52033586 (FGK01 martes/jueves 17:00 -> 17:30).
-- 17:30 ya fue verificado como slot válido y con cupo (remaining=10, blocked=false).
-- Los turnos PRESENTE pasados NO se tocan; solo se mueven los PENDIENTE.
-- Generado tras detectar el caso con el chequeo de salud (ver agenda_salud_horarios.sql).

begin;

-- 1) Horarios del plan: 17:00 -> 17:30
update marathon.agenda_horarios ah set hora='17:30'
from marathon.agenda_planes p
where ah.plan_id = p.id
  and p.dni = '52033586'
  and ah.profesional_id = 'FGK01'
  and ah.hora = '17:00';

-- 2) Turnos pendientes de ese plan: 17:00 -> 17:30 (dispara el guard, que valida cupo en 17:30)
update marathon.turnos t set hora='17:30'
from marathon.agenda_planes p
where t.plan_id = p.id
  and p.dni = '52033586'
  and t.hora = '17:00'
  and t.estado = 'PENDIENTE';

commit;

-- Verificación (debe devolver 0 filas para FGK01 17:00):
-- select * from marathon.agenda_horarios_invalidos() where profesional_id='FGK01';
