"""Respaldo lógico de la base; contraseña solo en memoria y entrada oculta.
No migra, activa ni modifica registros. No publicar este archivo ni respaldos.
"""
import hashlib,json,os,subprocess,threading,tkinter as tk
from tkinter import messagebox,ttk
from datetime import datetime,timezone,timedelta
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PG=Path(r'C:\Program Files\PostgreSQL\18\bin')
HOST='aws-0-us-east-1.pooler.supabase.com'
USER='postgres.zcjlgaociqmzjqlyacoi'
BACKUPS=ROOT.parent/'Respaldos'
STATUS=ROOT/'Documentacion/Caja_saldo_a_favor/RESPALDO_EN_CURSO.json'

def state(value):
 STATUS.parent.mkdir(parents=True,exist_ok=True)
 STATUS.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding='utf-8')

window=tk.Tk();window.title('Marathon · Crear respaldo de Supabase')
window.geometry('630x355');window.resizable(False,False)
window.attributes('-topmost',True)
frame=ttk.Frame(window,padding=22);frame.pack(fill='both',expand=True)
ttk.Label(frame,text='Respaldo de Marathon',font=('Segoe UI',17,'bold')).pack(anchor='w')
ttk.Label(frame,text='Proyecto: marathoncrm26 · Supabase',font=('Segoe UI',11)).pack(anchor='w',pady=(8,4))
ttk.Label(frame,text='Ingresá la contraseña actual de la base de datos.\nEs distinta de la contraseña para ingresar a Marathon.',font=('Segoe UI',11)).pack(anchor='w')
secret=tk.StringVar();entry=ttk.Entry(frame,textvariable=secret,show='●',width=58,font=('Segoe UI',12));entry.pack(anchor='w',pady=(14,5));entry.focus_set()
ttk.Label(frame,text='Se usa solo en esta PC para leer y respaldar la base.\nNo se guarda en archivos ni se envía por el chat.',font=('Segoe UI',10)).pack(anchor='w')
status=tk.StringVar(value='La aplicación y sus movimientos siguen funcionando.');ttk.Label(frame,textvariable=status,wraplength=570,font=('Segoe UI',10)).pack(anchor='w',pady=(12,8))
busy=False

def complete(result):
 global busy
 busy=False;entry.configure(state='normal');submit.configure(state='normal')
 if result['status']=='backup_created':
  status.set('Respaldo creado. Falta verificar su restauración antes de activar el cambio.')
  submit.configure(state='disabled');messagebox.showinfo('Marathon','Respaldo creado correctamente.\nPodés avisar en el chat para continuar con la verificación.\n\n'+result['directory'],parent=window)
 else:
  status.set('No se completó el respaldo. Revisá la contraseña o avisá en el chat.')
  messagebox.showerror('Marathon','No se completó el respaldo. No se cambió ningún movimiento.\n\n'+result['error'][:900],parent=window)

def backup(password):
 # La contraseña no forma parte de los argumentos, registros ni manifiestos.
 env={**os.environ,'PGPASSWORD':password,'PGSSLMODE':'require','PGCONNECT_TIMEOUT':'15','PGAPPNAME':'Marathon_backup'}
 password=None
 folder=BACKUPS/('Supabase_completo_'+datetime.now(timezone(timedelta(hours=-3))).strftime('%Y%m%d_%H%M%S'))
 result={'status':'error','directory':str(folder)}
 try:
  folder.mkdir(parents=True,exist_ok=False)
  partial=folder/'database.partial.dump'
  cmd=[str(PG/'pg_dump.exe'),'-w','-h',HOST,'-p','5432','-U',USER,'-d','postgres','--format=custom','--lock-wait-timeout=10000','--file',str(partial)]
  run=subprocess.run(cmd,env=env,capture_output=True,encoding='utf-8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW)
  (folder/'backup.log').write_text(run.stderr,encoding='utf-8')
  if run.returncode:raise RuntimeError(run.stderr)
  listing=subprocess.run([str(PG/'pg_restore.exe'),'--list',str(partial)],capture_output=True,encoding='utf-8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW)
  if listing.returncode:raise RuntimeError(listing.stderr)
  for table in ['movimientos','pacientes','turnos','anticipos','anticipo_eventos','bonos_serie','agenda_cuotas']:
   if not any('TABLE DATA marathon '+table+' 'in line for line in listing.stdout.splitlines()):raise RuntimeError('No se encontró la tabla esperada en el archivo: '+table)
  final=folder/'database.dump';partial.rename(final)
  (folder/'contenido.txt').write_text(listing.stdout,encoding='utf-8')
  result={'status':'backup_created','directory':str(folder),'file':str(final),'bytes':final.stat().st_size,'sha256':hashlib.file_digest(final.open('rb'),'sha256').hexdigest(),'archive_verified':True,'restore_verified':False,'host':HOST,'database':'postgres','scope':'Database completo, sin filtros de esquema o tabla; no incluye archivos físicos de Storage.','production_writes':0}
  (folder/'manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
 except Exception as error:
  result['error']=str(error)
 finally:
  env.pop('PGPASSWORD',None)
  state(result);window.after(0,lambda:complete(result))

def start():
 global busy
 if busy:return
 value=secret.get()
 if not value:status.set('Ingresá la contraseña de la base para crear el respaldo.');return
 secret.set('');entry.configure(state='disabled');submit.configure(state='disabled');busy=True
 status.set('Creando el respaldo completo. Esta ventana no modifica datos de la base.')
 state({'status':'running','host':HOST,'production_writes':0})
 threading.Thread(target=backup,args=(value,),daemon=False).start()

submit=ttk.Button(frame,text='Crear respaldo',command=start);submit.pack(anchor='w')
entry.bind('<Return>',lambda event:start())
def close():
 if busy:messagebox.showinfo('Marathon','Esperá a que termine el respaldo antes de cerrar.',parent=window)
 else:window.destroy()
window.protocol('WM_DELETE_WINDOW',close)
state({'status':'waiting_for_password','host':HOST,'production_writes':0})
window.mainloop()
