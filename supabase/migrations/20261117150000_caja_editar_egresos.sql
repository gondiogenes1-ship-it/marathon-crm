begin;
lock table marathon.movimientos in share mode;
create temporary table egreso_edit_install_before on commit drop as
select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)huella from marathon.movimientos x;

create function marathon.egreso_edit_fingerprint(p_data jsonb)returns text language sql stable set search_path=''as $function$
 select encode(sha256(convert_to(jsonb_build_object('datos',p_data-'huella','movement',(select to_jsonb(m)from marathon.movimientos m where id=p_data->>'id'))::text,'UTF8')),'hex')
$function$;
revoke all on function marathon.egreso_edit_fingerprint(jsonb)from public,anon,authenticated;

create function public.marathon_egreso_edit_get(p_id text)returns jsonb
language plpgsql stable security definer set search_path=''as $function$
declare m marathon.movimientos%rowtype;history jsonb;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar egresos.'using errcode='42501';end if;
 select *into m from marathon.movimientos where id=p_id;
 if not found or m.tipo<>'EGRESO'or m.dni is not null or m.compensacion_de is not null then raise exception 'Egreso original no encontrado.'using errcode='PT404';end if;
 if exists(select 1 from marathon.movimientos where compensacion_de=m.id)then raise exception 'El egreso ya fue anulado o reemplazado.'using errcode='PT409';end if;
 select coalesce(jsonb_agg(jsonb_build_object('fecha',a.created_at,'responsable',u.display_name,'antes',a.before_data,'despues',a.after_data)order by a.created_at desc),'[]')into history
 from marathon.operation_audit a left join marathon.app_users u on u.user_id=a.actor where a.entity='egreso_edit'and a.entity_id=m.id;
 return jsonb_build_object('movement',to_jsonb(m),'history',history);
end$function$;

create function marathon.egreso_edit_run(p_request_id text,p_data jsonb)returns jsonb language plpgsql set search_path=''as $function$
declare old marathon.movimientos%rowtype;newrow marathon.movimientos%rowtype;previous jsonb;reply jsonb;kind text;prof text;sec text;ter text;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar egresos.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'egreso:edit',p_data);if previous is not null then return previous;end if;
 if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['id','version','fecha','hora','monto','medio','sede','concepto','observaciones','categoria','subtipo','profesional','terapia','secretaria','motivo','huella']))then raise exception 'Campos de edición inválidos.'using errcode='22023';end if;
 perform public.marathon_egreso_edit_get(p_data->>'id');
 select *into strict old from marathon.movimientos where id=p_data->>'id'for update;
 if old.version<>marathon.operation_version(p_data)then raise exception 'El egreso cambió. Volvé a abrirlo.'using errcode='PT409';end if;
 perform marathon.master_text(p_data,'motivo',1000,true);perform marathon.master_text(p_data,'concepto',200,true);
 perform marathon.master_text(p_data,'observaciones',1000,false);perform marathon.master_text(p_data,'categoria',100,false);
 if length(btrim(p_data->>'motivo'))<3 then raise exception 'Indicá el motivo de la edición.'using errcode='22023';end if;
 perform marathon.saldo_importe(p_data->>'monto');
 kind=p_data->>'subtipo';
 if kind not in('OTRO_EGRESO','GASTO_GENERAL','PAGO_PROFESIONAL','CONSERVAR')or kind is null then raise exception 'Elegí un subtipo de egreso válido.'using errcode='22023';end if;
 if kind='CONSERVAR'and old.subtipo is not null then raise exception 'Este egreso ya tiene subtipo asignado; elegí uno.'using errcode='22023';end if;
 if p_data->>'medio'not in('EFECTIVO','TRANSFERENCIA')or nullif(p_data->>'medio','')is null or p_data->>'hora'!~'^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9](\.[0-9]{1,6})?)?$'or nullif(p_data->>'hora','')is null then raise exception 'Medio u hora inválidos.'using errcode='22023';end if;
 perform marathon.agenda_date(p_data->>'fecha');
 if not exists(select 1 from marathon.sedes where nombre=p_data->>'sede'and(estado='ACTIVO'or nombre=old.sede))then raise exception 'Sede inválida.'using errcode='22023';end if;
 prof=nullif(p_data->>'profesional','');sec=nullif(p_data->>'secretaria','');ter=nullif(p_data->>'terapia','');
 if prof is not null and not exists(select 1 from marathon.profesionales where id=prof and(estado='ACTIVO'or id=old.profesional_asociado_id))then raise exception 'Profesional inválido.'using errcode='22023';end if;
 if sec is not null and not exists(select 1 from marathon.secretarias where nombre=sec and(estado='ACTIVO'or nombre=old.secretaria_asociada))then raise exception 'Secretaría inválida.'using errcode='22023';end if;
 if prof is not null and sec is not null then raise exception 'Asociá un profesional o una secretaría.'using errcode='22023';end if;
 if ter is not null and not exists(select 1 from marathon.terapias where id=ter and(estado='ACTIVO'or id=old.terapia_asociada_id))then raise exception 'Terapia inválida.'using errcode='22023';end if;
 if kind='PAGO_PROFESIONAL'and(prof is null or ter is null)then raise exception 'Pago a profesional requiere elegir profesional y terapia.'using errcode='22023';end if;
 update marathon.movimientos set fecha=(p_data->>'fecha')::date,hora=(p_data->>'hora')::time,monto=marathon.saldo_importe(p_data->>'monto'),medio=p_data->>'medio',sede=p_data->>'sede',concepto=btrim(p_data->>'concepto'),observaciones_legacy=nullif(p_data->>'observaciones',''),categoria=nullif(p_data->>'categoria',''),subtipo=case when kind='CONSERVAR'then null else kind end,profesional_asociado_id=prof,terapia_asociada_id=ter,secretaria_asociada=sec,updated_by=auth.uid()where id=old.id returning *into newrow;
 reply=jsonb_build_object('id',newrow.id,'antes',to_jsonb(old),'despues',to_jsonb(newrow),'motivo',btrim(p_data->>'motivo'),'message','Egreso corregido. Se conservó el historial de la edición.');
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)values(p_request_id,auth.uid(),'egreso_edit',old.id,'editar',to_jsonb(old),reply);
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 return reply;
end$function$;
revoke all on function marathon.egreso_edit_run(text,jsonb)from public,anon,authenticated;

create function public.marathon_egreso_edit_preview(p_data jsonb)returns jsonb language plpgsql security definer set search_path=''as $function$
declare r jsonb;fingerprint text;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar egresos.'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 fingerprint=marathon.egreso_edit_fingerprint(p_data);
 begin
  r=marathon.egreso_edit_run('preview-edit-'||gen_random_uuid(),p_data);
  raise sqlstate 'ZP002'using message='preview_rollback';
 exception when sqlstate 'ZP002'then null;end;
 return r||jsonb_build_object('huella',fingerprint);
end$function$;
create function public.marathon_egreso_edit_save(p_request_id text,p_data jsonb)returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $function$
declare previous jsonb;begin
 if not marathon.active_user()then raise exception 'Se requiere un usuario activo para editar egresos.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'egreso:edit',p_data);if previous is not null then return previous;end if;
 if p_data->>'huella'is distinct from marathon.egreso_edit_fingerprint(p_data)then raise exception 'Los datos cambiaron. Volvé a revisar la edición.'using errcode='PT409';end if;
 return marathon.egreso_edit_run(p_request_id,p_data);
end$function$;
revoke all on function public.marathon_egreso_edit_get(text),public.marathon_egreso_edit_preview(jsonb),public.marathon_egreso_edit_save(text,jsonb)from public,anon;
grant execute on function public.marathon_egreso_edit_get(text),public.marathon_egreso_edit_preview(jsonb),public.marathon_egreso_edit_save(text,jsonb)to authenticated;

do $guard$declare h text;begin
 select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text)into h from marathon.movimientos x;
 if h<>(select huella from egreso_edit_install_before)then raise exception 'La instalación alteró movimientos.';end if;
end $guard$;
commit;
