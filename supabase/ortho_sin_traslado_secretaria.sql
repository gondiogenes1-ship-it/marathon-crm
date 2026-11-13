-- Ortopedia: la Secretaria de ortopedia ya no puede trasladar stock entre sedes
-- (lo maneja el personal administrativo). Mismo patrón que el bloqueo de alquiler.
-- Correr en el SQL Editor de Supabase (una sola vez).

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_command(text,text,jsonb)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if p_action='rent' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede registrar alquileres.';end if;$frag$,
  $frag$if p_action='rent' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede registrar alquileres.';end if;
 if p_action='transfer' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede trasladar stock entre sedes. Pedile a administración.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón del bloqueo de alquiler.'; end if;

 execute cur;
end $$;

notify pgrst,'reload schema';
commit;
