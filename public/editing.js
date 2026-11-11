// Seguimiento en memoria; excluye búsquedas/filtros y no copia contraseñas.
export function createEditing(ctx){
 const selector=['#patient-form','#master-form','#catalog-form','#agenda-book-form','#agenda-new-patient-form','#turn-coverage-form','#wait-form','#cash-manual-form','#turn-money-form','#bonus-form','#advance-form','#reschedule-form','#reverse-form','#ortho-dialog form:not(#ortho-patient-search)','#document-upload','#user-form','#password-form','#shared-space-form','#agenda-patient-edit-form','#cash-patient-edit-form','#whatsapp-config-form','[data-whatsapp-template-form]'].join(','),tracked=new Map(),previous=new WeakMap();
 const fingerprint=f=>JSON.stringify([[...f.querySelectorAll('input,select,textarea')].filter(i=>i.name||i.type==='file').map(i=>[i.name||i.id,i.type==='checkbox'||i.type==='radio'?i.checked:i.type==='file'?[...i.files].map(f=>[f.name,f.size]):i.type==='password'?!!i.value:i.value]),f.id==='agenda-book-form'?document.querySelector('#agenda-patient-selected')?.textContent:f.id==='ortho-operation-form'?document.querySelector('#ortho-patient-selected')?.textContent:null]);
 const visible=f=>!f.closest('[hidden]')&&(!f.closest('dialog')||f.closest('dialog').open);
 function collect(refresh=false){for(const f of document.querySelectorAll(selector)){if(!tracked.has(f))tracked.set(f,{base:fingerprint(f),touched:false});else if(refresh&&!tracked.get(f).touched)tracked.get(f).base=fingerprint(f);}for(const f of tracked.keys())if(!f.isConnected)tracked.delete(f);}
 const dirty=f=>{const r=tracked.get(f);return !!r?.touched&&fingerprint(f)!==r.base;};const all=()=>{collect();return[...tracked.keys()].filter(dirty);};
 function notify(){const e=document.querySelector('#edit-warning');if(e){const n=all().length;const text=n?'Cambios sin guardar'+(n>1?' · '+n+' formularios':''):'';if(e.hidden!==!n)e.hidden=!n;if(e.textContent!==text)e.textContent=text;}}
 function confirm(forms){return!forms.some(dirty)||window.confirm('Tenés cambios sin guardar. ¿Querés continuar sin guardarlos?');}
 function stop(e){e.preventDefault();e.stopImmediatePropagation();}
 const observer=new MutationObserver(records=>{for(const r of records)if(r.type==='attributes'&&r.attributeName==='open'&&!r.target.open)for(const f of r.target.querySelectorAll(selector))if(tracked.has(f))tracked.set(f,{base:fingerprint(f),touched:false});collect(true);notify();});observer.observe(document.querySelector('#workspace'),{childList:true,subtree:true,attributes:true,attributeFilter:['open']});
 document.addEventListener('focusin',e=>{collect(true);if(e.target.matches('select'))previous.set(e.target,e.target.value);});
 for(const event of ['input','change'])document.addEventListener(event,e=>{collect();const f=e.target.closest('form');if(f&&tracked.has(f))tracked.get(f).touched=true;notify();},true);
 document.addEventListener('change',e=>{if(!e.target.matches('#master-entity,#catalog-entity'))return;collect();const container=e.target.closest('section'),forms=[...container.querySelectorAll(selector)];if(!confirm(forms)){e.target.value=previous.get(e.target)||e.target.defaultValue||'';stop(e);}else previous.set(e.target,e.target.value);},true);
 document.addEventListener('click',e=>{const b=e.target.closest('button');if(!b||b.disabled)return;collect();
  if(b.id==='logout'&&ctx.isPending()){stop(e);ctx.message('Hay una operación sin confirmar. Usá Verificar guardado antes de cerrar sesión.',true);return;}
  let forms=[];
  if(b.id==='logout')forms=all();
  else if(b.id==='cash-patient-edit-cancel')forms=[...document.querySelectorAll('#cash-patient-edit-form')];
  else if(b.id==='agenda-patient-edit-cancel')forms=[...document.querySelectorAll('#agenda-patient-edit-form','#cash-patient-edit-form')];
  else if(b.id==='agenda-patient-create-cancel')forms=[...document.querySelectorAll('#agenda-new-patient-form')];
  else if(b.closest('#nav'))forms=[...tracked.keys()].filter(visible);
  else if(b.matches('#new-patient,#patient-list button,#home-new-patient'))forms=[...document.querySelectorAll('#patient-form')];
  else if(b.matches('#master-new,#master-list button'))forms=[...document.querySelectorAll('#master-form')];
  else if(b.matches('#catalog-new,#catalog-list button'))forms=[...document.querySelectorAll('#catalog-form')];
  else if(b.matches('#agenda-new,#home-new-booking'))forms=[...document.querySelectorAll('#agenda-book-form')];
  else if(b.matches('#users-create,#users-link,#users-list button,#users-pending button'))forms=[...document.querySelectorAll('#user-form')];
  else if(b.type!=='submit'&&(b.matches('.modal-close-x')||/^(Cerrar|Volver a cargar)/.test(b.textContent.trim()))){const container=b.closest('dialog')||b.closest('#detail,#master-detail,#catalog-detail,#agenda-booking,#users-detail,#shared-space-settings');if(container)forms=[...container.querySelectorAll(selector)];}
  if(!confirm(forms)){stop(e);return;}
  const form=b.closest('form');if(form&&tracked.has(form)&&b.type!=='submit')tracked.get(form).touched=true;
  if(b.matches('#agenda-patient-results button,#ortho-patient-results button')){const id=b.closest('#agenda-patient-results')?'#agenda-book-form':'#ortho-operation-form',f=document.querySelector(id);if(tracked.has(f))tracked.get(f).touched=true;}
 },true);
 document.addEventListener('cancel',e=>{if(e.target.id==='global-error-dialog')return;if(ctx.isBusy()||ctx.isPending()){e.preventDefault();return;}collect();if(!confirm([...e.target.querySelectorAll(selector)]))e.preventDefault();},true);
 window.addEventListener('beforeunload',e=>{if(all().length){e.preventDefault();e.returnValue='';}});
 for(const e of document.querySelectorAll('#master-entity,#catalog-entity'))previous.set(e,e.value);collect();return{hasChanges:()=>all().length>0,allowNavigation:()=>{collect();return confirm([...tracked.keys()].filter(visible));},reset:()=>{tracked.clear();collect();notify();}};
}
