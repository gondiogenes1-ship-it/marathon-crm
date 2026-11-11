"""Ensayo del corte con el archivo pg_dump real, exclusivamente en localhost.
La contraseña no se lee. Auth/Storage completos permanecen en el archivo;
se ensaya el esquema y todos los datos del CRM con identidades Auth locales.
"""
import hashlib,json,os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PG=Path(r'C:\Program Files\PostgreSQL\18\bin')
STATUS=json.loads((ROOT/'Documentacion/Caja_saldo_a_favor/RESPALDO_EN_CURSO.json').read_text(encoding='utf-8'))
assert STATUS['status']=='backup_created'
ARCHIVE=Path(STATUS['file']);assert hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()==STATUS['sha256']
DB='marathon_saldo_corte_20261105_'+str(os.getpid())
BASE=['-w','-h','127.0.0.1','-p','55439','-U','postgres']
OUT=ROOT/'Documentacion/Caja_saldo_a_favor/Corte_20261105';OUT.mkdir(exist_ok=True)
def run(exe,args,sql=None):
 p=subprocess.run([str(PG/exe),*args],input=sql,capture_output=True,text=True,encoding='utf-8',errors='replace')
 if p.returncode:raise RuntimeError(p.stderr)
 return p.stdout.strip()
def query(sql):return run('psql.exe',BASE+['-d',DB,'-XqAt','-v','ON_ERROR_STOP=1','-f','-'],sql)
def restore(section):
 out=run('pg_restore.exe',BASE+['-d',DB,'--exit-on-error','--no-owner','--no-privileges','--schema=public','--schema=marathon','--section='+section,str(ARCHIVE)])
 (OUT/('restore_'+section+'.log')).write_text(out,encoding='utf-8')
run('psql.exe',BASE+['-d','postgres','-Xq','-v','ON_ERROR_STOP=1','-f','-'],"do $$begin if not exists(select 1 from pg_roles where rolname='service_role')then create role service_role nologin;end if;end$$;")
run('createdb.exe',BASE+[DB])
query("create schema marathon;create schema auth;create schema extensions;create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);create function auth.uid()returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create function auth.role()returns text language sql stable as $$select current_setting('request.jwt.claim.role',true)$$;")
restore('pre-data');restore('data')
query("""do $$declare c record;begin
 for c in select table_schema,table_name,column_name from information_schema.columns where table_schema in('marathon','public')and data_type='uuid'and column_name in('user_id','actor','usuario_id','created_by','updated_by')loop
 execute format('insert into auth.users(id)select distinct %I from %I.%I where %I is not null on conflict do nothing',c.column_name,c.table_schema,c.table_name,c.column_name);
 end loop;end$$;""")
restore('post-data')
snapshot_sql="""select jsonb_build_object('cuentas',(select count(*)from marathon.pacientes),'movimientos',(select count(*)from marathon.movimientos),'tables',coalesce(jsonb_object_agg(name,jsonb_build_object('count',n,'hash',h)),'{}'))from(
 select 'movimientos'name,count(*)n,md5(coalesce(jsonb_agg(to_jsonb(t)-'subtipo'-'terapia_asociada_id'order by id),'[]')::text)h from marathon.movimientos t
 union all select 'turnos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.turnos t
 union all select 'anticipos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.anticipos t
 union all select 'anticipo_eventos',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.anticipo_eventos t
 union all select 'bonos_serie',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.bonos_serie t
 union all select 'agenda_cuotas',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.agenda_cuotas t
 union all select 'agenda_ajustes',count(*),md5(coalesce(jsonb_agg(to_jsonb(t)order by id),'[]')::text)from marathon.agenda_ajustes t)x;"""
(OUT/'snapshot_sql.sql').write_text(snapshot_sql,encoding='utf-8')
before=json.loads(query(snapshot_sql));(OUT/'antes.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
migrations=sorted((ROOT/'supabase/migrations').glob('*caja_saldo*.sql'))
for path in migrations:
 run('psql.exe',BASE+['-d',DB,'-Xq','-v','ON_ERROR_STOP=1','-f',str(path)])
assert json.loads(query(snapshot_sql))==before,'Instalar estructura cambió datos existentes'
plan=json.loads(query('select marathon.saldo_importacion_prever();'))
(OUT/'plan_local.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
assert not plan['bloqueos'],plan['bloqueos']
actor='41dc5b3e-8156-497d-b8ba-a38ecd45a7ad'
sql="begin;set local request.jwt.claim.sub='"+actor+"';select marathon.saldo_importar('saldo_ensayo_corte_20261105','"+plan['huella']+"');commit;"
result=json.loads(query(sql));assert result['conciliado']
assert json.loads(query(snapshot_sql))==before,'La importación cambió registros originales'
balance=json.loads(query("select jsonb_build_object('saldo_total',(select sum(marathon.saldo_disponible(dni))from marathon.pacientes),'fuentes',(select count(*)from marathon.saldo_fuentes),'aplicaciones',(select count(*)from marathon.saldo_aplicaciones),'activo',(select activo from marathon.saldo_config),'saldo_carlos',marathon.saldo_disponible('13328881'),'saldo_pruebas_gonzalo',marathon.saldo_disponible('41574311'));"))
report={'status':'PASS','database':DB,'backup':str(ARCHIVE),'sha256':STATUS['sha256'],'crm_restore_verified':True,'auth_service_simulated_locally':True,'migrations':len(migrations),'unchanged_original_records':True,'reconciliation':True,'balance':balance}
(OUT/'RESTAURACION_Y_ENSAYO.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
manifest=json.loads((ARCHIVE.parent/'manifest.json').read_text(encoding='utf-8'));manifest['restore_verified']=True;manifest['restore_scope']='Todos los datos, tablas, índices, restricciones, funciones y políticas del CRM (marathon/public), con identidades Auth locales; archivo completo Supabase conservado.';manifest['restore_evidence']=str(OUT/'RESTAURACION_Y_ENSAYO.json');(ARCHIVE.parent/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
