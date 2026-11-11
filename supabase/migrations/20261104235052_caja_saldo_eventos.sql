-- Complemento del circuito aislado: eventos automáticos y consulta de historial.
begin;
create function marathon.saldo_automatico()returns trigger language plpgsql set search_path=''as $$
declare person text;request text;reply jsonb;data jsonb;application record;begin
 if not exists(select 1 from marathon.saldo_config where activo)then return new;end if;
 if tg_table_name='turnos'then
  person=new.dni;
  if tg_op='UPDATE'and new.estado=old.estado and new.importe=old.importe then return new;end if;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'version',new.version,'estado',new.estado,'importe',new.importe);
 elsif tg_table_name='bonos_serie'then
  person=new.dni;
  if tg_op='UPDATE'and new.estado=old.estado and new.importe=old.importe then return new;end if;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'version',new.version,'estado',new.estado,'importe',new.importe);
 else
  select p.dni into person from marathon.agenda_planes p where p.id=new.plan_id;
  data=jsonb_build_object('table',tg_table_name,'id',new.id,'importe',new.importe);
 end if;
 request='saldo_auto_'||md5(data::text);
 reply=marathon.operation_begin(request,'saldo:auto',data);if reply is not null then return new;end if;
 if(tg_table_name='turnos'and new.estado<>'PRESENTE')or(tg_table_name='bonos_serie'and new.estado='ANULADO')then
  for application in select a.*,marathon.saldo_aplicado(a.id)actual from marathon.saldo_aplicaciones a where
   ((tg_table_name='turnos'and a.turno_id=new.id::text)or(tg_table_name='bonos_serie'and a.bono_id=new.id::text))and marathon.saldo_aplicado(a.id)>0 order by a.created_at,a.id loop
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(person,application.fuente_id,'REVERSO_APLICACION',application.actual,application.id,request,auth.uid(),'liberar:'||application.id);
  end loop;
 end if;
 -- Una salida de PRESENTE libera su pago. No redistribuye ese saldo en la misma acción.
 if tg_table_name<>'turnos'or new.estado='PRESENTE'then perform marathon.saldo_aplicar(person,request);end if;
 update marathon.solicitudes set resultado=jsonb_build_object('cuenta',marathon.saldo_cuenta_info(person))where id=request;
 return new;
end$$;
create trigger saldo_automatico after insert or update of estado,importe on marathon.turnos for each row execute function marathon.saldo_automatico();
create trigger saldo_automatico after insert or update of estado,importe on marathon.bonos_serie for each row execute function marathon.saldo_automatico();
create trigger saldo_automatico after insert on marathon.agenda_cuotas for each row execute function marathon.saldo_automatico();

create function public.marathon_saldo_historial(p_dni text,p_after jsonb default null,p_limit int default 25)returns jsonb language plpgsql stable security definer set search_path=''as $$declare rows jsonb;next_cursor jsonb;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or(p_after is not null and(not(p_after?&array['at','id'])or jsonb_typeof(p_after)<>'object'))then raise exception 'Consulta inválida.'using errcode='22023';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by created_at desc,id desc),'[]')into rows from(
  select e.id,e.created_at,e.tipo,e.monto::text as importe,e.fuente_id,e.movimiento_id,e.aplicacion_id,a.turno_id,a.cuota_id,a.bono_id,
   case when e.tipo='INGRESO'then'Ingreso de Caja'when e.tipo='DEVOLUCION'then'Egreso de Caja'else'Movimiento interno'end as efecto_caja,
   u.display_name as actor,m.fecha as fecha_caja,m.medio,m.sede,m.profesional_asociado_id
  from marathon.saldo_eventos e left join marathon.saldo_aplicaciones a on a.id=e.aplicacion_id
  left join marathon.movimientos m on m.id=e.movimiento_id left join marathon.app_users u on u.user_id=e.actor
  where e.dni=p_dni and(p_after is null or(e.created_at,e.id)<((p_after->>'at')::timestamptz,(p_after->>'id')::uuid))
  order by e.created_at desc,e.id desc limit p_limit+1)x;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;next_cursor=jsonb_build_object('at',rows->(p_limit-1)->>'created_at','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',next_cursor);
end$$;
revoke all on function marathon.saldo_automatico()from public,anon,authenticated;
revoke all on function public.marathon_saldo_historial(text,jsonb,int)from public,anon;
grant execute on function public.marathon_saldo_historial(text,jsonb,int)to authenticated;
commit;
