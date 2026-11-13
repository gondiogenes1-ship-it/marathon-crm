-- FIX: marathon_session no es SECURITY DEFINER (a diferencia de sus hermanas
-- active_user()/is_admin()), por lo que su lectura de marathon.app_users corre con
-- los permisos del rol que llama (authenticated), no con privilegios elevados.
-- Para SECRETARIA_ORTOPEDIA esto hace que la fila no se encuentre (sin error: la
-- función devuelve null), y el frontend falla con "Cannot read properties of null
-- (reading 'role')" al intentar iniciar sesión.
--
-- Se alinea con el mismo patrón que ya usan todas sus funciones hermanas.
-- Correr en el SQL Editor de Supabase (una sola vez), después de los scripts anteriores.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

alter function public.marathon_session() security definer;

notify pgrst,'reload schema';
commit;
