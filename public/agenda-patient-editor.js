import {appendPatientCoverages,appendPatientPhone,patientPayload} from './coverage.js?v=20261027-0120';

// Usa el mismo guardado, control de versión y permisos que la ficha de Pacientes.
export function createAgendaPatientEditor(ctx){
 const prefix=ctx.prefix||'agenda-patient-edit',fieldPrefix=ctx.prefix||'agenda-edit';
 const dialog=document.createElement('dialog');dialog.id=prefix+'-dialog';dialog.setAttribute('aria-labelledby',prefix+'-title');document.querySelector('#workspace').append(dialog);
 let record=null,pending=null,status=null;
 const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 function sync(){dialog.querySelectorAll('input,select,textarea,button').forEach(e=>e.disabled=ctx.isBusy()||!!pending);const retry=dialog.querySelector('[data-verify]');if(retry)retry.disabled=ctx.isBusy();}
 function close(){if(ctx.isBusy()||pending)return;dialog.close();}
 dialog.addEventListener('cancel',e=>{if(ctx.isBusy()||pending)e.preventDefault();});
 dialog.addEventListener('close',()=>{if(!dialog.open){record=null;dialog.replaceChildren();}});
 async function open(dni=null){
  if(pending)return;const [p,catalog]=await Promise.all([dni?rpc('marathon_patient_get',{p_dni:dni}):Promise.resolve({}),rpc('marathon_patient_catalog')]);record=dni?p:null;dialog.replaceChildren();
  const head=el('div');head.className='detail-head';const title=el('h2',dni?'Editar ficha del paciente':'Crear paciente');title.id=prefix+'-title';const cancel=el('button','Cerrar ficha');cancel.type='button';cancel.className='s';cancel.dataset.variant='ghost';cancel.onclick=close;head.append(title,cancel);dialog.append(head,el('p',dni?[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni:'Al guardar, el paciente quedará seleccionado. La ficha no crea un turno ni registra el movimiento de caja.'));
  const form=el('form');form.id=prefix+'-form';const grid=el('div');grid.className='form-grid';form.append(grid);
  const fields=[['dni','DNI','text'],['nombre','Nombre','text'],['segundo_nombre','Segundo nombre','text'],['apellido','Apellido','text'],['nacimiento','Fecha de nacimiento','date'],['sexo','Sexo','select'],['telefono','Teléfono','tel'],['email','Correo','email'],['domicilio','Domicilio','text'],['localidad','Localidad','text'],['provincia','Provincia','text'],['medico','Médico de cabecera','text'],['observaciones','Observaciones','textarea']];
  for(const [key,label,type]of fields){
   if(key==='telefono'){appendPatientPhone(grid,p,fieldPrefix);continue;}
   const box=el('label',label+(['dni','nombre','apellido'].includes(key)?' *':'')),input=el(type==='textarea'?'textarea':type==='select'?'select':'input');input.name=key;input.id=fieldPrefix+'-'+key;
   if(input.tagName==='INPUT')input.type=type;input.required=['dni','nombre','apellido'].includes(key);
   if(type==='select')for(const text of ['','Masculino','Femenino','Otro']){const o=el('option',text||'Sin especificar');o.value=text;input.append(o);}
   else input.maxLength=type==='textarea'?10000:key==='email'?254:500;
   if(key==='dni'){input.readOnly=!!dni;input.inputMode='numeric';input.pattern='[0-9]{1,12}';input.maxLength=12;}
   if(type==='select'&&p[key]&&![...input.options].some(o=>o.value===p[key])){const previous=el('option',p[key]);previous.value=p[key];input.append(previous);}
   if(type==='textarea')box.className='wide';input.value=p[key]??'';box.append(input);grid.append(box);
  }
  appendPatientCoverages(grid,catalog,p,fieldPrefix);const actions=el('div');actions.className='form-actions';const save=el('button',dni?'Guardar ficha':'Crear paciente');save.type='submit';save.className='b';save.dataset.variant='default';const back=el('button','Volver sin guardar');back.type='button';back.className='s';back.dataset.variant='ghost';back.id=prefix+'-cancel';back.onclick=close;actions.append(save,back);form.append(actions);
  status=el('p');status.setAttribute('role','status');form.append(status);form.onsubmit=e=>{e.preventDefault();if(ctx.isBusy()||pending||!form.reportValidity())return;let data;try{data=patientPayload(form);}catch(error){status.textContent=error.message;return;}pending={p_request_id:crypto.randomUUID(),p_data:data,p_version:record?.version??null};send();};dialog.append(form);dialog.showModal();sync();
 }
 async function send(){
  if(!pending||ctx.isBusy())return;ctx.setBusy(true);const request=pending;
  try{
   const reply=await rpc('marathon_patient_save',request,true);pending=null;dialog.close();
   ctx.message('Ficha del paciente guardada.');
   try{await ctx.onSaved(reply.dni);}catch{ctx.message('Ficha guardada. Volvé a consultar el paciente para ver sus datos actualizados.',true);}
  }catch(error){
   status.textContent=error.message;
   if(error.uncertain){if(!dialog.querySelector('[data-verify]')){const retry=el('button','Verificar guardado');retry.type='button';retry.className='s';retry.dataset.verify='';retry.onclick=send;status.after(retry);}}
   else{pending=null;dialog.querySelector('[data-verify]')?.remove();}
  }finally{ctx.setBusy(false);sync();}
 }
 return{open,sync,isPending:()=>!!pending,reset(){pending=null;record=null;if(dialog.open)dialog.close();dialog.replaceChildren();}};
}
