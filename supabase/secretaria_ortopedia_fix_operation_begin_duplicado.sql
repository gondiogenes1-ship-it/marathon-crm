-- FIX: al agregar el parámetro p_roles a marathon.operation_begin, Postgres no
-- reemplazó la función original (3 argumentos) — creó una SEGUNDA función en paralelo
-- (4 argumentos, con el 4to con valor por defecto). Con las dos versiones existiendo
-- a la vez, cualquier llamada con 3 argumentos (la inmensa mayoría del sistema) es
-- ambigua: "function marathon.operation_begin(text, unknown, jsonb) is not unique".
--
-- Solución: borrar la versión vieja de 3 argumentos. La nueva de 4 (ya creada por el
-- script anterior, con el 4to parámetro opcional) queda como única, y sigue aceptando
-- llamadas con 3 argumentos exactamente igual que antes.
--
-- Correr en el SQL Editor de Supabase (una sola vez), después de los dos scripts anteriores.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

drop function marathon.operation_begin(text,text,jsonb);

notify pgrst,'reload schema';
commit;
