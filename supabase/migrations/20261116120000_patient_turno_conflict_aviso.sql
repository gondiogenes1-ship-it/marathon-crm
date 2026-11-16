-- Aviso de superposicion de turnos para un paciente al agendar.
-- Aditiva y de solo lectura: no modifica registros operativos.
-- Reutiliza la misma logica de superposicion que ya usa marathon_booking_dates,
-- pero devuelve el detalle (horario, sede, terapia y profesional) del turno
-- existente que se superpone, para poder avisar en pantalla antes de reservar.
create or replace function public.marathon_patient_turno_conflict(p_dni text, p_fecha text, p_hora text, p_therapy text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare d date;minute_of_day integer;duration integer;found_hora time;found_sede text;found_therapy text;found_prof text;
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_dni is null or p_dni!~'^[0-9]{1,12}$' then raise sqlstate '22023' using message='DNI inválido.';end if;
 if p_fecha is null or p_fecha!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise sqlstate '22023' using message='Fecha inválida.';end if;
 if p_hora is null or p_hora!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise sqlstate '22023' using message='Horario inválido.';end if;
 if p_therapy is null or length(p_therapy)>100 then raise sqlstate '22023' using message='Terapia inválida.';end if;
 if not exists(select 1 from marathon.pacientes where dni=p_dni) then raise sqlstate 'P0002' using message='Paciente no encontrado.';end if;
 d:=p_fecha::date;minute_of_day:=(extract(epoch from p_hora::time)/60)::integer;
 select t.duracion_min into duration from marathon.terapias t where t.id=p_therapy;
 duration:=coalesce(duration,15);
 select t.hora,t.sede,th.nombre,concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido)
  into found_hora,found_sede,found_therapy,found_prof
 from marathon.turnos t join marathon.terapias th on th.id=t.terapia_id join marathon.profesionales pr on pr.id=t.profesional_id
 where t.dni=p_dni and t.fecha=d and t.estado<>'CANCELADO'
  and (extract(epoch from t.hora)/60)::integer<minute_of_day+duration
  and minute_of_day<(extract(epoch from t.hora)/60)::integer+coalesce(t.duracion_min,15)
 order by t.hora limit 1;
 if found_hora is null then return jsonb_build_object('conflict',false); end if;
 return jsonb_build_object('conflict',true,'hora',to_char(found_hora,'HH24:MI'),'sede',found_sede,'therapy',found_therapy,'profesional',found_prof);
end $function$;
