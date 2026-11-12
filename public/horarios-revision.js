// Panel "Horarios a revisar": lista los horarios de planes que hoy no pueden agendarse
// (el profesional no atiende ese día/hora, o no hay cupo) y permite reagendarlos o darlos
// de baja. Disponible para ADMIN y SECRETARIA (la autorización real está en las RPC).
const DAYS=['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
const DAY_OPTS=[[1,'Lunes'],[2,'Martes'],[3,'Miércoles'],[4,'Jueves'],[5,'Viernes'],[6,'Sábado'],[0,'Domingo']];

export function createHorariosRevision(ctx){
 const $=s=>document.querySelector(s);
 const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined&&text!==null)e.textContent=text;if(cls)e.className=cls;return e;};
 const action=(text,fn,cls='s')=>{const b=el('button',text,cls);b.type='button';b.addEventListener('click',fn);return b;};
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 let dialog=null,rows=[];

 function ensure(){
  if(dialog)return dialog;
  dialog=el('dialog',undefined,'hrev-dialog');dialog.id='hrev-dialog';
  dialog.addEventListener('cancel',()=>{if(ctx.isBusy()){/* no cerrar mientras guarda */}});
  $('#workspace').append(dialog);
  return dialog;
 }

 function describe(r){
  return r.profesional+' · '+DAYS[r.dia]+' '+r.hora+' · '+r.sede+' · '+(r.motivo||'horario no habilitado')+(r.pendientes?(' · '+r.pendientes+' turno'+(r.pendientes===1?'':'s')+' pendiente'+(r.pendientes===1?'':'s')):'');
 }

 function render(){
  const d=ensure();d.replaceChildren();
  const head=el('div',undefined,'detail-head');head.append(el('h2','Horarios a revisar'));head.append(action('Cerrar',()=>d.close()));d.append(head);
  d.append(el('p',rows.length
   ?'Estos horarios no se pueden agendar hoy: el profesional no atiende ese día/hora, o el lugar no tiene cupo. Reprogramá el horario o dalo de baja.'
   :'No hay horarios para revisar. Está todo en orden.','subtitle'));
  for(const r of rows){
   const card=el('div',undefined,'hrev-row');card.style.cssText='border:1px solid var(--border,#d8dee9);border-radius:8px;padding:.6rem .8rem;margin:.5rem 0;display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;justify-content:space-between;';
   const info=el('div');info.style.cssText='min-width:14rem;flex:1;';
   info.append(el('strong',r.paciente+' · '+r.terapia));info.append(document.createElement('br'));info.append(el('small',describe(r)));
   const acts=el('div',undefined,'form-actions');acts.style.margin='0';
   acts.append(action('Reagendar',()=>openReagendar(r,card),'b'));
   acts.append(action('Dar de baja',()=>openEliminar(r,card)));
   card.append(info,acts);d.append(card);
  }
 }

 function closeExtras(card){card.parentElement?.querySelectorAll('.hrev-extra').forEach(e=>e.remove());}

 function openReagendar(r,card){
  closeExtras(card);
  const box=el('div',undefined,'hrev-extra');box.style.cssText='flex-basis:100%;display:flex;flex-wrap:wrap;gap:.5rem;align-items:flex-end;border-top:1px dashed var(--border,#d8dee9);padding-top:.5rem;';
  const dl=el('label','Día');const day=el('select');for(const [v,t] of DAY_OPTS){const o=el('option',t);o.value=v;day.append(o);}day.value=String(r.dia);dl.append(day);
  const tl=el('label','Hora');const time=el('input');time.type='time';time.step='60';time.value=r.hora;tl.append(time);
  const save=action('Guardar',()=>ctx.work(async()=>{
   const res=await rpc('marathon_agenda_horario_reagendar',{p_request_id:crypto.randomUUID(),p_data:{horario_id:r.horario_id,day:Number(day.value),time:time.value}},true);
   ctx.message(res.message);await reload();await ctx.onChanged?.();
  }),'b');
  box.append(dl,tl,save,action('Cancelar',()=>box.remove()));
  card.after(box);
 }

 function openEliminar(r,card){
  closeExtras(card);
  const box=el('div',undefined,'hrev-extra');box.style.cssText='flex-basis:100%;display:flex;flex-wrap:wrap;gap:.5rem;align-items:center;border-top:1px dashed var(--border,#d8dee9);padding-top:.5rem;';
  box.append(el('small','¿Dar de baja este horario? Se quitan los turnos pendientes futuros; el historial se conserva.'));
  box.append(action('Sí, dar de baja',()=>ctx.work(async()=>{
   const res=await rpc('marathon_agenda_horario_eliminar',{p_request_id:crypto.randomUUID(),p_data:{horario_id:r.horario_id}},true);
   ctx.message(res.message);await reload();await ctx.onChanged?.();
  }),'b'));
  box.append(action('No',()=>box.remove()));
  card.after(box);
 }

 async function reload(){const res=await rpc('marathon_agenda_horarios_revision');rows=res.rows||[];render();updateBadge();}

 function updateBadge(){const b=$('#agenda-review-schedules');if(!b)return;b.textContent=rows.length?('Horarios a revisar ('+rows.length+')'):'Horarios a revisar';b.classList.toggle('alerta',rows.length>0);b.hidden=false;}

 async function open(){ensure();await reload();if(!dialog.open)dialog.showModal();}

 // Actualiza el contador del botón sin abrir el panel (se llama al entrar a Turnos).
 async function refreshBadge(){try{const res=await rpc('marathon_agenda_horarios_revision');rows=res.rows||[];updateBadge();}catch{}}

 return {open,refreshBadge,sync:()=>{},isPending:()=>false,reset:()=>{rows=[];if(dialog?.open)dialog.close();const b=$('#agenda-review-schedules');if(b){b.textContent='Horarios a revisar';b.classList.remove('alerta');}}};
}
