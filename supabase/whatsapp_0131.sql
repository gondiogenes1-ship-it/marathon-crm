create table marathon.whatsapp_config(
 singleton boolean primary key default true check(singleton),version bigint not null default 1,
 app_id text not null default '',config_id text not null default '',graph_version text not null default 'v26.0',
 app_secret_id uuid,verify_token text not null default gen_random_uuid()::text,
 coexistence_enabled boolean not null default false,webhook_verified_at timestamptz,
 connected boolean not null default false,phone_id text,waba_id text,phone_display text,phone_name text,access_token_id uuid,
 linked_at timestamptz,last_event_at timestamptz,last_request_id uuid,updated_at timestamptz not null default now()
);
insert into marathon.whatsapp_config(singleton)values(true);
create table marathon.whatsapp_attempts(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id),config_version bigint not null,
 status text not null default 'pending' check(status in('pending','processing','choose_phone','linked','failed')),
 created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '10 minutes',
 token_id uuid,waba_id text,phones jsonb not null default '[]'::jsonb
);
create index whatsapp_attempts_user_idx on marathon.whatsapp_attempts(user_id,created_at);
create table marathon.whatsapp_events(
 event_hash text primary key,received_at timestamptz not null default now(),payload jsonb not null
);
alter table marathon.whatsapp_config enable row level security;
alter table marathon.whatsapp_attempts enable row level security;
alter table marathon.whatsapp_events enable row level security;
revoke all on marathon.whatsapp_config,marathon.whatsapp_attempts,marathon.whatsapp_events from public,anon,authenticated;
create policy server_only on marathon.whatsapp_config to service_role using(true) with check(true);
create policy server_only on marathon.whatsapp_attempts to service_role using(true) with check(true);
create policy server_only on marathon.whatsapp_events to service_role using(true) with check(true);

create function marathon.wa_status() returns jsonb language plpgsql stable security definer set search_path='' as $f$
declare c marathon.whatsapp_config;begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede vincular WhatsApp.';end if;
 select * into c from marathon.whatsapp_config where singleton;
 return jsonb_build_object('version',c.version,'app_id',c.app_id,'config_id',c.config_id,'graph_version',c.graph_version,
 'secret_set',c.app_secret_id is not null,'coexistence_enabled',c.coexistence_enabled,'webhook_verified',c.webhook_verified_at is not null,
 'verify_token',c.verify_token,'ready',c.app_id<>'' and c.config_id<>'' and c.app_secret_id is not null and c.coexistence_enabled and c.webhook_verified_at is not null,
 'connected',c.connected,'phone_display',c.phone_display,'phone_name',c.phone_name,'linked_at',c.linked_at,'last_event_at',c.last_event_at);
end $f$;
create function public.marathon_whatsapp_status() returns jsonb language sql stable security invoker set search_path='' as $f$ select marathon.wa_status() $f$;
revoke all on function marathon.wa_status(),public.marathon_whatsapp_status() from public,anon;
grant execute on function marathon.wa_status(),public.marathon_whatsapp_status() to authenticated;

create function marathon.wa_configure(p_data jsonb,p_version bigint,p_request_id uuid)returns jsonb language plpgsql security definer set search_path='' as $f$
declare c marathon.whatsapp_config;s text;sid uuid;begin
 if auth.uid() is null or not marathon.is_admin() then raise sqlstate '42501' using message='Solo Administración puede vincular WhatsApp.';end if;
 if p_request_id is null or p_data is null or jsonb_typeof(p_data)<>'object' then raise sqlstate '22023' using message='Configuración inválida.';end if;
 select * into c from marathon.whatsapp_config where singleton for update;
 if c.last_request_id=p_request_id then return marathon.wa_status();end if;
 if c.version is distinct from p_version then raise sqlstate '40001' using message='La configuración cambió. Volvé a cargarla antes de guardar.';end if;
 if c.connected then raise sqlstate '22023' using message='El número está vinculado. Conservá esta configuración mientras esté conectado.';end if;
 if coalesce(p_data->>'app_id','') !~ '^[0-9]{5,30}$' or coalesce(p_data->>'config_id','') !~ '^[0-9]{5,30}$' then raise sqlstate '22023' using message='Revisá el ID de aplicación y el ID de configuración de Meta.';end if;
 s=coalesce(p_data->>'app_secret','');sid=c.app_secret_id;
 if s<>'' then
  if s !~ '^[0-9a-fA-F]{32}$' then raise sqlstate '22023' using message='La clave de aplicación debe ser la clave secreta de Meta de 32 caracteres.';end if;
  sid=vault.create_secret(s,null,'Marathon WhatsApp Meta app secret');
 elsif sid is null or c.app_id<>p_data->>'app_id' then raise sqlstate '22023' using message='Ingresá la clave secreta de esta aplicación de Meta.';
 end if;
 update marathon.whatsapp_config set app_id=p_data->>'app_id',config_id=p_data->>'config_id',app_secret_id=sid,
 coexistence_enabled=coalesce((p_data->>'coexistence_enabled')::boolean,false),
 webhook_verified_at=case when c.app_id=p_data->>'app_id' and s='' then c.webhook_verified_at else null end,
 version=version+1,last_request_id=p_request_id,updated_at=statement_timestamp() where singleton;
 return marathon.wa_status();
end $f$;
create function public.marathon_whatsapp_configure(p_data jsonb,p_version bigint,p_request_id uuid)returns jsonb language sql security invoker set search_path='' as $f$ select marathon.wa_configure(p_data,p_version,p_request_id) $f$;
revoke all on function marathon.wa_configure(jsonb,bigint,uuid),public.marathon_whatsapp_configure(jsonb,bigint,uuid) from public,anon;
grant execute on function marathon.wa_configure(jsonb,bigint,uuid),public.marathon_whatsapp_configure(jsonb,bigint,uuid) to authenticated;

create function marathon.wa_begin()returns jsonb language plpgsql security definer set search_path='' as $f$
declare s jsonb;aid uuid;begin
 s=marathon.wa_status();if not(s->>'ready')::boolean then raise sqlstate '22023' using message='Completá la preparación de Meta antes de vincular el número.';end if;
 if (select count(*) from marathon.whatsapp_attempts where user_id=auth.uid() and expires_at>statement_timestamp() and status in('pending','processing','choose_phone'))>=8 then raise sqlstate '22023' using message='Hay varios intentos abiertos. Esperá unos minutos antes de volver a iniciar.';end if;
 insert into marathon.whatsapp_attempts(user_id,config_version)values(auth.uid(),(s->>'version')::bigint)returning id into aid;
 return jsonb_build_object('attempt_id',aid);
end $f$;
create function public.marathon_whatsapp_begin()returns jsonb language sql security invoker set search_path='' as $f$ select marathon.wa_begin() $f$;
revoke all on function marathon.wa_begin(),public.marathon_whatsapp_begin() from public,anon;
grant execute on function marathon.wa_begin(),public.marathon_whatsapp_begin() to authenticated;

-- Solo el servidor puede acceder a credenciales o confirmar una conexión verificada con Meta.
create function marathon.wa_worker(p_action text,p_data jsonb)returns jsonb language plpgsql security definer set search_path='' as $f$
declare c marathon.whatsapp_config;a marathon.whatsapp_attempts;sid uuid;phone jsonb;begin
 select * into c from marathon.whatsapp_config where singleton;
 if p_action='config' then
  return jsonb_build_object('app_id',c.app_id,'graph_version',c.graph_version,'verify_token',c.verify_token,'webhook_verified',c.webhook_verified_at is not null,
   'app_secret',(select decrypted_secret from vault.decrypted_secrets where id=c.app_secret_id),'waba_id',c.waba_id,'connected',c.connected);
 elsif p_action='webhook_verified' then
  update marathon.whatsapp_config set webhook_verified_at=statement_timestamp() where singleton;return '{}'::jsonb;
 elsif p_action='event' then
  if p_data->'payload'->>'object'<>'whatsapp_business_account' then raise sqlstate '22023' using message='Evento inválido.';end if;
  insert into marathon.whatsapp_events(event_hash,payload)values(p_data->>'event_hash',p_data->'payload')on conflict do nothing;
  update marathon.whatsapp_config set last_event_at=statement_timestamp() where singleton;
  if c.waba_id is not null and exists(select 1 from jsonb_array_elements(p_data->'payload'->'entry')e cross join lateral jsonb_array_elements(e->'changes')x where e->>'id'=c.waba_id and x->>'field'='account_update' and x->'value'->>'event' in('PARTNER_REMOVED','ACCOUNT_OFFBOARDED')) then
   update marathon.whatsapp_config set connected=false where singleton;
  end if;
  return '{}'::jsonb;
 end if;
 select * into a from marathon.whatsapp_attempts where id=(p_data->>'attempt_id')::uuid and user_id=(p_data->>'user_id')::uuid for update;
 if a.id is null or a.expires_at<statement_timestamp() then raise sqlstate '22023' using message='El intento de vinculación venció. Volvé a iniciarlo.';end if;
 if c.version<>a.config_version then raise sqlstate '40001' using message='Cambió la configuración. Volvé a iniciar la vinculación.';end if;
 if p_action='claim' then
  if a.status='pending' then update marathon.whatsapp_attempts set status='processing' where id=a.id;return jsonb_build_object('claimed',true);end if;
  return jsonb_build_object('claimed',false,'status',a.status,'phones',a.phones);
 elsif p_action='stage' then
  if a.status<>'processing' then raise sqlstate '22023' using message='Intento no disponible.';end if;
  sid=vault.create_secret(p_data->>'token',null,'Marathon WhatsApp business token');
  update marathon.whatsapp_attempts set token_id=sid,waba_id=p_data->>'waba_id',phones=p_data->'phones',status='choose_phone' where id=a.id;
  return jsonb_build_object('status','choose_phone','phones',p_data->'phones');
 elsif p_action='credentials' then
  if a.status<>'choose_phone' then raise sqlstate '22023' using message='Volvé a iniciar la vinculación.';end if;
  select x into phone from jsonb_array_elements(a.phones)x where x->>'id'=p_data->>'phone_id';
  if phone is null then raise sqlstate '22023' using message='Seleccioná uno de los números autorizados.';end if;
  return jsonb_build_object('token',(select decrypted_secret from vault.decrypted_secrets where id=a.token_id),'waba_id',a.waba_id,'phone',phone);
 elsif p_action='complete' then
  if a.status='linked' then return jsonb_build_object('status','linked');end if;
  if a.status<>'choose_phone' then raise sqlstate '22023' using message='Intento no disponible.';end if;
  select x into phone from jsonb_array_elements(a.phones)x where x->>'id'=p_data->>'phone_id';
  if phone is null then raise sqlstate '22023' using message='Número inválido.';end if;
  update marathon.whatsapp_config set connected=true,phone_id=phone->>'id',waba_id=a.waba_id,phone_display=phone->>'display_phone_number',phone_name=phone->>'verified_name',access_token_id=a.token_id,linked_at=statement_timestamp() where singleton;
  update marathon.whatsapp_attempts set status='linked' where id=a.id;return jsonb_build_object('status','linked');
 elsif p_action='fail' then
  if a.status='processing' then update marathon.whatsapp_attempts set status='failed' where id=a.id;end if;return '{}'::jsonb;
 end if;
 raise sqlstate '22023' using message='Acción no disponible.';
end $f$;
create function public.marathon_wa_worker(p_action text,p_data jsonb default '{}'::jsonb)returns jsonb language sql security invoker set search_path='' as $f$ select marathon.wa_worker(p_action,p_data) $f$;
revoke all on function marathon.wa_worker(text,jsonb),public.marathon_wa_worker(text,jsonb) from public,anon,authenticated;
grant execute on function marathon.wa_worker(text,jsonb),public.marathon_wa_worker(text,jsonb) to service_role;
grant usage on schema marathon to service_role;
