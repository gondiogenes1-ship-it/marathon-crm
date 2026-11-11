-- Fase 2: desarrollo aislado. No ejecutar en producción sin conciliación y aprobación.
begin;
create table marathon.saldo_cuentas(
 dni text primary key references marathon.pacientes(dni), version bigint not null default 1 check(version>0)
);
create table marathon.saldo_fuentes(
 id uuid primary key default gen_random_uuid(), dni text not null references marathon.pacientes(dni),
 movimiento_id text unique references marathon.movimientos(id), origen text not null,
 created_at timestamptz not null default now(),unique(id,dni)
);
create table marathon.saldo_aplicaciones(
 id uuid primary key default gen_random_uuid(),dni text not null references marathon.pacientes(dni),fuente_id uuid not null,
 turno_id text references marathon.turnos(id),cuota_id uuid references marathon.agenda_cuotas(id),bono_id text references marathon.bonos_serie(id),
 monto numeric(18,2)not null check(monto>0),request_id text not null references marathon.solicitudes(id),
 actor uuid not null references marathon.app_users(user_id),created_at timestamptz not null default now(),
 foreign key(fuente_id,dni)references marathon.saldo_fuentes(id,dni),
 check(num_nonnulls(turno_id,cuota_id,bono_id)=1),unique(id,fuente_id,dni)
);
create table marathon.saldo_eventos(
 id uuid primary key default gen_random_uuid(),dni text not null references marathon.pacientes(dni),fuente_id uuid not null,
 tipo text not null check(tipo in('INGRESO','APLICACION','REVERSO_APLICACION','DEVOLUCION')),
 monto numeric(18,2)not null check(monto>0),aplicacion_id uuid,
 movimiento_id text references marathon.movimientos(id),request_id text not null references marathon.solicitudes(id),
 actor uuid not null references marathon.app_users(user_id),efecto text not null,created_at timestamptz not null default now(),
 foreign key(fuente_id,dni)references marathon.saldo_fuentes(id,dni),
 foreign key(aplicacion_id,fuente_id,dni)references marathon.saldo_aplicaciones(id,fuente_id,dni),
 check((tipo in('APLICACION','REVERSO_APLICACION')and aplicacion_id is not null and movimiento_id is null)
 or(tipo in('INGRESO','DEVOLUCION')and aplicacion_id is null and movimiento_id is not null)),
 unique(request_id,efecto)
);
create unique index saldo_aplicacion_evento_unico on marathon.saldo_eventos(aplicacion_id)where tipo='APLICACION';
create unique index saldo_ingreso_movimiento_unico on marathon.saldo_eventos(movimiento_id)where tipo='INGRESO';
create index saldo_eventos_fuente on marathon.saldo_eventos(fuente_id,tipo);
create index saldo_aplicaciones_turno on marathon.saldo_aplicaciones(turno_id)where turno_id is not null;
create index saldo_aplicaciones_cuota on marathon.saldo_aplicaciones(cuota_id)where cuota_id is not null;
create index saldo_aplicaciones_bono on marathon.saldo_aplicaciones(bono_id)where bono_id is not null;
create table marathon.saldo_ajustes_sesion(
 id uuid primary key default gen_random_uuid(),turno_id text not null references marathon.turnos(id),
 monto numeric(18,2)not null check(monto>0),motivo text not null check(length(btrim(motivo))between 3 and 1000),
 request_id text not null references marathon.solicitudes(id),actor uuid not null references marathon.app_users(user_id),
 created_at timestamptz not null default now()
);
create table marathon.saldo_importacion_map(
 origen text primary key,destino uuid not null,lote text not null,created_at timestamptz not null default now()
);
create function marathon.saldo_inmutable()returns trigger language plpgsql set search_path=''as $$begin
 raise exception 'El historial de saldo es inmutable. Registrá un reverso.'using errcode='42501';end$$;
do $$declare t text;begin foreach t in array array['saldo_fuentes','saldo_aplicaciones','saldo_eventos','saldo_ajustes_sesion','saldo_importacion_map']loop
 execute format('create trigger saldo_inmutable before update or delete on marathon.%I for each row execute function marathon.saldo_inmutable()',t);
 end loop;
 foreach t in array array['saldo_cuentas','saldo_fuentes','saldo_aplicaciones','saldo_eventos','saldo_ajustes_sesion','saldo_importacion_map']loop
 execute format('alter table marathon.%I enable row level security',t);
 execute format('revoke all on marathon.%I from public,anon,authenticated',t);
 end loop;end$$;
create function marathon.saldo_fuente_disponible(p_id uuid)returns numeric language sql stable set search_path=''as $$
 select coalesce(sum(case when tipo in('INGRESO','REVERSO_APLICACION')then monto else -monto end),0)
 from marathon.saldo_eventos where fuente_id=p_id
$$;
create function marathon.saldo_disponible(p_dni text)returns numeric language sql stable set search_path=''as $$
 select coalesce(sum(case when tipo in('INGRESO','REVERSO_APLICACION')then monto else -monto end),0)
 from marathon.saldo_eventos where dni=p_dni
$$;
create function marathon.saldo_aplicado(p_id uuid)returns numeric language sql stable set search_path=''as $$
 select coalesce(sum(case when tipo='APLICACION'then monto when tipo='REVERSO_APLICACION'then -monto else 0 end),0)
 from marathon.saldo_eventos where aplicacion_id=p_id
$$;
create function marathon.saldo_validar_aplicacion()returns trigger language plpgsql set search_path=''as $$declare owner_dni text;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if new.turno_id is not null then select dni into owner_dni from marathon.turnos where id=new.turno_id;
 elsif new.bono_id is not null then select dni into owner_dni from marathon.bonos_serie where id=new.bono_id;
 else select p.dni into owner_dni from marathon.agenda_cuotas q join marathon.agenda_planes p on p.id=q.plan_id where q.id=new.cuota_id;end if;
 if owner_dni is distinct from new.dni then raise exception 'La deuda y el saldo pertenecen a pacientes distintos.'using errcode='22023';end if;
 return new;end$$;
create trigger saldo_validar_aplicacion before insert on marathon.saldo_aplicaciones for each row execute function marathon.saldo_validar_aplicacion();
create function marathon.saldo_validar_evento()returns trigger language plpgsql set search_path=''as $$declare m marathon.movimientos%rowtype;a marathon.saldo_aplicaciones%rowtype;used numeric;begin
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
 if new.tipo='APLICACION'then
  select *into strict a from marathon.saldo_aplicaciones where id=new.aplicacion_id;
  if a.monto<>new.monto then raise exception 'Importe de aplicación inconsistente.'using errcode='22023';end if;
 end if;
 if new.tipo in('APLICACION','DEVOLUCION')and new.monto>marathon.saldo_fuente_disponible(new.fuente_id)then
  raise exception 'Saldo insuficiente.'using errcode='22023';end if;
 if new.tipo='REVERSO_APLICACION'and new.monto>marathon.saldo_aplicado(new.aplicacion_id)then
  raise exception 'El reverso supera lo aplicado.'using errcode='22023';end if;
 if new.movimiento_id is not null then
  select *into strict m from marathon.movimientos where id=new.movimiento_id;
  if m.dni is distinct from new.dni or m.origen='ORTOPEDIA'then raise exception 'Movimiento incompatible con el saldo.'using errcode='22023';end if;
  if(new.tipo='INGRESO'and m.tipo not in('PAGO','INGRESO'))or(new.tipo='DEVOLUCION'and m.tipo not in('REINTEGRO','EGRESO'))then
   raise exception 'Sentido de movimiento incompatible.'using errcode='22023';end if;
  select coalesce(sum(monto),0)into used from marathon.saldo_eventos where movimiento_id=m.id;
  if used+new.monto>m.monto then raise exception 'El evento supera el movimiento de Caja.'using errcode='22023';end if;
 end if;
 return new;end$$;
create trigger saldo_validar_evento before insert on marathon.saldo_eventos for each row execute function marathon.saldo_validar_evento();
-- Funciones internas sin acceso directo desde la API.
revoke all on function marathon.saldo_inmutable(),marathon.saldo_fuente_disponible(uuid),marathon.saldo_disponible(text),marathon.saldo_aplicado(uuid),marathon.saldo_validar_aplicacion(),marathon.saldo_validar_evento()from public,anon,authenticated;
commit;
