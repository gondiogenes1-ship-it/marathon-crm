-- Contexto de solo lectura para continuar sesiones de una terapia.
create or replace function public.marathon_extension_context(p_id text)
returns jsonb language plpgsql stable security invoker set search_path='' as $f$
declare t marathon.turnos;last_date date;local_now timestamp:=(statement_timestamp() at time zone 'America/Argentina/Buenos_Aires');begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or length(p_id) not between 1 and 200 then raise sqlstate '22023' using message='Seleccioná un turno válido.';end if;
 select * into t from marathon.turnos where id=p_id;
 if t.id is null then raise sqlstate 'P0002' using message='El turno ya no está disponible. Actualizá la planilla.';end if;
 select max(fecha) into last_date from marathon.turnos where dni=t.dni and terapia_id=t.terapia_id and estado in('PENDIENTE','PRESENTE');
 return jsonb_build_object('dni',t.dni,'sede',t.sede,'prof',t.profesional_id,'therapy',t.terapia_id,
  'hora',to_char(t.hora,'HH24:MI'),'source_date',t.fecha,'after_date',greatest(local_now::date+case when t.hora<=local_now::time then 1 else 0 end,coalesce(last_date+1,local_now::date)),
  'last_date',last_date,'days',case when jsonb_typeof(t.series_pattern->'days')='array' and t.series_pattern->'days'<>'[]'::jsonb then t.series_pattern->'days' when cardinality(t.fixed_days)>0 then to_jsonb(t.fixed_days) else jsonb_build_array(extract(dow from t.fecha)::int) end,
  'importe',t.importe,'coverage',t.coverage,'booking_notes',coalesce(t.booking_notes,''));
end $f$;
revoke all on function public.marathon_extension_context(text) from public,anon;
grant execute on function public.marathon_extension_context(text) to authenticated;



