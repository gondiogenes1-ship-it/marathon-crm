import {DailyUI} from './daily.js?v=20261019-0110';
import {BillingXlsx} from './xlsx.js?v=20261019-0110';
// Este módulo utiliza exclusivamente los RPC del CRM y la sesión en memoria de MarathonApi.
export function createRecurringAgenda(ctx){
 const $=s=>document.querySelector(s),el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
 const rpc=(n,a={},write=false)=>ctx.getApi().rpc(n,a,write),money=DailyUI.money;
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date());
 const date=s=>s?new Date(s+'T12:00:00').toLocaleDateString('es-AR',{day:'numeric',month:'short',year:'numeric'}):'Sin fecha';
 const plus=(d,n)=>{const x=new Date(d+'T12:00:00Z');x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10);};
 const dayNames=['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
 const button=(text,fn,variant='secondary')=>{const n=el('button',text,variant==='default'?'b':'s');n.type='button';n.dataset.variant=variant;n.addEventListener('click',fn);return n;};
 const field=(parent,label,type='text',value='',required=true)=>{const l=el('label',label),i=el(type==='textarea'?'textarea':'input');if(type!=='textarea')i.type=type;i.value=value;i.required=required;l.append(i);parent.append(l);return i;};
 const select=(parent,label,rows,value)=>{const l=el('label',label),i=el('select');for(const [id,text]of rows){const o=el('option',text);o.value=id;i.append(o);}i.value=value;l.append(i);parent.append(l);return i;};
 let view='grid',cache='',generation=0,pending=null,bookingButton=null,bookingRead=null,bookingControls=[],detach=()=>{},gridData=null,gridLabels=null;
 const tabs=el('div',undefined,'recurring-tabs');tabs.setAttribute('role','tablist');tabs.setAttribute('aria-label','Vistas de agenda');
 const panel=el('section',undefined,'recurring-panel');panel.id='recurring-panel';
 $('#agenda-filter').before(tabs);$('#agenda-list').before(panel);
 for(const [id,label]of[['week','Turnos de la semana'],['grid','Grilla habitual'],['roster','Pacientes asignados']]){
  const b=button(label,()=>ctx.work(async()=>{view=id;cache='';if(id==='week'){$('#agenda-view').value='week';await ctx.reloadWeek();}else await refresh();}),'ghost');b.dataset.view=id;b.setAttribute('role','tab');tabs.append(b);
 }
 function showView(){
  const custom=view!=='week';panel.hidden=!custom;
  for(const id of ['agenda-list','agenda-availability','agenda-info','agenda-recovery','agenda-period'])if($('#'+id))$('#'+id).hidden=custom;
  $('#agenda-page').parentElement.hidden=custom;
  $('#agenda-view').parentElement.hidden=custom;
  tabs.querySelectorAll('button').forEach(b=>b.setAttribute('aria-selected',String(b.dataset.view===view)));
 }
 async function refresh(force=false){
  showView();if($('#agenda-screen').hidden||view==='week')return;
  const d=$('#agenda-date').value||today(),monday=plus(d,-((new Date(d+'T12:00:00').getDay()+6)%7));
  const site=$('#agenda-sede').value,prof=$('#agenda-prof').value,therapy=$('#agenda-therapy').value;
  const key=[view,monday,site,prof,therapy].join('|');if(!force&&key===cache)return;cache=key;const token=++generation;
  panel.replaceChildren();gridData=null;
  if(!site||!prof){panel.append(el('p','Elegí una sede y un profesional para ver su grilla y sus pacientes. Inicio permite consultar las atenciones de todos juntos.','empty'));return;}
  panel.append(el('p','Consultando la agenda…','subtitle'));
  let data;try{data=await rpc('marathon_agenda_grilla',{p_from:monday,p_sede:site,p_prof:prof,p_therapy:therapy});}catch(e){cache='';throw e;}
  if(token!==generation)return;panel.replaceChildren();gridData=data;gridLabels={monday,site,prof,therapy};
  const options=ctx.getOptions(),therapyName=id=>options.therapies.find(t=>t.id===id)?.label||id;
  if(view==='roster'){
   const query=field(panel,'Buscar paciente','search','',false);query.placeholder='Nombre o DNI';const list=el('div',undefined,'recurring-roster');panel.append(list);
   const render=()=>{list.replaceChildren();for(const p of data.plans.filter(p=>`${p.paciente} ${p.dni}`.toLocaleLowerCase().includes(query.value.toLocaleLowerCase()))){const row=el('article',undefined,'card recurring-roster-row');if(p.absences>=2)row.classList.add('recurring-follow');row.append(el('h3',p.paciente),el('small','DNI '+p.dni+' · '+therapyName(p.terapia_id)),el('p',planLabel(p)),el('p',p.baja?'Baja desde '+date(p.baja):p.paused?'Pausado · conserva lugar':'Activo'));row.append(button('Ver asignación',()=>ctx.work(()=>openPlan(p.id))));list.append(row);}if(!list.children.length)list.append(el('p','No hay asignaciones para estos filtros.','empty'));};query.addEventListener('input',render);render();return;
  }
  const head=el('div',undefined,'recurring-grid-head');head.append(el('h2','Semana del '+date(monday)),el('p','Los lugares pausados se conservan. El espacio compartido excluye las pausas.','subtitle'));panel.append(head);
  const scroller=el('div',undefined,'recurring-scroll'),grid=el('div',undefined,'recurring-grid');scroller.append(grid);panel.append(scroller);
  grid.append(el('div','Horario','recurring-day-heading'));for(let n=0;n<5;n++){const h=el('div',dayNames[n+1],'recurring-day-heading');h.append(el('small',date(plus(monday,n))));grid.append(h);}
  const times=[...new Set(data.slots.filter(s=>new Date(s.fecha+'T12:00:00').getDay()>=1&&new Date(s.fecha+'T12:00:00').getDay()<=5).map(s=>s.hora))].sort();
  if(!times.length){panel.append(el('p','No hay horarios habilitados en esta semana.','empty'));return;}
  for(const time of times){grid.append(el('div',time,'recurring-hour'));for(let n=0;n<5;n++){
   const dt=plus(monday,n),s=data.slots.find(s=>s.fecha===dt&&s.hora===time),cell=el('div',undefined,'recurring-cell');grid.append(cell);
   if(!s){cell.classList.add('recurring-unavailable');cell.append(el('small','Sin atención'));continue;}
   const slotHead=el('div',undefined,'recurring-slot-head'),slotMeta=el('div',undefined,'recurring-slot-meta');slotMeta.append(el('strong',s.meta.remaining+' de '+s.meta.capacity+' libres','recurring-capacity'),el('small','Compartido ('+(s.meta.shared_space_count??0)+')'));slotHead.append(slotMeta);
   if(!s.meta.blocked&&s.meta.remaining>0){
    const past=dt<today(),add=button('Reservar turno',()=>{if(past||ctx.isBusy())return;return ctx.work(()=>ctx.bookAt({date:dt,sede:site,prof,therapy:s.therapy,hora:time}));},'secondary');
    add.classList.add('recurring-add');add.disabled=past;
    add.setAttribute('aria-label','Reservar turno · '+date(dt)+' · '+time+' · '+s.meta.remaining+' lugares libres');
    add.title=past?'No se pueden reservar turnos en fechas pasadas':'Reservar turno en este horario';slotHead.append(add);
    if(past){const note=el('small','Fecha pasada','recurring-slot-past');slotMeta.append(note);}
   }cell.append(slotHead);
   for(const p of s.patients){const card=el('article',undefined,'recurring-patient');if(p.paused)card.classList.add('recurring-paused');else if(p.plan?.absences>=2)card.classList.add('recurring-follow');
    const pick=button(p.paciente,()=>ctx.work(()=>p.plan_id?openPlan(p.plan_id):ctx.editPatient(p.dni)),'ghost');pick.className='recurring-patient-open';pick.append(el('small','DNI '+p.dni),el('small',therapyName(p.therapy)+' · '+p.hora+' a '+p.end_hour));if(p.plan)pick.append(el('span',planLabel(p.plan),'recurring-badge'));if(p.paused)pick.append(el('small','Pausado · conserva lugar'));if(p.plan?.absences>=2)pick.append(el('small',p.plan.absences+' faltas seguidas · contactar'));card.append(pick);
    ctx.appendWhatsApp?.(card,{...p,fecha:dt,sede:site,profesional:options.professionals.find(x=>x.id===prof)?.label||prof,terapia:therapyName(p.therapy)});cell.append(card);
   }

  }}
 }
 function planLabel(p){return p.modalidad==='sessions'?`${p.done}/${p.total} presentes · ${Math.max(0,p.total-p.done)} pendientes`:p.modalidad==='monthly'?'Mensual'+(p.renewed_today?' · renueva hoy':p.next_due?' · renueva '+date(p.next_due):''):'Indefinido';}
 function attachBooking({form,sessions,oldFields,read,onSaved}){
  form.classList.add('recurring-booking');oldFields.hidden=true;
  sessions.querySelector('h3').textContent='3. Modalidad, horarios habituales e importe';
  const box=el('div',undefined,'recurring-booking-fields');oldFields.after(box);
  const mode=select(box,'Modalidad de agenda',[['sessions','Cantidad de sesiones'],['monthly','Mensual'],['fixed','Indefinido']],'sessions');
  const total=field(box,'Cantidad de sesiones','number','10');total.min='1';total.max='1000';total.step='1';
  const billing=select(box,'Modalidad de pago',[['bonus_class','Bono inicial + por clase presente'],['class','Por clase presente'],['monthly','Mensual'],['none','No abona']],'class');
  const amount=field(box,'Importe por clase presente (ARS)','number','0');amount.min='0';amount.step='.01';amount.max='9999999999.99';
  const bonus=field(box,'Bono inicial adicional (ARS)','number','0');bonus.min='0';bonus.step='.01';
  const bonusPaid=field(box,'Registrar pago del bono ahora','checkbox','',false);bonusPaid.checked=false;
  const medium=select(box,'Medio del pago del bono',[['EFECTIVO','Efectivo'],['TRANSFERENCIA','Transferencia']],'EFECTIVO');
  const rotation=el('fieldset',undefined,'recurring-rotation');rotation.append(el('legend','Días, sede y profesional de cada atención'));box.append(rotation);
  const shortcuts=el('div',undefined,'form-actions');rotation.append(shortcuts);const rows=el('div');rotation.append(rows);
  const controls=[];bookingControls=controls;
  const options=ctx.getOptions();const first=read();amount.value=String(first.amount||0);
  const relevant=(day,site)=>options.professionals.filter(p=>p.therapy_ids.includes(first.therapy)&&options.hours.some(h=>h.prof===p.id&&h.sede===site&&Number(h.day)===day));
  for(let day=1;day<=5;day++){
   const row=el('div',undefined,'recurring-rotation-row'),check=field(row,dayNames[day],'checkbox','',false),site=select(row,'Sede',options.sedes.map(s=>[s.id,s.label]),first.sede),prof=select(row,'Profesional',[],''),hour=select(row,'Hora',[],''),occupancy=el('small','','recurring-occupancy');row.append(occupancy);rows.append(row);const control={day,check,site,prof,hour,occupancy};controls.push(control);
   const refreshHours=()=>{const old=hour.value;hour.replaceChildren();const ps=options.professionals.find(p=>p.id===prof.value),step=Number(ps?.start_step)||15;for(const h of options.hours.filter(h=>h.prof===prof.value&&h.sede===site.value&&Number(h.day)===day)){const mins=s=>Number(s.slice(0,2))*60+Number(s.slice(3,5));for(let m=mins(h.start);m<=mins(h.end)-15;m+=step){const time=String(Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0'),o=el('option',time);o.value=time;hour.append(o);}}if([...hour.options].some(x=>x.value===(old||first.hora)))hour.value=old||first.hora;check.disabled=!hour.options.length;loadOccupancy(control);};
   const refreshPros=()=>{const old=prof.value;prof.replaceChildren();for(const p of relevant(day,site.value)){const o=el('option',p.label);o.value=p.id;prof.append(o);}if([...prof.options].some(x=>x.value===(old||first.prof)))prof.value=old||first.prof;refreshHours();};
   site.addEventListener('change',refreshPros);prof.addEventListener('change',refreshHours);hour.addEventListener('change',()=>loadOccupancy(control));refreshPros();check.checked=day===new Date(first.start+'T12:00:00').getDay()&&!check.disabled;
  }
  for(const [text,days]of[['Lunes a viernes',[1,2,3,4,5]],['Lun · Mié · Vie',[1,3,5]],['Mar · Jue',[2,4]]])shortcuts.append(button(text,()=>{controls.forEach(c=>c.check.checked=days.includes(c.day)&&!c.check.disabled);}));
  async function loadOccupancy(c){
   if(!c.hour.value||!c.prof.value){c.occupancy.textContent='Sin atención';return;}
   const sequence=(c.sequence||0)+1;c.sequence=sequence;const start=read().start,dt=plus(start,(c.day-new Date(start+'T12:00:00').getDay()+7)%7);
   try{const slots=await rpc('marathon_agenda_slots',{p_fecha:dt,p_sede:c.site.value,p_prof:c.prof.value,p_therapy:read().therapy});if(c.sequence!==sequence||!box.isConnected)return;const s=slots.find(s=>s.hora===c.hour.value);c.occupancy.textContent=s?`Profesional (${s.professional_count??s.capacity-s.remaining}/${s.capacity}) · Compartido (${s.shared_space_count??0})`:'Horario no disponible';}catch{c.occupancy.textContent='Actualizar al confirmar';}
  }
  const note=el('p','Los días y horarios se repiten todas las semanas. Solo los presentes consumen sesiones.','subtitle');box.append(note);const notes=field(box,'Observaciones de la reserva','textarea','',false);notes.maxLength=1000;
  const error=el('p');error.setAttribute('role','alert');box.append(error);const review=el('section',undefined,'card recurring-review');review.hidden=true;box.append(review);
  const save=button('Revisar reserva',()=>form.requestSubmit(),'default');box.append(save);bookingButton=save;bookingRead=read;
  const show=()=>{total.parentElement.hidden=mode.value!=='sessions';total.required=mode.value==='sessions';bonus.parentElement.hidden=bonusPaid.parentElement.hidden=billing.value!=='bonus_class';medium.parentElement.hidden=billing.value!=='bonus_class'||!bonusPaid.checked;amount.parentElement.hidden=billing.value==='none';amount.min=billing.value==='monthly'?'.01':'0';amount.parentElement.firstChild.textContent=billing.value==='monthly'?'Importe mensual (ARS)':'Importe por clase presente (ARS)';note.textContent=mode.value==='fixed'?'El lugar se conserva sin fecha final, hasta la baja. Los horarios se repiten todas las semanas.':mode.value==='monthly'?'Agenda mensual con continuidad automática hasta la baja. La forma de pago se elige por separado.':'Solo los presentes descuentan sesiones; el saldo se comparte entre profesionales y sedes. No tiene vencimiento.';review.hidden=true;};
  mode.addEventListener('change',show);billing.addEventListener('change',show);bonusPaid.addEventListener('change',show);show();
  form.addEventListener('input',()=>review.hidden=true);
  form.addEventListener('change',()=>review.hidden=true);
  const submitHandler=async e=>{
   e.preventDefault();e.stopImmediatePropagation();if(ctx.isBusy()||pending)return;error.textContent='';
   const current=read();if(!current.patient||!current.therapy||!current.prof){error.textContent='Seleccioná paciente, terapia y profesional.';return;}if(!form.reportValidity())return;
   const schedules=controls.filter(c=>c.check.checked).map(c=>({day:c.day,site:c.site.value,prof:c.prof.value,time:c.hour.value}));if(!schedules.length){error.textContent='Elegí al menos un día de atención.';return;}
   let coverage;try{coverage=current.coverage();}catch(e){error.textContent=e.message;return;}
   const data={dni:current.patient.dni,therapy:current.therapy,mode:mode.value,billing:billing.value,amount:billing.value==='none'?0:Number(amount.value),start:current.start,total:mode.value==='sessions'?Number(total.value):0,coverage,notes:notes.value,schedules,...(billing.value==='bonus_class'?{bonus_amount:Number(bonus.value),bonus_paid:bonusPaid.checked,...(bonusPaid.checked?{bonus_medium:medium.value}:{})}:{}),...(current.wait?{wait_id:current.wait.id,wait_version:current.wait.version}:{})};
   if(data.billing==='bonus_class'&&data.bonus_amount<=0){error.textContent='Indicá el importe del bono inicial.';return;}
   review.replaceChildren(el('h3','Revisar reserva'),el('p',[current.patient.apellido,current.patient.nombre].filter(Boolean).join(' ')+' · DNI '+data.dni),el('p',mode.selectedOptions[0].textContent+(data.mode==='sessions'?' · '+data.total+' sesiones':'')),el('p',billing.selectedOptions[0].textContent+' · '+money(data.amount)),el('p','Inicio: '+date(data.start)));
   for(const s of schedules)review.append(el('p',dayNames[s.day]+' · '+s.time+' · '+s.site+' · '+(options.professionals.find(p=>p.id===s.prof)?.label||s.prof)));
   review.append(el('p','La disponibilidad y las superposiciones se vuelven a comprobar al confirmar.'));
   const confirmed=JSON.stringify(data);review.append(button('Confirmar reserva',()=>{if(JSON.stringify(data)!==confirmed)return;pending={request:{p_request_id:crypto.randomUUID(),p_action:'create',p_data:data},after:async reply=>{onSaved(reply);cache='';await ctx.onChanged();}};send();},'default'));review.hidden=false;
  };form.addEventListener('submit',submitHandler,true);
  detach=()=>{form.removeEventListener('submit',submitHandler,true);form.classList.remove('recurring-booking');box.remove();oldFields.hidden=false;bookingButton=null;bookingRead=null;bookingControls=[];detach=()=>{};};
 }
 async function send(){
  if(!pending||ctx.isBusy())return;const job=pending;ctx.setBusy(true);
  try{const reply=await rpc('marathon_agenda_plan_command',job.request,true);pending=null;await job.after(reply);ctx.message(reply.message);}
  catch(e){if(e.uncertain){ctx.message('No llegó la confirmación. Verificá el mismo guardado antes de continuar.',true);let b=$('#recurring-retry');if(!b){b=button('Verificar guardado',send);b.id='recurring-retry';$('#feedback').append(b);}}else{pending=null;ctx.message(e.message,true);}}
  finally{if(!pending)$('#recurring-retry')?.remove();ctx.setBusy(false);}
 }
 let dialog=null;
 function planDialog(title){if(!dialog){dialog=el('dialog');dialog.id='recurring-dialog';dialog.className='recurring-dialog';$('#workspace').append(dialog);dialog.addEventListener('cancel',e=>{if(pending||ctx.isBusy())e.preventDefault();});}dialog.replaceChildren();const head=el('div',undefined,'detail-head');head.append(el('h2',title),button('×',()=>{if(!pending&&!ctx.isBusy())dialog.close();},'ghost'));head.lastElementChild.dataset.modalX='true';head.lastElementChild.setAttribute('aria-label','Cerrar asignación');dialog.setAttribute('aria-label',title);dialog.append(head);if(!dialog.open)dialog.showModal();return dialog;}
 async function openPlan(id){
  const p=await rpc('marathon_agenda_plan',{p_id:id});if(!p)throw Error('No se encontró la asignación.');const person=await rpc('marathon_patient_get',{p_dni:p.dni}),box=planDialog('Asignación del paciente');
  box.append(el('h3',[person.apellido,person.nombre,person.segundo_nombre].filter(Boolean).join(' ')),el('p','DNI '+p.dni+' · '+planLabel(p)),el('p',p.baja?'Baja desde '+date(p.baja):p.paused?'Pausado · lugar reservado':'Activo'));
  for(const s of p.schedules)box.append(el('p',dayNames[s.dia]+' · '+String(s.hora).slice(0,5)+' · '+s.sede+' · '+(ctx.getOptions().professionals.find(x=>x.id===s.profesional_id)?.label||s.profesional_id)));
  const actions=el('div',undefined,'form-actions');box.append(actions);actions.append(button('Ver / editar ficha',()=>ctx.work(()=>{dialog.close();return ctx.editPatient(p.dni);})));ctx.appendWhatsApp?.(actions,{dni:p.dni,paciente:[person.apellido,person.nombre].filter(Boolean).join(' '),telefono:person.telefono,fecha:today(),hora:'',estado:'PENDIENTE'});
  if(!p.baja){actions.append(button(p.paused?'Reanudar tratamiento':'Pausar tratamiento',()=>showAction(p,p.paused?'resume':'pause')));if(p.modalidad==='sessions')actions.append(button('Agendar más sesiones',()=>showAction(p,'authorize')));actions.append(button('Dar de baja',()=>showAction(p,'end'),'destructive'));}
  if(p.absences>=2)box.append(el('p',p.absences+' faltas seguidas · contactar','recurring-alert'));
  if(p.authorizations.length){box.append(el('h3','Historial de cantidades autorizadas'));for(const a of p.authorizations)box.append(el('p',date(a.fecha)+' · '+a.done+'/'+a.cantidad+' presentes'));}
  if(p.pauses.length){const details=el('details'),summary=el('summary','Pausas registradas');details.append(summary);for(const a of p.pauses)details.append(el('p',date(a.desde)+' a '+(a.hasta?date(a.hasta):'sin fecha de regreso')+' · '+a.motivo));box.append(details);}
  if(p.facturacion==='monthly'){
   box.append(el('h3','Cuotas mensuales'),el('p','Saldo pendiente: '+money(p.debt)),el('p','La cuota del período iniciado se conserva completa. Las pausas suspenden las nuevas cuotas; al volver comienza un período nuevo.','subtitle'));
   if(!p.quotas.length)box.append(el('p','La primera cuota se genera en la fecha de inicio.'));
   for(const q of p.quotas){const row=el('article',undefined,'card recurring-quota');row.append(el('strong',date(q.fecha)+' al '+date(q.hasta)),el('p','Importe '+money(q.importe)+' · Pagado '+money(q.paid)+' · Saldo '+money(q.debt)));const buttons=el('div',undefined,'form-actions');if(q.debt>0)buttons.append(button('Cobrar cuota',()=>showAction(p,'quota_pay',q),'default'),button('Cancelar saldo de cuota',()=>showAction(p,'quota_waive',q),'destructive'));if(q.paid>0)buttons.append(button('Reintegrar cuota',()=>showAction(p,'quota_refund',q),'destructive'));row.append(buttons);box.append(row);}
  }
 }
 function showAction(p,kind,quota=null){
  const title={pause:'Pausar tratamiento',resume:'Reanudar tratamiento',end:'Dar de baja',authorize:'Nueva cantidad de sesiones',quota_pay:'Cobrar cuota',quota_waive:'Cancelar saldo de cuota',quota_refund:'Reintegrar cuota'}[kind],box=planDialog(title),form=el('form');box.append(form);
  let when=null,until=null,total=null,amount=null,medium=null,reason=null;
  if(['pause','end'].includes(kind))when=field(form,'Desde','date',p.inicio>today()?p.inicio:today());
  if(kind==='pause'){until=field(form,'Fecha de regreso (opcional)','date','',false);form.append(el('p','Se conserva siempre el lugar. La pausa no cuenta como falta y suspende nuevas cuotas mensuales.','subtitle'));}
  if(kind==='resume')form.append(el('p','Se reanuda hoy. Si abona mensual, comienza un período nuevo y se genera su cuota.'));
  if(kind==='authorize'){total=field(form,'Cantidad de sesiones','number','10');total.min='1';total.max='1000';form.append(el('p','Se agrega una autorización independiente. Las cantidades anteriores conservan su historial; solo se descuentan presentes.','subtitle'));}
  if(kind.startsWith('quota_')){amount=field(form,'Importe (ARS)','number',String(kind==='quota_refund'?quota.paid:quota.debt));amount.min='.01';amount.max=String(kind==='quota_refund'?quota.paid:quota.debt);amount.step='.01';if(kind!=='quota_waive')medium=select(form,'Medio',[['EFECTIVO','Efectivo'],['TRANSFERENCIA','Transferencia']],'EFECTIVO');}
  if(['pause','resume','end','quota_waive','quota_refund'].includes(kind)){reason=field(form,'Motivo obligatorio','textarea','');reason.minLength=3;reason.maxLength=1000;}
  const submit=el('button',title,['end','quota_waive','quota_refund'].includes(kind)?'s':'b');submit.type='submit';submit.dataset.variant=['end','quota_waive','quota_refund'].includes(kind)?'destructive':'default';form.append(submit,button('Volver',()=>ctx.work(()=>openPlan(p.id))));
  form.addEventListener('submit',e=>{e.preventDefault();if(pending||ctx.isBusy()||!form.reportValidity())return;const data={id:p.id,version:p.version,...(when?{date:when.value}:{}),...(until?{until:until.value}:{}),...(reason?{reason:reason.value}:{}),...(total?{total:Number(total.value)}:{}),...(amount?{quota:quota.id,amount:Number(amount.value)}:{}),...(medium?{medium:medium.value}:{})};pending={request:{p_request_id:crypto.randomUUID(),p_action:kind,p_data:data},after:async()=>{cache='';await ctx.onChanged();await openPlan(p.id);}};send();});
 }
 async function openAction(id,kind){const p=await rpc('marathon_agenda_plan',{p_id:id});if(!p)throw Error('No se encontró la asignación.');let q=null;if(kind==='quota_pay'){q=[...p.quotas].reverse().find(q=>q.debt>0);if(!q)return openPlan(id);}showAction(p,kind,q);}
 function exportView(){
  if(!gridData)throw Error('Consultá primero la grilla.');const options=ctx.getOptions(),rows=[],seen=new Set();
  if(view==='roster'){for(const p of gridData.plans)for(const h of p.schedules.filter(h=>h.sede===gridLabels.site&&h.profesional_id===gridLabels.prof))rows.push([dayNames[h.dia],String(h.hora).slice(0,5),p.paciente,p.dni,planLabel(p),p.baja?'Baja':p.paused?'Pausado':'Activo',seen.has(p.id)?0:Number(p.debt)]),seen.add(p.id);}
  else for(const s of gridData.slots)for(const p of s.patients){const key=p.id+'|'+s.fecha;if(seen.has(key))continue;seen.add(key);rows.push([s.fecha,p.hora+' a '+p.end_hour,p.paciente,p.dni,p.plan?planLabel(p.plan):'Reserva anterior',p.paused?'Pausado':p.estado,p.plan&&!seen.has(p.plan.id)?(seen.add(p.plan.id),Number(p.plan.debt)):0]);}
  if(!rows.length)throw Error('No hay pacientes para exportar con estos filtros.');const bytes=BillingXlsx.buildGrid({title:'Marathon · '+(view==='roster'?'Pacientes asignados':'Grilla habitual'),sheetName:'Agenda',columns:['Fecha / día','Horario','Paciente','DNI','Modalidad','Estado','Saldo cuotas (una vez)'].map((name,i)=>({name,numeric:i===6,width:i===2?30:24})),rows,metadata:[['Sede',gridLabels.site,'Profesional',options.professionals.find(p=>p.id===gridLabels.prof)?.label||gridLabels.prof],['Semana',gridLabels.monday]],note:'Lugares y asignaciones habituales. La grilla no representa asistencias realizadas. El saldo mensual se informa una sola vez por tratamiento.'});const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download='Marathon_agenda_'+gridLabels.monday+'.xlsx';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message('Excel descargado: '+rows.length+' filas de la vista.');
 }
 return {attachBooking,detachBooking:()=>detach(),refresh,openPlan,openAction,planLabel,exportView,isCustom:()=>view!=='week',isPending:()=>!!pending,sync:()=>{if(bookingButton)bookingButton.disabled=ctx.isBusy()||!!pending||!bookingRead?.().patient;for(const c of bookingControls){const available=!!c.hour.options.length;c.check.disabled=ctx.isBusy()||!!pending||!available;c.hour.disabled=ctx.isBusy()||!!pending||!available;c.prof.disabled=ctx.isBusy()||!!pending||!c.prof.options.length;if(!available)c.check.checked=false;}if(view!=='week')$('#agenda-export').disabled=ctx.isBusy()||!!pending||!gridData;if($('#recurring-retry'))$('#recurring-retry').disabled=ctx.isBusy();},reset:()=>{detach();++generation;cache='';pending=null;gridData=null;panel.replaceChildren();if(dialog?.open)dialog.close();}};
}
