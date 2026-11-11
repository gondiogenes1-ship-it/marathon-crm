import {createCashPatientPicker} from './cash-patient-picker.js?v=20261029-0131';
import {DailyUI} from './daily.js?v=20261019-0110';
import {exportCash} from './cash-export.js?v=20261104';
export function createOperations(ctx){
 const $=s=>document.querySelector(s),el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n));
 const days=['domingo','lunes','martes','miércoles','jueves','viernes','sábado'];
 let options={sedes:[],therapies:[],professionals:[]},pending=null,waitPages=[null],wp=0,wn=null,cashPages=[null],cp=0,cn=null,accountPages=[null],ap=0,an=null,accountDni='';
 let wf={state:'PENDIENTE',sede:'',query:''},cf={fecha:'',to:'',sede:'',medium:'',category:'',prof:'',actor:''};
 let cashExportFilters=null,cashExportLabels={};
 const cashPatientPicker=createCashPatientPicker({...ctx,isPending:()=>!!pending});
 const locked=()=>ctx.isBusy()||!!pending||cashPatientPicker.isPending();
 function action(text,fn,cls='s',variant){const b=el('button',text,cls);b.type='button';if(variant)b.dataset.variant=variant;b.addEventListener('click',fn);return b;}
 function input(parent,key,label,value='',type='text',required=false){const box=el('label',label),i=el(type==='textarea'?'textarea':'input');i.name=key;i.id='o-'+key;if(type!=='textarea')i.type=type;i.value=value??'';i.required=required;if(type==='text'||type==='textarea')i.maxLength=1000;box.append(i);parent.append(box);return i;}
 function choices(i,values,blank){i.replaceChildren();for(const r of [...(blank!==undefined?[{id:'',label:blank}]:[]),...values]){const o=el('option',r.label);o.value=r.id;i.append(o);}}
 function select(parent,key,label,values,value='',blank){const box=el('label',label),i=el('select');i.name=key;i.id='o-'+key;choices(i,values,blank);i.value=value;box.append(i);parent.append(box);return i;}
 function show(name){for(const n of ['home','patients','masters','agenda','wait','cash','ortho','catalog','reports','users']){$('#'+n+'-screen').hidden=n!==name;$('#nav-'+n).className=n===name?'b':'';}}
 function sync(){
  cashPatientPicker.sync();
  if($('#cash-export'))$('#cash-export').disabled=locked()||!cashExportFilters;
  for(const [id,disabled] of [['wait-previous',wp===0],['wait-next',!wn],['cash-previous',cp===0],['cash-next',!cn],['account-previous',ap===0],['account-next',!an]])$('#'+id).disabled=locked()||disabled;
  $('#operation-dialog').querySelectorAll('[data-allowed]').forEach(b=>b.disabled=locked()||b.dataset.allowed!=='true');
  if($('#retry-operation'))$('#retry-operation').disabled=ctx.isBusy();
 }
 function modal(title){const panel=$('#operation-body');panel.replaceChildren();$('#operation-error').textContent='';const head=el('div',undefined,'detail-head');head.append(el('h2',title),action('Cerrar',()=>{if(!locked())$('#operation-dialog').close();}));panel.append(head);if(!$('#operation-dialog').open)$('#operation-dialog').showModal();return panel;}
 function submitButton(form,label,variant){const b=el('button',label,'b');b.type='submit';if(variant)b.dataset.variant=variant;form.append(b);return b;}
 async function execute(name,args,after,notice){if(locked())return;pending={name,args,after,notice};await send();}
 async function send(){if(!pending||ctx.isBusy())return;ctx.setBusy(true);const task=pending;try{
  const r=await rpc(task.name,task.args,true);pending=null;$('#operation-dialog').close();try{await task.after?.(r);ctx.message(r.message);}catch{ctx.message('Guardado confirmado. Actualizá la pantalla para ver los cambios.',true);}task.notice?.();
 }catch(e){if(e.uncertain){ctx.message(e.message,true);$('#operation-error').textContent=e.message;if(!$('#retry-operation')){const b=action('Verificar guardado',send);b.id='retry-operation';$('#operation-recovery').append(b);}}else{pending=null;ctx.message(e.message,true);$('#operation-error').textContent=e.message;}}
 finally{if(!pending)$('#retry-operation')?.remove();ctx.setBusy(false);}}
 const command=(name,data,after,extra={},notice)=>execute(name,{p_request_id:crypto.randomUUID(),p_data:data,...extra},after,notice);

 function newAdvance(){
  const panel=modal('Recibir anticipo · Elegir paciente');
  panel.append(el('p','Primero seleccioná al paciente que entrega el anticipo.','subtitle'));
  const form=el('form'),query=input(form,'advance-patient-query','Buscar paciente por nombre, apellido o DNI','','search',true);
  query.maxLength=100;query.autocomplete='off';submitButton(form,'Buscar paciente');panel.append(form);
  const status=el('p'),results=el('div',undefined,'list-items');status.setAttribute('role','status');status.setAttribute('aria-live','polite');results.id='advance-patient-results';panel.append(status,results);
  let generation=0;
  const active=()=>query.isConnected&&$('#operation-dialog').open;
  query.addEventListener('input',()=>{generation++;results.replaceChildren();status.textContent='';});
  form.addEventListener('submit',e=>{e.preventDefault();if(locked())return;ctx.work(async()=>{
   const term=query.value.trim();if(!term){status.textContent='Escribí nombre, apellido o DNI para buscar.';return;}
   const request=++generation;results.replaceChildren();status.textContent='Buscando pacientes…';
   try{
    const data=await rpc('marathon_patient_search',{p_query:term,p_after:null,p_limit:10});
    if(request!==generation||!active())return;
    for(const patient of data.rows){
     const name=[patient.apellido,patient.nombre,patient.segundo_nombre].filter(Boolean).join(' ');
     const pick=action(name+' · DNI '+patient.dni,()=>{if(!active()||request!==generation)return;ctx.work(async()=>{await openAdvance('deposit',patient.dni);});});
     pick.setAttribute('aria-label','Recibir anticipo de '+name+' · DNI '+patient.dni);results.append(pick);
    }
    status.textContent=data.rows.length?(data.next?'Elegí un paciente. Hay más coincidencias: precisá el nombre o el DNI si no lo encontrás.':'Elegí al paciente para continuar con el anticipo.'):'No se encontraron pacientes. Probá otro nombre o DNI.';
   }catch(error){if(request===generation&&active())status.textContent='No se pudo buscar al paciente. '+error.message;}
  });});
 }
 async function openAdvance(kind,id,after=null){
  if(!['deposit','apply','refund','history'].includes(kind))throw Error('Operación de anticipo inválida.');
  const labels={deposit:'Recibir anticipo clínico',apply:'Aplicar anticipos a deuda clínica',refund:'Reintegrar anticipo disponible',history:'Historial del anticipo'};
  const result=['refund','history'].includes(kind)?await rpc('marathon_advance_get',{p_id:id,p_after:after,p_limit:50}):null,a=result?.advance;
  if(kind==='refund'&&Number(a.available)<=0)throw Error('El anticipo no tiene saldo disponible para reintegrar.');
  if(kind==='deposit')options=await rpc('marathon_agenda_options');
  const panel=modal(labels[kind]);panel.append(el('p','DNI '+(a?.dni||id)),el('p','El dinero se registra una sola vez en Caja al recibirlo. Se aplica a sesiones presentes compatibles; los bonos y ortopedia se cobran por separado.','subtitle'));
  if(a)panel.append(el('p',a.sede+' · '+a.terapia+' · '+a.profesional),el('p','Recibido: '+money(a.importe)+' · Disponible: '+money(a.available)));
  if(kind==='history'){
   const body=DailyUI.table(panel,['Registro','Movimiento','Sesión','Importe','Medio','Registró']);
   for(const e of result.rows)DailyUI.row(body,[new Date(e.created_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'}),{DEPOSITO:'Ingreso',APLICACION:'Aplicación a sesión',REVERSO:'Liberación de sesión',DEVOLUCION:'Reintegro'}[e.tipo]||e.tipo,e.turn_date?e.turn_date+' · '+String(e.turn_hour).slice(0,5):'—',money(e.monto),e.medio||'Sin movimiento de caja',e.actor_name],{id:e.id});
   if(after)panel.append(action('Volver al inicio del historial',()=>ctx.work(()=>openAdvance('history',id))));
   if(result.next)panel.append(action('Movimientos anteriores',()=>ctx.work(()=>openAdvance('history',id,result.next))));return;
  }
  const form=el('form');form.id='advance-form';let amount,medium,site,therapy,prof,apply,reason;
  if(kind==='deposit'){
   site=select(form,'advance-site','Sede',options.sedes,'','Elegir sede');site.required=true;
   therapy=select(form,'advance-therapy','Terapia',options.therapies,'','Cualquier terapia');
   prof=select(form,'advance-prof','Profesional',options.professionals,'','Cualquier profesional');
   therapy.addEventListener('change',()=>{const selected=prof.value;choices(prof,options.professionals.filter(p=>!therapy.value||p.therapy_ids.includes(therapy.value)),'Cualquier profesional');prof.value=selected;});
   const label=el('label'),check=el('input');check.type='checkbox';check.name='apply_existing';check.id='o-advance-apply';label.append(check,document.createTextNode('Aplicar también a sesiones presentes con deuda, empezando por las más antiguas'));form.append(label);apply=check;
  }
  if(kind!=='apply'){
   amount=input(form,'advance-amount','Importe',kind==='refund'?a.available:'','number',true);amount.min='0.01';amount.step='0.01';amount.max=String(kind==='refund'?a.available:9999999999.99);
   medium=select(form,'advance-medium','Medio',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],'EFECTIVO');
   reason=input(form,'advance-reason',kind==='refund'?'Motivo del reintegro':'Observaciones','','textarea',kind==='refund');reason.maxLength=1000;if(kind==='refund')reason.minLength=3;
  }else panel.append(el('p','Se usará el saldo disponible para las sesiones presentes compatibles con deuda, desde la más antigua. Podés revisar cada aplicación en el historial del anticipo.'));
  submitButton(form,kind==='deposit'?'Registrar anticipo':kind==='refund'?'Registrar reintegro':'Aplicar anticipos');panel.append(form);
  form.addEventListener('submit',e=>{e.preventDefault();if(locked()||!form.reportValidity())return;
   const data=kind==='refund'?{id:a.id,version:a.version}:{dni:id};
   if(kind!=='apply'){data.monto=Number(amount.value);data.medio=medium.value;data.observaciones=reason.value;}
   if(kind==='deposit')Object.assign(data,{sede:site.value,therapy:therapy.value,prof:prof.value,apply_existing:apply.checked});
   command('marathon_agenda_command',data,async()=>{await ctx.refreshPatient?.();await refreshMoney();},{p_action:'advance_'+kind});
  });
 }


 async function openBonus(kind,id,after=null){
  const result=await rpc('marathon_bonus_get',{p_id:id,p_after:after,p_limit:50}),b=result.bonus;
  const labels={pay:'Cobrar bono inicial',refund:'Reintegrar bono inicial',cancel:'Anular bono inicial',history:'Historial del bono inicial'};if(!labels[kind])throw Error('Operación de bono inválida.');
  if(kind!=='history'){if(b.estado!=='ACTIVO')throw Error('El bono está anulado.');if(kind==='cancel'&&Number(b.paid)!==0)throw Error('Reintegrá lo cobrado antes de anular el bono.');if(kind==='pay'&&Number(b.debt)<=0)throw Error('El bono no tiene saldo pendiente.');if(kind==='refund'&&Number(b.paid)<=0)throw Error('El bono no tiene cobros para reintegrar.');}
  const panel=modal(labels[kind]);panel.append(el('p',b.terapia+' · '+b.sede+' · DNI '+b.dni),el('p','Bono único: '+money(b.importe)+' · Cobrado neto: '+money(b.paid)+' · Saldo: '+money(b.debt)),el('p','Los movimientos del bono no pagan sesiones. Cancelar turnos no anula el bono.','subtitle'));
  if(kind==='history'){
   panel.append(el('p','Estado: '+b.estado+(b.observaciones?' · '+b.observaciones:'')));
   const table=DailyUI.table(panel,['Fecha / hora','Concepto','Medio','Importe','Registrado por','Observaciones']);for(const m of result.rows)DailyUI.row(table,[m.fecha+' · '+String(m.hora).slice(0,5),m.concepto,m.medio,(m.tipo==='EGRESO'?'− ':'+ ')+money(m.monto),m.actor,m.observaciones_legacy||'—'],{id:m.id});
   if(!result.rows.length)panel.append(el('p','Sin cobros ni reintegros registrados.'));
   if(after)panel.append(action('Volver al inicio del historial',()=>ctx.work(()=>openBonus('history',id))));
   if(result.next)panel.append(action('Movimientos anteriores',()=>ctx.work(()=>openBonus('history',id,result.next))));return;
  }
  const form=el('form');form.id='bonus-form';
  if(kind!=='cancel'){const amount=input(form,'bonus-amount','Importe',kind==='pay'?b.debt:b.paid,'number',true);amount.min='0.01';amount.step='0.01';amount.max=String(kind==='pay'?b.debt:b.paid);select(form,'bonus-medium','Medio',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],'EFECTIVO');}
  const reason=input(form,'bonus-reason',kind==='pay'?'Observaciones':'Motivo','','textarea',kind!=='pay');reason.maxLength=1000;if(kind!=='pay')reason.minLength=3;
  if(kind==='cancel')panel.append(el('p','Anular elimina la deuda del bono y conserva sus movimientos y las sesiones.'));
  if(kind==='refund')panel.append(el('p','El importe reintegrado vuelve a quedar pendiente en el bono. Si corresponde eliminar esa deuda, reintegrá todo lo cobrado y anulá el bono.'));
  submitButton(form,kind==='pay'?'Registrar cobro del bono':kind==='refund'?'Registrar reintegro del bono':'Confirmar anulación del bono');panel.append(form);
  form.addEventListener('submit',e=>{e.preventDefault();if(locked()||!form.reportValidity())return;const data={id:b.id,version:b.version};if(kind==='cancel')data.motivo=reason.value;else{data.monto=Number($('#o-bonus-amount').value);data.medio=$('#o-bonus-medium').value;data.observaciones=reason.value;}
   command('marathon_agenda_command',data,async()=>{await ctx.refreshPatient?.();await ctx.refreshHome?.();if(!$('#cash-screen').hidden)await loadCash();},{p_action:{pay:'bonus_pay',refund:'bonus_refund',cancel:'bonus_cancel'}[kind]});});
 }
 async function openReschedule(t){
  options=await rpc('marathon_agenda_options');const panel=modal('Reprogramar turnos pendientes'),form=el('form');form.id='reschedule-form';
  const scope=select(form,'scope','Qué reprogramar',[{id:'single',label:'Solo este turno'},{id:'series',label:'Todos los pendientes de la serie'}],'single');
  const tools=el('div',undefined,'form-grid');const delta=input(tools,'shift','Desplazar todos (días)','0','number');delta.min=-365;delta.max=365;delta.step=1;
  const commonTime=input(tools,'common-time','Hora para todos (opcional)','','time');commonTime.step=60;
  const commonSite=select(tools,'common-site','Sede para todos',options.sedes,'','Conservar cada sede');
  const commonProf=select(tools,'common-prof','Profesional para todos',[],'','Conservar cada profesional');
  const rows=el('div');rows.id='reschedule-rows';
  const review=el('section');review.id='reschedule-review';review.hidden=true;review.setAttribute('aria-live','polite');let originalTurns=[],reviewed=null,previewGeneration=0,previewTimer=null,previewKey=null,previewOk=false;
  const previewStatus=el('p','Completá los nuevos datos para consultar horarios.','subtitle');previewStatus.id='reschedule-preview-status';previewStatus.setAttribute('role','status');
  const proposal=()=>({id:t.id,scope:scope.value,changes:[...rows.children].map(row=>({id:row.dataset.id,version:Number(row.dataset.version),...Object.fromEntries([...row.querySelectorAll('input,select')].map(i=>[i.name,i.value]))}))});
  const current=()=>form.isConnected&&$('#operation-dialog').open;
  const invalidate=()=>{++previewGeneration;clearTimeout(previewTimer);previewKey=null;previewOk=false;reviewed=null;review.hidden=true;review.replaceChildren();save.textContent='Revisar reprogramación';previewStatus.textContent='Horarios pendientes de actualizar.';for(const box of rows.querySelectorAll('.reschedule-slots'))box.replaceChildren();previewTimer=setTimeout(()=>{if(current()&&!locked())void checkAvailability();},400);};
  async function checkAvailability(){
   clearTimeout(previewTimer);if(!current()||!rows.children.length)return false;
   if([...rows.querySelectorAll('input,select')].some(i=>!i.checkValidity())){previewStatus.textContent='Completá fecha, hora, sede y profesional en cada turno.';return false;}
   const data=proposal(),key=JSON.stringify(data),generation=++previewGeneration;previewKey=null;previewOk=false;previewStatus.textContent='Consultando horarios disponibles…';
   try{const result=await rpc('marathon_reschedule_preview',{p_data:data});
    if(!current()||generation!==previewGeneration||key!==JSON.stringify(proposal()))return false;
    if(!Array.isArray(result.rows)||result.rows.length!==data.changes.length||new Set(result.rows.map(r=>r.id)).size!==data.changes.length||data.changes.some(c=>!result.rows.some(r=>r.id===c.id)))throw Error('No se pudo comprobar toda la selección. Actualizá los horarios.');
    for(const row of rows.children){const r=result.rows.find(x=>x.id===row.dataset.id),box=row.querySelector('.reschedule-slots');box.replaceChildren(el('p',r.ok?'Horario elegido disponible.':r.reason||'Elegí otro horario.',r.ok?'':'ui-debt'));
     const available=r.slots.filter(s=>s.available),details=el('details'),summary=el('summary',available.length+' horarios disponibles');details.append(summary);const buttons=el('div',undefined,'row-actions');
     for(const s of available)buttons.append(action(s.hora+(s.end_hour?'–'+s.end_hour+' ('+s.duration_min+' min)':'')+' · '+s.remaining+' libre(s)',()=>{if(locked())return;row.querySelector('[name=hora]').value=s.hora;row.querySelector('[name=hora]').dispatchEvent(new Event('change',{bubbles:true}));}));details.append(buttons);box.append(details);
    }
    previewKey=key;previewOk=result.ok===true&&result.rows.every(r=>r.ok===true);$('#operation-error').textContent='';previewStatus.textContent=previewOk?'Todos los horarios están disponibles. Se volverán a verificar al guardar.':'Hay conflictos. Elegí otro horario o cambiá la fecha, sede o profesional.';return previewOk;
   }catch(e){if(current()&&generation===previewGeneration){previewStatus.textContent='No se pudieron consultar los horarios: '+e.message;$('#operation-error').textContent=e.message;}return false;}
  }
  tools.append(action('Aplicar al conjunto',()=>{if(locked())return;
   const shift=Number(delta.value),hour=commonTime.value;
   const fail=text=>{$('#operation-error').textContent=text;};
   if(delta.value===''||!Number.isInteger(shift)||Math.abs(shift)>365)return fail('El desplazamiento debe ser entero, entre -365 y 365 días.');
   if(!commonTime.checkValidity()||(hour&&!/^([01]\d|2[0-3]):[0-5]\d$/.test(hour)))return fail('Elegí una hora válida.');
   const changes=[];
   for(const row of rows.children){const date=row.querySelector('[name=fecha]'),d=new Date(date.value+'T12:00:00Z');
    if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==date.value)return fail('Completá las fechas antes de aplicar cambios.');
    d.setUTCDate(d.getUTCDate()+shift);const value=d.toISOString().slice(0,10);
    if(value<'2000-01-01'||value>'2100-12-31')return fail('Las fechas deben estar entre 2000 y 2100.');
    const prof=row.querySelector('[name=prof]');if(commonProf.value&&![...prof.options].some(o=>o.value===commonProf.value))return fail('El profesional no realiza todas las terapias seleccionadas.');
    changes.push({row,value});
   }
   for(const {row,value}of changes){row.querySelector('[name=fecha]').value=value;if(hour)row.querySelector('[name=hora]').value=hour;if(commonSite.value)row.querySelector('[name=sede]').value=commonSite.value;if(commonProf.value)row.querySelector('[name=prof]').value=commonProf.value;}
   invalidate();form.dispatchEvent(new Event('input',{bubbles:true}));$('#operation-error').textContent='';
  }));form.append(tools,rows,previewStatus,action('Actualizar horarios',()=>{if(!locked())void checkAvailability();}),el('p','Se conservan importes, pagos, coberturas e identificadores. La consulta contempla todos los cambios de la serie. Al confirmar se vuelven a validar los cupos; si hay un conflicto no se modifica ningún turno.','subtitle'),review);
  const save=submitButton(form,'Revisar reprogramación');panel.append(form);
  async function load(){const turns=await rpc('marathon_reschedule_get',{p_id:t.id,p_scope:scope.value});originalTurns=turns;rows.replaceChildren();for(const turn of turns){const row=el('fieldset');row.className='reschedule-row form-grid';row.dataset.id=turn.id;row.dataset.version=turn.version;row.append(el('legend',turn.fecha+' · '+turn.hora));input(row,'fecha','Nueva fecha',turn.fecha,'date',true);input(row,'hora','Nueva hora',turn.hora,'time',true).step=60;select(row,'sede','Sede',options.sedes,turn.sede,'Elegir sede').required=true;select(row,'prof','Profesional',options.professionals.filter(p=>p.therapy_ids.includes(turn.therapy)),turn.prof,'Elegir profesional').required=true;row.append(el('div',undefined,'reschedule-slots wide'));rows.append(row);}ctx.sync();}
  async function reload(){invalidate();await load();const profs=options.professionals.filter(p=>[...rows.children].every(row=>[...row.querySelector('[name=prof]').options].some(o=>o.value===p.id)));choices(commonProf,profs,'Conservar cada profesional');for(const i of rows.querySelectorAll('[name=fecha]')){i.min='2000-01-01';i.max='2100-12-31';}commonSite.value='';commonTime.value='';delta.value='0';invalidate();}
  scope.addEventListener('change',()=>ctx.work(reload));form.addEventListener('input',invalidate);form.addEventListener('change',invalidate);await reload();
  form.addEventListener('submit',async e=>{e.preventDefault();if(locked()||!form.reportValidity())return;const data=proposal(),changes=data.changes,signature=JSON.stringify(data);
   if(reviewed!==signature){if(!await checkAvailability()||!current()||signature!==JSON.stringify(proposal()))return;review.replaceChildren(el('h3','Revisá los nuevos turnos'));for(const c of changes){const site=options.sedes.find(s=>s.id===c.sede)?.label||c.sede,prof=options.professionals.find(p=>p.id===c.prof)?.label||c.prof;review.append(el('p',c.fecha+' · '+c.hora+' · '+site+' · '+prof));}review.append(el('p',changes.length+' turno(s). Horarios consultados; se vuelven a verificar al confirmar.'));review.hidden=false;reviewed=signature;save.textContent='Confirmar reprogramación';return;}
   if(previewKey!==signature||!previewOk)return;
   const notices=changes.map(c=>{const original=originalTurns.find(r=>r.id===c.id);return {...t,fecha:c.fecha,hora:c.hora,sede:options.sedes.find(s=>s.id===c.sede)?.label||c.sede,profesional:options.professionals.find(p=>p.id===c.prof)?.label||c.prof,terapia:options.therapies.find(x=>x.id===original?.therapy)?.label||t.terapia};});
   await command('marathon_reschedule_save',data,()=>ctx.refreshAgenda(),{},()=>{const box=el('section');box.setAttribute('aria-label','Avisos de reprogramación');box.append(el('p','Reprogramación guardada. Revisá y enviá el aviso de cada nuevo horario:'));for(const turn of notices){const row=el('div',undefined,'row-actions');row.append(el('span',turn.fecha+' · '+turn.hora+' · '+turn.sede));ctx.appendWhatsApp?.(row,turn,'reschedule');box.append(row);}$('#feedback').append(box);});if(current()&&!pending)invalidate();});
 }
 async function openMoney(id){
  const t=await rpc('marathon_turn_account',{p_id:id}),panel=modal('Cuenta del turno');panel.append(el('p',t.fecha+' · '+String(t.hora).slice(0,5)+' · DNI '+t.dni),el('p','Estado: '+t.estado+' · Importe: '+money(t.importe)),el('p','Pagos: '+money(t.cash_paid??t.paid)+' · Anticipos aplicados: '+money(t.advance_paid||0)+' · Saldo: '+money(t.debt)));
  chargeHistory(panel,t);if(t.estado==='PRESENTE'&&Number(t.debt)>0)panel.append(action('Cancelar cobro',()=>ctx.work(()=>openCancelCharge(t.id)),'s','destructive'));
  const allowed=[];if(t.estado==='PRESENTE'&&Number(t.debt)>0)allowed.push({id:'pay',label:'Registrar cobro'});if(Number(t.cash_paid??t.paid)>0)allowed.push({id:'refund',label:'Registrar reintegro de pago clínico'});if(Number(t.advance_paid)>0)panel.append(el('p','El anticipo aplicado se libera si corregís la asistencia y el turno deja de estar presente. Luego podés reintegrar el saldo disponible desde la ficha del paciente.','subtitle'));if(!allowed.length){panel.append(el('p','No hay cobros clínicos pendientes ni pagos clínicos para reintegrar.'));return;}const form=el('form');form.id='turn-money-form';const kind=select(form,'payment-action','Operación',allowed,allowed[0].id);
  const amount=input(form,'monto','Importe',t.estado==='PRESENTE'&&Number(t.debt)>0?t.debt:(t.cash_paid??t.paid),'number',true);amount.min='0.01';amount.max='9999999999.99';amount.step='0.01';select(form,'medio','Medio',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],'EFECTIVO');input(form,'fecha','Fecha del movimiento',today(),'date',true);input(form,'observaciones','Observaciones','','textarea');submitButton(form,'Registrar movimiento');panel.append(form);
  const updateAmount=()=>{const max=kind.value==='pay'?Number(t.debt):Number(t.cash_paid??t.paid);amount.value=String(max);amount.max=String(max);};kind.addEventListener('change',updateAmount);updateAmount();
  form.addEventListener('submit',e=>{e.preventDefault();if(!form.reportValidity())return;command('marathon_cash_command',{id:t.id,version:t.version,monto:Number(amount.value),medio:$('#o-medio').value,fecha:$('#o-fecha').value,observaciones:$('#o-observaciones').value},refreshMoney,{p_action:kind.value});});
 }
 function chargeHistory(panel,t){
  if(!t.charge_cancellations?.length)return;
  const section=el('section');section.append(el('h3','Cancelaciones del saldo de esta sesión'));const body=DailyUI.table(section,['Fecha','Importe anterior','Cancelado','Importe resultante','Motivo','Registró']);
  for(const r of t.charge_cancellations)DailyUI.row(body,[new Date(r.created_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'}),money(r.before_amount),money(r.amount),money(r.after_amount),r.reason,r.actor]);panel.append(section);
 }
 async function openCancelCharge(id){
  const t=await rpc('marathon_turn_account',{p_id:id});if(t.estado!=='PRESENTE'||Number(t.debt)<=0)throw Error('Solo se puede cancelar el saldo pendiente de una sesión presente. Actualizá los turnos.');
  const panel=modal('Cancelar cobro · Contraasiento de la sesión');panel.append(el('p',t.fecha+' · '+String(t.hora).slice(0,5)+' · DNI '+t.dni),el('p','Importe actual: '+money(t.importe)+' · Pagos y anticipos aplicados: '+money(t.paid)),el('p','Saldo a cancelar: '+money(t.debt)+' · Saldo resultante: '+money(0)),el('p','El paciente conserva el Presente. Se registra un ajuste por el saldo pendiente, con el importe anterior, el motivo y tu usuario. Los pagos realizados se conservan; no se devuelve dinero ni se mueve caja.','subtitle'));
  const form=el('form');form.id='cancel-charge-form';const reason=input(form,'motivo','Observación obligatoria · motivo de la cancelación','','textarea',true);reason.minLength=3;reason.maxLength=1000;reason.addEventListener('input',()=>reason.setCustomValidity(''));submitButton(form,'Confirmar cancelación del saldo','destructive');panel.append(form);chargeHistory(panel,t);
  form.addEventListener('submit',event=>{event.preventDefault();reason.setCustomValidity(reason.value.trim().length<3?'Indicá un motivo de al menos 3 caracteres.':'');if(!form.reportValidity())return;command('marathon_turn_cancel_charge',{id:t.id,version:t.version,saldo:Number(t.debt),motivo:reason.value.trim()},refreshMoney);});
 }
 async function refreshMoney(){if(!$('#cash-screen').hidden){await openCash();if(accountDni)await loadAccount();}if(!$('#agenda-screen').hidden)await ctx.refreshAgenda();await ctx.refreshHome?.();if(!$('#patients-screen').hidden)await ctx.refreshPatient?.();}
 async function openCash(){show('cash');options=await rpc('marathon_daily_options');if(!cf.fecha)cf.fecha=today();if(!cf.to)cf.to=cf.fecha;$('#cash-date').value=cf.fecha;$('#cash-to').value=cf.to;choices($('#cash-sede'),options.sedes,'Todas las sedes');$('#cash-sede').value=cf.sede;
  choices($('#cash-category'),[...options.therapies.map(t=>({id:'T:'+t.id,label:t.label})),...options.categories],'Todas las terapias / categorías');choices($('#cash-prof'),options.professionals,'Todos los profesionales');choices($('#cash-actor'),options.actors,'Todas las personas');for(const k of ['medium','category','prof','actor'])$('#cash-'+k).value=cf[k]||'';await loadCash();}
 async function loadCash(){cashExportFilters=null;const applied={from:cf.fecha,to:cf.to||cf.fecha,sede:cf.sede,medium:cf.medium||'',category:cf.category||'',prof:cf.prof||'',actor:cf.actor||''};const result=await rpc('marathon_cash_search',{p_filters:applied,p_after:cashPages[cp],p_limit:50});cashExportFilters=applied;cashExportLabels=Object.fromEntries(['sede','category','prof','actor'].map(k=>[k,$('#cash-'+k).selectedOptions?.[0]?.textContent||'']));cn=result.next;$('#cash-totals').replaceChildren();
  const v=Object.values(result.totals),sum=k=>v.reduce((n,x)=>n+Number(x[k]||0),0);for(const [title,value,direction,medium]of [['Ingresos',sum('income'),'income'],['Egresos',sum('expense'),'expense'],['Efectivo neto',result.totals.EFECTIVO?.net||0,null,'EFECTIVO'],['Transferencia neta',result.totals.TRANSFERENCIA?.net||0,null,'TRANSFERENCIA']]){const p=el('article',undefined,'card metric-card');if(direction)p.dataset.cashDirection=direction;p.append(el('span',title,'metric-label'),el('strong',money(value)));if(medium){const expense=Number(result.totals[medium]?.expense||0);p.append(el('small',(medium==='EFECTIVO'?'Egresos en efectivo: ':'Egresos por transferencia: ')+money(expense),expense>0?'ui-debt':''));}$('#cash-totals').append(p);}
  const list=$('#cash-list');list.replaceChildren();const body=DailyUI.table(list,['Fecha / hora','Concepto','Terapia / categoría','Paciente','Medio','Sede','Secretaría que registra','Profesional / secretaría asociada','Importe','Acciones']);
  for(const m of result.rows){const actions=el('div',undefined,'row-actions');if(ctx.getUser()?.role==='ADMIN'&&!m.reversed&&!m.compensacion_de&&((m.tipo==='PAGO'&&['CLINICA','ORTOPEDIA'].includes(m.origen))||(m.origen==='CAJA'&&['INGRESO','EGRESO'].includes(m.tipo))))actions.append(action('Anular con contrasiento',()=>ctx.work(()=>m.origen==='ORTOPEDIA'?ctx.openOrthoReverse(m):openReverse(m)),'s','destructive'));if(m.reversed)actions.append(el('small','Con contrasiento registrado'));if(m.compensacion_de)actions.append(el('small','Compensa: '+m.compensacion_de));
   const concept=el('div');concept.append(el('strong',m.concepto||m.tipo),el('small',m.tipo));if(m.observaciones_legacy)concept.append(el('small',m.observaciones_legacy));
   const outgoing=['EGRESO','REINTEGRO'].includes(m.tipo);const amount=el('strong',(outgoing?'− ':'+ ')+money(m.monto),outgoing?'ui-debt':'');DailyUI.row(body,[m.fecha+' · '+String(m.hora).slice(0,5),concept,m.category_label,m.paciente?(m.paciente+' · DNI '+m.dni):'—',m.medio,m.sede,m.actor,m.associated||'—',amount,actions],{id:m.id,cashDirection:outgoing?'expense':'income'});}
  $('#cash-info').textContent=result.rows.length+' movimientos en esta página. Los totales incluyen todas las páginas del filtro.';$('#cash-page').textContent='Página '+(cp+1);sync();
 }
 function openReverse(m){const panel=modal('Aprobar contrasiento');panel.append(el('p','Se registrará un movimiento contrario de '+money(m.monto)+' en '+m.medio+'. El movimiento original quedará conservado.'));const form=el('form');form.id='reverse-form';input(form,'motivo','Motivo','','textarea',true).minLength=3;input(form,'fecha','Fecha del contrasiento',today(),'date',true);submitButton(form,'Registrar contrasiento','destructive');panel.append(form);form.addEventListener('submit',e=>{e.preventDefault();if(form.reportValidity())command('marathon_cash_command',{id:m.id,version:m.version,motivo:$('#o-motivo').value,fecha:$('#o-fecha').value},refreshMoney,{p_action:'reverse'});});}
 async function newCash(){cashPatientPicker.reset();options=await rpc('marathon_daily_options');const panel=modal('Movimiento manual de caja'),form=el('form');form.id='cash-manual-form';const type=select(form,'tipo','Tipo',[{id:'INGRESO',label:'Ingreso'},{id:'EGRESO',label:'Egreso'}],'INGRESO');type.dataset.cashType='INGRESO';select(form,'sede','Sede',options.sedes,cf.sede||'','Elegir sede').required=true;input(form,'concepto','Concepto','','text',true).maxLength=200;cashPatientPicker.mount(form);const amount=input(form,'monto','Importe','','number',true);amount.min='0.01';amount.max='9999999999.99';amount.step='0.01';select(form,'medio','Medio',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],'EFECTIVO');input(form,'fecha','Fecha',cf.fecha||today(),'date',true);input(form,'categoria','Categoría (opcional)','','text').maxLength=100;
  const associated=select(form,'associated','Profesional o secretaría asociada',[...options.professionals.filter(p=>p.estado!=='INACTIVO').map(p=>({id:'P:'+p.id,label:'Profesional · '+p.label})),...options.secretaries.filter(p=>p.estado==='ACTIVO').map(p=>({id:'S:'+p.id,label:'Secretaría · '+p.label}))],'','Sin asociar');
  input(form,'observaciones','Observaciones','','textarea');const save=submitButton(form,'Guardar ingreso','default');const updateType=()=>{const outgoing=type.value==='EGRESO';type.dataset.cashType=type.value;save.dataset.variant=outgoing?'destructive':'default';save.textContent=outgoing?'Guardar egreso':'Guardar ingreso';};type.addEventListener('change',updateType);updateType();panel.append(form);form.addEventListener('submit',e=>{e.preventDefault();if(!form.reportValidity())return;const data=Object.fromEntries(new FormData(form));data.monto=Number(data.monto);const person=data.associated;delete data.associated;if(person.startsWith('P:'))data.profesional_asociado_id=person.slice(2);if(person.startsWith('S:'))data.secretaria_asociada=person.slice(2);command('marathon_cash_command',data,refreshMoney,{p_action:'cash'});});}
 async function openAccount(dni){await openCash();accountDni=dni;$('#account-dni').value=dni;ap=0;accountPages=[null];await loadAccount();}
 async function loadAccount(){const data=await rpc('marathon_patient_account',{p_dni:accountDni,p_after:accountPages[ap],p_limit:50});an=data.next;$('#account-summary').textContent=data.name+' · Saldo clínico total: '+money(data.debt);$('#account-list').replaceChildren();for(const t of data.rows){const row=el('article',undefined,'turn-card');row.append(el('h3',t.fecha+' · '+t.hora+' · '+t.terapia),el('p',t.sede+' · Saldo: '+money(t.debt)),action('Cobrar / reintegrar',()=>ctx.work(()=>openMoney(t.id))));$('#account-list').append(row);}for(const p of data.plans||[]){const row=el('article',undefined,'turn-card');row.append(el('h3','Cuotas mensuales · '+p.terapia),el('p','Saldo: '+money(p.debt)),action('Ver cuotas / cobrar',()=>ctx.work(()=>ctx.openPlan(p.id))));$('#account-list').append(row);}$('#account-page').textContent='Página '+(ap+1);sync();}
 function preferenceText(raw){try{const p=JSON.parse(raw);return p.any?'Cualquier horario':p.slots.map(s=>days[s.day]+' '+String(Math.floor(s.m/60)).padStart(2,'0')+':'+String(s.m%60).padStart(2,'0')).join('; ');}catch{return raw||'Cualquier horario';}}
 async function openWait(){show('wait');options=await rpc('marathon_daily_options');choices($('#wait-sede'),options.sedes,'Todas las sedes');$('#wait-sede').value=wf.sede;$('#wait-state').value=wf.state;choices($('#wait-therapy'),options.therapies,'Todas las terapias');choices($('#wait-prof'),options.professionals,'Todos los profesionales');choices($('#wait-insurance'),[{id:'__PARTICULAR__',label:'Particular'},...options.insurances],'Todas las obras sociales');for(const k of ['therapy','prof','insurance'])$('#wait-'+k).value=wf[k]||'';await loadWait();}
 async function loadWait(){const data=await rpc('marathon_wait_search',{p_filters:{state:wf.state,sede:wf.sede,query:wf.query,therapy:wf.therapy||'',prof:wf.prof||'',insurance:wf.insurance||'',show_cancelled:!!wf.show_cancelled},p_after:waitPages[wp],p_limit:50});wn=data.next;const list=$('#wait-list');list.replaceChildren();const kanban=$('#wait-view').value==='kanban',columns={};list.className=kanban?'wait-kanban':'';
  if(kanban)for(const [key,title]of [['PENDIENTE','Pendiente'],['CONTACTADO','Contactado'],['RESUELTO','Resuelto'],['CANCELADO','Cancelados']]){const col=el('section',undefined,'kanban-column');col.append(el('h2',title+' · '+data.counts[key]));const cards=el('div');col.append(cards);if(key==='CANCELADO'&&!wf.show_cancelled)col.append(el('small','Activá Mostrar cancelados para consultarlos.'));columns[key]=cards;list.append(col);}
  for(const r of data.rows){const row=el('article',undefined,'turn-card wait-card');row.dataset.id=r.id;row.append(el('h3',r.paciente+' · '+r.estado),el('p','DNI '+r.dni+' · '+r.terapia+' · '+r.sede),el('p',r.profesional||'Cualquier profesional'),el('p',r.obra_social),el('p',preferenceText(r.preferencias_legacy)));if(r.observaciones)row.append(el('p',r.observaciones));const buttons=el('div',undefined,'row-actions');
   if(['PENDIENTE','CONTACTADO'].includes(r.estado))buttons.append(action('Editar pedido',()=>ctx.work(()=>waitForm(r))),action('Reservar turno',()=>ctx.work(()=>ctx.openWaitBooking({...r,preference_label:preferenceText(r.preferencias_legacy)})),'b'));
   for(const [state,label]of [['PENDIENTE','Marcar pendiente'],['CONTACTADO','Marcar contactado'],['RESUELTO','Marcar resuelto'],['CANCELADO','Cancelar pedido']])if(state!==r.estado)buttons.append(action(label,()=>command('marathon_wait_status',{id:r.id,version:r.version,estado:state},loadWait)));row.append(buttons);(kanban?columns[r.estado]:list).append(row);}
  $('#wait-info').textContent=data.rows.length+' pedidos en esta página. '+(kanban?'Los contadores de columnas incluyen todas las páginas del filtro.':'');$('#wait-page').textContent='Página '+(wp+1);sync();
 }
 async function waitForm(record=null,preset=null){options=await rpc('marathon_agenda_options');const panel=modal(record?'Editar pedido de espera':'Nuevo pedido de espera');let patient=record?{dni:record.dni,label:record.paciente}:preset?{dni:preset.dni,label:[preset.apellido,preset.nombre].filter(Boolean).join(' ')}:null;
  const search=el('form');search.id='wait-patient-search';input(search,'query','Buscar paciente por DNI o nombre','','search',true).maxLength=100;submitButton(search,'Buscar paciente');panel.append(search);const results=el('div'),selected=el('p',patient?patient.label+' · DNI '+patient.dni:'Seleccioná un paciente de los resultados.');results.id='wait-patient-results';panel.append(results,selected);
  search.addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{patient=null;selected.textContent='Seleccioná un paciente.';const data=await rpc('marathon_patient_search',{p_query:$('#o-query').value.trim(),p_after:null,p_limit:10});results.replaceChildren();for(const p of data.rows)results.append(action(p.apellido+' '+p.nombre+' · '+p.dni,()=>{if(locked())return;patient={dni:p.dni,label:p.apellido+' '+p.nombre};selected.textContent=patient.label+' · DNI '+p.dni;results.replaceChildren();}));if(data.next)results.append(el('p','Hay más resultados. Escribí el DNI o un nombre más específico.'));});});
  const form=el('form');form.id='wait-form';select(form,'sede','Sede',options.sedes,record?.sede||'','Elegir sede').required=true;const therapy=select(form,'therapy','Terapia',options.therapies,record?.terapia_id||'','Elegir terapia');therapy.required=true;const prof=select(form,'prof','Profesional',[],record?.profesional_id||'','Cualquier profesional');const refresh=()=>{const value=prof.value;choices(prof,options.professionals.filter(p=>p.therapy_ids.includes(therapy.value)),'Cualquier profesional');prof.value=value;};therapy.addEventListener('change',refresh);refresh();if(record)prof.value=record.profesional_id||'';
  let pref;try{pref=JSON.parse(record?.preferencias_legacy||'');}catch{pref={any:true,slots:[]};}
  const label=el('label',undefined,'therapy-check'),any=el('input');any.type='checkbox';any.id='wait-any';any.checked=pref.any;label.append(any,document.createTextNode('Cualquier horario'));form.append(label);
  const preferences=input(form,'preferences','Horarios preferidos (uno por línea: lunes 09:00)',pref.any?'':preferenceText(record?.preferencias_legacy).replaceAll('; ','\n'),'textarea');preferences.maxLength=3000;preferences.parentElement.hidden=any.checked;any.addEventListener('change',()=>preferences.parentElement.hidden=any.checked);
  input(form,'observaciones','Observaciones',record?.observaciones||'','textarea').maxLength=2000;submitButton(form,'Guardar pedido');panel.append(form);
  form.addEventListener('submit',e=>{e.preventDefault();if(!form.reportValidity())return;if(!patient){$('#operation-error').textContent='Seleccioná un paciente de los resultados.';return;}let slots=[];
   if(!any.checked){try{slots=preferences.value.split(/[;\n]+/).map(x=>x.trim()).filter(Boolean).map(x=>{const m=x.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().match(/^(domingo|lunes|martes|miercoles|jueves|viernes|sabado)\s+([01][0-9]|2[0-3]):([0-5][0-9])$/);if(!m)throw Error();return{day:['domingo','lunes','martes','miercoles','jueves','viernes','sabado'].indexOf(m[1]),m:Number(m[2])*60+Number(m[3])};});}catch{$('#operation-error').textContent='Usá un día y una hora por línea, por ejemplo: lunes 09:00.';return;}}
   const data={dni:patient.dni,sede:$('#o-sede').value,therapy:therapy.value,prof:prof.value,observaciones:$('#o-observaciones').value,preferences:{version:1,any:any.checked,slots}};if(record){data.id=record.id;data.version=record.version;}command('marathon_wait_save',data,loadWait);
  });
 }
 $('#operation-dialog').addEventListener('cancel',e=>{if(locked())e.preventDefault();});
 $('#wait-filter').addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{wf={state:$('#wait-state').value,sede:$('#wait-sede').value,query:$('#wait-query').value.trim(),therapy:$('#wait-therapy').value,prof:$('#wait-prof').value,insurance:$('#wait-insurance').value,show_cancelled:$('#wait-show-cancelled').checked};wp=0;waitPages=[null];await loadWait();});});
 $('#wait-new').addEventListener('click',()=>ctx.work(()=>waitForm()));
 $('#cash-filter').addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{cf={fecha:$('#cash-date').value,to:$('#cash-to').value,sede:$('#cash-sede').value,medium:$('#cash-medium').value,category:$('#cash-category').value,prof:$('#cash-prof').value,actor:$('#cash-actor').value};cp=0;cashPages=[null];await loadCash();});});
 $('#cash-new').addEventListener('click',()=>ctx.work(newCash));
 $('#cash-export')?.addEventListener('click',()=>{if(!cashExportFilters)return;const filters={...cashExportFilters},labels={...cashExportLabels};ctx.work(async()=>{const count=await exportCash(ctx.getApi(),filters,labels);ctx.message('Excel descargado: '+count+' movimientos de los filtros aplicados.');});});
 $('#cash-advance')?.addEventListener('click',()=>ctx.work(newAdvance));
 $('#account-form').addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{accountDni=$('#account-dni').value.trim();ap=0;accountPages=[null];await loadAccount();});});
 for(const prefix of ['wait','cash','account'])for(const direction of ['previous','next'])$('#'+prefix+'-'+direction).addEventListener('click',()=>ctx.work(async()=>{
  if(prefix==='wait'){if(direction==='next'){if(!wn)return;waitPages=waitPages.slice(0,wp+1);waitPages.push(wn);wp++;}else if(wp>0)wp--;await loadWait();}
  else if(prefix==='cash'){if(direction==='next'){if(!cn)return;cashPages=cashPages.slice(0,cp+1);cashPages.push(cn);cp++;}else if(cp>0)cp--;await loadCash();}
  else{if(direction==='next'){if(!an)return;accountPages=accountPages.slice(0,ap+1);accountPages.push(an);ap++;}else if(ap>0)ap--;await loadAccount();}
 }));
 $('#cash-date').addEventListener('change',()=>{if($('#cash-to').value<$('#cash-date').value||$('#cash-to').value===cf.fecha)$('#cash-to').value=$('#cash-date').value;});
 $('#wait-state').addEventListener('change',()=>{if($('#wait-state').value==='CANCELADO')$('#wait-show-cancelled').checked=true;});
 $('#wait-show-cancelled').addEventListener('change',()=>{if(!$('#wait-show-cancelled').checked&&$('#wait-state').value==='CANCELADO')$('#wait-state').value='';});
 $('#wait-view').addEventListener('change',()=>{if($('#wait-view').value==='kanban')$('#wait-state').value='';});
 return {openAdvance,newAdvance,openBonus,newCash,newWait:preset=>waitForm(null,preset||null),openCashAt:async(date,site)=>{cf={fecha:date,to:date,sede:site||'',medium:'',category:'',prof:'',actor:''};cashPages=[null];cp=0;await openCash();},reloadCash:refreshMoney,openWait,openCash,openMoney,openCancelCharge,openReschedule,openAccount,sync,isPending:()=>!!pending||cashPatientPicker.isPending(),reset:()=>{cashExportFilters=null;cashExportLabels={};cashPatientPicker.reset();pending=null;options={sedes:[],therapies:[],professionals:[]};waitPages=[null];wp=0;wn=null;cashPages=[null];cp=0;cn=null;accountPages=[null];ap=0;an=null;accountDni='';wf={state:'PENDIENTE',sede:'',query:''};cf={fecha:'',to:'',sede:'',medium:'',category:'',prof:'',actor:''};$('#operation-dialog').close();$('#operation-body').replaceChildren();$('#operation-recovery').replaceChildren();$('#operation-error').textContent='';for(const id of ['wait-list','cash-list','cash-totals','account-list'])$('#'+id).replaceChildren();for(const id of ['cash-info','wait-info','account-summary','wait-page','cash-page','account-page'])$('#'+id).textContent='';$('#account-dni').value='';$('#wait-query').value='';$('#wait-state').value='PENDIENTE';$('#wait-show-cancelled').checked=false;$('#wait-view').value='list';}};
}
