export function appendSharedSpace(slot,row){
 if(!row.shared_space)return;
 const box=document.createElement('small');box.className='shared-space-count';
 box.title='Máximo de personas con turnos pendientes o presentes que coinciden durante esta sesión, en la misma sede y entre las terapias configuradas. No incluye la reserva nueva.';
 const label=document.createElement('span');label.textContent='Espacio compartido:';
 const count=document.createElement('strong');count.textContent=Number.isInteger(row.shared_space_count)?row.shared_space_count+' actuales':'Sin dato confirmado';
 box.append(label,count);slot.append(box);
}

export function createSharedSpaceSettings(ctx){
 const $=s=>document.querySelector(s),el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
 const rpc=(n,a={},write=false)=>ctx.getApi().rpc(n,a,write);
 const panel=el('details');panel.className='card shared-space-settings';panel.id='shared-space-settings';panel.append(el('summary','Espacio compartido'));
 const content=el('div');panel.append(content);$('#masters-screen .topbar').after(panel);
 let config=null,pending=null;
 const sorted=ids=>[...ids].sort().join('|');
 const selection=()=>[...panel.querySelectorAll('[name=shared_therapy]:checked')].map(i=>i.value);
 const dirty=()=>!!config&&sorted(selection())!==sorted(config.therapy_ids);
 function sync(){const locked=ctx.isBusy()||!!pending;panel.querySelectorAll('input').forEach(i=>i.disabled=locked);const save=$('#shared-space-save');if(save)save.disabled=locked||!dirty();const reload=$('#shared-space-reload');if(reload)reload.disabled=locked;const verify=$('#shared-space-retry');if(verify)verify.disabled=ctx.isBusy();}
 function render(value){config=value;content.replaceChildren();
  content.append(el('p','Elegí las terapias que usan el mismo lugar. Las fichas de horario suman personas de todos sus profesionales, siempre dentro de la misma sede.'));
  const form=el('form');form.id='shared-space-form';const fields=el('fieldset');fields.append(el('legend','Terapias del espacio compartido'));
  for(const t of value.therapies){const label=el('label');label.className='therapy-check';const input=el('input');input.type='checkbox';input.name='shared_therapy';input.value=t.id;input.checked=value.therapy_ids.includes(t.id);label.append(input,document.createTextNode(t.label+(t.estado==='INACTIVO'?' (inactiva)':'')));fields.append(label);}
  form.append(fields);const note=el('p','El conteo es informativo: no agrega un límite físico ni cambia los cupos del profesional. Sin terapias seleccionadas se deja de mostrar el indicador.');note.className='subtitle';form.append(note);
  const actions=el('div');actions.className='form-actions';const save=el('button','Guardar configuración');save.id='shared-space-save';save.type='submit';save.className='b';const reload=el('button','Volver a cargar');reload.id='shared-space-reload';reload.type='button';reload.className='s';reload.onclick=()=>ctx.work(load);actions.append(save,reload);form.append(actions);form.onchange=sync;
  form.onsubmit=e=>{e.preventDefault();if(ctx.isBusy()||pending||!dirty())return;pending={p_therapy_ids:selection(),p_version:config.version};send();};content.append(form);sync();
 }
 async function load(){render(await rpc('marathon_shared_space_get'));}
 async function send(){if(ctx.isBusy()||!pending)return;ctx.setBusy(true);try{const result=await rpc('marathon_shared_space_save',pending,true);pending=null;render(result);ctx.message('Configuración de espacio compartido guardada. Los próximos horarios consultados usarán esta selección.');}
  catch(e){ctx.message(e.message,true);if(e.uncertain){if(!$('#shared-space-retry')){const verify=el('button','Verificar guardado');verify.id='shared-space-retry';verify.type='button';verify.className='s';verify.onclick=verifySave;content.append(verify);}}else pending=null;}
  finally{ctx.setBusy(false);sync();}}
 async function verifySave(){if(ctx.isBusy()||!pending)return;ctx.setBusy(true);try{const result=await rpc('marathon_shared_space_get');const expected=pending;pending=null;
   if(sorted(result.therapy_ids)===sorted(expected.p_therapy_ids)){render(result);ctx.message('Guardado confirmado.');}
   else{config=result;$('#shared-space-retry')?.remove();ctx.message('La configuración enviada no está aplicada. Revisá la selección y volvé a guardar.',true);}
  }catch(e){ctx.message(e.message,true);}finally{ctx.setBusy(false);sync();}}
 return {load,sync,isPending:()=>!!pending,reset(){config=null;pending=null;panel.open=false;content.replaceChildren();}};
}
