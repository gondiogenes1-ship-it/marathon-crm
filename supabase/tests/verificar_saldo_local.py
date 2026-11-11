"""Verificación de Fase 2. Solo localhost y las bases sintéticas de esta mejora."""
import json,os,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PG=Path(r'C:\Program Files\PostgreSQL\18\bin\psql.exe')
DB='marathon_saldo_restauracion_20261104'
args=[str(PG),'-w','-h','127.0.0.1','-p','55439','-U','postgres','-d',DB,'-qAt','-v','ON_ERROR_STOP=1']
tests=['saldo_unificado_smoke.sql','saldo_eventos_smoke.sql','saldo_importacion_smoke.sql','saldo_orden_smoke.sql','saldo_cuota_smoke.sql']
results=[]
for test in tests:
 r=subprocess.run(args+['-f',str(ROOT/'supabase/tests'/test)],capture_output=True,text=True,encoding='utf-8')
 assert r.returncode==0,r.stderr
 results.append({'prueba':test,'resultado':'PASS','evidencia':[s.strip()for s in r.stderr.splitlines()if 'OK:'in s]})
audit="""select
 (select count(*)from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='marathon'and left(relname,6)='saldo_'and relkind='r'and not relrowsecurity)+
 (select count(*)from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'and left(proname,15)='marathon_saldo_'and has_function_privilege('anon',p.oid,'EXECUTE'))+
 (select count(*)from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='marathon'and left(proname,6)='saldo_'and has_function_privilege('authenticated',p.oid,'EXECUTE'));
 select activo from marathon.saldo_config;
 select count(*)from marathon.pacientes;
"""
r=subprocess.run(args+['-f','-'],input=audit,capture_output=True,text=True,encoding='utf-8');assert r.returncode==0,r.stderr
assert r.stdout.strip().splitlines()==['0','f','0'],r.stdout
results.append({'prueba':'RLS, ACL, circuito apagado y rollback de fixtures','resultado':'PASS'})
r=subprocess.run([sys.executable,str(ROOT/'supabase/tests/saldo_concurrencia.py')],capture_output=True,text=True,encoding='utf-8',env={**os.environ,'PYTHONIOENCODING':'utf-8'})
assert r.returncode==0,r.stderr
results.append({'prueba':'Dos conexiones independientes','resultado':'PASS','evidencia':r.stdout.strip()})
report={'fecha_utc':datetime.now(timezone.utc).isoformat(),'base_local':DB,'datos':'Sintéticos; sin escrituras en producción','resultados':results,'resultado':'PASS'}
path=ROOT/'Documentacion/Caja_saldo_a_favor/Fase_2_aislada/RESULTADO_PRUEBAS.json'
path.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('PASS: 5 suites SQL, auditoría de permisos y concurrencia real. Informe guardado.')
