"""Dos conexiones reales, únicamente en una base local desechable y sintética."""
import json, os, subprocess, tempfile, uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
PG=Path(r'C:\Program Files\PostgreSQL\18\bin')
BASE=['-w','-h','127.0.0.1','-p','55439','-U','postgres']
db='marathon_saldo_qa_'+uuid.uuid4().hex[:12]
def run(exe,args,**kw):
    return subprocess.run([str(PG/exe),*args],capture_output=True,text=True,encoding='utf-8',**kw)
def query(sql):
    r=run('psql.exe',BASE+['-d',db,'-qAt','-v','ON_ERROR_STOP=1','-f','-'],input=sql);assert r.returncode==0,r.stderr;return r.stdout.strip()
def literal(value):return "'"+value.replace("'","''")+"'"
def async_query(sql):
    return subprocess.Popen([str(PG/'psql.exe'),*BASE,'-d',db,'-qAt','-v','ON_ERROR_STOP=1','-c',sql],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8')
assert run('createdb.exe',BASE+['-T','marathon_saldo_restauracion_20261104',db]).returncode==0
try:
    fixture=(ROOT/'supabase/tests/saldo_fixture.sql').read_text(encoding='utf-8')
    query(fixture.replace('\\set ON_ERROR_STOP on','')+"\nupdate marathon.saldo_config set activo=true;commit;")
    auth="set request.jwt.claim.sub='00000000-0000-4000-8000-000000009901';"
    income={'subtipo':'SALDO_INGRESO','dni':'99001002','monto':'100','medio':'EFECTIVO','sede':'SALDO_QA','fecha':'2026-11-04'}
    def preview(data):return json.loads(query(auth+'select public.marathon_saldo_prever('+literal(json.dumps(data))+');'))
    p=preview(income);income.update(huella=p['huella'],version=p['version'])
    cmd=auth+"select public.marathon_saldo_command('saldo_concurrent_income',"+literal(json.dumps(income))+');'
    a=async_query('begin;'+cmd+'select pg_sleep(0.6);commit;')
    b=async_query(cmd)
    out_a,err_a=a.communicate(timeout=15);out_b,err_b=b.communicate(timeout=15)
    assert a.returncode==b.returncode==0,(err_a,err_b)
    assert query("select count(*)from marathon.movimientos where dni='99001002';")=='1','Reintento concurrente duplicó ingreso'
    withdrawal={'subtipo':'SALDO_DEVOLUCION','dni':'99001002','monto':'80','medio':'EFECTIVO','sede':'SALDO_QA','fecha':'2026-11-04','observaciones':'Prueba simultánea'}
    p=preview(withdrawal);withdrawal.update(huella=p['huella'],version=p['version'])
    payload=literal(json.dumps(withdrawal))
    a=async_query('begin;'+auth+"select public.marathon_saldo_command('saldo_concurrent_out01',"+payload+');select pg_sleep(0.6);commit;')
    b=async_query(auth+"select public.marathon_saldo_command('saldo_concurrent_out02',"+payload+');')
    oa,ea=a.communicate(timeout=15);ob,eb=b.communicate(timeout=15)
    assert sorted([a.returncode,b.returncode])==[0,1],(ea,eb)
    assert 'La cuenta cambió' in ea+eb,(ea,eb)
    assert query("select marathon.saldo_disponible('99001002');") in ['20.00','20'],'Retiro duplicado o saldo negativo'
    assert query("select count(*)from marathon.movimientos where tipo='EGRESO'and dni='99001002';")=='1'
    print('OK: mismo ingreso simultáneo una sola vez; dos retiros simultáneos no exceden saldo; revisión obsoleta rechazada.')
finally:
    # Solo la base creada en esta ejecución, jamás la base de trabajo ni producción.
    assert db.startswith('marathon_saldo_qa_') and len(db)==30
    r=run('dropdb.exe',BASE+[db]);assert r.returncode==0,r.stderr
