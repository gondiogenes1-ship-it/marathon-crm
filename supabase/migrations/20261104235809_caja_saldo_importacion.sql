-- Preparación de corte. No se invoca automáticamente ni se publica como RPC.
begin;
create function marathon.saldo_caja_foto()returns jsonb language sql stable set search_path=''as $$
 select coalesce(jsonb_agg(to_jsonb(x)order by fecha,medio,sede,origen),'[]')from(
 select fecha,medio,sede,origen,count(*)cantidad,sum(case when tipo in('PAGO','INGRESO')then monto else 0 end)::text ingresos,
 sum(case when tipo in('EGRESO','REINTEGRO')then monto else 0 end)::text egresos
 from marathon.movimientos group by fecha,medio,sede,origen)x
$$;
create function marathon.saldo_huella_legacy()returns text language sql stable set search_path=''as $$
 select encode(sha256(convert_to(jsonb_build_object(
 'm',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.movimientos x),
 't',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.turnos x),
 'q',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.agenda_cuotas x),
 'b',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.bonos_serie x),
 'a',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.anticipos x),
 'ae',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.anticipo_eventos x),
 'aj',(select coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')from marathon.agenda_ajustes x))::text,'UTF8')),'hex')
$$;
create function marathon.saldo_importacion_fuentes()returns table(movimiento_id text,dni text,monto numeric,anticipo_id text,turno_id text,cuota_id uuid,bono_id text)language sql stable set search_path=''as $$
 select m.id,m.dni,m.monto,m.anticipo_id,m.turno_id,m.cuota_id,m.bono_id from marathon.movimientos m where m.tipo in('PAGO','INGRESO')and m.monto>0 and m.dni is not null and m.origen<>'ORTOPEDIA'and
 (m.turno_id is not null or m.cuota_id is not null or m.bono_id is not null or m.anticipo_id is not null or m.id='MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95')
 order by m.fecha,m.hora,m.created_at,m.id
$$;
create function marathon.saldo_importacion_prever()returns jsonb language plpgsql stable set search_path=''as $$
declare problems jsonb:='[]';accounts jsonb;begin
 -- Se detiene ante nuevos históricos que no encajan; nunca adivina su significado.
 select coalesce(jsonb_agg(jsonb_build_object('motivo','Ingreso manual pendiente de clasificación','id',m.id)),'[]')into problems
 from marathon.movimientos m where m.origen='CAJA'and m.tipo='INGRESO'and m.dni is not null and m.cuota_id is null and m.compensacion_de is null and m.id<>all(array[
 'MOV-b56fbddb-e1eb-4376-96c1-df1f786ec1ac','MOV-69c21c72-3972-4294-a2d2-600a50f5b883','MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95']);
 if exists(select 1 from marathon.movimientos m where(m.turno_id is not null or m.cuota_id is not null or m.bono_id is not null or m.anticipo_id is not null)and(m.tipo in('REINTEGRO','EGRESO')or m.compensacion_de is not null))or
 exists(select 1 from marathon.movimientos m join marathon.saldo_importacion_fuentes()f on f.movimiento_id=m.compensacion_de)then problems=problems||jsonb_build_array(jsonb_build_object('motivo','Hay reintegros o contrasientos clínicos que requieren plan individual.'));end if;
 if exists(select 1 from marathon.anticipo_eventos where tipo not in('DEPOSITO','APLICACION'))or exists(select 1 from marathon.anticipos a where(select count(*)from marathon.anticipo_eventos e where e.anticipo_id=a.id and e.tipo='DEPOSITO')<>1)then problems=problems||jsonb_build_array(jsonb_build_object('motivo','Anticipo con estructura histórica no cubierta.'));end if;
 if exists(select 1 from marathon.movimientos where id='MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95'and(monto<>40000 or concepto<>'GIMNASIO X 3'))then problems=problems||jsonb_build_array(jsonb_build_object('motivo','Cambió el ingreso de Carlos aprobado por el usuario.'));end if;
 if exists(select 1 from marathon.turnos t where marathon.saldo_legacy_pagado('sesion',t.id)>0 and(t.estado<>'PRESENTE'or marathon.saldo_legacy_pagado('sesion',t.id)>t.importe))or
 exists(select 1 from marathon.bonos_serie b where marathon.saldo_legacy_pagado('bono',b.id)>0 and(b.estado<>'ACTIVO'or marathon.saldo_legacy_pagado('bono',b.id)>b.importe))or
 exists(select 1 from marathon.agenda_cuotas q where marathon.saldo_legacy_pagado('cuota',q.id::text)>q.importe-coalesce((select sum(importe)from marathon.agenda_ajustes where cuota_id=q.id),0))then problems=problems||jsonb_build_array(jsonb_build_object('motivo','Pagos históricos exceden cargos o corresponden a deuda inactiva.'));end if;
 select coalesce(jsonb_agg(jsonb_build_object('dni',p.dni,'deuda',coalesce((select sum(deuda)from marathon.saldo_deudas(p.dni)),0)::text,
 'saldo',(coalesce((select sum(case e.tipo when'DEPOSITO'then e.monto when'REVERSO'then e.monto else -e.monto end)from marathon.anticipos a join marathon.anticipo_eventos e on e.anticipo_id=a.id where a.dni=p.dni),0)+
 coalesce((select sum(monto)from marathon.movimientos m where m.dni=p.dni and m.id='MOV-fecd8747-bfa4-43e0-81f9-56d5a336fc95'),0))::text)order by p.dni),'[]')into accounts from marathon.pacientes p;
 return jsonb_build_object('huella',marathon.saldo_huella_legacy(),'bloqueos',problems,'cuentas',accounts,'caja',marathon.saldo_caja_foto(),'fuentes',(select count(*)from marathon.saldo_importacion_fuentes()),'activo',(select activo from marathon.saldo_config));
end$$;

create function marathon.saldo_importar(p_request_id text,p_huella text)returns jsonb language plpgsql set search_path=''set lock_timeout='3s'as $$
declare previous jsonb;plan jsonb;f record;d record;aid uuid;source uuid;reply jsonb;begin
 if not marathon.is_admin()then raise exception 'Solo ADMIN.'using errcode='42501';end if;
 previous=marathon.operation_begin(p_request_id,'saldo:importar',jsonb_build_object('huella',p_huella));if previous is not null then return previous;end if;
 if exists(select 1 from marathon.saldo_config where activo)or exists(select 1 from marathon.saldo_fuentes)then raise exception 'El circuito ya contiene datos o está activo.'using errcode='55000';end if;
 plan=marathon.saldo_importacion_prever();
 if plan->>'huella'is distinct from p_huella then raise exception 'La base cambió desde la prueba en seco.'using errcode='PT409';end if;
 if jsonb_array_length(plan->'bloqueos')>0 then raise exception 'La prueba en seco contiene casos pendientes: %',plan->'bloqueos'using errcode='22023';end if;
 -- Congelar exclusivamente la representación de pagos, sin modificar originales.
 insert into marathon.saldo_base_legacy(tipo,id,pagado)
 select 'sesion',t.id,marathon.saldo_legacy_pagado('sesion',t.id)from marathon.turnos t where marathon.saldo_legacy_pagado('sesion',t.id)>0
 union all select 'bono',b.id,marathon.saldo_legacy_pagado('bono',b.id)from marathon.bonos_serie b where marathon.saldo_legacy_pagado('bono',b.id)>0
 union all select 'cuota',q.id::text,marathon.saldo_legacy_pagado('cuota',q.id::text)from marathon.agenda_cuotas q where marathon.saldo_legacy_pagado('cuota',q.id::text)>0;
 for f in select *from marathon.saldo_importacion_fuentes()loop
  insert into marathon.saldo_fuentes(dni,movimiento_id,origen)values(f.dni,f.movimiento_id,'IMPORTADO')returning id into source;
  insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,movimiento_id,request_id,actor,efecto)values(f.dni,source,'INGRESO',f.monto,f.movimiento_id,p_request_id,auth.uid(),'importar:'||f.movimiento_id);
  insert into marathon.saldo_importacion_map(origen,destino,lote)values(f.movimiento_id,source,p_request_id);
  for d in
   select f.turno_id as turno_id,f.cuota_id as cuota_id,f.bono_id as bono_id,f.monto as monto where f.anticipo_id is null and num_nonnulls(f.turno_id,f.cuota_id,f.bono_id)=1
   union all select e.turno_id,null::uuid,null::text,sum(e.monto)from marathon.anticipo_eventos e where e.anticipo_id=f.anticipo_id and e.tipo='APLICACION'group by e.turno_id
  loop
   insert into marathon.saldo_aplicaciones(dni,fuente_id,turno_id,cuota_id,bono_id,monto,request_id,actor)values(f.dni,source,d.turno_id,d.cuota_id,d.bono_id,d.monto,p_request_id,auth.uid())returning id into aid;
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(f.dni,source,'APLICACION',d.monto,aid,p_request_id,auth.uid(),'importar:aplicar:'||aid);
  end loop;
 end loop;
 -- No aplicar remanentes durante la importación: conservar deudas y disponibilidad.
 if plan->'caja'<>marathon.saldo_caja_foto()or exists(select 1 from jsonb_array_elements(plan->'cuentas')x where(x->>'saldo')::numeric<>marathon.saldo_disponible(x->>'dni')or(x->>'deuda')::numeric<>coalesce((select sum(deuda)from marathon.saldo_deudas(x->>'dni')),0))then raise exception 'Conciliación fallida: importación revertida.'using errcode='22023';end if;
 reply=jsonb_build_object('conciliado',true,'plan',plan,'aplicaciones',(select count(*)from marathon.saldo_aplicaciones),'circuito_activo',false);
 update marathon.solicitudes set resultado=reply where id=p_request_id;
 return reply;
end$$;
revoke all on function marathon.saldo_caja_foto(),marathon.saldo_huella_legacy(),marathon.saldo_importacion_fuentes(),marathon.saldo_importacion_prever(),marathon.saldo_importar(text,text)from public,anon,authenticated;
commit;
