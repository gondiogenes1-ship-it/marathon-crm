import {saldoEnabled} from './saldo-state.js?v=20261104-saldo';
import {createWhatsApp} from './whatsapp.js?v=20261029-0131-icono';
import {createMotion} from './motion.js?v=20261028-0131';
import {appendTurnWhatsApp,exportTurns} from './turn-tools.js?v=20261030-0140';
import {createPatientHistory} from './patient-history.js?v=20261104-saldo';
import {createUsers} from './users.js?v=20261019-0110';
import {appendPatientCoverages,patientPayload,patientCoverages,appendPatientPhone} from './coverage.js?v=20261027-0120';
import {createEditing} from './editing.js?v=20261029-caja-pacientes';
import {createHelp} from './help.js?v=20261105-saldo';
import {createHome} from './home.js?v=20261102-cancelados';
import {createCatalogs} from './catalogs.js?v=20261019-0110';
import {createReports} from './reports.js?v=20261111-roles';
import {createDocuments} from './documents.js?v=20261029-caja-pacientes';
import {MarathonApi} from './api.js?v=20261104-saldo';
import {createMasters} from './masters.js?v=20261112-horarios-revision';
import {createAgenda} from './agenda.js?v=20261111-continuidad';
import {createHorariosRevision} from './horarios-revision.js?v=20261112-horarios-revision-2';
import {createOperations} from './operations.js?v=20261106-editar-secretarias-1';
import {createOrtho} from './ortho.js?v=20261112-traslado-sede';
import {createModalUI} from './modal-ui.js?v=20261027-0128';
const $=s=>document.querySelector(s);
let saldoActive=false;
let api=null,user=null,catalog=[],query='',pages=[null],page=0,next=null,selected=null,pending=null,busy=false,searchGeneration=0,detailGeneration=0,patientsLoaded=false;
const motion=createMotion();
const modalUI=createModalUI();
function msg(text,error=false){const f=$('#feedback');f.hidden=!text;f.textContent=text;f.dataset.error=String(error);f.setAttribute('role',error?'alert':'status');if(error&&text)modalUI.showError(text);}
function button(label,action,cls='s'){const b=document.createElement('button');b.type='button';b.className=cls;b.textContent=label;b.addEventListener('click',action);return b;}
const masters=createMasters({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,setBusy:value=>{busy=value;sync();}});
async function exportTurnList(filters,labels){const count=await exportTurns(api,filters,labels);msg('Excel descargado: '+count+' turnos del filtro completo.');}
const agenda=createAgenda({saldoActive:()=>saldoActive,openSaldo:p=>operations.openSaldo(p),appendWhatsApp:(parent,turn,kind)=>appendTurnWhatsApp(parent,turn,{kind,getApi:()=>api,isBusy:()=>busy,onError:text=>msg(text,true)}),exportTurns:exportTurnList,getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,onChanged:()=>home.reloadVisible(),openReschedule:t=>operations.openReschedule(t),openMoney:id=>operations.openMoney(id),openCancelCharge:id=>operations.openCancelCharge(id),setBusy:value=>{busy=value;sync();}});
const operations=createOperations({saldoActive:()=>saldoActive,openPlan:id=>agenda.openPlan(id),appendWhatsApp:(parent,turn,kind)=>appendTurnWhatsApp(parent,turn,{kind,getApi:()=>api,isBusy:()=>busy,onError:text=>msg(text,true)}),getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,refreshAgenda:async()=>{if(!$('#agenda-screen').hidden)await agenda.reload();await home.reloadVisible();},refreshHome:()=>home.reloadVisible(),refreshPatient:()=>patientHistory.reload(),openWaitBooking:r=>agenda.openFromWait(r),openOrthoReverse:m=>ortho.openReverse(m),setBusy:value=>{busy=value;sync();}});
const ortho=createOrtho({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,refreshCash:()=>operations.reloadCash(),setBusy:value=>{busy=value;sync();}});
const catalogs=createCatalogs({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,show:showSection,refreshPatientCatalog:async()=>{catalog=await api.rpc('marathon_patient_catalog',{});},setBusy:value=>{busy=value;sync();}});
const reports=createReports({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,show:showSection});
const documents=createDocuments({getApi:()=>api,isBusy:()=>busy,work,message:msg,sync,setBusy:value=>{busy=value;sync();}});
const home=createHome({exportTurns:exportTurnList,getApi:()=>api,getUser:()=>user,isBusy:()=>busy,isPending:()=>!!pending||agenda.isPending()||operations.isPending()||ortho.isPending()||masters.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending(),renderTurns:(panel,rows,partial,scope)=>agenda.renderRows(panel,rows,false,partial,scope),work,message:msg,show:showSection,navigate:async(target,filter)=>{
 if(target==='booking'){await agenda.openAt(filter.date,filter.site);agenda.startBooking();}
 else if(target==='agenda')await agenda.openAt(filter.date,filter.site);
 else if(target==='cash')await operations.openCashAt(filter.date,filter.site);
 else if(target==='patient'){showSection('patients');editPatient(null);if(!patientsLoaded)await search();}
 else if(target==='reports')await reports.open();
 else if(target==='new-wait'){await operations.openWait();await operations.newWait();}
 else if(target==='new-advance')await operations.newAdvance();
 else if(target==='new-cash'){await operations.openCashAt(filter.date,filter.site);await operations.newCash();}
 else if(target==='ortho')await ortho.open();
}});
const horarios=createHorariosRevision({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,setBusy:value=>{busy=value;sync();},onChanged:async()=>{if(!$('#agenda-screen').hidden)await agenda.reload();await home.reloadVisible();}});
const users=createUsers({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,sync,show:showSection,setBusy:value=>{busy=value;sync();},refreshSession:async()=>{user=await api.rpc('marathon_session',{});$('#current-user').textContent=user.name+' · '+(user.role==='ADMIN'?'Administración':'Secretaría');}});
const whatsapp=createWhatsApp({getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work,message:msg,setBusy:value=>{busy=value;sync();}});
const help=createHelp({saldoActive:()=>saldoActive,getApi:()=>api,getUser:()=>user,isBusy:()=>busy,work});
const patientHistory=createPatientHistory({saldoActive:()=>saldoActive,onSaldo:dni=>work(()=>operations.openSaldo({dni})),onSaldoHistory:dni=>work(()=>operations.saldoHistory(dni)),isBusy:()=>busy||!!pending||agenda.isPending()||operations.isPending()||ortho.isPending()||masters.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending(),getApi:()=>api,getCatalog:()=>catalog,onClose:()=>{selected=null;renderPatientEmpty();highlight();},onEdit:p=>work(async()=>editPatient(await api.rpc('marathon_patient_get',{p_dni:p.dni}))),onBook:p=>work(()=>agenda.bookFor(p)),onWait:p=>work(async()=>{await operations.openWait();await operations.newWait(p);}),onAccount:dni=>work(()=>operations.openAccount(dni)),onDocuments:dni=>work(()=>documents.open(dni)),onAdvance:(kind,id)=>work(()=>operations.openAdvance(kind,id)),onBonus:(kind,id)=>work(()=>operations.openBonus(kind,id)),onAgenda:t=>work(()=>agenda.openAt(t.fecha,t.sede))});
const editing=createEditing({isBusy:()=>busy,isPending:()=>!!pending||masters.isPending()||agenda.isPending()||operations.isPending()||ortho.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending(),message:msg});
function showSection(name){const target=$("#"+name+"-screen"),changed=target?.hidden;for(const n of ['home','patients','masters','agenda','wait','cash','ortho','catalog','reports','users']){$('#'+n+'-screen').hidden=n!==name;$('#nav-'+n).className=n===name?'b':'';}if(changed)motion.enter(target);}
function sync(){
  const names={home:'Inicio',patients:'Pacientes',masters:'Datos de agenda',agenda:'Turnos',wait:'Lista de espera',cash:'Caja',ortho:'Ortopedia y stock',catalog:'Otros datos',reports:'Informes',users:'Usuarios'};
  for(const [key,title] of Object.entries(names)){const active=!$('#'+key+'-screen').hidden;$('#nav-'+key).setAttribute('aria-current',active?'page':'false');if(active)$('#current-section').textContent=title;}
  $('#workspace').setAttribute('aria-busy',String(busy));$('#work-status').textContent=busy?'Procesando…':'Área de trabajo';$('#work-status').classList.toggle('working',busy);

  document.querySelectorAll('#workspace button,#search').forEach(e=>{e.disabled=busy||!!pending||(masters.isPending()||agenda.isPending()||operations.isPending()||ortho.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending());});
  $('#logout').disabled=busy;
  if($('#retry-save'))$('#retry-save').disabled=busy;
  $('#previous').disabled=busy||!!pending||page===0;$('#next').disabled=busy||!!pending||!next;
  document.querySelectorAll('#workspace input,#workspace textarea,#workspace select').forEach(e=>{e.disabled=busy||!!pending||(masters.isPending()||agenda.isPending()||operations.isPending()||ortho.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending());});
  home.sync();patientHistory.sync();masters.sync();agenda.sync();operations.sync();ortho.sync();catalogs.sync();reports.sync();documents.sync();users.sync();whatsapp.sync();
}
async function work(fn){if(busy||pending||(masters.isPending()||agenda.isPending()||operations.isPending()||ortho.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending()))return;const focused=document.activeElement;busy=true;sync();try{await fn();}catch(e){msg(e.message,true);}finally{busy=false;sync();restoreFocus(focused);}}
// Los controles se bloquean mientras se guarda; al terminar se devuelve el foco para no perder el lugar al trabajar con teclado.
function restoreFocus(el){if(!el||el===document.body||!el.isConnected||el.disabled||(document.activeElement&&document.activeElement!==document.body&&document.activeElement.isConnected))return;if(el.closest?.('[hidden]'))return;try{el.focus({preventScroll:true});}catch{}}
function clearScreen(){
  ++searchGeneration;++detailGeneration;masters.reset();agenda.reset();operations.reset();ortho.reset();catalogs.reset();reports.reset();documents.reset();home.reset();users.reset();whatsapp.reset();help.reset();horarios.reset();editing.reset();patientHistory.reset();hideOperations();$('#agenda-screen').hidden=true;$('#nav-agenda').className='';$('#masters-screen').hidden=true;$('#patients-screen').hidden=false;$('#nav-masters').hidden=true;$('#nav-catalog').hidden=true;$('#nav-users').hidden=true;$('#nav-patients').className='b';$('#nav-masters').className='';
  saldoActive=false;operations.updateSaldoLabels();user=null;catalog=[];pages=[null];page=0;next=null;selected=null;pending=null;query='';patientsLoaded=false;quickReset();
  $('#patient-list').replaceChildren();$('#detail').replaceChildren();$('#search').value='';$('#current-user').textContent='';msg('');
  $('#workspace').hidden=true;$('#login').hidden=false;$('#login-form').reset();
}
async function search(){
  const generation=++searchGeneration;
  const result=await api.rpc('marathon_patient_search',{p_query:query,p_after:pages[page],p_limit:25});
  if(generation!==searchGeneration||!user)return;
  next=result.next;patientsLoaded=true;
  $('#patient-list').replaceChildren();
  for(const p of result.rows){
    const item=button([p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' '),()=>work(()=>openPatient(p.dni)),'patient-item');
    item.dataset.dni=p.dni;item.dataset.initials=[p.apellido?.[0],p.nombre?.[0]].filter(Boolean).join('').toUpperCase();item.setAttribute('aria-pressed',String(selected?.dni===p.dni));
    const detail=document.createElement('small');detail.textContent='DNI '+p.dni+(p.telefono?' · '+p.telefono:'');item.append(detail);$('#patient-list').append(item);
  }
  $('#result-info').textContent=result.rows.length?result.rows.length+' pacientes en esta página.':'No hay coincidencias.';
  $('#page-label').textContent='Página '+(page+1);sync();
}
const fields=[['dni','DNI','text'],['nombre','Nombre','text'],['segundo_nombre','Segundo nombre','text'],['apellido','Apellido','text'],['nacimiento','Fecha de nacimiento','date'],['sexo','Sexo','select'],['obra_social_id','Obra social','select'],['afiliado','N.º afiliado','text'],['telefono','Teléfono','tel'],['email','Correo','email'],['domicilio','Domicilio','text'],['localidad','Localidad','text'],['provincia','Provincia','text'],['medico','Médico de cabecera','text'],['observaciones','Observaciones','textarea']];
function editPatient(p){patientHistory.reset();
  selected=p?{...p}:null;const detail=$('#detail');detail.replaceChildren();
  const head=document.createElement('div');head.className='detail-head';
  const title=document.createElement('h2');title.textContent=p?[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' '):'Nuevo paciente';head.append(title);if(p){const id=document.createElement('p');id.className='patient-id';id.textContent='DNI '+p.dni+' · '+(patientCoverages(p).map(c=>catalog.find(o=>o.id===c.obra_social_id)?.name||c.obra_social_id).join(', ')||'Sin obra social');detail.append(id);}
  head.append(button('Cerrar ficha',()=>{selected=null;renderPatientEmpty();highlight();}));detail.append(head);
  if(p){const quick=document.createElement('div');quick.className='patient-quick-actions';quick.append(button('Reservar turno',()=>work(()=>agenda.bookFor(p)),'b'),button('Agregar a lista de espera',()=>work(async()=>{await operations.openWait();await operations.newWait(p);})),button('Cuenta clínica',()=>work(()=>operations.openAccount(p.dni))),button('Documentos',()=>work(()=>documents.open(p.dni))));detail.append(quick);}
  const form=document.createElement('form');form.id='patient-form';const grid=document.createElement('div');grid.className='form-grid';
  const groups={dni:'01 · Identificación',obra_social_id:'02 · Cobertura',telefono:'03 · Contacto',domicilio:'04 · Domicilio',medico:'05 · Información clínica'};
  for(const [key,label,type] of fields){
    if(key==='obra_social_id'){appendPatientCoverages(grid,catalog,p,'patient');continue;}
    if(key==='afiliado')continue;
    if(groups[key]){const h=document.createElement('h3');h.className='form-section-heading';h.textContent=groups[key];grid.append(h);}
    if(key==='telefono'){appendPatientPhone(grid,p,'patient');continue;}
    const box=document.createElement('label');box.textContent=label+(['dni','nombre','apellido'].includes(key)?' *':'');
    const input=document.createElement(type==='textarea'?'textarea':type==='select'?'select':'input');input.name=key;input.id='p-'+key;
    if(input.tagName==='INPUT')input.type=type;
    if(['dni','nombre','apellido'].includes(key))input.required=true;
    if(key==='dni'){input.readOnly=!!p;input.pattern='[0-9]{1,12}';input.inputMode='numeric';input.maxLength=12;}
    if(type==='textarea'){box.className='wide';input.maxLength=10000;}else if(type!=='select')input.maxLength=key==='email'?254:500;
    if(type==='select'){
      const options=key==='sexo'?[['','Sin especificar'],['Masculino','Masculino'],['Femenino','Femenino'],['Otro','Otro']]:[['','Particular'],...catalog.filter(o=>o.status==='ACTIVO'||o.id===p?.obra_social_id).map(o=>[o.id,o.name+(o.status==='INACTIVO'?' (inactiva)':'')])];
      for(const [value,text] of options){const o=document.createElement('option');o.value=value;o.textContent=text;input.append(o);}
    }
    input.value=p?.[key]??'';box.append(input);grid.append(box);
  }
  form.append(grid);
  const actions=document.createElement('div');actions.className='form-actions patient-save-actions';
  const save=document.createElement('button');save.className='b';save.type='submit';save.textContent='Guardar paciente';actions.append(save);
  if(p)actions.append(button('Volver a cargar ficha',()=>work(()=>openPatient(p.dni))));
  const hint=document.createElement('small');hint.textContent='* Campos obligatorios';hint.className='save-hint';actions.append(hint);
  form.prepend(actions);form.addEventListener('submit',savePatient);detail.append(form);
  if(p?.documentos_legacy){const docs=document.createElement('details');const summary=document.createElement('summary');summary.textContent='Documentos / enlaces conservados';docs.append(summary);
    let items=[];try{const v=JSON.parse(p.documentos_legacy);items=Array.isArray(v.items)?v.items:[];}catch{items=String(p.documentos_legacy).split('\n').filter(Boolean).map(name=>({name,url:name}));}
    for(const item of items){const line=document.createElement('p');let u;try{u=new URL(item.url);}catch{}
      if(u&&['http:','https:'].includes(u.protocol)){const a=document.createElement('a');a.href=u.href;a.target='_blank';a.rel='noopener noreferrer';a.textContent=item.name||'Documento';line.append(a);}else line.textContent=item.name||'';
      docs.append(line);
    }
    detail.append(docs);
  }
  highlight();sync();
}
function renderPatientEmpty(){patientHistory.reset();const box=document.createElement('div');box.className='patient-empty';const h=document.createElement('h2');h.textContent='Cada paciente, una historia.';const p=document.createElement('p');p.textContent='Seleccioná una ficha de la lista para ver sus datos, documentos y cuenta clínica.';box.append(h,p);$('#detail').replaceChildren(box);}
function highlight(){document.querySelectorAll('.patient-item').forEach(e=>e.setAttribute('aria-pressed',String(e.dataset.dni===selected?.dni)));}
async function openPatient(dni){const generation=++detailGeneration;const p=await api.rpc('marathon_patient_get',{p_dni:dni});if(generation!==detailGeneration||!user)return;selected=p;highlight();await patientHistory.mount($('#detail'),p);msg('');}
async function savePatient(event){
  event.preventDefault();if(busy||pending)return;
  const form=event.currentTarget;if(!form.reportValidity())return;
  let p_data;try{p_data=patientPayload(form);}catch(e){msg(e.message,true);return;}
  pending={p_request_id:crypto.randomUUID(),p_data,p_version:selected?.version??null};
  await sendPending();
}
// Paciente nuevo: sigue el trabajo sin volver a buscarlo.
function offerNextSteps(dni){const box=document.createElement('span');box.className='next-steps';
  box.append(' ',button('Reservar turno',()=>work(async()=>{await agenda.bookFor(await api.rpc('marathon_patient_get',{p_dni:dni}));}),'b'),' ',button('Agregar a lista de espera',()=>work(async()=>{const p=await api.rpc('marathon_patient_get',{p_dni:dni});await operations.openWait();await operations.newWait(p);})));
  $('#feedback').append(box);}
async function sendPending(){
  if(!pending||busy)return;busy=true;sync();const request=pending;
  try{
    const result=await api.rpc('marathon_patient_save',request,true);pending=null;
    // Confirmación se muestra aun cuando falle la actualización posterior de la pantalla.
    msg(result.message);pages=[null];page=0;
    try{await openPatient(result.dni);await search();msg(result.message);if(request.p_version===null)offerNextSteps(result.dni);}catch{msg('Guardado confirmado. No se pudo actualizar la pantalla; volvé a buscar el paciente.',true);}
  }catch(e){
    if(!e.uncertain){pending=null;msg(e.message,true);}else{
      msg(e.message,true);
      if(!$('#retry-save')){const retry=button('Verificar guardado',sendPending);retry.id='retry-save';$('#detail').append(retry);}
    }
  }finally{busy=false;if(!pending)$('#retry-save')?.remove();sync();}
}
$('#login-form').addEventListener('submit',async event=>{
  event.preventDefault();const form=event.currentTarget;const submit=form.querySelector('button');submit.disabled=true;$('#login-error').textContent='';
  try{
    api??=new MarathonApi(window.MARATHON_CONFIG);api.onDenied=()=>{if(!user)return;const current=api;clearScreen();current.signOut();$('#login-error').textContent='Tu sesión o tus permisos cambiaron. Volvé a ingresar.';};
    user=await api.signIn($('#login-email').value,$('#login-password').value);form.reset();saldoActive=await saldoEnabled(api,{fresh:true});operations.updateSaldoLabels();
    catalog=await api.rpc('marathon_patient_catalog',{});
    $('#nav-users').hidden=user.role!=='ADMIN';$('#nav-catalog').hidden=user.role!=='ADMIN';$('#nav-masters').hidden=user.role!=='ADMIN';$('#ortho-new-product').hidden=user.role!=='ADMIN';$('#ortho-tab-catalog').hidden=user.role!=='ADMIN';
    $('#current-user').textContent=user.name+' · '+(user.role==='ADMIN'?'Administración':'Secretaría');
    $('#workspace').hidden=false;$('#login').hidden=true;
    await work(()=>home.open());
  }catch(e){if(api)await api.signOut();clearScreen();$('#login-error').textContent=e.message;}
  finally{submit.disabled=false;}
});
$('#login-form').dataset.loginReady='true';$('#login-submit').disabled=false;
$('#search-form').addEventListener('submit',event=>{event.preventDefault();work(async()=>{query=$('#search').value.trim();page=0;pages=[null];await search();});});
$('#next').addEventListener('click',()=>work(async()=>{if(!next)return;pages=pages.slice(0,page+1);pages.push(next);page++;await search();}));
$('#previous').addEventListener('click',()=>work(async()=>{if(page>0){page--;await search();}}));
$('#new-patient').addEventListener('click',()=>{if(!busy&&!pending){msg('');editPatient(null);}});
$('#logout').addEventListener('click',async()=>{if(busy)return;clearScreen();await api?.signOut();});
window.addEventListener('beforeunload',event=>{if(pending||(masters.isPending()||agenda.isPending()||operations.isPending()||ortho.isPending()||catalogs.isPending()||documents.isPending()||users.isPending()||whatsapp.isPending())){event.preventDefault();event.returnValue='';}});

// Búsqueda rápida de pacientes desde cualquier pantalla (no bloquea la interfaz; no guarda nada).
const quick={gen:0,timer:null,rows:[],active:-1};
function quickReset(clear=true){clearTimeout(quick.timer);quick.gen++;quick.rows=[];quick.active=-1;const q=$('#quick-q');if(q){if(clear)q.value='';q.setAttribute('aria-expanded','false');q.removeAttribute('aria-activedescendant');}$('#quick-results')?.replaceChildren();if($('#quick-results'))$('#quick-results').hidden=true;$('#quick-status').textContent='';}
function quickMark(index){quick.active=index;const items=[...$('#quick-results').children];items.forEach((li,i)=>li.setAttribute('aria-selected',String(i===index)));const li=items[index];if(li){$('#quick-q').setAttribute('aria-activedescendant',li.id);li.scrollIntoView?.({block:'nearest'});}else $('#quick-q').removeAttribute('aria-activedescendant');}
function quickRender(rows,text){const list=$('#quick-results');list.replaceChildren();quick.rows=rows;quick.active=-1;
  rows.forEach((p,i)=>{const li=document.createElement('li');li.id='quick-opt-'+i;li.setAttribute('role','option');li.setAttribute('aria-selected','false');const name=document.createElement('strong');name.textContent=[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ');const info=document.createElement('small');info.textContent='DNI '+p.dni+(p.telefono?' · '+p.telefono:'');li.append(name,info);li.addEventListener('mousedown',e=>e.preventDefault());li.addEventListener('click',()=>quickPick(p));list.append(li);});
  if(!rows.length){const li=document.createElement('li');li.className='quick-empty';li.setAttribute('role','presentation');li.textContent=text||'Sin coincidencias. Podés cargarlo desde Pacientes.';list.append(li);}
  list.hidden=false;$('#quick-q').setAttribute('aria-expanded','true');$('#quick-status').textContent=rows.length?rows.length+' pacientes encontrados. Usá las flechas y Enter.':'Sin coincidencias.';}
async function quickFind(){const q=$('#quick-q').value.trim();if(q.length<2||!api||!user)return;const gen=++quick.gen;quickRender([],'Buscando pacientes…');
  try{const result=await api.rpc('marathon_patient_search',{p_query:q,p_after:null,p_limit:8});if(gen!==quick.gen||!user)return;quickRender(result.rows);if(result.next){const li=document.createElement('li');li.className='quick-empty';li.setAttribute('role','presentation');li.textContent='Hay más resultados: escribí el DNI o más letras.';$('#quick-results').append(li);}}
  catch(e){if(gen===quick.gen&&user)quickRender([],e.message);}}
function quickPick(p){if(busy||pending||!editing.allowNavigation())return;work(async()=>{quickReset();showSection('patients');await openPatient(p.dni);if(!patientsLoaded)await search();});}
$('#quick-q').addEventListener('input',()=>{quickReset(false);if($('#quick-q').value.trim().length<2)return;quick.timer=setTimeout(quickFind,250);});
$('#quick-q').addEventListener('keydown',e=>{const n=quick.rows.length;
  if(e.key==='ArrowDown'&&n){e.preventDefault();quickMark((quick.active+1)%n);}
  else if(e.key==='ArrowUp'&&n){e.preventDefault();quickMark((quick.active-1+n)%n);}
  else if(e.key==='Enter'){e.preventDefault();clearTimeout(quick.timer);if(n)quickPick(quick.rows[Math.max(quick.active,0)]);else quickFind();}
  else if(e.key==='Escape'){quickReset();}});
$('#quick-q').addEventListener('blur',()=>setTimeout(()=>{if(document.activeElement!==$('#quick-q')){$('#quick-results').hidden=true;$('#quick-q').setAttribute('aria-expanded','false');}},150));
$('#quick-q').addEventListener('focus',()=>{if(quick.rows.length){$('#quick-results').hidden=false;$('#quick-q').setAttribute('aria-expanded','true');}});
$('#quick-search').addEventListener('submit',e=>e.preventDefault());
document.addEventListener('keydown',e=>{if($('#workspace').hidden)return;const t=e.target,typing=t&&(['INPUT','TEXTAREA','SELECT'].includes(t.tagName)||t.isContentEditable);
  if((e.key==='/'&&!typing&&!e.ctrlKey&&!e.metaKey&&!e.altKey)||((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k')){if(document.querySelector('dialog[open]'))return;e.preventDefault();$('#quick-q').focus();$('#quick-q').select();}
  if(e.key==='Escape')document.querySelectorAll('details.row-more[open]').forEach(d=>d.open=false);});
// Menús "Más" de las filas: se cierran al tocar fuera.
document.addEventListener('click',e=>{document.querySelectorAll('details.row-more[open]').forEach(d=>{if(!d.contains(e.target))d.open=false;});});
function hideOperations(){for(const n of ['home','wait','cash','ortho','catalog','reports','users']){$('#'+n+'-screen').hidden=true;$('#nav-'+n).className='';}}
$('#nav-ortho').addEventListener('click',()=>work(()=>ortho.open()));
$('#nav-wait').addEventListener('click',()=>work(()=>operations.openWait()));
$('#nav-cash').addEventListener('click',()=>work(()=>operations.openCash()));
$('#nav-agenda').addEventListener('click',()=>work(async()=>{await agenda.open();await horarios.refreshBadge();}));
$('#agenda-review-schedules').addEventListener('click',()=>work(()=>horarios.open()));
$('#nav-masters').addEventListener('click',()=>work(async()=>{hideOperations();$('#agenda-screen').hidden=true;$('#nav-agenda').className='';await masters.open();}));
$('#nav-patients').addEventListener('click',()=>work(async()=>{hideOperations();$('#agenda-screen').hidden=true;$('#nav-agenda').className='';$('#masters-screen').hidden=true;$('#patients-screen').hidden=false;$('#nav-masters').className='';$('#nav-patients').className='b';if(!patientsLoaded)await search();else if(selected&&!$('#patient-form'))await patientHistory.reload();}));

$('#nav-catalog').addEventListener('click',()=>work(()=>catalogs.open()));
$('#nav-reports').addEventListener('click',()=>work(()=>reports.open()));

$('#nav-home').addEventListener('click',()=>work(()=>home.open()));

$('#nav').addEventListener('click',event=>{if(event.target.closest('button')&&!busy)msg('');},true);

$('#nav-users').addEventListener('click',()=>work(()=>users.open()));
