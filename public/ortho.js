import {DailyUI} from './daily.js?v=20261019-0110';
import {createAgendaPatientEditor} from './agenda-patient-editor.js?v=20261029-caja-pacientes';
export function createOrtho(ctx){
 const $=s=>document.querySelector(s),el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write),money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n||0));
 const admin=()=>ctx.getUser()?.role==='ADMIN',orthoOnly=()=>ctx.getUser()?.role==='SECRETARIA_ORTOPEDIA',locked=()=>ctx.isBusy()||!!pending||patientEditor.isPending();
 let tab='stock',sites=[],pages=[null],page=0,next=null,pending=null,filter={sede:'',query:'',dni:'',kind:''};
 let activePatientPicker=null;
 const patientEditor=createAgendaPatientEditor({...ctx,prefix:'ortho-patient-edit',onSaved:async dni=>{
  const picker=activePatientPicker;if(!picker?.active())return;
  const patient=await rpc('marathon_patient_get',{p_dni:dni});
  if(activePatientPicker===picker&&picker.active())picker.pick(patient);
 }});
 function button(text,fn,cls='s'){const b=el('button',text,cls);b.type='button';b.dataset.variant=cls==='b'?'default':'secondary';b.addEventListener('click',fn);return b;}
 function field(parent,key,label,value='',type='text',required=false){const l=el('label',label),i=el(type==='textarea'?'textarea':'input');i.name=key;i.id='r-'+key;if(type!=='textarea')i.type=type;i.value=value??'';i.required=required;if(['text','textarea'].includes(type))i.maxLength=type==='textarea'?2000:300;l.append(i);parent.append(l);return i;}
 function options(i,rows,blank){i.replaceChildren();for(const r of [...(blank!==undefined?[{id:'',label:blank}]:[]),...rows]){const o=el('option',r.label);o.value=r.id;i.append(o);}}
 function select(parent,key,label,rows,value='',blank){const l=el('label',label),i=el('select');i.id='r-'+key;i.name=key;options(i,rows,blank);i.value=value;l.append(i);parent.append(l);return i;}
 const mediums=[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}];
 function numeric(parent,key,label,value,min=0,max='9999999999.99',step='0.01'){const i=field(parent,key,label,value,'number',true);i.min=min;i.max=max;i.step=step;return i;}
 function sync(){patientEditor.sync();activePatientPicker?.sync();$('#ortho-previous').disabled=locked()||page===0;$('#ortho-next').disabled=locked()||!next;if($('#retry-ortho'))$('#retry-ortho').disabled=ctx.isBusy();$('#ortho-body').querySelectorAll('[data-allowed]').forEach(b=>b.disabled=locked()||b.dataset.allowed!=='true');}
 function modal(title){$('#ortho-body').replaceChildren();$('#ortho-error').textContent='';const head=el('div',undefined,'detail-head');head.append(el('h2',title),button('Cerrar',()=>{if(!locked())$('#ortho-dialog').close();}));$('#ortho-body').append(head);if(!$('#ortho-dialog').open)$('#ortho-dialog').showModal();return $('#ortho-body');}
 function form(parent,id,label,submit){const f=el('form');f.id=id;f.addEventListener('submit',e=>{e.preventDefault();if(!locked()&&f.reportValidity())submit(f);});parent.append(f);const b=el('button',label,'b');b.type='submit';return{f,finish:()=>{f.append(b);ctx.sync();}};}
 async function command(name,data,after=refresh,extra={}){if(locked())return;ctx.message('Guardando…');$('#ortho-error').textContent='';pending={name,args:{p_request_id:crypto.randomUUID(),p_data:data,...extra},after};await send();}
 async function send(){if(!pending||ctx.isBusy())return;ctx.setBusy(true);const task=pending;try{const reply=await rpc(task.name,task.args,true);pending=null;$('#ortho-dialog').close();try{await task.after(reply);ctx.message(reply.message);}catch{ctx.message('Guardado confirmado. Actualizá el listado para ver los cambios.',true);}}
 catch(e){ctx.message(e.message,true);$('#ortho-error').textContent=e.message;if(e.uncertain){if(!$('#retry-ortho')){const b=button('Verificar guardado',send);b.id='retry-ortho';$('#ortho-recovery').append(b);}}else pending=null;}
 finally{if(!pending)$('#retry-ortho')?.remove();ctx.setBusy(false);}}
 const oc=(action,data,after=refresh)=>command('marathon_ortho_command',data,after,{p_action:action});
 function show(){for(const n of ['home','patients','masters','agenda','wait','cash','ortho','catalog','reports','users']){$('#'+n+'-screen').hidden=n!=='ortho';$('#nav-'+n).className=n==='ortho'?'b':'';}}
 async function open(){show();sites=await rpc('marathon_ortho_sites');options($('#ortho-sede'),sites,'Todas las sedes');
  if(orthoOnly())options($('#ortho-actor'),[],'Todas las personas');
  else{const lookup=await rpc('marathon_daily_options');options($('#ortho-actor'),lookup.actors,'Todas las personas');}
  if(!$('#ortho-from').value)$('#ortho-from').value=new Date().toISOString().slice(0,7)+'-01';if(!$('#ortho-to').value)$('#ortho-to').value=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date());$('#ortho-sede').value=filter.sede;$('#ortho-tab-catalog').hidden=!admin();$('#ortho-new-product').hidden=!admin();$('#ortho-sale').textContent=orthoOnly()?'Venta':'Venta / alquiler';await list();}
 async function refresh(){page=0;pages=[null];await list();await ctx.refreshCash?.();}
 async function choose(which){tab=which;page=0;pages=[null];filter={...filter,query:'',dni:'',kind:''};$('#ortho-query').value='';$('#ortho-dni').value='';$('#ortho-kind').value='';await list();}
 async function list(){
  const stock=tab==='stock',catalog=tab==='catalog',history=tab==='history';$('#ortho-query-label').hidden=!stock&&!catalog;$('#ortho-dni-label').hidden=stock||catalog;$('#ortho-kind-label').hidden=!history;$('#ortho-sede-label').hidden=catalog;
  for(const id of ['ortho-from-label','ortho-to-label','ortho-actor-label'])$('#'+id).hidden=!history||(id==='ortho-actor-label'&&orthoOnly());$('#ortho-stock-label').hidden=!stock;
  for(const n of ['stock','catalog','history','returns','debts'])$('#ortho-tab-'+n).className=tab===n?'b':'s';
  let result;if(catalog)result=await rpc('marathon_ortho_catalog',{p_query:filter.query,p_state:'',p_after:pages[page],p_limit:50});else result=await rpc('marathon_ortho_search',{p_kind:tab,p_filters:{sede:filter.sede,query:stock?filter.query:filter.dni,stock_state:$('#ortho-stock-state').value,from:$('#ortho-from').value,to:$('#ortho-to').value,actor:$('#ortho-actor').value,operation:filter.kind},p_after:pages[page],p_limit:50});
  next=result.next;const panel=$('#ortho-list');panel.replaceChildren();
  if(catalog){for(const row of result.rows){const card=el('article',undefined,'turn-card');card.dataset.id=row.id;productCard(card,row);panel.append(card);}}
  else{const headers=stock?['Producto','Marca','Código','Sede','Disponible','Mínimo','Estado','Acciones']:tab==='returns'?['Paciente','Producto','Sede','Pendientes','Vence','Saldo','Acciones']:tab==='debts'?['Fecha','Paciente','Operación / producto','Total','Pagado','Saldo','Acciones']:['Fecha','Operación','Ingresos netos acumulados'];const body=DailyUI.table(panel,headers);
   for(const row of result.rows){const details=el('div');if(stock){productCard(details,row);const actions=details.querySelector('.form-actions');const available=Number(row.stock),minimum=Number(row.minimo),known=row.stock!==null&&row.stock!==undefined&&row.stock!==''&&Number.isFinite(available);const stockStatus=!known?'unknown':available<=0?'empty':available<=minimum?'low':'available';const state=!known?'Sin stock informado':stockStatus==='empty'?'Agotado':stockStatus==='low'?(available===minimum?'En mínimo':'Bajo mínimo'):'Disponible';DailyUI.row(body,[row.descripcion,row.marca||'—',row.codigo||row.id,row.sede,row.stock,row.minimo,state+' · '+row.estado,actions],{id:row.id,sede:row.sede,stockStatus});}
    else{historyCard(details,row);const actions=details.querySelector('.form-actions');const patient=row.paciente+' · DNI '+row.dni;
     if(tab==='returns')DailyUI.row(body,[patient,row.producto,row.sede,row.pending,row.devolucion_prevista,money(row.debt),actions],{id:row.id});
     else if(tab==='debts')DailyUI.row(body,[row.fecha,patient,row.tipo+' · '+row.producto,money(row.importe_total),money(row.paid),money(row.debt),actions],{id:row.id});
     else DailyUI.row(body,[row.fecha+' · '+String(row.hora).slice(0,5),details,money(row.income)],{id:row.id});}
   }
  }
  $('#ortho-summary').textContent=history?'Ingresos netos acumulados por operación: cobros menos reintegros, incluso si se registraron después de la fecha de la operación. Para movimientos por fecha usá Caja.':tab==='returns'?'Alquileres con unidades pendientes, sin limitar por fecha. La devolución no cancela la deuda.':tab==='debts'?'Ventas y alquileres con saldo pendiente, sin limitar por fecha.':'';
  $('#ortho-info').textContent=result.rows.length+' registros en esta página.';$('#ortho-page').textContent='Página '+(page+1);sync();
 }
 async function startOperation(mode){const panel=modal(mode==='transfer'?'Traslado entre sedes':'Venta / alquiler'),search=el('form');search.id='ortho-start-form';const typeOptions=mode==='transfer'?[{id:'transfer',label:'Traslado entre sedes'}]:orthoOnly()?[{id:'sale',label:'Venta'}]:[{id:'sale',label:'Venta'},{id:'rent',label:'Alquiler'}];const type=select(search,'start-type','Operación',typeOptions,mode==='transfer'?'transfer':'sale');field(search,'start-query','Producto, marca o código','','search').maxLength=100;select(search,'start-site','Sede de origen',sites,filter.sede,'Todas las sedes');const submit=el('button','Buscar productos','s');submit.type='submit';search.append(submit);panel.append(search);const results=el('div');panel.append(results);let cursor=null;
  async function load(after=null){const r=await rpc('marathon_ortho_search',{p_kind:'stock',p_filters:{query:$('#r-start-query').value.trim(),sede:$('#r-start-site').value},p_after:after,p_limit:30});cursor=r.next;results.replaceChildren();const body=DailyUI.table(results,['Producto','Sede','Disponible','Elegir']);for(const p of r.rows){const choose=button('Elegir',()=>ctx.work(()=>operationForm(type.value,p)));choose.disabled=p.estado!=='ACTIVO'||Number(p.stock)<1;choose.dataset.allowed=String(!choose.disabled);DailyUI.row(body,[p.descripcion+' · '+(p.marca||'')+' · '+(p.codigo||p.id),p.sede,p.stock,choose],{id:p.id,sede:p.sede});}if(cursor)results.append(button('Más productos',()=>ctx.work(()=>load(cursor))));if(!r.rows.length)results.append(el('p','No hay productos habilitados para estos filtros.'));}
  search.addEventListener('submit',e=>{e.preventDefault();ctx.work(()=>load());});await load();
 }
 function productCard(card,p){card.append(el('h3',p.descripcion),el('p',[p.pieza,p.talle,p.marca,p.codigo].filter(Boolean).join(' · ')),el('p',p.id+' · '+p.estado,'subtitle'),el('p',p.modalidad+' · Venta: '+(p.precio_venta===null?'sin precio':money(p.precio_venta))+' · Alquiler semanal: '+(p.precio_alquiler===null?'sin precio':money(p.precio_alquiler))));
  if(tab==='stock'){const note=el('p',p.sede+' · Stock disponible: '+p.stock+' · Mínimo: '+p.minimo);if(Number(p.stock)<=Number(p.minimo))note.className='ui-debt';card.append(note);}
  const actions=el('div',undefined,'form-actions');
  if(tab==='stock'&&p.estado==='ACTIVO'){
   if(p.modalidad.includes('VENTA'))actions.append(button('Vender',()=>ctx.work(()=>operationForm('sale',p))));
   if(p.modalidad.includes('ALQUILER')&&!orthoOnly())actions.append(button('Alquilar',()=>ctx.work(()=>operationForm('rent',p))));
   actions.append(button('Transferir',()=>ctx.work(()=>operationForm('transfer',p))));
   if(admin())for(const [key,label]of[['purchase','Comprar'],['adjust_in','Ajuste positivo'],['adjust_out','Ajuste negativo']])actions.append(button(label,()=>ctx.work(()=>operationForm(key,p))));
  }
  if(admin()){actions.append(button('Editar producto',()=>ctx.work(()=>productForm(p.id))),button('Configurar por sede',()=>ctx.work(()=>configForm(p.id))));}
  card.append(actions);
 }
 function historyCard(card,o){card.append(el('h3',o.tipo+' · '+o.producto),el('p',o.fecha+' · '+String(o.hora).slice(0,5)+' · '+o.sede+' · '+o.cantidad+' unidades'));if(o.dni)card.append(el('p','DNI '+o.dni+' · '+o.paciente));
  if(['VENTA','ALQUILER','COMPRA'].includes(o.tipo))card.append(el('p','Total: '+money(o.importe_total)+' · Pagado neto: '+money(o.paid)+' · Saldo: '+money(o.debt)));
  if(o.discount_rate!=null)card.append(el('p','Subtotal: '+money(o.subtotal)+' · Descuento: '+o.discount_rate+'% ('+money(o.discount_amount)+')'));
  if(o.tipo==='ALQUILER'){const line=el('p','Pendientes de devolución: '+o.pending+' · Fecha prevista: '+o.devolucion_prevista);const today=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());if(Number(o.pending)>0&&o.devolucion_prevista<today)line.className='ui-debt';card.append(line);}
  if(o.transfer_id)card.append(el('p','Traslado vinculado: '+o.transfer_id,'subtitle'));if(o.actor)card.append(el('p','Registró: '+o.actor,'subtitle'));if(o.observaciones)card.append(el('p',o.observaciones));const actions=el('div',undefined,'form-actions');
  if(o.tipo==='ALQUILER'&&Number(o.pending)>0)actions.append(button('Devolver unidades',()=>ctx.work(()=>settleForm('return',o.id))));
  if(['VENTA','ALQUILER'].includes(o.tipo)){if(Number(o.debt)>0)actions.append(button('Registrar cobro',()=>ctx.work(()=>settleForm('pay',o.id))));if(Number(o.paid)>0)actions.append(button('Registrar reintegro',()=>ctx.work(()=>settleForm('refund',o.id))));}
  if(o.tipo==='COMPRA'&&Number(o.debt)>0&&admin())actions.append(button('Pagar compra',()=>ctx.work(()=>settleForm('purchase_pay',o.id))));
  if(o.tipo==='VENTA'){if(o.anulada)card.append(el('p','ANULADA','ui-debt'));else{const voidBtn=button('Anular venta',()=>ctx.work(()=>voidForm(o.id)));voidBtn.dataset.variant='destructive';actions.append(voidBtn);}}
  card.append(actions);
 }
 async function productForm(id=null){if(!admin())throw Error('Solo ADMIN puede administrar productos.');const p=id?await rpc('marathon_ortho_product',{p_id:id}):null;const panel=modal(p?'Editar producto':'Nuevo producto');const{f,finish}=form(panel,'ortho-product-form','Guardar producto',()=>{const data=Object.fromEntries(new FormData(f));for(const k of ['costo','precio_venta','precio_alquiler'])data[k]=data[k]===''?null:Number(data[k]);if(p){data.id=p.id;data.version=p.version;}command('marathon_ortho_product_save',data,async()=>{tab='catalog';await refresh();});});
  const grid=el('div',undefined,'form-grid');f.append(grid);for(const[k,label]of[['pieza','Pieza'],['talle','Talle'],['marca','Marca'],['descripcion','Descripción'],['codigo','Código']])field(grid,k,label,p?.[k]||'','text',['pieza','descripcion'].includes(k)).maxLength={pieza:100,talle:60,marca:100,descripcion:300,codigo:80}[k];select(grid,'modalidad','Modalidad',['VENTA','ALQUILER','VENTA Y ALQUILER'].map(x=>({id:x,label:x})),p?.modalidad||'VENTA Y ALQUILER');
  for(const[k,label]of[['costo','Costo de compra (opcional)'],['precio_venta','Precio de venta'],['precio_alquiler','Precio semanal de alquiler']]){const i=field(grid,k,label,p?.[k]??'','number');i.min=0;i.max='9999999999.99';i.step='0.01';}
  select(grid,'estado','Estado',[{id:'ACTIVO',label:'Activo'},{id:'INACTIVO',label:'Inactivo'}],p?.estado||'ACTIVO');field(grid,'observaciones','Observaciones',p?.observaciones||'','textarea').maxLength=1000;finish();
 }
 async function configForm(id){const p=await rpc('marathon_ortho_product',{p_id:id});const panel=modal('Configurar stock · '+p.descripcion);panel.append(el('p','Habilitá una sede, definí el mínimo y cargá unidades iniciales una sola vez. Después usá compra o ajuste.','subtitle'));
  const{f,finish}=form(panel,'ortho-config-form','Guardar configuración',()=>{const site=$('#r-sede').value,old=p.sites.find(s=>s.sede===site),data={product:p.id,sede:site,minimo:Number($('#r-minimo').value)};if(old)data.version=old.version;if($('#r-inicial').value!=='')data.inicial=Number($('#r-inicial').value);command('marathon_ortho_config',data);});
  const s=select(f,'sede','Sede',sites,'','Elegir sede');s.required=true;numeric(f,'minimo','Stock mínimo',0,0,1000000,1);const initial=field(f,'inicial','Cantidad inicial (dejar vacío para no cargar)','','number');initial.min=0;initial.max=1000000;initial.step=1;
  const info=el('p','Elegí la sede.','subtitle');f.append(info);s.addEventListener('change',()=>{const old=p.sites.find(x=>x.sede===s.value);$('#r-minimo').value=old?.minimo??0;initial.value='';info.textContent=old?'Stock actual: '+old.stock+(old.initial_loaded?' · Carga inicial ya realizada.':''):'Sede todavía no habilitada para este producto.';});finish();
 }
 function patientPicker(parent){
  let patient=null,generation=0;const search=el('form');search.id='ortho-patient-search';
  const query=field(search,'patient-query','Buscar paciente por DNI o nombre','','search',true);query.maxLength=100;
  const find=el('button','Buscar paciente','s');find.type='submit';search.append(find);
  const actions=el('div',undefined,'form-actions');
  const create=button('Nueva ficha',()=>{if(!locked())ctx.work(()=>patientEditor.open());});create.id='ortho-patient-create';
  const edit=button('Editar ficha',()=>{if(!locked()&&patient)ctx.work(()=>patientEditor.open(patient.dni));});edit.id='ortho-patient-edit';actions.append(create,edit);
  const results=el('div');results.id='ortho-patient-results';results.className='list-items';
  const selected=el('p','Seleccioná un paciente de los resultados.');selected.id='ortho-patient-selected';selected.setAttribute('role','status');
  const status=el('p');status.setAttribute('role','status');parent.append(search,actions,results,selected,status);
  const active=()=>query.isConnected&&$('#ortho-dialog').open;
  const syncPicker=()=>{if(!active())return;find.disabled=create.disabled=query.disabled=locked();edit.disabled=locked()||!patient;};
  const pick=p=>{if(!active())return;generation++;patient=p;query.value='';results.replaceChildren();status.textContent='';selected.textContent=p?[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni:'Seleccioná un paciente de los resultados.';syncPicker();};
  activePatientPicker={active,pick,sync:syncPicker};syncPicker();
  query.addEventListener('input',()=>{generation++;patient=null;results.replaceChildren();status.textContent='';selected.textContent='Seleccioná un paciente de los resultados.';syncPicker();});
  search.addEventListener('submit',e=>{e.preventDefault();if(locked()||!search.reportValidity())return;const term=query.value.trim();if(!term){status.textContent='Escribí nombre, apellido o DNI para buscar.';return;}
   ctx.work(async()=>{const request=++generation;patient=null;results.replaceChildren();selected.textContent='Seleccioná un paciente de los resultados.';status.textContent='Buscando pacientes…';
    try{const data=await rpc('marathon_patient_search',{p_query:term,p_after:null,p_limit:10});if(request!==generation||!active())return;
     for(const p of data.rows)results.append(button([p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+p.dni,()=>{if(!locked()&&request===generation)pick(p);}));
     status.textContent=data.rows.length?(data.next?'Hay más resultados. Precisá el nombre o el DNI.':'Elegí un paciente para continuar.'):'No hay coincidencias. Podés cargar una nueva ficha.';
    }catch(error){if(request===generation&&active())status.textContent='No se pudo buscar al paciente. '+error.message;}
   });
  });return()=>patient;
 }
 async function operationForm(action,row){const p=await rpc('marathon_ortho_product',{p_id:row.id});const site=p.sites.find(s=>s.sede===row.sede);if(!site)throw Error('El producto no está habilitado en esa sede.');const labels={sale:'Venta',rent:'Alquiler',purchase:'Compra',adjust_in:'Ajuste positivo',adjust_out:'Ajuste negativo',transfer:'Traslado entre sedes'};const panel=modal(labels[action]+' · '+p.descripcion);panel.append(el('p',row.sede+' · Stock actual: '+site.stock));const discountable=['sale','rent'].includes(action),showPatient=discountable&&!orthoOnly(),getPatient=showPatient?patientPicker(panel):()=>null;
  const{f,finish}=form(panel,'ortho-operation-form','Confirmar operación',()=>{const patient=getPatient();if(action==='rent'&&!patient){$('#ortho-error').textContent='Buscá y seleccioná un paciente.';return;}
   const data={product:p.id,product_version:p.version,sede:row.sede,cantidad:Number($('#r-cantidad').value),observaciones:$('#r-observaciones').value};if(discountable){data.discount_rate=Number($('#r-discount_rate').value);if(patient)data.dni=patient.dni;}if(action==='rent')data.semanas=Number($('#r-semanas').value);if(['sale','rent','purchase'].includes(action)){data.pago=Number($('#r-pago').value);data.medio=$('#r-medio').value;}if(action==='transfer')data.destino=$('#r-destino').value;oc(action,data);
  });numeric(f,'cantidad','Cantidad',1,1,10000,1);if(action==='rent')numeric(f,'semanas','Semanas de alquiler',1,1,520,1);
  if(discountable)numeric(f,'discount_rate','Descuento (%)',0,0,100,'0.01');
  const estimate=el('p');estimate.id='ortho-estimate';f.append(estimate);
  if(['sale','rent','purchase'].includes(action)){numeric(f,'pago',action==='purchase'?'Importe pagado ahora':'Importe recibido ahora',0);select(f,'medio','Medio',mediums,'EFECTIVO');const update=()=>{const price=action==='sale'?p.precio_venta:action==='rent'?p.precio_alquiler:p.costo;const subtotal=Math.round(Number(price)*Number($('#r-cantidad').value)*(action==='rent'?Number($('#r-semanas').value):1)*100)/100,rate=discountable?Number($('#r-discount_rate').value):0,discount=Math.round((subtotal*rate/100+Number.EPSILON)*100)/100,total=Math.round((subtotal-discount)*100)/100;estimate.textContent=price===null?'Falta precio o costo en el catálogo.':(discountable?'Subtotal: '+money(subtotal)+' · Descuento: '+rate+'% ('+money(discount)+') · ':'')+'Total: '+money(total);$('#r-pago').max=String(Math.max(0,total));};$('#r-cantidad').addEventListener('input',update);$('#r-semanas')?.addEventListener('input',update);$('#r-discount_rate')?.addEventListener('input',update);update();}
  if(action==='transfer')select(f,'destino','Sede de destino',sites.filter(s=>s.id!==row.sede),'','Elegir sede destino').required=true;
  field(f,'observaciones',action.startsWith('adjust')||action==='transfer'?'Motivo obligatorio':'Observaciones','','textarea',action.startsWith('adjust')||action==='transfer');finish();
 }
 async function settleForm(action,id){const o=await rpc('marathon_ortho_get',{p_id:id}),panel=modal(({return:'Devolver unidades',pay:'Cobrar saldo',refund:'Registrar reintegro',purchase_pay:'Pagar compra'})[action]);panel.append(el('p',o.producto+' · '+o.sede),el('p','Total: '+money(o.importe_total)+' · Pagado neto: '+money(o.paid)+' · Saldo: '+money(o.debt)));
  if(o.discount_rate!=null)panel.append(el('p','Subtotal: '+money(o.subtotal)+' · Descuento: '+o.discount_rate+'% ('+money(o.discount_amount)+')'));
  const{f,finish}=form(panel,'ortho-settle-form','Registrar',()=>{const data={id:o.id,version:o.version,observaciones:$('#r-observaciones').value};if(action==='return')data.cantidad=Number($('#r-cantidad').value);else{data.monto=Number($('#r-monto').value);data.medio=$('#r-medio').value;}oc(action,data);});
  if(action==='return'){panel.append(el('p','La devolución recupera stock y conserva la deuda.'));numeric(f,'cantidad','Unidades a devolver',o.pending,1,o.pending,1);}else{numeric(f,'monto','Importe',action==='refund'?o.paid:o.debt,'0.01');select(f,'medio','Medio',mediums,'EFECTIVO');}field(f,'observaciones','Observaciones','','textarea');finish();
 }
 async function voidForm(id){const o=await rpc('marathon_ortho_get',{p_id:id}),panel=modal('Anular venta · '+o.producto);
  panel.append(el('p',o.sede+' · '+o.cantidad+' unidades · Total: '+money(o.importe_total)),el('p','Repone el stock vendido. Si la venta ya tiene un cobro registrado, no se puede anular desde acá: primero hay que reintegrar el pago.','subtitle'));
  const{f,finish}=form(panel,'ortho-void-form','Anular venta',()=>oc('void',{id:o.id,version:o.version,motivo:$('#r-motivo').value}));
  field(f,'motivo','Motivo','','textarea',true).minLength=3;finish();f.querySelector('button[type=submit]').dataset.variant='destructive';
 }
 function openReverse(m){const panel=modal('Contrasiento de ortopedia');panel.append(el('p','Se reintegrarán '+money(m.monto)+' en '+m.medio+'. El cobro original se conserva.'));const{f,finish}=form(panel,'ortho-reverse-form','Registrar contrasiento',()=>oc('reverse',{id:m.id,version:m.version,motivo:$('#r-motivo').value},()=>ctx.refreshCash()));field(f,'motivo','Motivo','','textarea',true).minLength=3;finish();f.querySelector('button[type=submit]').dataset.variant='destructive';}
 $('#ortho-dialog').addEventListener('cancel',e=>{if(locked())e.preventDefault();});
 $('#ortho-filter').addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{filter={sede:$('#ortho-sede').value,query:$('#ortho-query').value.trim(),dni:$('#ortho-dni').value.trim(),kind:$('#ortho-kind').value};page=0;pages=[null];await list();});});
 for(const n of ['stock','catalog','history','returns','debts'])$('#ortho-tab-'+n).addEventListener('click',()=>ctx.work(()=>choose(n)));
 $('#ortho-sale').addEventListener('click',()=>ctx.work(()=>startOperation('sale')));$('#ortho-transfer').addEventListener('click',()=>ctx.work(()=>startOperation('transfer')));
 $('#ortho-new-product').addEventListener('click',()=>ctx.work(()=>productForm()));
 for(const n of ['previous','next'])$('#ortho-'+n).addEventListener('click',()=>ctx.work(async()=>{if(n==='next'){if(!next)return;pages=pages.slice(0,page+1);pages.push(next);page++;}else if(page>0)page--;await list();}));
 return{open,openReverse,sync,isPending:()=>!!pending||patientEditor.isPending(),reset:()=>{patientEditor.reset();activePatientPicker=null;pending=null;$('#ortho-new-product').hidden=true;$('#ortho-tab-catalog').hidden=true;tab='stock';sites=[];pages=[null];page=0;next=null;filter={sede:'',query:'',dni:'',kind:''};$('#ortho-dialog').close();for(const id of ['ortho-body','ortho-recovery','ortho-list'])$('#'+id).replaceChildren();for(const id of ['ortho-error','ortho-info','ortho-summary','ortho-page'])$('#'+id).textContent='';$('#ortho-query').value='';$('#ortho-dni').value='';$('#ortho-kind').value='';$('#ortho-sede').replaceChildren();}};
}
