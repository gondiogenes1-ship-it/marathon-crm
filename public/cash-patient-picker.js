import {createAgendaPatientEditor} from './agenda-patient-editor.js?v=20261029-caja-pacientes';

// Selección opcional. Solo el DNI seleccionado forma parte del movimiento.
export function createCashPatientPicker(ctx){
 let host=null,hidden=null,query=null,results=null,status=null,selection=null,generation=0;
 const el=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 const rpc=(name,args={})=>ctx.getApi().rpc(name,args);
 const editor=createAgendaPatientEditor({...ctx,prefix:'cash-patient-edit',onSaved:async dni=>{if(!host?.isConnected)return;pick(await rpc('marathon_patient_get',{p_dni:dni}));}});
 function button(text,fn,variant='secondary'){const b=el('button',text);b.type='button';b.className='s';b.dataset.variant=variant;b.onclick=fn;return b;}
 function pick(p){if(!host?.isConnected)return;generation++;hidden.value=p?.dni||'';query.value='';results.replaceChildren();selection.textContent=p?[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni:'Sin paciente asociado (opcional).';selection.dataset.selected=String(!!p);status.textContent='';sync();host.dispatchEvent(new Event('input',{bubbles:true}));}
 function sync(){editor.sync();if(!host?.isConnected)return;const disabled=ctx.isBusy()||ctx.isPending()||editor.isPending();host.querySelectorAll('button,input[type=search]').forEach(b=>{b.disabled=disabled||b.dataset.requiresPatient==='true'&&!hidden.value;});}
 async function search(){
  const term=query.value.trim();if(!term){status.textContent='Escribí nombre, apellido o DNI para buscar.';return;}
  const request=++generation;results.replaceChildren();status.textContent='Buscando pacientes…';
  try{const data=await rpc('marathon_patient_search',{p_query:term,p_after:null,p_limit:10});if(request!==generation||!host?.isConnected)return;
   for(const p of data.rows)results.append(button([p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni,()=>{if(!ctx.isBusy())pick(p);}));
   status.textContent=data.rows.length?(data.next?'Hay más coincidencias. Precisá el nombre o el DNI.':'Elegí un paciente de los resultados.'):'No hay coincidencias. Podés crear la ficha o continuar sin asociar paciente.';
  }catch(error){if(request===generation)status.textContent=error.message;throw error;}
 }
 function mount(form,patient=null){
  generation++;host=el('section');host.className='cash-patient-picker';host.setAttribute('aria-label','Paciente del movimiento (opcional)');
  const title=el('h3','Paciente (opcional)'),label=el('label','Buscar entre pacientes registrados');query=el('input');query.type='search';query.id='cash-patient-query';query.maxLength=100;query.placeholder='Nombre, apellido o DNI';label.htmlFor=query.id;label.append(query);
  hidden=el('input');hidden.type='hidden';hidden.name='dni';hidden.id='o-dni';hidden.value='';
  const actions=el('div');actions.className='form-actions';const find=button('Buscar paciente',()=>ctx.work(search));
  const create=button('Crear paciente',()=>ctx.work(()=>editor.open()));
  const edit=button('Editar ficha',()=>ctx.work(()=>editor.open(hidden.value)));edit.dataset.requiresPatient='true';
  const clear=button('Quitar paciente',()=>{if(!ctx.isBusy())pick(null);},'ghost');clear.dataset.requiresPatient='true';
  actions.append(find,create,edit,clear);results=el('div');results.id='cash-patient-results';selection=el('p','Sin paciente asociado (opcional).');selection.id='cash-patient-selected';status=el('p');status.setAttribute('role','status');
  query.addEventListener('input',()=>{generation++;hidden.value='';results.replaceChildren();selection.textContent='Sin paciente asociado (opcional).';selection.dataset.selected='false';status.textContent='';sync();});
  query.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();ctx.work(search);}});
  host.append(title,label,hidden,actions,results,selection,status);form.append(host);if(patient)pick(patient);else sync();
 }
 return {mount,sync,isPending:()=>editor.isPending(),reset(){generation++;editor.reset();host=null;hidden=null;query=null;results=null;status=null;selection=null;}};
}
