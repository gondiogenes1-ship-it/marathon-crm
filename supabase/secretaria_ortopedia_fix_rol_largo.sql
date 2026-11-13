-- FIX: marathon_user_save / marathon_user_link / marathon_user_provision_begin
-- limitaban el campo "role" a 10 caracteres (el largo de 'SECRETARIA'), por lo que
-- guardar 'SECRETARIA_ORTOPEDIA' (20 caracteres) fallaba con "Completá un valor
-- válido para role (máximo 10 caracteres)." antes de llegar a validar nada más.
-- Correr en el SQL Editor de Supabase (una sola vez), después del script anterior.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_save(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$marathon.master_text(p_data,'role',10,true)$frag$, $frag$marathon.master_text(p_data,'role',32,true)$frag$);
 if newsrc = src then raise exception 'marathon_user_save: no se encontró el patrón de largo de rol.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_link(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$marathon.master_text(p_data,'role',10,true)$frag$, $frag$marathon.master_text(p_data,'role',32,true)$frag$);
 if newsrc = src then raise exception 'marathon_user_link: no se encontró el patrón de largo de rol.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_provision_begin(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$marathon.master_text(p_data,'role',10,true)$frag$, $frag$marathon.master_text(p_data,'role',32,true)$frag$);
 if newsrc = src then raise exception 'marathon_user_provision_begin: no se encontró el patrón de largo de rol.'; end if;
 execute newsrc;
end $$;

notify pgrst,'reload schema';
commit;
