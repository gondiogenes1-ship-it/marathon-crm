import {createAgendaPatientEditor} from './agenda-patient-editor.js?v=20261029-caja-pacientes';

const labels={SALDO_INGRESO:'A favor del paciente',OTRO_INGRESO:'Otro ingreso',PAGO_PROFESIONAL:'Pago a profesional',SALDO_DEVOLUCION:'Devolución de saldo',REINTEGRO_SESION:'Reintegrar sesión',REINTEGRO_CUOTA:'Reintegrar cuota a saldo',GASTO_GENERAL:'Gasto general',OTRO_EGRESO:'Otro'};
const income=['SALDO_INGRESO','OTRO_INGRESO'],expense=['PAGO_PROFESIONAL','SALDO_DEVOLUCION','REINTEGRO_SESION','REINTEGRO_CUOTA','GASTO_GENERAL','OTRO_EGRESO'];
const personal=kind=>['SALDO_INGRESO','SALDO_DEVOLUCION','REINTEGRO_SESION','REINTEGRO_CUOTA'].includes(kind);
const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n));
const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const debtLabel=d=>({sesion:'Sesión presente',cuota:'Cuota mensual',bono:'Bono inicial'}[d.tipo]||d.tipo)+' · '+d.fecha+(d.hora?' · '+String(d.hora).slice(0,5):'');
const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
const button=(label,fn,cls='s')=>{const b=el('button',label,cls);b.type='button';b.addEventListener('click',fn);return b;};
function field(parent,key,label,type='text',value='',required=false){const wrap=el('label',label),n=el(type==='select'?'select':type==='textarea'?'textarea':'input');if(!['select','textarea'].includes(type))n.type=type;n.id='saldo-'+key;n.name=key;n.value=value;n.required=required;wrap.htmlFor=n.id;wrap.append(n);parent.append(wrap);return n;}
function choices(n,rows,blank){n.replaceChildren();for(const r of [...(blank!==undefined?[{id:'',label:blank}]:[]),...rows]){const o=el('option',r.label);o.value=r.id;n.append(o);}}
function card(parent,label,value,cls=''){const a=el('article',undefined,'saldo-metric '+cls);a.append(el('span',label),el('strong',money(value)));parent.append(a);}

export function historyMediumDetail(row){
 const label=value=>({EFECTIVO:'Efectivo',TRANSFERENCIA:'Transferencia'}[value]||value||'Medio no registrado');
 if(row.medio)return label(row.medio);
 if(row.medio_origen)return 'Pago original: '+label(row.medio_origen)+' · Sin entrada ni salida de dinero';
 return ['INGRESO','DEVOLUCION'].includes(row.tipo)?'Medio no registrado':'Sin entrada ni salida de dinero';
}

export function createSaldoUI(ctx){
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 let view=null,generation=0,loading=false;
 const editor=createAgendaPatientEditor({...ctx,prefix:'saldo-patient-edit',onSaved:async dni=>{if(view?.form.isConnected)await pick(dni);}});
 const locked=()=>ctx.isBusy()||ctx.isPending()||editor.isPending();
 const current=(v=view)=>!!v&&view===v&&v.form.isConnected;
 function sync(){
  editor.sync();if(!current())return;
  const disabled=locked()||loading;
  view.form.querySelectorAll('button,input,select,textarea').forEach(n=>n.disabled=disabled);
  view.previewButton.disabled=disabled;
  view.save.disabled=disabled||!view.proposal;
  view.edit.disabled=disabled||!view.dni;
 }
 function invalidate(){if(!current())return;generation++;view.proposal=null;view.review.replaceChildren(el('p','Revisá el movimiento para ver el resultado antes de confirmar.'));view.save.disabled=true;view.status.textContent='';}
 function fillSessions(){const v=view;choices(v.session,(v.account?.deudas||[]).filter(d=>d.tipo===(v.kind.value==='REINTEGRO_CUOTA'?'cuota':'sesion')&&Number(d.pagado)>0).map(d=>({id:d.id,label:debtLabel(d)+' · Pagado '+money(d.pagado)})),v.kind.value==='REINTEGRO_CUOTA'?'Elegir cuota pagada':'Elegir sesión presente');v.session.value=v.turno||'';}
 async function pick(dni){
  const v=view,token=++generation;v.dni='';v.account=null;v.proposal=null;v.selection.textContent='Consultando cuenta…';v.results.replaceChildren();loading=true;sync();
  try{const account=await rpc('marathon_saldo_consultar',{p_dni:dni});if(!current(v)||token!==generation)return;
   v.dni=dni;v.account=account;v.query.value='';v.selection.textContent=account.name+' · DNI '+dni;v.balance.replaceChildren();card(v.balance,'Deuda clínica',account.deuda);card(v.balance,'Saldo a favor',account.saldo,'saldo-credit');fillSessions();
   v.amount.value=Number(account.deuda)>0?account.deuda:'';invalidate();
  }catch(e){if(current(v))v.status.textContent=e.message;}
  finally{if(current(v)){loading=false;sync();}}
 }
 function kindChanged(){const v=view;invalidate();const kind=v.kind.value,isPersonal=personal(kind),internal=['REINTEGRO_SESION','REINTEGRO_CUOTA'].includes(kind);
  v.patient.hidden=!isPersonal;v.assignment.hidden=kind!=='PAGO_PROFESIONAL';v.assignment.querySelectorAll('select').forEach(n=>n.required=kind==='PAGO_PROFESIONAL');
  v.session.parentElement.hidden=!internal;v.session.required=internal;v.session.parentElement.firstChild.textContent=kind==='REINTEGRO_CUOTA'?'Cuota a reintegrar al saldo':'Sesión a reintegrar';
  for(const n of [v.amount,v.medium,v.site,v.date]){n.parentElement.hidden=internal;n.required=!internal;}
  v.extra.hidden=internal;v.associated.parentElement.hidden=kind==='PAGO_PROFESIONAL';v.reason.required=kind!=='SALDO_INGRESO';v.reason.minLength=v.reason.required?3:0;
  v.note.textContent=kind==='REINTEGRO_CUOTA'?'Lo pagado se acredita como saldo a favor del paciente y la cuota queda sin deuda. Este reintegro NO devuelve dinero de Caja. Para devolver dinero, registrá después una Devolución de saldo.':internal?'El pago vuelve al saldo a favor. La sesión conserva el Presente y queda sin deuda. Para devolver dinero, registrá después una devolución de saldo.':kind==='SALDO_INGRESO'?'Se aplicará primero a las deudas más antiguas del paciente. El sobrante quedará a favor.':kind==='SALDO_DEVOLUCION'?'Se registra un egreso de Caja. El importe no puede superar el saldo disponible.':kind==='PAGO_PROFESIONAL'?'Registrá el pago y asociá su profesional y terapia.':'Este movimiento se registra en Caja y no modifica el saldo de pacientes.';
  v.previewButton.textContent='Revisar '+(internal?'reintegro':'movimiento');v.save.textContent=internal?'Confirmar reintegro al saldo':income.includes(kind)?'Confirmar ingreso':'Confirmar egreso';v.save.dataset.variant=income.includes(kind)?'collect':'destructive';
  if(kind==='SALDO_DEVOLUCION'&&v.account)v.amount.value=Number(v.account.saldo)>0?v.account.saldo:'';
  else if(kind==='SALDO_INGRESO'&&v.account)v.amount.value=Number(v.account.deuda)>0?v.account.deuda:'';
  else if(!isPersonal)v.amount.value='';
  fillSessions();sync();
 }
 function data(){const v=view,k=v.kind.value;const d={subtipo:k,observaciones:v.reason.value.trim()};
  if(personal(k)){if(!v.dni)throw Error('Buscá y elegí un paciente.');d.dni=v.dni;}
  if(k==='REINTEGRO_CUOTA')d.cuota_id=v.session.value;
  else if(k==='REINTEGRO_SESION')d.turno_id=v.session.value;
  else{if(!/^\d{1,10}(\.\d{1,2})?$/.test(v.amount.value)||Number(v.amount.value)<=0)throw Error('Indicá un importe positivo, con hasta dos decimales.');Object.assign(d,{monto:v.amount.value,medio:v.medium.value,sede:v.site.value,fecha:v.date.value});
   if(v.category.value.trim())d.categoria=v.category.value.trim();
   if(k==='PAGO_PROFESIONAL'){d.profesional=v.prof.value;d.terapia=v.therapy.value;}
   else if(v.associated.value.startsWith('P:'))d.profesional=v.associated.value.slice(2);
   else if(v.associated.value.startsWith('S:'))d.secretaria=v.associated.value.slice(2);
  }return d;
 }
 async function preview(){const v=view;if(locked()||loading||!v.form.reportValidity())return;
  let payload;try{payload=data();}catch(e){v.status.textContent=e.message;return;}
  const token=++generation;v.proposal=null;loading=true;v.status.textContent='Calculando el resultado…';sync();
  try{const p=await rpc('marathon_saldo_prever',{p_data:payload});if(!current(v)||token!==generation)return;
   if(personal(payload.subtipo)){v.account=p.cuenta;v.balance.replaceChildren();card(v.balance,'Deuda clínica',p.cuenta.deuda);card(v.balance,'Saldo a favor',p.cuenta.saldo,'saldo-credit');}v.proposal={payload,result:p};v.review.replaceChildren(el('h3','Así quedará el movimiento'));const metrics=el('div',undefined,'saldo-metrics');v.review.append(metrics);
   if(personal(payload.subtipo)){card(metrics,'Deuda actual',p.cuenta.deuda);if(payload.subtipo==='SALDO_INGRESO')card(metrics,'Se aplicará a deudas',p.aplicar);card(metrics,'Quedará a favor',p.saldo_resultante,'saldo-credit');}
   else card(metrics,'Importe del '+(income.includes(payload.subtipo)?'ingreso':'egreso'),p.monto);
   for(const d of p.detalle||[]){const row=el('div',undefined,'saldo-application');row.append(el('span',d.fecha?debtLabel(d):d.tipo==='cuota'?'Cuota seleccionada · Crédito para el paciente':'Sesión seleccionada'),el('strong',money(d.aplicar??d.pagado_liberado)));const origin=p.cuenta?.deudas?.find(x=>x.tipo===d.tipo&&x.id===d.id);if(origin)row.append(el('small',[v.options.therapies.find(x=>x.id===origin.terapia)?.label,v.options.professionals.find(x=>x.id===origin.profesional)?.label,origin.sede].filter(Boolean).join(' · ')));if(d.deuda_bonificada!==undefined)row.append(el('small','Pendiente que se bonifica: '+money(d.deuda_bonificada)));v.review.append(row);}
   v.review.append(el('p',['REINTEGRO_SESION','REINTEGRO_CUOTA'].includes(payload.subtipo)?'El importe reintegrado queda como saldo a favor del paciente. No se devuelve dinero de Caja. Para devolver dinero, registrá una Devolución de saldo.':'Se registra un único movimiento de Caja.','subtitle'));v.status.textContent='Revisá el detalle y confirmá cuando esté correcto.';
  }catch(e){if(current(v)){v.proposal=null;v.status.textContent=e.message;}}
  finally{if(current(v)){loading=false;sync();}}
 }
 async function open({dni='',subtipo='SALDO_INGRESO',turno_id='',cuota_id='',sede=''}={}){
  reset();const [options,daily]=await Promise.all([rpc('marathon_agenda_options'),rpc('marathon_daily_options')]);
  const panel=ctx.modal('Registrar movimiento'),form=el('form',undefined,'saldo-form');form.id='saldo-form';panel.append(form);
  const v={form,options,dni:'',turno:cuota_id||turno_id,proposal:null,account:null};view=v;
  const top=el('div',undefined,'saldo-form-grid');form.append(top);
  v.type=field(top,'type','Tipo','select');choices(v.type,[{id:'INGRESO',label:'Ingreso'},{id:'EGRESO',label:'Egreso'}]);v.type.value=income.includes(subtipo)?'INGRESO':'EGRESO';
  v.kind=field(top,'kind','Subtipo','select');
  const setKinds=()=>choices(v.kind,(v.type.value==='INGRESO'?income:expense).map(id=>({id,label:labels[id]})));setKinds();v.kind.value=subtipo;
  v.note=el('p',undefined,'saldo-explanation');form.append(v.note);
  v.patient=el('section',undefined,'saldo-patient');v.patient.setAttribute('aria-label','Paciente del movimiento');form.append(v.patient);
  v.query=field(v.patient,'query','Buscar paciente por nombre, apellido o DNI','search');v.query.maxLength=100;
  const searchActions=el('div',undefined,'form-actions');v.patient.append(searchActions);
  const search=button('Buscar paciente',async()=>{if(locked()||loading)return;const term=v.query.value.trim();if(!term){v.status.textContent='Escribí un nombre, apellido o DNI.';return;}const token=++generation;loading=true;sync();
   try{const r=await rpc('marathon_patient_search',{p_query:term,p_after:null,p_limit:10});if(!current(v)||token!==generation)return;v.results.replaceChildren();for(const p of r.rows)v.results.append(button([p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni,()=>pick(p.dni)));v.status.textContent=r.rows.length?'Elegí al paciente de los resultados.':'Sin coincidencias. Podés crear su ficha.';}
   catch(e){if(current(v))v.status.textContent=e.message;}finally{if(current(v)){loading=false;sync();}}});
  v.edit=button('Editar ficha',()=>ctx.work(()=>editor.open(v.dni)));searchActions.append(search,button('Crear paciente',()=>ctx.work(()=>editor.open())),v.edit);
  v.results=el('div',undefined,'saldo-patient-results');v.selection=el('p','Sin paciente seleccionado');v.selection.setAttribute('role','status');v.balance=el('div',undefined,'saldo-metrics');v.patient.append(v.results,v.selection,v.balance);
  v.query.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();search.click();}});
  v.query.addEventListener('input',()=>{v.dni='';v.account=null;v.selection.textContent='Elegí un paciente de los resultados.';v.balance.replaceChildren();v.results.replaceChildren();fillSessions();invalidate();});
  v.session=field(form,'session','Sesión a reintegrar','select');
  const fields=el('div',undefined,'saldo-form-grid');form.append(fields);
  v.amount=field(fields,'amount','Importe (ARS)','number','',true);v.amount.min='0.01';v.amount.step='0.01';v.amount.max='9999999999.99';
  v.medium=field(fields,'medium','Medio','select');choices(v.medium,[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}]);
  v.site=field(fields,'site','Sede','select');choices(v.site,options.sedes,'Elegir sede');v.site.value=sede;
  v.date=field(fields,'date','Fecha','date',today(),true);v.date.min='2000-01-01';v.date.max='2100-12-31';
  v.assignment=el('div',undefined,'saldo-form-grid');form.append(v.assignment);v.prof=field(v.assignment,'professional','Profesional','select');choices(v.prof,options.professionals,'Elegir profesional');
  v.therapy=field(v.assignment,'therapy','Terapia','select');const fillTherapies=()=>{const p=options.professionals.find(p=>p.id===v.prof.value);choices(v.therapy,options.therapies.filter(t=>p?.therapy_ids?.includes(t.id)),'Elegir terapia');};v.prof.addEventListener('change',fillTherapies);fillTherapies();
  v.extra=el('div',undefined,'saldo-form-grid');form.append(v.extra);v.category=field(v.extra,'category','Categoría (opcional)');v.category.maxLength=100;
  v.associated=field(v.extra,'associated','Profesional o secretaría asociada','select');choices(v.associated,[...options.professionals.map(p=>({id:'P:'+p.id,label:'Profesional · '+p.label})),...(daily.secretaries||[]).filter(s=>s.estado==='ACTIVO').map(s=>({id:'S:'+s.id,label:'Secretaría · '+s.label}))],'Sin asociar');
  v.reason=field(form,'reason','Concepto / observaciones','textarea');v.reason.maxLength=1000;
  v.previewButton=button('Revisar movimiento',preview);form.append(v.previewButton);v.review=el('section',undefined,'saldo-review');v.review.setAttribute('aria-live','polite');form.append(v.review);
  v.status=el('p');v.status.setAttribute('role','status');v.status.setAttribute('aria-live','polite');form.append(v.status);
  v.save=el('button','Confirmar ingreso','b');v.save.type='submit';v.save.dataset.saldoConfirm='true';v.save.disabled=true;form.append(v.save);
  v.type.addEventListener('change',()=>{setKinds();kindChanged();});v.kind.addEventListener('change',kindChanged);
  form.addEventListener('input',invalidate);form.addEventListener('change',e=>{if(e.target!==v.type&&e.target!==v.kind)invalidate();});
  form.addEventListener('submit',e=>{e.preventDefault();if(locked()||loading||!v.form.reportValidity())return;if(!v.proposal){v.status.textContent='Primero revisá el movimiento.';return;}
   const {payload,result}=v.proposal;if(JSON.stringify(payload)!==JSON.stringify(data())){invalidate();return;}
   ctx.execute('marathon_saldo_command',{p_request_id:crypto.randomUUID(),p_data:{...payload,huella:result.huella,version:result.version}},ctx.refresh,{onDefiniteError:error=>{if(error.code==='PT409'){invalidate();v.status.textContent='La cuenta cambió. Volvé a revisar el movimiento antes de confirmar.';}}});
  });
  kindChanged();if(dni)await pick(dni);if(subtipo==='SALDO_DEVOLUCION'&&v.account)v.amount.value=Number(v.account.saldo)>0?v.account.saldo:'';sync();
 }
 async function history(dni,after=null){reset();const result=await rpc('marathon_saldo_historial',{p_dni:dni,p_after:after,p_limit:25}),panel=ctx.modal('Saldo del paciente · Historial');panel.classList.add('saldo-history');
  for(const r of result.rows){const row=el('article',undefined,'saldo-history-row');row.append(el('strong',r.efecto_caja+' · '+money(r.importe)),el('p',({INGRESO:'Ingreso a favor',DEVOLUCION:'Devolución / anulación',APLICACION:'Aplicación a deuda',REVERSO_APLICACION:'Saldo liberado'}[r.tipo]||r.tipo)+' · '+(r.fecha_caja||new Date(r.created_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'}))),el('small',[r.turno_id?'Sesión presente':r.cuota_id?'Cuota mensual':r.bono_id?'Bono inicial':'',r.actor,historyMediumDetail(r),r.sede].filter(Boolean).join(' · ')));panel.append(row);}
  if(!result.rows.length)panel.append(el('p','No hay movimientos de saldo registrados.'));panel.append(button('Registrar movimiento',()=>ctx.work(()=>open({dni}))));if(after)panel.append(button('Volver al inicio',()=>ctx.work(()=>history(dni))));if(result.next)panel.append(button('Movimientos anteriores',()=>ctx.work(()=>history(dni,result.next))));
 }
 async function reverse(id){reset();const p=await rpc('marathon_saldo_anular_prever',{p_id:id}),panel=ctx.modal('Anular ingreso de saldo');if(p.bloqueado){panel.append(el('p',p.motivo_bloqueo));return;}
  panel.append(el('p','Se devolverán '+money(p.importe)+' mediante un único contrasiento en '+p.medio+'. Las aplicaciones siguientes se liberarán y sus deudas volverán a quedar pendientes.'));
  for(const a of p.aplicaciones)panel.append(el('p',(a.turno_id?'Sesión':a.cuota_id?'Cuota':'Bono')+' · '+money(a.liberar)));
  const form=el('form');panel.append(form);const reason=field(form,'reverse-reason','Motivo obligatorio','textarea','',true);reason.minLength=3;reason.maxLength=1000;const date=field(form,'reverse-date','Fecha','date',today(),true),save=el('button','Confirmar anulación','b');save.type='submit';save.dataset.variant='destructive';form.append(save);
  form.addEventListener('submit',e=>{e.preventDefault();if(locked()||!form.reportValidity())return;ctx.execute('marathon_saldo_anular',{p_request_id:crypto.randomUUID(),p_data:{id:p.id,version:p.version,fecha:date.value,motivo:reason.value.trim()}},ctx.refresh);});
 }
 function reset(){generation++;loading=false;view=null;editor.reset();}
 return {open,history,reverse,sync,reset,isPending:()=>editor.isPending()};
}
