// Edición de egresos con vista previa y control de usuario activo en la base.
export async function openEgresoEditor({ctx,rpc,modal,execute,refresh},id){
 const [info,options]=await Promise.all([rpc('marathon_egreso_edit_get',{p_id:id}),rpc('marathon_daily_options')]),m=info.movement;
 const el=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
 const money=n=>Number(n).toLocaleString('es-AR',{style:'currency',currency:'ARS'});
 const panel=modal('Editar egreso'),form=el('form');form.className='saldo-form';form.id='egreso-edit-form';panel.append(form);
 form.append(el('p','Podés corregir los datos del egreso. El original queda en el historial de la edición.'));
 const grid=el('div');grid.className='saldo-form-grid';form.append(grid);
 function field(parent,key,label,type,value,required=false){const wrap=el('label',label),input=el(type==='select'?'select':type==='textarea'?'textarea':'input');input.id='egreso-edit-'+key;input.name=key;if(!['select','textarea'].includes(type))input.type=type;input.required=required;input.value=value??'';wrap.htmlFor=input.id;wrap.append(input);parent.append(wrap);return input;}
 function select(parent,key,label,rows,value,blank){const n=field(parent,key,label,'select','');for(const r of [...(blank!==undefined?[{id:'',label:blank}]:[]),...rows]){const o=el('option',r.label);o.value=r.id;n.append(o);}n.value=value||'';return n;}
 const kind=select(grid,'subtipo','Subtipo',[...(!m.subtipo?[{id:'CONSERVAR',label:'Conservar el circuito del egreso histórico'}]:[]),{id:'OTRO_EGRESO',label:'Otro egreso'},{id:'GASTO_GENERAL',label:'Gasto general'},{id:'PAGO_PROFESIONAL',label:'Pago a profesional'}],m.subtipo||'CONSERVAR');
 const amount=field(grid,'monto','Importe (ARS)','number',m.monto,true);amount.min='0.01';amount.step='0.01';amount.max='9999999999.99';
 select(grid,'medio','Medio',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],m.medio);
 select(grid,'sede','Sede',options.sedes,m.sede,'Elegir sede').required=true;
 field(grid,'fecha','Fecha','date',m.fecha,true);const originalHour=String(m.hora).slice(0,12),hour=field(grid,'hora','Hora','time',originalHour,true);hour.step='0.001';
 const extra=el('div');extra.className='saldo-form-grid';form.append(extra);
 field(extra,'categoria','Categoría (opcional)','text',m.categoria).maxLength=100;
 const association=select(extra,'asociacion','Profesional o secretaría asociada',[
 ...options.professionals.map(x=>({id:'P:'+x.id,label:'Profesional · '+x.label})),
 ...(options.secretaries||[]).map(x=>({id:'S:'+x.id,label:'Secretaría · '+x.label}))],m.profesional_asociado_id?'P:'+m.profesional_asociado_id:m.secretaria_asociada?'S:'+m.secretaria_asociada:'','Sin asociación manual');
 select(extra,'terapia','Terapia asociada',options.therapies,m.terapia_asociada_id,'Sin terapia');
 form.append(el('small','Pago a profesional requiere elegir profesional y terapia.'));
 field(form,'concepto','Concepto','text',m.concepto,true).maxLength=200;
 field(form,'observaciones','Observaciones','textarea',m.observaciones_legacy).maxLength=1000;
 const reason=field(form,'motivo','Motivo obligatorio de la edición','textarea','',true);reason.minLength=3;reason.maxLength=1000;
 const reviewButton=el('button','Revisar edición');reviewButton.type='button';reviewButton.className='s';form.append(reviewButton);
 const review=el('section');review.className='saldo-review';review.setAttribute('aria-live','polite');form.append(review);
 const status=el('p');status.setAttribute('role','status');form.append(status);
 const save=el('button','Confirmar corrección');save.type='submit';save.className='b';save.disabled=true;save.dataset.allowed='false';form.append(save);
 let proposal=null,generation=0;
 const invalidate=()=>{generation++;proposal=null;save.disabled=true;save.dataset.allowed='false';review.replaceChildren();status.textContent='Volvé a revisar la edición antes de confirmar.';};
 const data=()=>{const d=Object.fromEntries(new FormData(form));d.id=m.id;d.version=m.version;if(d.hora===originalHour)d.hora=m.hora;delete d.asociacion;d.profesional=association.value.startsWith('P:')?association.value.slice(2):'';d.secretaria=association.value.startsWith('S:')?association.value.slice(2):'';if(d.subtipo==='PAGO_PROFESIONAL'&&(!d.profesional||!d.terapia))throw Error('Pago a profesional requiere elegir profesional y terapia.');return d;};
 const pretty=(k,v)=>k==='monto'?money(v):k==='medio'?({EFECTIVO:'Efectivo',TRANSFERENCIA:'Transferencia'}[v]||v):k==='subtipo'?({OTRO_EGRESO:'Otro egreso',GASTO_GENERAL:'Gasto general',PAGO_PROFESIONAL:'Pago a profesional'}[v]||'Sin subtipo'):k==='profesional_asociado_id'?(options.professionals.find(x=>x.id===v)?.label||'Sin asociación manual'):k==='terapia_asociada_id'?(options.therapies.find(x=>x.id===v)?.label||'Sin terapia'):v||'—';
 form.addEventListener('input',invalidate);form.addEventListener('change',invalidate);
 reviewButton.addEventListener('click',()=>{
  if(!form.reportValidity())return;let payload;try{payload=data();}catch(error){status.textContent=error.message;return;}const token=++generation;proposal=null;save.dataset.allowed='false';save.disabled=true;
  ctx.work(async()=>{
  try{const result=await rpc('marathon_egreso_edit_preview',{p_data:payload});if(token!==generation||!form.isConnected)return;review.replaceChildren(el('h3','Así quedará la corrección'));
   const labels={fecha:'Fecha',hora:'Hora',monto:'Importe',medio:'Medio',sede:'Sede',subtipo:'Subtipo',concepto:'Concepto',observaciones_legacy:'Observaciones',categoria:'Categoría',profesional_asociado_id:'Profesional asociado',secretaria_asociada:'Secretaría asociada',terapia_asociada_id:'Terapia asociada'};
   for(const [key,label]of Object.entries(labels))if(String(result.antes[key]??'')!==String(result.despues[key]??''))review.append(el('p',label+': '+pretty(key,result.antes[key])+' → '+pretty(key,result.despues[key])));
   proposal={payload,result};save.dataset.allowed='true';save.disabled=false;status.textContent='Revisá los cambios antes de confirmar.';
  }catch(error){proposal=null;save.dataset.allowed='false';save.disabled=true;status.textContent=error.message;}
  });
 });
 form.addEventListener('submit',event=>{event.preventDefault();if(!proposal||!form.reportValidity())return;let payload;try{payload=data();}catch(error){status.textContent=error.message;return;}if(JSON.stringify(payload)!==JSON.stringify(proposal.payload)){invalidate();return;}
  execute('marathon_egreso_edit_save',{p_request_id:crypto.randomUUID(),p_data:{...payload,huella:proposal.result.huella}},refresh,{onDefiniteError:error=>{if(error.code==='PT409')invalidate();}});
 });
 if(info.history?.length){const history=el('section');history.append(el('h3','Historial de correcciones'));for(const entry of info.history){const row=el('article');row.append(el('strong',new Date(entry.fecha).toLocaleString('es-AR')+' · '+entry.responsable),el('p',entry.despues.motivo),el('p',money(entry.antes.monto)+' → '+money(entry.despues.despues.monto)+' · '+entry.antes.medio+' → '+entry.despues.despues.medio));history.append(row);}panel.append(history);}
}
