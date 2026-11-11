create table marathon.whatsapp_message_templates(
 id text primary key check(id in('confirmation','reminder','cancellation','reschedule')),
 title text not null,trigger_label text not null,body text not null check(length(body) between 1 and 1000),
 default_body text not null,version bigint not null default 1,last_request_id uuid,updated_at timestamptz not null default now(),updated_by uuid references auth.users(id)
);
insert into marathon.whatsapp_message_templates(id,title,trigger_label,body,default_body)
select id,title,trigger_label,body,body from(values
 ('confirmation','Confirmación de reserva','Al confirmar una reserva','Hola {paciente}, tu turno en Marathon está confirmado para el {fecha} a las {hora}, en {sede}. Si necesitás cambiarlo, escribinos. Gracias.'),
 ('reminder','Recordatorio de turno','Antes del turno','Hola {paciente}, te recordamos tu turno en Marathon el {fecha} a las {hora}, en {sede}. Si no podés asistir, avisanos. ¡Te esperamos!'),
 ('cancellation','Aviso de cancelación','Al cancelar un turno','Hola {paciente}, te informamos que tu turno en Marathon del {fecha} a las {hora}, en {sede}, fue cancelado. Escribinos para coordinar una nueva fecha.'),
 ('reschedule','Aviso de reprogramación','Al reprogramar un turno','Hola {paciente}, tu turno en Marathon fue reprogramado para el {fecha} a las {hora}, en {sede}. Cualquier consulta, escribinos.')
) seed(id,title,trigger_label,body);
alter table marathon.whatsapp_message_templates enable row level security;
revoke all on marathon.whatsapp_message_templates from public,anon,authenticated;
grant select on marathon.whatsapp_message_templates to authenticated;
create policy active_read on marathon.whatsapp_message_templates for select to authenticated using((select marathon.active_user()));

create function public.marathon_whatsapp_templates()returns jsonb language plpgsql stable security invoker set search_path='' as $f$
begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'trigger_label',trigger_label,'body',body,'default_body',default_body,'version',version,'updated_at',updated_at,'status','DRAFT') order by case id when 'confirmation' then 1 when 'reminder' then 2 when 'cancellation' then 3 else 4 end),'[]'::jsonb)from marathon.whatsapp_message_templates);
end $f$;
revoke all on function public.marathon_whatsapp_templates() from public,anon;
grant execute on function public.marathon_whatsapp_templates() to authenticated;
create function marathon.whatsapp_template_save(p_id text,p_body text,p_version bigint,p_request_id uuid)returns jsonb language plpgsql security definer set search_path='' as $f$
declare t marathon.whatsapp_message_templates;begin
 if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_request_id is null or p_body is null or length(trim(p_body)) not between 1 and 1000 then raise sqlstate '22023' using message='Escribí un mensaje de 1 a 1.000 caracteres.';end if;
 if exists(select 1 from regexp_matches(p_body,'\{([^{}]*)\}','g') m where m[1] not in('paciente','fecha','hora','sede','terapia','profesional')) or regexp_replace(p_body,'\{(paciente|fecha|hora|sede|terapia|profesional)\}','','g')~'[{}]' then raise sqlstate '22023' using message='Usá los datos disponibles: {paciente}, {fecha}, {hora}, {sede}, {terapia} y {profesional}.';end if;
 select * into t from marathon.whatsapp_message_templates where id=p_id for update;
 if t.id is null then raise sqlstate 'P0002' using message='Mensaje no disponible. Volvé a abrir WhatsApp.';end if;
 if t.last_request_id is distinct from p_request_id then
  if t.version is distinct from p_version then raise sqlstate '40001' using message='Otra persona cambió este mensaje. Conservá tu texto y volvé a abrir WhatsApp para revisar la versión guardada.';end if;
  update marathon.whatsapp_message_templates set body=trim(p_body),version=version+1,last_request_id=p_request_id,updated_at=statement_timestamp(),updated_by=auth.uid()where id=p_id;
 end if;
 return(select x from jsonb_array_elements(public.marathon_whatsapp_templates())x where x->>'id'=p_id);
end $f$;
create function public.marathon_whatsapp_template_save(p_id text,p_body text,p_version bigint,p_request_id uuid)returns jsonb language sql security invoker set search_path='' as $f$ select marathon.whatsapp_template_save(p_id,p_body,p_version,p_request_id) $f$;
revoke all on function marathon.whatsapp_template_save(text,text,bigint,uuid),public.marathon_whatsapp_template_save(text,text,bigint,uuid) from public,anon;
grant execute on function marathon.whatsapp_template_save(text,text,bigint,uuid),public.marathon_whatsapp_template_save(text,text,bigint,uuid) to authenticated;
