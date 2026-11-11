-- Resumen histórico por paciente y terapia. Solo lectura; conserva las políticas RLS.
create or replace function public.marathon_patient_sessions(p_pairs jsonb)
returns jsonb language plpgsql stable security invoker set search_path='' as $fn$
declare cut date := (statement_timestamp() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_pairs is null or jsonb_typeof(p_pairs)<>'array' then raise sqlstate '22023' using message='La consulta de sesiones requiere una lista de pacientes y terapias.';end if;
 if jsonb_array_length(p_pairs)>500 then raise sqlstate '22023' using message='Consultá hasta 500 pacientes y terapias por vez.';end if;
 if exists(select 1 from jsonb_array_elements(p_pairs) x where jsonb_typeof(x) is distinct from 'object'
  or jsonb_typeof(x->'dni') is distinct from 'string' or coalesce(x->>'dni','') !~ '^[0-9]{1,12}$'
  or jsonb_typeof(x->'therapy_id') is distinct from 'string' or length(coalesce(x->>'therapy_id','')) not between 1 and 100)
 then raise sqlstate '22023' using message='Paciente o terapia inválidos para consultar sesiones.';end if;
 return (
  with wanted as(select distinct x->>'dni' dni,x->>'therapy_id' therapy_id from jsonb_array_elements(p_pairs)x),
  counts as(
   select w.dni,w.therapy_id,
    count(t.id) filter(where t.estado='PRESENTE' and t.fecha<=cut) completed,
    count(t.id) filter(where t.estado='PENDIENTE' and t.fecha>=cut) remaining
   from wanted w left join marathon.turnos t on t.dni=w.dni and t.terapia_id=w.therapy_id
   group by w.dni,w.therapy_id
  ) select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('as_of',cut) order by c.dni,c.therapy_id),'[]'::jsonb) from counts c
 );
end $fn$;
revoke all on function public.marathon_patient_sessions(jsonb) from public,anon;
grant execute on function public.marathon_patient_sessions(jsonb) to authenticated;
