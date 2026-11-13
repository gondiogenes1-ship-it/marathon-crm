-- Nuevo rol SECRETARIA_ORTOPEDIA: acceso exclusivo a Ortopedia (venta, devolución, pago,
-- traslado), limitado a las sedes que se le asignen, SIN acceso a fichas de pacientes,
-- turnos clínicos, caja general ni informes. No hace alquiler (las sedes nuevas no lo
-- ofrecen); la venta queda sin paciente obligatorio.
--
-- Modelo de seguridad: "denegado por defecto". marathon.active_user() y
-- marathon.operation_begin() (los dos puntos de entrada que usa casi todo el sistema)
-- pasan a exigir rol ADMIN o SECRETARIA. Como hoy sólo existen esos dos roles, esto no
-- cambia nada para ningún usuario actual. El nuevo rol sólo se habilita explícitamente
-- en las funciones de Ortopedia que necesita.
--
-- Reutiliza la tabla marathon.user_sedes, que ya existe en el esquema (con RLS de
-- lectura) pero no estaba conectada a ninguna función todavía.
--
-- Correr en el SQL Editor de Supabase (una sola vez). Es una sola transacción: si algún
-- bloque no encuentra el patrón esperado (por ejemplo porque una función cambió desde
-- que se escribió este script), todo el script se cancela sin aplicar nada a medias.

begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));

-- 1) Nuevo valor de rol en los dos constraints existentes.
alter table marathon.app_users drop constraint app_users_role_check;
alter table marathon.app_users add constraint app_users_role_check
  check (role = any (array['ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA']));
alter table marathon.user_provision drop constraint user_provision_role_check;
alter table marathon.user_provision add constraint user_provision_role_check
  check (role = any (array['ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA']));

-- 2) Helpers nuevos.
create or replace function marathon.ortho_only() returns boolean
  language sql stable security definer set search_path='' as $$
  select exists(select 1 from marathon.app_users where user_id=(select auth.uid()) and active and role='SECRETARIA_ORTOPEDIA')
$$;
revoke all on function marathon.ortho_only() from public,anon;
grant execute on function marathon.ortho_only() to authenticated;

create or replace function marathon.ortho_sede_allowed(p_sede text) returns boolean
  language sql stable security definer set search_path='' as $$
  select case when marathon.ortho_only()
    then exists(select 1 from marathon.user_sedes where user_id=(select auth.uid()) and sede=p_sede)
    else true end
$$;
revoke all on function marathon.ortho_sede_allowed(text) from public,anon;
grant execute on function marathon.ortho_sede_allowed(text) to authenticated;

-- 3) Puerta general: active_user() exige ahora ADMIN o SECRETARIA (sin cambios para
--    esos dos roles; el nuevo rol queda afuera salvo donde se lo habilite explícito).
create or replace function marathon.active_user() returns boolean
  language sql stable security definer set search_path='' as
  $$ select exists(select 1 from marathon.app_users where user_id=(select auth.uid()) and active and role in('ADMIN','SECRETARIA')) $$;

-- 4) Puerta de las funciones de escritura ("_command"/"_save"): operation_begin gana un
--    parámetro opcional de roles permitidos; por defecto son los dos de siempre, así que
--    ningún llamador existente cambia de comportamiento. Sólo marathon_ortho_command va a
--    pasar un valor distinto.
create or replace function marathon.operation_begin(p_id text, p_kind text, p_data jsonb,
    p_roles text[] default array['ADMIN','SECRETARIA']) returns jsonb
  language plpgsql set search_path='' as $_$
declare uid uuid:=auth.uid();h text;r marathon.solicitudes%rowtype;begin
 perform 1 from marathon.app_users where user_id=uid and active and role=any(p_roles) for share;
 if not found then raise sqlstate '42501' using message='Acceso no autorizado.';end if;
 if p_id is null or p_id !~ '^[a-zA-Z0-9_-]{12,100}$' or p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>60000 then raise sqlstate '22023' using message='Solicitud inválida.';end if;
 if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '22023' using message='La operación requiere transacciones READ COMMITTED.';end if;
 h=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 insert into marathon.solicitudes(id,usuario_id,tipo,payload_hash) values(p_id,uid,p_kind,h) on conflict on constraint solicitudes_pkey do nothing;
 select * into r from marathon.solicitudes s where s.id=p_id for update;
 if r.id is null or r.usuario_id<>uid or r.tipo<>p_kind or r.payload_hash<>h then raise sqlstate '22023' using message='Identificador de solicitud utilizado con otros datos.';end if;
 if r.resultado is not null then return r.resultado;end if;
 perform pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));return null;
end $_$;

-- 5) marathon_agenda_command (turnos clínicos) y marathon_patient_save (ficha de
--    paciente) tienen su propia puerta inline, sin pasar por active_user() ni por
--    operation_begin — hay que restringirlas una por una.
do $$
declare src text; newsrc text; old_frag text := $frag$perform 1 from marathon.app_users where user_id=uid and active for share;$frag$;
 new_frag text := $frag$perform 1 from marathon.app_users where user_id=uid and active and role in('ADMIN','SECRETARIA') for share;$frag$;
begin
 src := pg_get_functiondef('public.marathon_agenda_command(text,text,jsonb)'::regprocedure);
 newsrc := replace(src, old_frag, new_frag);
 if newsrc = src then raise exception 'marathon_agenda_command: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; newsrc text; old_frag text := $frag$perform 1 from marathon.app_users where user_id=uid and active for share;$frag$;
 new_frag text := $frag$perform 1 from marathon.app_users where user_id=uid and active and role in('ADMIN','SECRETARIA') for share;$frag$;
begin
 src := pg_get_functiondef('public.marathon_patient_save(text,jsonb,bigint)'::regprocedure);
 newsrc := replace(src, old_frag, new_frag);
 if newsrc = src then raise exception 'marathon_patient_save: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

-- 6) Las funciones de alta/edición de usuarios validan el rol contra una lista fija de 2
--    valores; hay que sumar el nuevo rol en cada una.
do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_link(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$role not in('ADMIN','SECRETARIA')$frag$, $frag$role not in('ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA')$frag$);
 if newsrc = src then raise exception 'marathon_user_link: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_provision_begin(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$role not in('ADMIN','SECRETARIA')$frag$, $frag$role not in('ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA')$frag$);
 if newsrc = src then raise exception 'marathon_user_provision_begin: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_user_save(text,jsonb)'::regprocedure);
 newsrc := replace(src, $frag$role not in('ADMIN','SECRETARIA')$frag$, $frag$role not in('ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA')$frag$);
 if newsrc = src then raise exception 'marathon_user_save: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

-- 7) marathon_user_list: suma las sedes asignadas a cada usuario, para mostrarlas en la
--    pantalla de Usuarios al editar.
do $$
declare src text; newsrc text;
 old_frag text := $frag$select a.user_id,a.display_name,a.role,a.active,a.version,coalesce(u.email,'')email,u.email_confirmed_at is not null confirmed,u.last_sign_in_at
 from marathon.app_users a join auth.users u on u.id=a.user_id where$frag$;
 new_frag text := $frag$select a.user_id,a.display_name,a.role,a.active,a.version,coalesce(u.email,'')email,u.email_confirmed_at is not null confirmed,u.last_sign_in_at,
 coalesce((select jsonb_agg(s.sede order by s.sede) from marathon.user_sedes s where s.user_id=a.user_id),'[]'::jsonb) sedes
 from marathon.app_users a join auth.users u on u.id=a.user_id where$frag$;
begin
 src := pg_get_functiondef('public.marathon_user_list(text,uuid,integer)'::regprocedure);
 newsrc := replace(src, old_frag, new_frag);
 if newsrc = src then raise exception 'marathon_user_list: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

-- 8) Nueva función: ADMIN asigna o cambia las sedes habilitadas de un usuario
--    (sólo tiene efecto real para SECRETARIA_ORTOPEDIA; para ADMIN/SECRETARIA no
--    restringe nada, ya que esos roles siguen operando en todas las sedes).
create or replace function public.marathon_user_sedes_save(p_request_id text, p_data jsonb) returns jsonb
  language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare reply jsonb; target uuid; sedes text[]; bad text;
begin
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo administración puede asignar sedes.'; end if;
 reply=marathon.operation_begin(p_request_id,'user:sedes',p_data);
 if not marathon.is_admin() then raise sqlstate '42501' using message='Solo administración puede asignar sedes.'; end if;
 if reply is not null then return reply; end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['user_id','sedes']))
   or coalesce(p_data->>'user_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(p_data->'sedes') is distinct from 'array' or jsonb_array_length(p_data->'sedes')>50
 then raise sqlstate '22023' using message='Datos de sedes inválidos.'; end if;
 target=(p_data->>'user_id')::uuid;
 if not exists(select 1 from marathon.app_users where user_id=target) then raise sqlstate 'PT404' using message='El usuario no existe.'; end if;
 select array_agg(distinct value) into sedes from jsonb_array_elements_text(p_data->'sedes') value;
 select sede into bad from unnest(coalesce(sedes,array[]::text[])) sede where not exists(select 1 from marathon.sedes s where s.nombre=sede and s.estado='ACTIVO') limit 1;
 if bad is not null then raise sqlstate '22023' using message='Sede inválida o inactiva: '||bad; end if;
 delete from marathon.user_sedes where user_id=target;
 insert into marathon.user_sedes(user_id,sede,created_by,updated_by)
   select target,s,auth.uid(),auth.uid() from unnest(coalesce(sedes,array[]::text[])) s;
 insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,after_data)
   values(p_request_id,auth.uid(),'user-sedes',target::text,'save',jsonb_build_object('sedes',coalesce(sedes,array[]::text[])));
 reply=jsonb_build_object('message','Sedes actualizadas.');
 update marathon.solicitudes set resultado=reply where id=p_request_id;return reply;
end $$;
revoke all on function public.marathon_user_sedes_save(text,jsonb) from public,anon;
grant execute on function public.marathon_user_sedes_save(text,jsonb) to authenticated;

-- 9) marathon_session: sin esto el nuevo rol no puede ni iniciar sesión (signIn llama a
--    esta función inmediatamente después de autenticar, y hoy exige active_user()).
do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_session()'::regprocedure);
 newsrc := replace(src,
  $frag$if not marathon.active_user() then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 select jsonb_build_object('user_id',user_id,'name',display_name,'role',role,'all_sites',true)
 into r from marathon.app_users where user_id=auth.uid(); return r;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise exception using errcode='42501',message='Acceso no autorizado.'; end if;
 select jsonb_build_object('user_id',user_id,'name',display_name,'role',role,'all_sites',role<>'SECRETARIA_ORTOPEDIA')
 into r from marathon.app_users where user_id=auth.uid(); return r;$frag$);
 if newsrc = src then raise exception 'marathon_session: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

-- 10) Funciones de lectura de Ortopedia: habilitar al nuevo rol y acotarlas a sus sedes.
do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_sites()'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_sites: no se encontró el patrón de la puerta de acceso.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$return coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre) order by nombre)from marathon.sedes where estado='ACTIVO'),'[]'::jsonb);$frag$,
  $frag$return coalesce((select jsonb_agg(jsonb_build_object('id',nombre,'label',nombre) order by nombre)from marathon.sedes where estado='ACTIVO' and(not marathon.ortho_only() or nombre in(select sede from marathon.user_sedes where user_id=auth.uid()))),'[]'::jsonb);$frag$);
 if cur = prev then raise exception 'marathon_ortho_sites: no se encontró el patrón del listado de sedes.'; end if;

 execute cur;
end $$;

do $$
declare src text; newsrc text;
begin
 src := pg_get_functiondef('public.marathon_ortho_catalog(text,text,text,integer)'::regprocedure);
 newsrc := replace(src,
  $frag$if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$);
 if newsrc = src then raise exception 'marathon_ortho_catalog: no se encontró el patrón esperado.'; end if;
 execute newsrc;
end $$;

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_product(text)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if not marathon.active_user() then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_product: no se encontró el patrón de la puerta de acceso.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$select to_jsonb(p)||jsonb_build_object('sites',coalesce((select jsonb_agg(to_jsonb(x) order by x.sede) from(select c.*,marathon.ortho_stock(c.producto_id,c.sede) stock from marathon.stock_config c where c.producto_id=p.id)x),'[]'::jsonb)) into r from marathon.productos p where id=p_id;$frag$,
  $frag$select to_jsonb(p)||jsonb_build_object('sites',coalesce((select jsonb_agg(to_jsonb(x) order by x.sede) from(select c.*,marathon.ortho_stock(c.producto_id,c.sede) stock from marathon.stock_config c where c.producto_id=p.id and(not marathon.ortho_only() or c.sede in(select sede from marathon.user_sedes where user_id=auth.uid())))x),'[]'::jsonb)) into r from marathon.productos p where id=p_id;$frag$);
 if cur = prev then raise exception 'marathon_ortho_product: no se encontró el patrón del listado de sedes del producto.'; end if;

 execute cur;
end $$;

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_get(text)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if not marathon.active_user()then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise sqlstate '42501' using message='Acceso no autorizado.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_get: no se encontró el patrón de la puerta de acceso.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$into r from marathon.ortopedia_operaciones o join marathon.productos p on p.id=o.producto_id where o.id=p_id;
 if r is null then raise sqlstate 'PT404' using message='Operación no encontrada.';end if;return r;$frag$,
  $frag$into r from marathon.ortopedia_operaciones o join marathon.productos p on p.id=o.producto_id where o.id=p_id;
 if r is null then raise sqlstate 'PT404' using message='Operación no encontrada.';end if;
 if not marathon.ortho_sede_allowed(r->>'sede') then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;
 return r;$frag$);
 if cur = prev then raise exception 'marathon_ortho_get: no se encontró el patrón de retorno/validación de sede.'; end if;

 execute cur;
end $$;

do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_search(text,jsonb,jsonb,integer)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;$frag$,
  $frag$if not(marathon.active_user() or marathon.ortho_only())then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 if marathon.ortho_only() and coalesce(p_filters->>'sede','')<>'' and not marathon.ortho_sede_allowed(p_filters->>'sede') then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_search: no se encontró el patrón de la puerta de acceso.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$where(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(concat_ws(' ',id,descripcion,pieza,marca,codigo,talle)),marathon.master_norm(p_filters->>'query'))>0)and(case coalesce(p_filters->>'stock_state','')$frag$,
  $frag$where(case when marathon.ortho_only()then sede in(select us.sede from marathon.user_sedes us where us.user_id=auth.uid())else(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')end)and(coalesce(p_filters->>'query','')=''or strpos(marathon.master_norm(concat_ws(' ',id,descripcion,pieza,marca,codigo,talle)),marathon.master_norm(p_filters->>'query'))>0)and(case coalesce(p_filters->>'stock_state','')$frag$);
 if cur = prev then raise exception 'marathon_ortho_search: no se encontró el patrón de filtro de sede (stock).'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$select coalesce(jsonb_agg(to_jsonb(x)order by fecha desc,hora desc,id desc),'[]'::jsonb)into rows from(select * from marathon.daily_ortho o where(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')and(coalesce(p_filters->>'query','')=''$frag$,
  $frag$select coalesce(jsonb_agg(to_jsonb(x)order by fecha desc,hora desc,id desc),'[]'::jsonb)into rows from(select * from marathon.daily_ortho o where(case when marathon.ortho_only()then sede in(select us.sede from marathon.user_sedes us where us.user_id=auth.uid())else(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')end)and(coalesce(p_filters->>'query','')=''$frag$);
 if cur = prev then raise exception 'marathon_ortho_search: no se encontró el patrón de filtro de sede (historial/devoluciones/deudas).'; end if;

 execute cur;
end $$;

-- 11) marathon_ortho_command: habilitar al rol sólo para venta/devolución/cobro/
--     reintegro/traslado (nunca alquiler ni compra/ajustes, que ya son sólo ADMIN),
--     acotar cada sede tocada a las habilitadas del usuario, y permitir venta sin
--     paciente (alquiler sigue exigiéndolo).
do $$
declare src text; cur text; prev text;
begin
 src := pg_get_functiondef('public.marathon_ortho_command(text,text,jsonb)'::regprocedure);
 cur := src;

 prev := cur;
 cur := replace(cur,
  $frag$reply=marathon.operation_begin(p_request_id,'ortho:'||coalesce(p_action,''),p_data);if reply is not null then return reply;end if;$frag$,
  $frag$reply=marathon.operation_begin(p_request_id,'ortho:'||coalesce(p_action,''),p_data,array['ADMIN','SECRETARIA','SECRETARIA_ORTOPEDIA']);if reply is not null then return reply;end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de operation_begin.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$if p_action in('purchase','adjust_in','adjust_out','purchase_pay','reverse')and not marathon.is_admin()then raise sqlstate '42501' using message='Solo ADMIN puede comprar, ajustar stock o aprobar contrasientos.';end if;$frag$,
  $frag$if p_action in('purchase','adjust_in','adjust_out','purchase_pay','reverse')and not marathon.is_admin()then raise sqlstate '42501' using message='Solo ADMIN puede comprar, ajustar stock o aprobar contrasientos.';end if;
 if p_action='rent' and marathon.ortho_only() then raise sqlstate '42501' using message='Esta cuenta no puede registrar alquileres.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón del bloqueo de ADMIN (purchase/adjust/reverse).'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$if p.id is null or p.estado<>'ACTIVO'or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')then raise sqlstate '22023' using message='Elegí un producto y una sede activos.';end if;$frag$,
  $frag$if p.id is null or p.estado<>'ACTIVO'or not exists(select 1 from marathon.sedes where nombre=site and estado='ACTIVO')then raise sqlstate '22023' using message='Elegí un producto y una sede activos.';end if;
 if not marathon.ortho_sede_allowed(site) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de validación de sede de origen.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$destination=marathon.master_text(p_data,'destino',40,true);$frag$,
  $frag$destination=marathon.master_text(p_data,'destino',40,true);
 if not marathon.ortho_sede_allowed(destination) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de sede destino (traslado).'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$if p_action in('sale','rent')then dni=marathon.master_text(p_data,'dni',12,true);if not exists(select 1 from marathon.pacientes where pacientes.dni=dni)then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;$frag$,
  $frag$if p_action in('sale','rent')then dni=nullif(marathon.master_text(p_data,'dni',12,p_action='rent'),'');if dni is not null and not exists(select 1 from marathon.pacientes where pacientes.dni=dni)then raise sqlstate '22023' using message='Buscá y seleccioná un paciente registrado.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de validación de DNI en venta/alquiler.'; end if;

 prev := cur;
 cur := replace(cur,
  $frag$if old.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='La operación cambió. Volvé a abrirla.';end if;end if;$frag$,
  $frag$if old.version<>marathon.operation_version(p_data)then raise sqlstate 'PT409' using message='La operación cambió. Volvé a abrirla.';end if;end if;
 if not marathon.ortho_sede_allowed(old.sede) then raise sqlstate '42501' using message='Esta cuenta no puede operar en esa sede.';end if;$frag$);
 if cur = prev then raise exception 'marathon_ortho_command: no se encontró el patrón de sede en devolución/cobro/reintegro.'; end if;

 execute cur;
end $$;

notify pgrst,'reload schema';
commit;
