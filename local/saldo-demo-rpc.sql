-- SOLO base de demostración local. Nunca aplicar en Supabase.
create or replace function public.saldo_demo_rpc(p_name text,p_args jsonb)returns jsonb language plpgsql set search_path=''as $$
declare fn record;args text;result jsonb;begin
 if current_database()<>'marathon_saldo_demo_20261104'or p_name!~'^marathon_[a-z_]+$'then raise exception 'Demostración aislada requerida.';end if;
 select p.*into strict fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and p.proname=p_name;
 if exists(select 1 from jsonb_object_keys(p_args)k where not(k=any(fn.proargnames)))then raise exception 'Argumento no permitido.';end if;
 select string_agg(format('%I => %s',fn.proargnames[i],case when fn.proargtypes[i-1] in('json'::regtype,'jsonb'::regtype)then format('nullif($1->%L,''null''::jsonb)::%s',fn.proargnames[i],fn.proargtypes[i-1]::regtype)else format('($1->>%L)::%s',fn.proargnames[i],fn.proargtypes[i-1]::regtype)end),','order by i)into args from generate_series(1,fn.pronargs)i where p_args?fn.proargnames[i];
 execute format('select to_jsonb(public.%I(%s))',p_name,coalesce(args,''))into result using p_args;return result;
end$$;
