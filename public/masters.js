import {createSharedSpaceSettings} from './shared-space.js?v=20261028-0131-espacio';
// Administración de catálogos. La autorización real se verifica en las RPC.
export function createMasters(ctx){
 const $=s=>document.querySelector(s);let entity='therapy',record=null,options={sedes:[],therapies:[]},pages=[null],page=0,next=null,query='',pending=null;
 const sharedSpace=createSharedSpaceSettings(ctx);
 const labels={sede:'Sedes',therapy:'Terapias',professional:'Profesionales'};
 const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const action=(text,fn,cls='s')=>{const b=el('button',text,cls);b.type='button';b.addEventListener('click',fn);return b;};
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 const locked=()=>ctx.isBusy()||!!pending;
 function sync(){sharedSpace.sync();
  $('#master-previous').disabled=locked()||page===0;$('#master-next').disabled=locked()||!next;
  if($('#retry-master'))$('#retry-master').disabled=ctx.isBusy();
 }
 function show(){
  $('#patients-screen').hidden=true;$('#masters-screen').hidden=false;
  $('#nav-patients').className='';$('#nav-masters').className='b';
 }
 async function open(){if(ctx.getUser()?.role!=='ADMIN')throw Error('Solo el administrador puede mantener estos datos.');show();options=await rpc('marathon_master_options');await list();await sharedSpace.load();}
 async function list(){
  const result=await rpc('marathon_master_list',{p_entity:entity,p_query:query,p_after:pages[page],p_limit:50});next=result.next;
  $('#master-list').replaceChildren();
  for(const r of result.rows){const b=action(r.label,()=>ctx.work(()=>load(r.id)),'patient-item');b.dataset.id=r.id;b.setAttribute('aria-pressed',String((record?.id||record?.nombre)===r.id));b.append(el('small',r.id+' · '+r.estado));$('#master-list').append(b);}
  $('#master-info').textContent=result.rows.length+' registros en esta página.';$('#master-page').textContent='Página '+(page+1);sync();
 }
 async function load(id){options=await rpc('marathon_master_options');const r=await rpc('marathon_master_get',{p_entity:entity,p_id:id});render(r);ctx.message('');}
 function field(form,key,title,value='',type='text',required=false,max=100){
  const label=el('label',title);const input=el(type==='textarea'?'textarea':'input');input.name=key;input.id='m-'+key;
  if(type!=='textarea')input.type=type;input.value=value??'';input.required=required;if(type==='text'||type==='textarea')input.maxLength=max;
  label.append(input);form.append(label);return input;
 }
 function select(form,key,title,values,value){const label=el('label',title);const input=el('select');input.name=key;input.id='m-'+key;for(const [id,text] of values){const o=el('option',text);o.value=id;input.append(o);}input.value=String(value??values[0]?.[0]??'');label.append(input);form.append(label);return input;}
 function hourRow(container,h={}){
  if(container.children.length>=40){ctx.message('Se admiten hasta 40 horarios.',true);return;}
  const row=el('div',undefined,'master-hour');row.dataset.id=h.id||'';
  select(row,'sede','Sede',[['','Elegir sede'],...options.sedes.filter(s=>s.estado==='ACTIVO').map(s=>[s.id,s.label])],h.sede||'');
  select(row,'day','Día',[[1,'Lunes'],[2,'Martes'],[3,'Miércoles'],[4,'Jueves'],[5,'Viernes'],[6,'Sábado'],[0,'Domingo']],h.day??1);
  const start=field(row,'start','Desde',h.start||'09:00','time',true);start.step='60';const end=field(row,'end','Hasta',h.end||'10:00','time',true);end.step='60';
  row.append(action('Quitar horario',()=>{if(!locked())row.remove();}));row.querySelectorAll('[id]').forEach(input=>input.removeAttribute('id'));container.append(row);
 }
 function render(r=null){
  record=r;const panel=$('#master-detail');panel.replaceChildren();panel.append(el('h2',(r?'Editar ':'Crear ')+({sede:'sede',therapy:'terapia',professional:'profesional'})[entity]));
  if(r)panel.append(el('p','ID: '+(r.id||r.nombre),'subtitle'));
  const form=el('form');form.id='master-form';const grid=el('div',undefined,'form-grid');form.append(grid);
  if(entity==='sede'){
   const name=field(grid,'nombre','Nombre de la sede',r?.nombre,'text',true,40);name.readOnly=!!r;
   field(grid,'direccion','Dirección',r?.direccion,'text',false,160);field(grid,'telefono','Teléfono',r?.telefono,'tel',false,30);field(grid,'observaciones','Observaciones',r?.observaciones,'textarea',false,300);
  }else if(entity==='therapy'){
   field(grid,'nombre','Nombre de terapia',r?.nombre,'text',true,100);field(grid,'especialidad','Especialidad',r?.especialidad,'text',false,100);
   const duration=field(grid,'duracion_min','Duración (minutos)',r?.duracion_min??60,'number',true);duration.min=5;duration.max=480;duration.step=1;
   const cap=field(grid,'capacidad','Pacientes simultáneos',r?.capacidad??1,'number',true);cap.min=1;cap.max=200;cap.step=1;
  }else{
   field(grid,'nombre','Nombre',r?.nombre,'text',true,60);field(grid,'segundo_nombre','Segundo nombre',r?.segundo_nombre,'text',false,60);field(grid,'apellido','Apellido',r?.apellido,'text',true,60);field(grid,'matricula','Matrícula',r?.matricula,'text',false,40);field(grid,'especialidad','Especialidad',r?.especialidad,'text',true,80);
   const therapies=el('fieldset');therapies.className='wide';therapies.append(el('legend','Terapias que realiza'));
   if(!options.therapies.length)therapies.append(el('p','Creá primero las terapias que atiende este profesional.','subtitle'));
   for(const t of options.therapies){const label=el('label',undefined,'therapy-check');const input=el('input');input.type='checkbox';input.name='therapy_ids';input.value=t.id;input.checked=(r?.therapy_ids||[]).includes(t.id);label.append(input,document.createTextNode(t.label+(t.estado==='INACTIVO'?' (inactiva)':'')));therapies.append(label);}form.append(therapies);
   form.append(el('h3','Horarios de atención'));const hours=el('div');hours.id='master-hours';form.append(hours);
   if(!options.sedes.some(s=>s.estado==='ACTIVO'))form.append(el('p','Creá una sede activa antes de agregar horarios.','subtitle'));
   for(const h of r?.hours||[])hourRow(hours,h);
   form.append(action('+ Agregar horario',()=>{if(!locked()){hourRow(hours);ctx.sync();}}));
  }
  select(grid,'estado','Estado',[['ACTIVO','Activo'],['INACTIVO','Inactivo']],r?.estado||'ACTIVO');
  const actions=el('div',undefined,'form-actions');const save=el('button','Guardar','b');save.type='submit';actions.append(save);
  if(r)actions.append(action('Volver a cargar',()=>ctx.work(()=>load(r.id||r.nombre))));
  actions.append(action('Cerrar',()=>{if(!locked()){record=null;panel.replaceChildren();}}));form.append(actions);form.addEventListener('submit',submit);panel.append(form);ctx.sync();
 }
 async function submit(event){
  event.preventDefault();if(locked())return;const form=event.currentTarget;if(!form.reportValidity())return;
  const values=new FormData(form);const data={};
  for(const [key,value] of values){if(!['therapy_ids','sede','day','start','end'].includes(key))data[key]=value;}
  if(record)data.id=record.id||record.nombre;
  if(entity==='therapy'){data.duracion_min=Number(data.duracion_min);data.capacidad=Number(data.capacidad);}
  if(entity==='professional'){
   data.therapy_ids=values.getAll('therapy_ids');data.hours=[...$('#master-hours').children].map(row=>({id:row.dataset.id,sede:row.querySelector('[name=sede]').value,day:Number(row.querySelector('[name=day]').value),start:row.querySelector('[name=start]').value,end:row.querySelector('[name=end]').value}));
  }
  // La confirmación usa una huella que se vuelve a verificar dentro de la transacción.
  ctx.setBusy(true);
  try{
   if(record?.estado==='ACTIVO'&&data.estado==='INACTIVO'){
    const impact=await rpc('marathon_master_preview',{p_entity:entity,p_id:data.id});
    if(impact.token){if(!window.confirm('Este registro tiene '+impact.turn_count+' turnos futuros pendientes y '+impact.wait_count+' pedidos de espera abiertos. Se conservarán. ¿Querés inactivarlo?'))return;data.inactive_token=impact.token;}
   }
   pending={p_request_id:crypto.randomUUID(),p_entity:entity,p_data:data,p_version:record?.version??null};
  }catch(e){ctx.message(e.message,true);return;}finally{ctx.setBusy(false);}
  await send();
 }
 async function send(){
  if(!pending||ctx.isBusy())return;ctx.setBusy(true);
  try{
   const reply=await rpc('marathon_master_save',pending,true);pending=null;
   try{await load(reply.id);page=0;pages=[null];await list();ctx.message(reply.message);
    if(entity==='professional'){try{const c=await rpc('marathon_profesional_horarios_conflicto',{p_prof:reply.id});if(c.rows&&c.rows.length){const det=c.rows.map(x=>x.paciente+' ('+['Dom','Lun','Mar','Mié','Jue','Vie','Sáb'][x.dia]+' '+x.hora+')').join('; ');ctx.message('Guardado. ATENCIÓN: '+c.rows.length+' turno(s) quedaron fuera de la agenda del profesional: '+det+'. Revisalos en Turnos → «Horarios a revisar».',true);}}catch{}}
   }catch{ctx.message('Guardado confirmado. Volvé a cargar el listado para ver los cambios.',true);}
  }catch(e){if(e.uncertain){ctx.message(e.message,true);if(!$('#retry-master')){const retry=action('Verificar guardado',send);retry.id='retry-master';$('#master-detail').append(retry);}}else{pending=null;ctx.message(e.message,true);}}
  finally{if(!pending)$('#retry-master')?.remove();ctx.setBusy(false);}
 }
 $('#master-entity').addEventListener('change',()=>ctx.work(async()=>{entity=$('#master-entity').value;page=0;pages=[null];next=null;record=null;$('#master-detail').replaceChildren();$('#master-title').textContent=labels[entity];await list();}));
 $('#master-search-form').addEventListener('submit',event=>{event.preventDefault();ctx.work(async()=>{query=$('#master-search').value.trim();page=0;pages=[null];await list();});});
 $('#master-new').addEventListener('click',()=>ctx.work(async()=>{options=await rpc('marathon_master_options');render();ctx.message('');}));
 $('#master-next').addEventListener('click',()=>ctx.work(async()=>{if(!next)return;pages=pages.slice(0,page+1);pages.push(next);page++;await list();}));
 $('#master-previous').addEventListener('click',()=>ctx.work(async()=>{if(page>0){page--;await list();}}));
 return {open,sync,isPending:()=>!!pending||sharedSpace.isPending(),reset:()=>{sharedSpace.reset();pending=null;record=null;options={sedes:[],therapies:[]};pages=[null];page=0;next=null;query='';entity='therapy';$('#master-entity').value=entity;$('#master-title').textContent=labels[entity];$('#master-search').value='';$('#master-list').replaceChildren();$('#master-detail').replaceChildren();}};
}
