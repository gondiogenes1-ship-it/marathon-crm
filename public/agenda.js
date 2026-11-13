import {createRecurringAgenda} from './agenda-recurrente.js?v=20261113-inicio-retroactivo';
import {createTurnSeriesUI} from './turn-series.js?v=20261105-series';
import {sessionCountLabel,loadSessionCounts} from './session-counts.js?v=20261029-0131';
import {createAgendaPatientEditor} from './agenda-patient-editor.js?v=20261029-caja-pacientes';
import {appendSharedSpace} from './shared-space.js?v=20261028-0131-espacio';
import {DailyUI} from './daily.js?v=20261019-0110';
import {createAgendaAvailability} from './agenda-availability.js?v=20261028-0131-reserva-fichas';
import {appendPatientCoverages,patientPayload,createTurnCoverage,coverageLabel,appendPatientPhone} from './coverage.js?v=20261027-0120';
// Agenda: consultas paginadas; reservas y cambios de estado se confirman en la base.
export function createAgenda(ctx){
 const $=s=>document.querySelector(s);
 let options={sedes:[],therapies:[],professionals:[]},pages=[null],page=0,next=null,pending=null,patient=null,chosen=null,waitContext=null;
 let filter={fecha:'',sede:'',prof:'',therapy:'',view:'day'},prefsLoaded=false,autoTimer=null,autoTries=0,collectOffer=null,continuityOffer=null,slotTimer=null,slotTries=0,slotKey='';
 let cancelOffer=null,exportReady=false,bulkPending=null,bulkDialog=null;
 let datesPreview=null,selectedDates=new Set(),selectedDays=new Set(),datesKey='',datesGeneration=0,datesLoading=false,lastReceipt=null,pendingReceipt=null;
 let recurring=null,bookingEdit=null,bookingSeed=null;
 let insuranceCatalog=[],coverageControl=null,coverageReady=false,coverageGeneration=0,reviewGeneration=0,reviewLoading=false;
 let infoTimer=null,infoGeneration=0;
 const weekday=date=>new Date(date+'T12:00:00Z').getUTCDay();
 const minutes=value=>Number(value.split(':')[0])*60+Number(value.split(':')[1]);
 const isFixed=()=>$('#a-mode')?.value==='fixed';
 function fixedDates(){const from=$('#a-fecha')?.value,until=$('#a-fixed-until')?.value;if(!from||!until||until<from||until>plusDays(from,366)||until>'2100-12-31')return[];const dates=[];for(let d=from;d<=until;d=plusDays(d,1))if(selectedDays.has(weekday(d)))dates.push(d);return dates;}
 const wantedSessions=()=>isFixed()?fixedDates().length:Number($('#a-count')?.value);
 const datesNow=()=>[keyNow(),chosen,patient?.dni,wantedSessions(),[...selectedDays].sort().join(','),isFixed()?$('#a-fixed-until')?.value:''].join('|');
 function resetDates(){++datesGeneration;++reviewGeneration;reviewLoading=false;datesLoading=false;datesPreview=null;datesKey='';selectedDates.clear();$('#agenda-review')?.remove();$('#agenda-dates')?.replaceChildren();if($('#agenda-dates-summary'))$('#agenda-dates-summary').textContent='Indicá la cantidad de sesiones y generá las fechas.';}
 function professionalStep(prof){const durations=options.therapies.filter(t=>prof.therapy_ids.includes(t.id)).map(t=>Number(t.duration)).filter(n=>Number.isFinite(n)&&n>0);return Number(prof.start_step)||(durations.length?Math.min(...durations):15);}
 function supports(prof,therapy,date,site,hour=null){
  const t=options.therapies.find(x=>x.id===therapy);if(!date||!site||!t||!prof.therapy_ids.includes(therapy))return false;
  if($('#a-exception')?.checked)return true;
  return (options.hours||[]).some(h=>h.prof===prof.id&&h.sede===site&&Number(h.day)===weekday(date)&&minutes(h.end)-minutes(h.start)>=15&&(hour===null||minutes(h.start)<=minutes(hour)&&minutes(hour)+15<=minutes(h.end)&&(minutes(hour)-minutes(h.start))%professionalStep(prof)===0));
 }
 function refreshBookingFilters(){
  const date=$('#a-fecha').value,site=$('#a-sede').value,oldTherapy=$('#a-therapy').value,oldProf=$('#a-prof').value;
  const therapies=options.therapies.filter(t=>options.professionals.some(p=>supports(p,t.id,date,site)));
  selectOptions($('#a-therapy'),therapies,!date?'Elegí una fecha primero':!site?'Elegí una sede primero':therapies.length?'Elegir terapia':'Sin atención en esta fecha y sede');
  $('#a-therapy').value=therapies.some(t=>t.id===oldTherapy)?oldTherapy:'';
  const candidates=options.professionals.filter(p=>supports(p,$('#a-therapy').value,date,site));
  selectOptions($('#a-prof'),candidates,$('#a-therapy').value?'Elegir profesional':'Elegí una terapia primero');
  $('#a-prof').value=candidates.some(p=>p.id===oldProf)?oldProf:'';
  if(!$('#a-prof').value&&candidates.length===1&&!waitContext)$('#a-prof').value=candidates[0].id;
  invalidate();maybeLoad();
 }
 function renderSessionDays(){
  const box=$('#agenda-session-days');if(!box)return;box.replaceChildren();
  const prof=options.professionals.find(p=>p.id===$('#a-prof').value),date=$('#a-fecha').value;
  if(!chosen||!prof||!date)return;
  for(const day of [1,2,3,4,5,6,0]){
   const candidate=plusDays(date,(day-weekday(date)+7)%7);if(!supports(prof,$('#a-therapy').value,candidate,$('#a-sede').value,chosen))continue;
   const label=el('label',undefined,'booking-check'),input=el('input');input.type='checkbox';input.value=String(day);input.checked=selectedDays.has(day);input.dataset.sessionDay=String(day);
   input.addEventListener('change',()=>{if(locked())return;if(input.checked)selectedDays.add(day);else selectedDays.delete(day);resetDates();sync();});
   label.append(input,document.createTextNode(['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'][day]));box.append(label);
  }
 }
 function dateSummary(){
  if(!$('#agenda-dates-summary'))return;const dates=[...selectedDates].sort(),last=dates.at(-1);
  $('#agenda-dates-summary').textContent=(isFixed()?'Fechas fijas disponibles: ':'Sesiones seleccionadas: ')+dates.length+' de '+wantedSessions()+'.'+(last?' Última sesión: '+DailyUI.dayLabel(last)+'.':'')+(datesPreview&&!datesPreview.complete?(isFixed()?' Hay fechas sin cupo: cambiá el horario, los días o la fecha de revisión. No se guardará una serie parcial.':' No se encontraron suficientes fechas: cambiá los días, el horario o la cantidad.'):'');
 }
 function renderDates(){
  const box=$('#agenda-dates');box.replaceChildren();
  for(const row of datesPreview.rows){
   const label=el('label',undefined,'booking-check booking-date'+(row.ok?'':' unavailable')),input=el('input');input.type='checkbox';input.dataset.sessionDate=row.fecha;input.checked=selectedDates.has(row.fecha);input.dataset.available=String(row.ok);
   input.addEventListener('change',()=>{if(locked())return;if(input.checked){if(selectedDates.size>=wantedSessions()){input.checked=false;return;}selectedDates.add(row.fecha);}else selectedDates.delete(row.fecha);dateSummary();sync();});
   const text=el('span',DailyUI.dayLabel(row.fecha)+' · '+chosen+(row.end_hour?'–'+row.end_hour:''));text.append(el('small',row.reason+(row.shortened?' · Sesión hasta el cierre: '+row.duration_min+' minutos':'')));label.append(input,text);box.append(label);
  }
  dateSummary();sync();
 }
 async function generateDates(){
  if(!patient||!chosen)throw Error('Elegí un paciente y un horario antes de generar las fechas.');
  if(!Number.isInteger(wantedSessions())||wantedSessions()<1||wantedSessions()>60)throw Error(isFixed()?'El horario fijo debe incluir entre 1 y 60 fechas, con revisión hasta un año después.':'Indicá una cantidad de 1 a 60 sesiones.');
  if(!selectedDays.size)throw Error('Tildá al menos un día de atención.');
  resetDates();const generation=datesGeneration,asked=datesNow();datesLoading=true;sync();
  try{
   const result=await rpc('marathon_booking_dates',{p_data:{from:$('#a-fecha').value,sede:$('#a-sede').value,prof:$('#a-prof').value,therapy:$('#a-therapy').value,hora:chosen,dni:patient.dni,count:wantedSessions(),days:[...selectedDays].sort(),...(isFixed()?{fixed_until:$('#a-fixed-until').value}:{})}});
   if(generation!==datesGeneration||asked!==datesNow()||!$('#agenda-book-form'))return;
   datesPreview=result;datesKey=asked;selectedDates=new Set(result.selected);renderDates();
  }catch(error){if(error.code==='PGRST202'||error.code==='404')throw Error('Falta instalar la actualización de reservas en Supabase.');throw error;}
  finally{if(generation===datesGeneration){datesLoading=false;sync();}}
 }
 const keyNow=()=>[$('#a-fecha')?.value,$('#a-sede')?.value,$('#a-prof')?.value,$('#a-therapy')?.value].join('|');
 const uid=()=>ctx.getUser()?.user_id;
 const savePrefs=()=>DailyUI.prefs.save(uid(),{agendaSede:filter.sede,agendaProf:filter.prof,agendaTherapy:filter.therapy,agendaView:filter.view});
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write);
 const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const action=(text,fn,cls='s')=>{const b=el('button',text,cls);b.type='button';b.addEventListener('click',fn);return b;};
 const today=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const seriesUI=createTurnSeriesUI({...ctx,onChanged:async()=>{await list();await recurring.refresh(true);await ctx.onChanged?.();}});
 const locked=()=>ctx.isBusy()||!!pending||!!bulkPending||seriesUI.isPending();
 const bookingPanel=$('#agenda-booking'),bookingDialog=el('dialog');
 bookingDialog.id='agenda-dialog';bookingDialog.setAttribute('aria-labelledby','agenda-booking-title');
 bookingPanel.parentElement.classList.add('agenda-list-only');
 const feedback=$('#feedback'),feedbackAnchor=document.createComment('Mensajes de la aplicación');
 feedback.before(feedbackAnchor);bookingDialog.append(bookingPanel);$('#workspace').append(bookingDialog);
 const availabilityPanel=el('section',undefined,'agenda-availability');availabilityPanel.id='agenda-availability';$('#agenda-list').before(availabilityPanel);
 const availability=createAgendaAvailability({getApi:ctx.getApi,container:availabilityPanel,isBusy:locked,onBook:selection=>{if(!locked())ctx.work(()=>bookAvailableSlot(selection));}});
 const patientEditor=createAgendaPatientEditor({...ctx,onSaved:async dni=>{
  if(bookingDialog.open&&patient?.dni===dni)await choosePatient(await rpc('marathon_patient_get',{p_dni:dni}),true);
  else if(!$('#agenda-screen').hidden)await list();
 }});
 recurring=createRecurringAgenda({...ctx,getOptions:()=>options,editPatient:dni=>patientEditor.open(dni),bookAt:bookAvailableSlot,continuePlan:id=>extendSessions({id}),manageTurn:(turn,kind)=>kind==='edit'?openBookingEditor(turn):seriesUI.open(turn,kind),
  reloadWeek:async()=>{filter.view='week';filter.fecha=$('#agenda-date').value;filter.sede=$('#agenda-sede').value;filter.prof=$('#agenda-prof').value;filter.therapy=$('#agenda-therapy').value;page=0;pages=[null];await list();},
  onChanged:async()=>{if(!$('#agenda-screen').hidden)await list();await ctx.onChanged?.();}
 });
 let cancelPatientSearch=()=>{};
 function clearBooking(){bookingEdit=null;bookingSeed=null;recurring?.detachBooking();cancelPatientSearch();clearPatientCoverage();clearTimeout(slotTimer);slotKey='';resetDates();selectedDays.clear();bookingPanel.hidden=true;bookingPanel.replaceChildren();patient=null;chosen=null;waitContext=null;feedbackAnchor.after(feedback);}
 function closeBooking(force=false){if(!force&&locked())return;if(bookingDialog.open)bookingDialog.close();clearBooking();}
 bookingDialog.addEventListener('cancel',event=>{if(locked())event.preventDefault();});
 bookingDialog.addEventListener('close',()=>{if(!bookingDialog.open)clearBooking();});
 function selectOptions(input,rows,empty){input.replaceChildren();for(const r of [{id:'',label:empty},...rows]){const o=el('option',r.label);o.value=r.id;input.append(o);}}
 function field(parent,key,label,value='',type='text',required=false){const l=el('label',label),input=el(type==='textarea'?'textarea':'input');input.id='a-'+key;input.name=key;if(type!=='textarea')input.type=type;input.value=value;input.required=required;l.append(input);parent.append(l);return input;}
 function select(parent,key,label,rows,empty){const l=el('label',label),input=el('select');input.id='a-'+key;input.name=key;input.required=true;selectOptions(input,rows,empty);l.append(input);parent.append(l);return input;}
 function sync(){
  availability.sync();patientEditor.sync();seriesUI.sync();
  if($('#agenda-edit-patient')){$('#agenda-edit-patient').hidden=!patient;$('#agenda-edit-patient').disabled=locked()||!coverageReady;}
  $('#agenda-list').querySelectorAll('[data-turn-state]').forEach(b=>b.disabled=locked());
  if($('#agenda-export'))$('#agenda-export').disabled=locked()||!filter.fecha||!exportReady;
  const contextReady=!!($('#a-fecha')?.value&&$('#a-sede')?.value&&$('#a-therapy')?.value&&$('#a-prof')?.value);const newFlow=$('#agenda-book-form')?.dataset.legacy==='false';
  if($('#agenda-step-slots'))$('#agenda-step-slots').hidden=newFlow||!contextReady;
  if($('#agenda-step-patient'))$('#agenda-step-patient').hidden=newFlow?!contextReady:!chosen;
  if($('#agenda-step-sessions'))$('#agenda-step-sessions').hidden=newFlow?!contextReady||!patient:!chosen||!patient;
  $('#agenda-new-patient-form')?.querySelectorAll('input,select,button').forEach(e=>e.disabled=locked());
  $('#turn-coverage-form')?.querySelectorAll('input,select,textarea,button').forEach(e=>e.disabled=locked());
  $('#agenda-previous').disabled=locked()||page===0;$('#agenda-next').disabled=locked()||!next;
  $('#agenda-slots')?.querySelectorAll('button').forEach(b=>{b.disabled=locked()||b.dataset.available!=='true';});
  if($('#agenda-submit')){$('#agenda-submit').disabled=locked()||reviewLoading||!coverageReady||datesLoading||!chosen||!patient||datesKey!==datesNow()||selectedDates.size!==wantedSessions();$('#agenda-submit').textContent=reviewLoading?'Consultando turnos existentes…':wantedSessions()>1?'Revisar '+wantedSessions()+' turnos':'Revisar reserva';}
  if($('#agenda-confirm'))$('#agenda-confirm').disabled=locked();
  if($('#a-bonus-paid')){const hasBonus=Number($('#a-bonus-amount').value)>0;if(!hasBonus||ctx.saldoActive?.())$('#a-bonus-paid').checked=false;$('#a-bonus-paid').parentElement.hidden=!hasBonus||ctx.saldoActive?.()===true;$('#a-bonus-paid').disabled=locked()||!hasBonus||ctx.saldoActive?.()===true;$('#a-bonus-medium').parentElement.hidden=!hasBonus||!$('#a-bonus-paid').checked;$('#a-bonus-medium').disabled=locked()||!hasBonus||!$('#a-bonus-paid').checked;}
  if($('#agenda-dates-help'))$('#agenda-dates-help').textContent=isFixed()?'Se incluyen todos los días elegidos hasta la revisión. Si una fecha no tiene cupo, ajustá la selección antes de confirmar. No se saltean fechas.':'Elegí los días de atención y generá el listado. Se tildan las primeras fechas disponibles; podés destildar una y elegir otra.';
  if($('#a-fixed-until')){$('#a-fixed-until').parentElement.hidden=!isFixed();$('#a-fixed-until').disabled=locked()||!isFixed();$('#a-fixed-until').required=isFixed();$('#a-fixed-until').min=$('#a-fecha').value;$('#a-fixed-until').max=plusDays($('#a-fecha').value||today(),366)>'2100-12-31'?'2100-12-31':plusDays($('#a-fecha').value||today(),366);$('#a-count').parentElement.hidden=isFixed();$('#a-count').disabled=locked()||isFixed();}
  if($('#agenda-generate-dates'))$('#agenda-generate-dates').disabled=locked()||datesLoading||!chosen||!patient||!selectedDays.size;
  $('#agenda-session-days')?.querySelectorAll('input').forEach(i=>{i.disabled=locked()||!chosen;});
  $('#agenda-dates')?.querySelectorAll('input').forEach(i=>{i.disabled=locked()||isFixed()||i.dataset.available!=='true'||!i.checked&&selectedDates.size>=wantedSessions();});
  if($('#a-therapy'))$('#a-therapy').disabled=locked()||!$('#a-fecha').value||!$('#a-sede').value;
  if($('#a-prof'))$('#a-prof').disabled=locked()||!$('#a-therapy').value;
  if(waitContext){for(const key of ['sede','therapy'])if($('#a-'+key))$('#a-'+key).disabled=true;if(waitContext.profesional_id&&$('#a-prof'))$('#a-prof').disabled=true;}
  if($('#retry-agenda'))$('#retry-agenda').disabled=ctx.isBusy();
  if($('#bulk-retry'))$('#bulk-retry').disabled=ctx.isBusy();
  if(contextReady&&patient&&coverageReady&&$('#agenda-book-form')&&!$('#agenda-book-form').classList.contains('recurring-booking')&&$('#agenda-book-form').dataset.legacy!=='true'){
   recurring.attachBooking({form:$('#agenda-book-form'),sessions:$('#agenda-step-sessions'),oldFields:$('#a-mode').closest('.form-grid'),edit:bookingEdit,seed:bookingSeed,
    read:()=>({start:$('#a-fecha')?.value,sede:$('#a-sede')?.value,therapy:$('#a-therapy')?.value,prof:$('#a-prof')?.value,hora:chosen,amount:Number($('#a-importe')?.value||0),patient,coverage:()=>coverageControl.read(),wait:waitContext,exception:!!$('#a-exception')?.checked}),
    onSaved:reply=>{if(bookingEdit){closeBooking(true);return;}if(reply.exceptional){filter.view='day';filter.state='';pages=[null];page=0;next=null;$('#agenda-view').value='day';recurring.showRecorded();}const p=reply.exceptional?{inicio:reply.turn.fecha,schedules:[reply.turn]}:reply.plan;filter.fecha=p.inicio;filter.sede=p.schedules[0]?.sede||filter.sede;filter.prof=p.schedules[0]?.profesional_id||filter.prof;$('#agenda-date').value=filter.fecha;$('#agenda-sede').value=filter.sede;$('#agenda-prof').value=filter.prof;closeBooking(true);}
   });
  }
  recurring?.sync();
  if(bookingEdit){if($('#a-exception'))$('#a-exception').disabled=true;$('#agenda-patient-search').hidden=true;$('#agenda-coverage').querySelectorAll('input,select,textarea,button').forEach(n=>n.disabled=locked());}
  if(bookingDialog.open&&!locked()&&!bookingDialog.contains(document.activeElement))requestAnimationFrame(()=>{if(bookingDialog.open&&!locked()&&!bookingDialog.contains(document.activeElement))$('#a-patient-query')?.focus();});
 }
 function show(){for(const s of ['home','patients','masters','wait','cash','ortho','catalog','reports','users'])$('#'+s+'-screen').hidden=true;$('#agenda-screen').hidden=false;for(const n of ['home','patients','masters','agenda','wait','cash','ortho','catalog','reports','users'])$('#nav-'+n).className=n==='agenda'?'b':'';}
 async function open(){show();options=await rpc('marathon_agenda_options');selectOptions($('#agenda-sede'),options.sedes,'Todas las sedes');selectOptions($('#agenda-prof'),options.professionals,'Todos los profesionales');selectOptions($('#agenda-therapy'),options.therapies,'Todas las terapias');$('#agenda-therapy').value=filter.therapy||'';$('#agenda-view').value=filter.view||'day';if(!prefsLoaded){prefsLoaded=true;if(!filter.fecha){const p=DailyUI.prefs.load(uid());filter={...filter,sede:p.agendaSede||'',prof:p.agendaProf||'',therapy:p.agendaTherapy||'',view:p.agendaView||'day'};}}if(!filter.fecha)filter.fecha=today();$('#agenda-therapy').value=filter.therapy||'';$('#agenda-view').value=filter.view||'day';$('#agenda-date').value=filter.fecha;$('#agenda-sede').value=filter.sede;$('#agenda-prof').value=filter.prof;refreshAgendaTherapies();filter={...filter,sede:$('#agenda-sede').value,prof:$('#agenda-prof').value,therapy:$('#agenda-therapy').value};await list();}
 function refreshAgendaTherapies(){
  const selected=$('#agenda-therapy').value,prof=options.professionals.find(p=>p.id===$('#agenda-prof').value);
  const therapies=options.therapies.filter(t=>!prof||(prof.therapy_ids||[]).includes(t.id));
  selectOptions($('#agenda-therapy'),therapies,'Todas las terapias');$('#agenda-therapy').value=therapies.some(t=>t.id===selected)?selected:'';
 }
 function summaryStrip(rows,partial,scope=null){
  const s=scope?.summary||DailyUI.summarize(rows),box=el('div',undefined,'turn-summary');box.setAttribute('role','group');box.setAttribute('aria-label',scope?'Filtrar turnos por estado':'Resumen de los turnos mostrados');
  const chip=(label,value,cls,state='')=>{const c=el(scope?'button':'span',undefined,'chip-stat'+(cls?' '+cls:''));if(scope){c.type='button';c.dataset.turnState=state;c.setAttribute('aria-pressed',String((scope.state||'')===state));c.title=state?'Mostrar solo '+label:'Mostrar todos los turnos';c.addEventListener('click',()=>{if(!locked())scope.onState(state);});}c.append(el('strong',String(value)),document.createTextNode(' '+label));return c;};
  box.append(chip(s.total===1?'turno':'turnos',s.total),chip('pendientes',s.PENDIENTE,'st-pendiente','PENDIENTE'),chip('presentes',s.PRESENTE,'st-presente','PRESENTE'),chip('ausentes',s.AUSENTE,'st-ausente','AUSENTE'));
  if(ctx.getUser()?.role==='ADMIN')box.append(chip('cancelados',s.CANCELADO,'st-cancelado','CANCELADO'));
  if(s.PAUSADO)box.append(chip('en pausa',s.PAUSADO,'st-cancelado','PAUSADO'));
  const balance=scope?.state&&scope.state!=='PRESENTE'?0:s.debt;const debt=el('span',undefined,'chip-stat'+(balance>0?' st-debt':''));debt.append(el('strong',DailyUI.money(balance)),document.createTextNode(' saldo a cobrar'));box.append(debt);
  if(scope?.summary)box.append(el('small','Los contadores incluyen todos los turnos del período y los filtros, antes de elegir un estado.','summary-note'));else if(partial)box.append(el('small','Resumen de esta página; hay más turnos en las páginas vecinas.','summary-note'));
  return box;
 }
 const canChangeCoverage=t=>ctx.getUser()?.role==='ADMIN'||t.estado==='PENDIENTE'||(Object.hasOwn(t,'coverage')&&!t.coverage?.type);
 function professionalColor(id){let hash=2166136261;for(const ch of String(id||'')){hash^=ch.codePointAt(0);hash=Math.imul(hash,16777619);}return Math.abs(hash%360);}
 function bulkControls(panel,rows){
  const selected=new Map(),controls=el('div',undefined,'bulk-controls'),allLabel=el('label',undefined,'booking-check bulk-all'),all=el('input');all.type='checkbox';all.setAttribute('aria-label','Seleccionar todos los turnos de esta página');allLabel.append(all,document.createTextNode('Seleccionar todos los de esta página'));controls.append(allLabel);
  const bar=el('div',undefined,'bulk-actions');bar.hidden=true;bar.setAttribute('role','group');bar.setAttribute('aria-label','Acciones para turnos seleccionados');const count=el('span');bar.append(count);
  const checks=new Map();
  function update(){bar.hidden=selected.size===0;count.textContent=selected.size+' de 30 turnos seleccionados';all.checked=rows.length>0&&selected.size===rows.length;all.indeterminate=selected.size>0&&selected.size<rows.length;for(const [id,box]of checks)box.checked=selected.has(id);}
  function clear(){selected.clear();update();}
  all.addEventListener('change',()=>{if(locked()){update();return;}if(all.checked&&rows.length>30){all.checked=false;ctx.message('Hay más de 30 turnos en esta página. Filtrá o seleccioná hasta 30 individualmente.',true);return;}selected.clear();if(all.checked)for(const row of rows)selected.set(row.id,row);update();});
  for(const [label,kind] of [['Marcar presentes','present'],['Cancelar seleccionados','cancel'],['Reagendar sesiones canceladas','recover']])bar.append(action(label,()=>{if(selected.size)ctx.work(()=>previewBulk(kind,[...selected.values()]));},kind==='recover'?'b':'s'));
  bar.append(action('Quitar selección',clear));controls.append(bar);panel.append(controls);
  return t=>{const label=el('label',undefined,'booking-check bulk-patient'),input=el('input');input.type='checkbox';input.setAttribute('aria-label','Seleccionar turno de '+t.paciente+' el '+t.fecha+' a las '+String(t.hora).slice(0,5));checks.set(t.id,input);input.addEventListener('change',()=>{if(locked()){update();return;}if(input.checked){if(selected.size>=30){input.checked=false;ctx.message('Se pueden seleccionar hasta 30 turnos por operación.',true);return;}selected.set(t.id,t);}else selected.delete(t.id);update();});label.append(input,document.createTextNode('Seleccionar'));return label;};
 }
 async function previewBulk(kind,rows){
  const selected=rows.map(t=>({id:t.id,version:t.version}));const review=await rpc('marathon_turns_preview',{p_action:kind,p_turns:selected});
  if(!bulkDialog){bulkDialog=el('dialog');bulkDialog.id='bulk-dialog';$('#workspace').append(bulkDialog);bulkDialog.addEventListener('cancel',e=>{if(bulkPending)e.preventDefault();});}
  bulkDialog.replaceChildren();const heading=el('h2',kind==='recover'?'Revisar recuperaciones':kind==='cancel'?'Revisar cancelaciones':'Revisar presentes');bulkDialog.append(heading,el('p','Se modificarán '+review.rows.length+' turnos. Comprobá los datos antes de confirmar.'));
  const list=el('ul');for(const r of review.rows){let line=r.paciente+' · DNI '+r.dni+' · '+r.fecha+' '+r.hora+' · '+r.estado;if(kind==='recover')line+=' → '+r.proposed_fecha+' '+r.proposed_hora+' · '+(r.pattern_inferred?'Patrón deducido de la serie':'Patrón guardado')+' · días '+r.pattern.days.join(', ');list.append(el('li',line));}bulkDialog.append(list);
  const controls=el('div',undefined,'form-actions');const confirm=action('Confirmar '+review.rows.length+' turnos',()=>commitBulk(),'b');confirm.id='bulk-confirm';controls.append(confirm,action('Cerrar revisión',()=>{if(!bulkPending)bulkDialog.close();}));bulkDialog.append(controls);
  bulkDialog._reviewData={p_request_id:crypto.randomUUID(),p_data:{action:kind,turns:selected,review_token:review.review_token}};bulkDialog.showModal();
 }
 async function commitBulk(){
  if(!bulkDialog?.open||bulkPending||ctx.isBusy())return;
  const data=bulkDialog._reviewData;if(!data)return;
  bulkPending=data;await sendBulk();
 }
 async function sendBulk(){
  if(!bulkPending||ctx.isBusy())return;ctx.setBusy(true);const request=bulkPending;
  try{const reply=await rpc('marathon_turns_commit',request,true);bulkPending=null;bulkDialog._reviewData=null;bulkDialog.close();try{if(!$('#agenda-screen').hidden)await list();await ctx.onChanged?.();ctx.message(reply.message);}catch{ctx.message('Guardado confirmado. Actualizá la agenda para ver los cambios.',true);}}
  catch(e){if(e.uncertain){ctx.message('La respuesta del servidor no llegó. Verificá el mismo guardado antes de continuar.',true);let retry=$('#bulk-retry');if(!retry){retry=action('Verificar guardado',sendBulk);retry.id='bulk-retry';bulkDialog.append(retry);}retry.disabled=false;}else{bulkPending=null;ctx.message(e.message,true);bulkDialog._reviewData=null;$('#bulk-confirm').disabled=true;bulkDialog.append(el('p','Actualizá la lista y revisá nuevamente antes de confirmar.'));}}
  finally{ctx.setBusy(false);}
 }
 function renderRows(panel,rows,weekly=false,partial=false,scope=null){
  if(ctx.getUser()?.role==='SECRETARIA')rows=rows.filter(t=>t.estado!=='CANCELADO');
  panel.replaceChildren();if(rows.length||scope)panel.append(summaryStrip(rows,partial,scope));const selectTurn=rows.length?bulkControls(panel,rows.filter(t=>!t.paused)):null;const body=DailyUI.table(panel,['Horario','Paciente','Estado / saldo','Acciones']);body.closest('table').classList.add('planilla-table');
  const blockKey=t=>JSON.stringify([t.fecha,String(t.hora).slice(0,5),t.sede,t.profesional_id||t.profesional,t.terapia_id||t.terapia]);
  const groups=new Map();for(const t of rows){const key=blockKey(t);if(!groups.has(key))groups.set(key,[]);groups.get(key).push(t);}
  for(const [key,members]of groups){members.sort((a,b)=>a.paciente.localeCompare(b.paciente,'es')||a.id.localeCompare(b.id));const meta=scope?.blocks?.find(b=>blockKey(b)===key);let firstRow=true;
  for(const t of members){const info=el('div',undefined,'recurring-patient-info');if(selectTurn&&!t.paused)info.append(selectTurn(t));info.append(el('strong',t.paciente),el('small','DNI '+t.dni),el('small',t.telefono?'Tel.: '+t.telefono:'Teléfono sin cargar','turn-phone'));
   const state=el('span',(t.paused?'PAUSADO · RESERVA LUGAR':t.estado)+(t.attendance_auto?' · Automático':''),'pill status-'+t.estado.toLowerCase()),actions=el('div',undefined,'row-actions');
   if(t.booking_notes?.startsWith('Atención excepcional'))info.append(el('span','Atención excepcional','recurring-badge'));if(t.plan)info.append(el('span',recurring.planLabel(t.plan),'recurring-badge'));else info.append(sessionCountLabel(t));
   if(t.plan?.absences>=2)info.append(el('p',t.plan.absences+' faltas seguidas · contactar','recurring-alert'));

   const edit=action('Editar ficha',()=>ctx.work(()=>patientEditor.open(t.dni)),'s');edit.setAttribute('aria-label','Editar ficha de '+t.paciente);info.append(edit);
   const who=' · '+t.paciente+' · '+String(t.hora).slice(0,5);
   const mk=(label,fn,cls='s',data)=>{const b=action(label,fn,cls);b.setAttribute('aria-label',label+who);if(data)b.dataset.action=data;b.dataset.variant=['cancel-charge','cancel'].includes(data)?'destructive':['collect','present','recover'].includes(data)||cls==='b'?'default':'secondary';return b;};
   const stateButton=value=>mk({PRESENTE:'Marcar presente',AUSENTE:'Marcar ausente',PENDIENTE:t.estado==='CANCELADO'?'Restaurar pendiente':'Marcar pendiente',CANCELADO:'Cancelar turno'}[value],()=>changeState(t,value),'s',{PRESENTE:'present',AUSENTE:'absent',CANCELADO:'cancel'}[value]);
   const money=mk('Cuenta / cobros',()=>ctx.work(()=>ctx.openMoney(t.id))),owes=t.estado==='PRESENTE'&&Number(t.debt)>0;
   const primary=[],more=[];
   if(t.paused){primary.push(money);more.push(stateButton('CANCELADO'));}else if(t.estado==='PENDIENTE'){primary.push(stateButton('PRESENTE'),stateButton('AUSENTE'),money);more.push(mk('Editar turno',()=>ctx.work(()=>openBookingEditor(t))),stateButton('CANCELADO'));}
   else if(t.estado==='PRESENTE'){primary.push(owes?mk('Cobrar',()=>ctx.work(()=>ctx.openMoney(t.id)),'b','collect'):money);more.push(stateButton('AUSENTE'),stateButton('PENDIENTE'),stateButton('CANCELADO'));}
   else if(t.estado==='AUSENTE'){primary.push(stateButton('PRESENTE'),money);more.push(stateButton('PENDIENTE'),stateButton('CANCELADO'));}
   else if(t.estado==='CANCELADO'){if(!t.has_recovery)primary.push(mk('Reagendar',()=>ctx.work(()=>previewBulk('recover',[t])),'b','recover'));else more.push(mk('Recuperación ya creada',()=>ctx.message('Esta cancelación ya fue recuperada. Consultá la nueva sesión.')));if(!t.has_recovery)more.push(stateButton('PENDIENTE'));more.push(money);}
   else{primary.push(stateButton('PENDIENTE'),money);}
   ctx.appendWhatsApp?.(actions,t);const whatsappAction=actions.querySelector('.turn-whatsapp');if(whatsappAction)whatsappAction.dataset.variant='ghost';
   const visible=primary.filter(b=>['present','collect','recover'].includes(b.dataset.action));actions.append(...visible);if(owes)actions.append(mk('Cancelar cobro',()=>ctx.work(()=>ctx.openCancelCharge(t.id)),'s','cancel-charge'));if(t.plan){
    if(t.plan.facturacion==='monthly'&&Number(t.plan.debt)>0)actions.append(mk('Cobrar cuota',()=>ctx.work(()=>recurring.openAction(t.plan.id,'quota_pay')),'b','collect'));
    actions.append(mk(t.plan.modalidad==='sessions'?'Agendar más sesiones':'Ver asignación',()=>ctx.work(()=>t.plan.modalidad==='sessions'?extendSessions(t):recurring.openPlan(t.plan.id)),'s','extend'));
    more.push(mk(t.plan.paused?'Reanudar tratamiento':'Pausar tratamiento',()=>ctx.work(()=>recurring.openAction(t.plan.id,t.plan.paused?'resume':'pause'))));
   }else actions.append(mk('Agendar más sesiones',()=>ctx.work(()=>extendSessions(t)),'s','extend'));
   const allActions=[...primary.filter(b=>!visible.includes(b)),...more];if(allActions.length){const d=el('details',undefined,'row-more'),sum=el('summary','Acciones');sum.dataset.variant='ghost';sum.setAttribute('aria-label','Más acciones'+who);const menu=el('div',undefined,'row-more-menu');menu.append(...allActions);d.append(sum,menu);actions.append(d);}
   const balance=el('span',DailyUI.money(Number(t.debt||0)+Number(t.plan?.debt||0)),Number(t.debt)>0?'ui-debt':'');balance.title='Saldo exigible de turnos presentes. Importe: '+t.importe;
   const hour=el('div',undefined,'planilla-hour-info');hour.append(el('strong',String(t.hora).slice(0,5)+(t.end_hour?' a '+t.end_hour:'')),el('small',t.fecha.split('-').reverse().join('/')),el('strong',t.profesional,'planilla-professional'),el('small',t.terapia),el('small',t.sede));
   const status=el('div');status.append(state,balance);if(t.plan?.facturacion==='monthly')status.append(el('small','Saldo de cuotas del tratamiento'));if(Object.hasOwn(t,'coverage'))status.append(el('small',coverageLabel(t.coverage),'turn-coverage-label'));const notes=el('details',undefined,'turn-notes'),notesTitle=el('summary','Observaciones');notes.append(notesTitle,el('strong','Reserva'),el('p',t.booking_notes||'Sin observaciones de la reserva.'),el('strong','Ficha del paciente'),el('p',t.patient_notes||'Sin observaciones en la ficha.'));info.append(notes);if(t.fixed_until)info.append(el('small','Fijo hasta '+t.fixed_until));
   DailyUI.row(body,[hour,info,status,actions],{id:t.id});const tr=body.lastElementChild;tr.style.setProperty('--professional-hue',professionalColor(t.profesional_id||t.profesional));tr.classList.add('planilla-patient','planilla-'+t.estado.toLowerCase());if(t.plan?.absences>=2&&!t.paused)tr.classList.add('recurring-follow');if(firstRow){tr.cells[0].rowSpan=members.length+1;tr.cells[0].classList.add('planilla-hour');firstRow=false;}else tr.cells[0].remove();
  }
  const footer=el('tr',undefined,'planilla-block-end'),cell=el('td');cell.colSpan=3;cell.textContent=meta?.availability_known?(meta.blocked?'No disponible por superposición':meta.remaining+' de '+meta.capacity+' lugares disponibles'):(meta?'Horario agendado · sin disponibilidad habilitada para nuevas reservas':members.length+' pacientes en este bloque');cell.title='Disponibilidad actual de la terapia: contempla todos los turnos del profesional, aunque no coincidan con los filtros.';footer.append(cell);body.append(footer);
  }
  loadSessionCounts(panel,rows,ctx.getApi());
 }
 function groupsCount(rows){return new Set(rows.map(t=>JSON.stringify([t.fecha,String(t.hora).slice(0,5),t.sede,t.profesional_id||t.profesional,t.terapia_id||t.terapia]))).size;}
 async function list(){
  exportReady=false;
  const period=filter.view==='week'?DailyUI.week(filter.fecha):{from:filter.fecha,to:filter.fecha};
  const [result]=await Promise.all([rpc('marathon_agenda_search',{p_filters:{...period,sede:filter.sede,prof:filter.prof,therapy:filter.therapy||'',state:filter.state||'',layout:'blocks'},p_after:pages[page],p_limit:12}),availability.load({...period,sede:filter.sede,prof:filter.prof,therapy:filter.therapy||''})]);next=result.next;
  exportReady=result.rows.length>0;renderRows($('#agenda-list'),result.rows,filter.view==='week',!!next||page>0,{summary:result.summary,blocks:result.blocks,state:filter.state||'',onState:state=>ctx.work(async()=>{clearTimeout(autoTimer);filter.state=state;page=0;pages=[null];await list();})});$('#agenda-period').textContent=filter.view==='week'?'Semana · '+DailyUI.period(period.from,period.to):DailyUI.dayLabel(filter.fecha);$('#agenda-today').setAttribute('aria-pressed',String(filter.fecha===today()));
  const blockCount=groupsCount(result.rows);$('#agenda-info').textContent=result.rows.length?result.rows.length+' '+(result.rows.length===1?'paciente':'pacientes')+' en '+blockCount+' '+(blockCount===1?'bloque completo':'bloques completos')+(ctx.getUser()?.role==='SECRETARIA'?'.':'. Incluye cancelados.'):'No hay turnos para estos filtros.';$('#agenda-page').textContent='Página '+(page+1);sync();await recurring.refresh();
 }
 function invalidate(){if($('#agenda-book-form')?.dataset.legacy!=='false')recurring?.detachBooking();chosen=null;slotKey='';resetDates();selectedDays.clear();$('#agenda-session-days')?.replaceChildren();$('#agenda-slots')?.replaceChildren();if($('#agenda-slot-info'))$('#agenda-slot-info').textContent='Consultá los horarios disponibles.';sync();}
 function refreshProfessionals(){if($('#agenda-instructions'))$('#agenda-instructions').textContent='';refreshBookingFilters();}
 function clearPatientCoverage(){++coverageGeneration;++infoGeneration;clearTimeout(infoTimer);coverageReady=false;coverageControl=null;$('#agenda-coverage')?.replaceChildren();if($('#agenda-instructions'))$('#agenda-instructions').textContent='';}
 async function loadTherapyInstructions(){
  if(!patient||!$('#a-therapy')?.value)throw Error('Elegí un paciente y una terapia.');
  if(!coverageReady)throw Error('Esperá a que se carguen las coberturas.');
  const coverage=coverageControl.read(),token=++infoGeneration,target=$('#agenda-instructions');
  target.textContent='Consultando indicaciones…';
  try{const rows=await rpc('marathon_therapy_info',{p_therapy:$('#a-therapy').value,p_insurance:coverage.type==='OBRA_SOCIAL'?coverage.obra_social_id:''});
   if(token!==infoGeneration||!target.isConnected)return;target.textContent=rows.length?rows.map(r=>r.mensaje).join('\n'):'No hay indicaciones cargadas para esta terapia y cobertura.';
  }catch(e){if(token===infoGeneration&&target.isConnected)target.textContent='No se pudieron cargar las indicaciones. Usá Ver indicaciones de la terapia para reintentar.';}
 }
 function scheduleInstructions(){
  clearTimeout(infoTimer);++infoGeneration;const target=$('#agenda-instructions');if(!target)return;target.textContent='';
  if(!coverageReady||!patient||!$('#a-therapy')?.value)return;
  try{coverageControl.read();}catch{return;}
  infoTimer=setTimeout(()=>loadTherapyInstructions().catch(()=>{}),250);
 }
 async function choosePatient(p,full=false,initialCoverage=null){
  cancelPatientSearch();clearPatientCoverage();patient=p;resetDates();const generation=coverageGeneration;$('#agenda-patient-results')?.replaceChildren();
  if($('#agenda-instructions'))$('#agenda-instructions').textContent='';const l=[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ');$('#agenda-patient-selected').textContent='Paciente seleccionado: '+l+' · DNI '+p.dni;
  $('#agenda-patient-results')?.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.dni===p.dni)));$('#agenda-book-form')?.dispatchEvent(new Event('change',{bubbles:true}));sync();maybeLoad();
  const target=$('#agenda-coverage');target.append(el('p','Cargando coberturas de la ficha…'));
  try{
   const [detail,catalog]=await Promise.all([full?Promise.resolve(p):rpc('marathon_patient_get',{p_dni:p.dni}),rpc('marathon_patient_catalog')]);
   if(generation!==coverageGeneration||!target.isConnected||patient?.dni!==p.dni)return;
   patient=detail;insuranceCatalog=catalog;target.replaceChildren();coverageControl=createTurnCoverage(target,detail,catalog,initialCoverage,'booking');coverageReady=true;sync();scheduleInstructions();
  }catch(e){if(generation===coverageGeneration&&target.isConnected){target.replaceChildren(el('p','No se pudieron cargar las coberturas. Volvé a seleccionar el paciente.'));ctx.message(e.message,true);}}
 }
 // Consulta los horarios sola cuando ya están elegidos fecha, sede, terapia y profesional (el botón manual sigue disponible).
 function maybeLoad(){if($('#agenda-book-form')?.dataset.legacy==='false')return;clearTimeout(slotTimer);slotTimer=setTimeout(function tick(){if(!$('#a-fecha')||!$('#a-fecha').value||!$('#a-sede').value||!$('#a-prof').value||!$('#a-therapy').value)return;if(ctx.isBusy()||pending){if(++slotTries<20)slotTimer=setTimeout(tick,250);return;}slotTries=0;if(slotKey&&slotKey===keyNow())return;ctx.work(loadSlots);},250);}
 async function openBookingEditor(turn){
  const info=await rpc('marathon_turn_series_context',{p_id:turn.id});if(info.target.estado!=='PENDIENTE')throw Error('Solo se pueden editar turnos pendientes.');
  options=await rpc('marathon_agenda_options');const t=info.target;renderBooking(false,info);$('#agenda-booking-title').textContent='Editar turno · Reserva existente';$('#a-fecha').value=t.fecha;$('#a-sede').value=t.sede;refreshBookingFilters();$('#a-therapy').value=t.terapia_id;refreshProfessionals();$('#a-prof').value=t.profesional_id;chosen=String(t.hora).slice(0,5);$('#a-importe').value=t.importe;
  await choosePatient(await rpc('marathon_patient_get',{p_dni:t.dni}),true,t.coverage);sync();
 }
 function renderBooking(legacy=false,edit=null,seed=null){
  if(!Array.isArray(options.hours))throw Error('Falta instalar la actualización de reservas en Supabase.');
  recurring?.detachBooking();bookingEdit=edit;bookingSeed=seed;waitContext=null;clearPatientCoverage();patient=null;chosen=null;const panel=$('#agenda-booking');panel.replaceChildren();panel.hidden=false;
  cancelPatientSearch();const head=el('div',undefined,'detail-head'),title=el('h2','Nueva reserva');title.id='agenda-booking-title';head.append(title,action('Cerrar reserva',()=>closeBooking()));panel.append(head);
  const search=el('div');search.id='agenda-patient-search';const queryInput=field(search,'patient-query','Buscar paciente por DNI, nombre o teléfono','','search');queryInput.maxLength=100;queryInput.autocomplete='off';const find=action('Buscar paciente',()=>{clearTimeout(liveTimer);ctx.work(findPatients);});search.append(find,action('Nuevo paciente',()=>ctx.work(openPatientCreate)));
  let searchGen=0,liveTimer=null;
  cancelPatientSearch=()=>{clearTimeout(liveTimer);++searchGen;};
  async function findPatients(){
   if(!document.contains(queryInput))return;
   const gen=++searchGen;patient=null;clearPatientCoverage();resetDates();$('#agenda-patient-selected').textContent='Seleccioná un paciente de los resultados.';sync();
   const data=await rpc('marathon_patient_search',{p_query:queryInput.value.trim(),p_after:null,p_limit:10});
   if(gen!==searchGen||!document.contains(queryInput))return;
   const results=$('#agenda-patient-results');results.replaceChildren();
   for(const p of data.rows){const label=[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ');const pick=action('Seleccionar: '+label+' · DNI '+p.dni,()=>{if(!locked())choosePatient(p);},'patient-item');pick.dataset.dni=p.dni;pick.setAttribute('aria-pressed','false');results.append(pick);}
   if(!data.rows.length)results.append(el('p','Sin coincidencias. Cargá el paciente desde Pacientes si todavía no existe.'));
   if(data.next)results.append(el('p','Hay más resultados. Escribí el DNI o un nombre más específico.','subtitle'));
  }
  search.addEventListener('submit',event=>{event.preventDefault();clearTimeout(liveTimer);ctx.work(findPatients);});
  queryInput.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();clearTimeout(liveTimer);ctx.work(findPatients);}});
  // Búsqueda mientras se escribe: no bloquea la pantalla ni el cursor.
  queryInput.addEventListener('input',()=>{cancelPatientSearch();patient=null;clearPatientCoverage();resetDates();$('#agenda-patient-results').replaceChildren();$('#agenda-patient-selected').textContent=queryInput.value.trim().length<3?'Escribí al menos 3 caracteres o presioná Buscar paciente.':'Buscando pacientes…';sync();if(queryInput.value.trim().length<3)return;liveTimer=setTimeout(()=>{if(locked())return;findPatients().catch(e=>ctx.message(e.message,true));},350);});
  const patientStep=el('section',undefined,'booking-step');patientStep.id='agenda-step-patient';patientStep.append(el('h3',legacy?'3. Paciente':'2. Paciente'),search);const results=el('div',undefined,'list-items');results.id='agenda-patient-results';const selected=el('p','Seleccioná un paciente de los resultados.');selected.id='agenda-patient-selected';selected.className='selected-patient';selected.setAttribute('role','status');patientStep.append(results,selected);const editPatient=action('Editar ficha del paciente',()=>{if(!locked()&&patient)ctx.work(()=>patientEditor.open(patient.dni));});editPatient.id='agenda-edit-patient';patientStep.append(editPatient);
  const coverage=el('div');coverage.id='agenda-coverage';patientStep.append(coverage);
  const form=el('form');form.id='agenda-book-form';form.dataset.legacy=String(legacy);if(!legacy)form.classList.add('recurring-flow');const context=el('section',undefined,'booking-step');context.append(el('h3','1. Fecha, sede, terapia y profesional'));const grid=el('div',undefined,'form-grid');context.append(grid);form.append(context);
  if(!legacy){const label=el('label',undefined,'checkbox-filter'),check=el('input'),copy=el('span');check.type='checkbox';check.id='a-exception';check.checked=!!edit?.target?.excepcional;check.disabled=!!edit;label.hidden=!!edit&&!edit.target.excepcional;copy.append(el('strong','Atención excepcional'),el('br'),el('small','Un único turno, incluso en una fecha pasada o fuera del horario habitual.','subtitle'));label.append(check,copy);form.prepend(label);check.addEventListener('change',refreshBookingFilters);}
  const date=field(grid,'fecha','Fecha de inicio',filter.fecha,'date',true);date.min='2000-01-01';date.max='2100-12-31';date.addEventListener('change',refreshBookingFilters);
  const site=select(grid,'sede','Sede',options.sedes,'Elegir sede');site.value=filter.sede;site.addEventListener('change',refreshBookingFilters);
  const therapy=select(grid,'therapy','Terapia',options.therapies,'Elegir terapia');therapy.addEventListener('change',refreshProfessionals);
  const prof=select(grid,'prof','Profesional',[],'Elegir profesional');prof.addEventListener('change',()=>{invalidate();maybeLoad();});
  const instructions=el('p');instructions.id='agenda-instructions';patientStep.append(action('Ver indicaciones de la terapia',()=>ctx.work(loadTherapyInstructions)),instructions);
  const slotStep=el('section',undefined,'booking-step');slotStep.id='agenda-step-slots';slotStep.append(el('h3','2. Horario'));const query=action('Consultar horarios',()=>ctx.work(loadSlots));query.id='agenda-check-slots';slotStep.append(query);
  const info=el('p','Consultá los horarios disponibles.','subtitle');info.id='agenda-slot-info';const slots=el('div',undefined,'slots');slots.id='agenda-slots';slotStep.append(info,slots);form.append(slotStep,patientStep);
  const sessions=el('section',undefined,'booking-sessions');sessions.id='agenda-step-sessions';sessions.append(el('h3','4. Cantidad de turnos y fechas'));const sessionFields=el('div',undefined,'form-grid');sessions.append(sessionFields);
  const mode=select(sessionFields,'mode','Modalidad de reserva',[{id:'sessions',label:'Cantidad de sesiones'},{id:'fixed',label:'Horario fijo semanal'}],'Elegir modalidad');mode.value='sessions';mode.addEventListener('change',()=>{resetDates();sync();});
  const until=field(sessionFields,'fixed-until','Revisar horario fijo hasta',plusDays(filter.fecha||today(),84),'date');until.addEventListener('change',()=>{resetDates();sync();});
  const count=field(sessionFields,'count','Cantidad de sesiones a agendar','1','number',true);count.min=1;count.max=60;count.step=1;count.addEventListener('input',()=>{resetDates();sync();});
  const amount=field(sessionFields,'importe','Importe por turno (ARS)','0','number',true);amount.min=0;amount.max='9999999999.99';amount.step='0.01';
  const bonusAmount=field(sessionFields,'bonus-amount','Bono inicial adicional (ARS, opcional)','0','number');bonusAmount.min=0;bonusAmount.max='9999999999.99';bonusAmount.step='0.01';
  const bonusPaid=field(sessionFields,'bonus-paid','Registrar pago del bono al confirmar','','checkbox');bonusPaid.parentElement.className='checkbox-filter';
  const bonusMedium=select(sessionFields,'bonus-medium','Medio de pago del bono',[{id:'EFECTIVO',label:'Efectivo'},{id:'TRANSFERENCIA',label:'Transferencia'}],'Elegir medio');bonusMedium.value='EFECTIVO';
  const bonusNote=el('p','El bono se agrega una sola vez a la serie y se cobra por separado. Si no registrás el pago ahora, queda pendiente en la ficha. No se usa como anticipo para sesiones.','subtitle wide');sessionFields.append(bonusNote);
  const obs=field(sessionFields,'observaciones','Observaciones de la reserva','','textarea');obs.maxLength=1000;
  const datesHelp=el('p','', 'subtitle');datesHelp.id='agenda-dates-help';sessions.append(datesHelp);
  const days=el('div',undefined,'booking-days');days.id='agenda-session-days';sessions.append(days);
  const generate=action('Generar fechas',()=>ctx.work(generateDates));generate.id='agenda-generate-dates';sessions.append(generate);
  const dates=el('div',undefined,'booking-dates');dates.id='agenda-dates';const summary=el('p','Indicá la cantidad de sesiones y generá las fechas.');summary.id='agenda-dates-summary';summary.setAttribute('role','status');sessions.append(dates,summary);form.append(sessions);
  sessions.append(el('p','Antes de guardar se vuelven a comprobar todas las fechas. Si alguna perdió disponibilidad, no se reserva ninguna.','subtitle'));
  const save=el('button','Reservar turno','b');save.id='agenda-submit';save.type='submit';sessions.append(save);form.addEventListener('submit',submitBooking);
  for(const name of ['input','change'])form.addEventListener(name,event=>{++reviewGeneration;reviewLoading=false;$('#agenda-review')?.remove();if(event.target.closest('.turn-coverage')||event.target.id==='a-therapy')scheduleInstructions();if(name==='change'&&['a-therapy','a-fecha','a-sede','a-prof','a-exception'].includes(event.target.id))recurring.refreshBookingContext(event.target.id);sync();});
  panel.append(form);refreshBookingFilters();bookingDialog.append(feedback);if(!bookingDialog.open)bookingDialog.showModal();sync();
 }
 async function openPatientCreate(){
  if(pending||$('#agenda-new-patient-form'))return;
  const insurances=await rpc('marathon_patient_catalog');
  const box=el('section',undefined,'booking-step');box.id='agenda-create-patient';box.append(el('h3','Nuevo paciente para esta reserva'),el('p','Al guardar volverás a la reserva con el paciente seleccionado.'));
  const f=el('form');f.id='agenda-new-patient-form';const grid=el('div',undefined,'form-grid');f.append(grid);
  for(const [key,label,type]of [['dni','DNI','text'],['nombre','Nombre','text'],['segundo_nombre','Segundo nombre','text'],['apellido','Apellido','text'],['telefono','Teléfono','tel'],['email','Correo','email'],['nacimiento','Fecha de nacimiento','date']]){
   if(key==='telefono'){appendPatientPhone(grid,null,'new-patient');continue;}
   const i=field(grid,'new-'+key,label,'',type,['dni','nombre','apellido'].includes(key));i.name=key;i.maxLength=key==='email'?254:500;
   if(key==='dni'){i.inputMode='numeric';i.pattern='[0-9]{1,12}';i.maxLength=12;}
  }
  appendPatientCoverages(grid,insurances,null,'new-patient');
  const save=el('button','Guardar paciente y volver a la reserva','b');save.type='submit';
  const cancel=action('Volver a la reserva',()=>{if(!locked()){box.remove();$('#agenda-book-form').hidden=false;$('#a-patient-query').focus();}});cancel.id='agenda-patient-create-cancel';
  f.append(save,cancel);f.addEventListener('submit',async event=>{
   event.preventDefault();if(locked()||!f.reportValidity())return;
   let data;try{data=patientPayload(f);}catch(e){ctx.message(e.message,true);return;}
   pending={p_request_id:crypto.randomUUID(),p_action:'patient',p_data:data};await send();
  });box.append(f);$('#agenda-book-form').hidden=true;bookingPanel.append(box);sync();$('#a-new-dni').focus();
 }
 function receiptText(r){
  return ['MARATHON · COMPROBANTE DE TURNOS',r.patient+' · DNI '+r.dni,'Cobertura: '+coverageLabel(r.coverage)+(r.coverage?.affiliate?' · Afiliado / referencia: '+r.coverage.affiliate:''),r.therapy+' · '+r.prof,'Sede: '+r.sede,'Importe por sesión: '+DailyUI.money(r.importe),r.fixed_until?'Horario fijo semanal · revisar hasta '+DailyUI.dayLabel(r.fixed_until):'',...r.dates.map(date=>{const session=r.sessions?.find(s=>s.fecha===date);return DailyUI.dayLabel(date)+' · '+r.hora+(session?.end_hour?'–'+session.end_hour+' ('+session.duration_min+' min)':'');}),r.observaciones?'Observaciones: '+r.observaciones:'',r.bonus?'Bono inicial único: '+DailyUI.money(r.bonus.importe)+' · Cobrado neto: '+DailyUI.money(r.bonus.paid)+' · Saldo del bono: '+DailyUI.money(r.bonus.debt):'','La reserva de sesiones no acredita su pago.'].filter(Boolean).join('\n');
 }
 function showReceipt(){
  if(!lastReceipt)return;
  let dialog=$('#agenda-receipt');if(!dialog){dialog=el('dialog');dialog.id='agenda-receipt';dialog.setAttribute('aria-labelledby','agenda-receipt-title');$('#workspace').append(dialog);}
  dialog.replaceChildren();const title=el('h2','Comprobante de turnos');title.id='agenda-receipt-title';const text=el('pre',receiptText(lastReceipt));text.className='booking-receipt-text';
  const status=el('p');status.setAttribute('role','status');
  const copy=action('Copiar para enviar',async()=>{try{await navigator.clipboard.writeText(text.textContent);status.textContent='Comprobante copiado.';}catch{status.textContent='No se pudo copiar automáticamente. Seleccioná el texto del comprobante para copiarlo.';}});
  dialog.append(title,text);const receipt=lastReceipt;dialog.append(el('p','La confirmación por WhatsApp indica la primera sesión reservada. Podés copiar el comprobante para compartir todas las fechas.','subtitle'));ctx.appendWhatsApp?.(dialog,{paciente:receipt.patient,telefono:receipt.telefono,fecha:[...receipt.dates].sort()[0],hora:receipt.hora,sede:receipt.sede,terapia:receipt.therapy,profesional:receipt.prof},'confirmation');dialog.append(copy,action('Imprimir',()=>window.print()),action('Cerrar comprobante',()=>dialog.close()),status);if(!dialog.open)dialog.showModal();
 }
 async function openTurnCoverage(turn){
  const [p,catalog,fresh]=await Promise.all([rpc('marathon_patient_get',{p_dni:turn.dni}),rpc('marathon_patient_catalog'),rpc('marathon_turn_account',{p_id:turn.id})]);turn={...turn,...fresh};
  if(!canChangeCoverage(turn))throw Error('Solo administración puede corregir la cobertura de un turno que no está pendiente.');
  let dialog=$('#turn-coverage-dialog');if(!dialog){dialog=el('dialog');dialog.id='turn-coverage-dialog';dialog.setAttribute('aria-labelledby','turn-coverage-title');$('#workspace').append(dialog);dialog.addEventListener('cancel',event=>{if(locked())event.preventDefault();});dialog.addEventListener('close',()=>{feedbackAnchor.after(feedback);dialog.replaceChildren();});}
  const title=el('h2','Cobertura del turno');title.id='turn-coverage-title';dialog.replaceChildren(title,el('p',turn.paciente+' · '+turn.fecha+' · '+String(turn.hora).slice(0,5)),el('p','Cobertura actual: '+coverageLabel(turn.coverage)));
  const f=el('form');f.id='turn-coverage-form';const control=createTurnCoverage(f,p,catalog,turn.coverage,'turn');
  const reason=field(f,'coverage-reason','Motivo de la corrección','','textarea',true);reason.minLength=3;reason.maxLength=500;
  const save=el('button','Guardar cobertura','b');save.type='submit';f.append(save,action('Cerrar cobertura',()=>{if(!locked())dialog.close();}));
  f.addEventListener('submit',async event=>{event.preventDefault();if(locked()||!f.reportValidity())return;if(!canChangeCoverage(turn)){ctx.message('Solo administración puede corregir la cobertura de un turno que no está pendiente.',true);return;}let coverage;try{coverage=control.read();}catch(e){ctx.message(e.message,true);return;}
   pending={p_request_id:crypto.randomUUID(),p_action:'coverage',p_data:{id:turn.id,version:turn.version,coverage,motivo:reason.value}};await send();});
  dialog.append(f,el('p','Se modifica solo este turno. Se conservan importe, asistencia y pagos; la corrección queda registrada.'),feedback);dialog.showModal();sync();
 }
 async function extendSessions(turn){
  const source=await rpc('marathon_extension_context',{p_id:turn.id});
  const [freshOptions,p]=await Promise.all([rpc('marathon_agenda_options'),rpc('marathon_patient_get',{p_dni:source.dni})]);options=freshOptions;
  let date=source.after_date,selection=null;
  for(let i=0;i<14&&!selection;i++){const candidate=plusDays(source.after_date,i);for(const s of source.schedules||[]){const prof=options.professionals.find(x=>x.id===s.profesional_id);if(Number(s.dia)===weekday(candidate)&&prof&&supports(prof,source.therapy,candidate,s.sede,String(s.hora).slice(0,5))){date=candidate;selection=s;break;}}}
  const seed={...source,...(selection?{sede:selection.sede,prof:selection.profesional_id,hora:String(selection.hora).slice(0,5)}:{})};
  renderBooking(false,null,seed);$('#agenda-booking-title').textContent='Nueva serie · Agendar más sesiones';
  const note=el('p','Nueva serie con los datos anteriores precargados. Podés modificar todos los datos y agregar un nuevo bono. Los turnos y saldos anteriores se conservan.','subtitle');note.id='agenda-extension-info';$('#agenda-book-form').before(note);
  $('#a-fecha').value=date;$('#a-sede').value=seed.sede;refreshBookingFilters();$('#a-therapy').value=seed.therapy;refreshProfessionals();$('#a-prof').value=seed.prof;chosen=seed.hora;$('#a-importe').value=seed.importe;$('#a-observaciones').value=seed.booking_notes||'';clearTimeout(slotTimer);
  await choosePatient(p,true,seed.coverage);clearTimeout(slotTimer);sync();
 }
 async function bookAvailableSlot(selection){
  renderBooking();$('#a-fecha').value=selection.date;$('#a-sede').value=selection.sede;refreshBookingFilters();
  $('#a-therapy').value=selection.therapy;refreshProfessionals();$('#a-prof').value=selection.prof;clearTimeout(slotTimer);
  if(!$('#a-therapy').value||!$('#a-prof').value){ctx.message('La selección ya no está disponible. Revisá la terapia y el profesional.',true);sync();return;}
  await loadSlots(selection.hora);
 }
 function selectSlot(row){
  if(row.blocked||row.remaining<1)return;chosen=row.hora;resetDates();selectedDays=new Set([weekday($('#a-fecha').value)]);renderSessionDays();
  $('#agenda-slots').querySelectorAll('button').forEach(x=>{const selected=x.dataset.hora===chosen;x.classList.toggle('on',selected);x.setAttribute('aria-pressed',String(selected));});
  $('#agenda-slot-info').textContent='Horario elegido: '+chosen;sync();
 }
 async function loadSlots(preferredHour=null){
  if(!$('#a-fecha').value||!$('#a-sede').value||!$('#a-prof').value||!$('#a-therapy').value)throw Error('Elegí fecha, sede, terapia y profesional.');
  invalidate();slotKey='';const asked=keyNow();const rows=await rpc('marathon_agenda_slots',{p_fecha:$('#a-fecha').value,p_sede:$('#a-sede').value,p_prof:$('#a-prof').value,p_therapy:$('#a-therapy').value});
  if(asked!==keyNow()||!$('#agenda-book-form'))return;
  for(const r of rows){const b=action(r.hora,()=>{if(!locked())selectSlot(r);},'slot'+(r.remaining<1?' x':r.remaining<r.capacity?' w':''));b.dataset.available=String(!r.blocked&&r.remaining>0);b.dataset.hora=r.hora;b.setAttribute('aria-pressed','false');b.append(el('small',r.blocked?'No disponible':r.remaining+' de '+r.capacity+' cupos libres'+(r.end_hour?' · hasta '+r.end_hour:'')+(r.shortened?' · '+r.duration_min+' min hasta el cierre':'')));appendSharedSpace(b,r);$('#agenda-slots').append(b);}
  $('#agenda-slot-info').textContent=rows.length?'Elegí un horario.':'No hay horarios de atención para esta selección.';sync();if(keyNow()===asked)slotKey=asked;
  if(preferredHour){const row=rows.find(r=>r.hora===preferredHour&&!r.blocked&&r.remaining>0);if(row){selectSlot(row);ctx.message('');$('#a-patient-query')?.focus();}else ctx.message('Ese horario ya no tiene disponibilidad. Elegí otro de los horarios actualizados.',true);}

 }
 function plusDays(date,n){const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);}
 async function submitBooking(event,confirmedData=null){
  event.preventDefault();if(locked()||reviewLoading)return;const form=event.currentTarget;if(!form.reportValidity())return;
  if(!patient||!chosen){ctx.message('Seleccioná un paciente y un horario.',true);return;}
  const dates=[...selectedDates].sort();
  if(datesKey!==datesNow()||dates.length!==wantedSessions()||dates.length<1||dates.length>60){ctx.message('Generá las fechas y tildá exactamente '+wantedSessions()+' sesiones antes de reservar.',true);return;}
  if(!coverageReady){ctx.message('Esperá a que se carguen las coberturas del paciente.',true);return;}
  let coverage;try{coverage=coverageControl.read();}catch(e){ctx.message(e.message,true);return;}
  const data={dates,sede:$('#a-sede').value,prof:$('#a-prof').value,therapy:$('#a-therapy').value,dni:patient.dni,hora:chosen,importe:Number($('#a-importe').value),observaciones:$('#a-observaciones').value,coverage,series_days:[...selectedDays].sort()};
  const bonus=Number($('#a-bonus-amount')?.value||0);if(bonus>0){data.bonus_amount=bonus;data.bonus_paid=$('#a-bonus-paid').checked;if(data.bonus_paid)data.bonus_medium=$('#a-bonus-medium').value;}
  if(isFixed()){if(JSON.stringify(dates)!==JSON.stringify(fixedDates())){ctx.message('El horario fijo debe incluir todas las fechas elegidas hasta la revisión.',true);return;}data.fixed_until=$('#a-fixed-until').value;data.fixed_from=$('#a-fecha').value;data.fixed_days=[...selectedDays].sort();}
  const snapshot=JSON.stringify(data);
  if(confirmedData!==snapshot){
   $('#agenda-review')?.remove();
   const generation=++reviewGeneration;let existing;reviewLoading=true;sync();
   try{existing=await rpc('marathon_patient_upcoming',{p_dni:patient.dni,p_therapy:data.therapy,p_limit:50});}
   catch(e){if(generation===reviewGeneration)ctx.message('No se pudieron consultar los turnos existentes. '+e.message,true);return;}
   finally{if(generation===reviewGeneration){reviewLoading=false;sync();}}
   if(generation!==reviewGeneration||!form.isConnected)return;
   const review=el('section',undefined,'card');review.id='agenda-review';review.setAttribute('aria-label','Revisar reserva');
   review.append(el('h3','Revisar reserva antes de confirmar'));
   if(data.fixed_until)review.append(el('p','Horario fijo semanal · revisar hasta '+DailyUI.dayLabel(data.fixed_until)));
   const label=id=>$('#a-'+id).selectedOptions[0]?.textContent||data[id];
   review.append(el('p','Paciente: '+[patient.apellido,patient.nombre,patient.segundo_nombre].filter(Boolean).join(' ')+' · DNI '+patient.dni),el('p','Sede: '+label('sede')+' · Terapia: '+label('therapy')+' · Profesional: '+label('prof')),el('p','Horario: '+chosen+' · Sesiones: '+dates.length));
   const list=el('ul');for(const date of dates){const session=datesPreview?.rows?.find(r=>r.fecha===date);list.append(el('li',date.split('-').reverse().join('/')+(session?.end_hour?' · '+chosen+'–'+session.end_hour+' ('+session.duration_min+' min)':'')));}review.append(list);
   review.append(el('p','Importe por sesión: '+DailyUI.money(data.importe)+' · Total de sesiones: '+DailyUI.money(data.importe*dates.length)));
   if(data.bonus_amount)review.append(el('p','Bono inicial único: '+DailyUI.money(data.bonus_amount)+(data.bonus_paid?' · Se registrará su pago por '+data.bonus_medium:' · Pendiente de cobro')),el('p','Sesiones más bono: '+DailyUI.money(data.importe*dates.length+data.bonus_amount)+'. Los saldos se mantienen separados.'));
   review.append(el('p','Cobertura: '+coverageLabel(coverage)+(coverage.affiliate?' · Afiliado / referencia: '+coverage.affiliate:'')));
   if(existing.total>0){
    const warning=el('section',undefined,'booking-existing-warning');warning.setAttribute('role','note');warning.append(el('h4','Revisá los turnos existentes'),el('p','El paciente ya tiene '+existing.total+' turno(s) pendiente(s) de esta terapia desde hoy. Verificá que esta reserva sea necesaria.'));
    const list=el('ul');for(const t of existing.rows)list.append(el('li',DailyUI.dayLabel(t.fecha)+' · '+t.hora+' · '+t.profesional+' · '+t.sede));warning.append(list);
    if(existing.limited)warning.append(el('p','Se muestran los primeros 50 turnos. Consultá la agenda para ver el resto.'));review.append(warning);
   }
   if(data.observaciones)review.append(el('p','Observaciones: '+data.observaciones));
   review.append(el('p','La reserva no acredita un pago. La disponibilidad se vuelve a comprobar al confirmar.'));
   if(waitContext)review.append(el('p','Al confirmar, se resolverá el pedido asociado de la lista de espera.'));
   const confirm=action('Confirmar reserva',()=>submitBooking({preventDefault(){},currentTarget:form},snapshot));confirm.id='agenda-confirm';
   review.append(confirm,action('Volver a editar',()=>{review.remove();$('#agenda-submit')?.focus();}));form.append(review);
   const clear=()=>review.remove();form.addEventListener('input',clear,{once:true});form.addEventListener('change',clear,{once:true});
   confirm.focus();return;
  }
  pending={p_request_id:crypto.randomUUID(),p_action:'book',p_data:data};
  pendingReceipt={...data,dates:[...data.dates],telefono:patient.telefono,patient:[patient.apellido,patient.nombre,patient.segundo_nombre].filter(Boolean).join(' '),therapy:$('#a-therapy').selectedOptions[0].textContent,prof:$('#a-prof').selectedOptions[0].textContent};
  if(waitContext)pending.wait={id:waitContext.id,version:waitContext.version};
  await send();
 }
 async function changeState(t,state){
  if(locked())return;
  if(state==='CANCELADO')return ctx.work(()=>seriesUI.open(t,'cancel'));
  pending={p_request_id:crypto.randomUUID(),p_action:'status',p_data:{id:t.id,version:t.version,estado:state}};cancelOffer=state==='CANCELADO'?{request:pending.p_request_id,turn:{...t,estado:'CANCELADO'}}:null;collectOffer=state==='PRESENTE'&&Number(t.importe)>0?{request:pending.p_request_id,turn:t.id}:null;continuityOffer=state==='PRESENTE'?{request:pending.p_request_id,info:{dni:t.dni,terapia_id:t.terapia_id,terapia:t.terapia,paciente:t.paciente,sede:t.sede,profesional_id:t.profesional_id}}:null;await send();
 }
 async function endFixed(t){if(locked()||!window.confirm('¿Finalizar el horario fijo de '+t.paciente+' desde '+t.fecha+'? Se cancelan este y los siguientes pendientes futuros. Se conservan los turnos anteriores, la asistencia y los cobros.'))return;pending={p_request_id:crypto.randomUUID(),p_action:'fixed_end',p_data:{id:t.id,version:t.version}};await send();}
 async function bookContinuation(info){
  await open();renderBooking();
  await choosePatient(await rpc('marathon_patient_get',{p_dni:info.dni}),true);
  if(info.sede){$('#a-sede').value=info.sede;refreshBookingFilters();}
  if(info.terapia_id){$('#a-therapy').value=info.terapia_id;refreshProfessionals();}
  if(info.profesional_id)$('#a-prof').value=info.profesional_id;
  ctx.sync();ctx.message('Agendá la continuación de '+info.paciente+(info.terapia?' ('+info.terapia+')':'')+'. Elegí fecha, horario y cantidad de sesiones.');
 }
 async function send(){
  if(!pending||ctx.isBusy())return;ctx.setBusy(true);const request=pending;let confirmedBooking=false;
  try{
   if(request.p_action==='patient'){
    const reply=await rpc('marathon_patient_save',{p_request_id:request.p_request_id,p_data:request.p_data,p_version:null},true);pending=null;
    $('#agenda-create-patient')?.remove();$('#agenda-book-form').hidden=false;await choosePatient({...request.p_data,dni:reply.dni,version:reply.version},true);$('#a-patient-query').value='';$('#agenda-patient-results').replaceChildren();ctx.message('Paciente guardado y seleccionado. Podés continuar con la reserva.');return;
   }
   const reply=await rpc(request.wait?'marathon_wait_book':'marathon_agenda_command',request.wait?{p_request_id:request.p_request_id,p_data:{wait_id:request.wait.id,version:request.wait.version,booking:request.p_data}}:request,true);pending=null;
   if(request.p_action==='book'){lastReceipt={...pendingReceipt,coverage:reply.coverage??pendingReceipt.coverage,sessions:reply.sessions,bonus:reply.bonus};pendingReceipt=null;confirmedBooking=true;filter.state='';filter.fecha=[...request.p_data.dates].sort()[0];filter.sede=request.p_data.sede;filter.prof=request.p_data.prof;$('#agenda-date').value=filter.fecha;$('#agenda-sede').value=filter.sede;$('#agenda-prof').value=filter.prof;closeBooking(true);}
   if(request.p_action==='coverage')$('#turn-coverage-dialog')?.close();
   page=0;pages=[null];try{if(!$('#agenda-screen').hidden)await list();await ctx.onChanged?.();ctx.message(reply.message);if(collectOffer&&collectOffer.request===request.p_request_id){const turn=collectOffer.turn,account=await rpc('marathon_turn_account',{p_id:turn});if(account.estado==='PRESENTE'&&Number(account.debt)>0){const b=action('Cobrar ahora',()=>ctx.work(()=>ctx.openMoney(turn)),'b');b.id='collect-now';b.dataset.variant='default';const cancel=action('Cancelar cobro',()=>ctx.work(()=>ctx.openCancelCharge(turn)));cancel.dataset.variant='destructive';$('#feedback').append(' ',b,' ',cancel);}}collectOffer=null;if(continuityOffer&&continuityOffer.request===request.p_request_id){const info=continuityOffer.info;try{const sc=await rpc('marathon_patient_sessions',{p_pairs:[{dni:info.dni,therapy_id:info.terapia_id}]});if(Number(sc?.[0]?.remaining)===0){const note=document.createElement('span');note.style.fontWeight='600';note.textContent=' ⚠️ Última sesión agendada de '+info.paciente+(info.terapia?' en '+info.terapia:'')+'. No tiene más turnos de esta terapia.';const bc=action('Agendar continuación',()=>ctx.work(()=>bookContinuation(info)),'b');bc.id='book-continuation';bc.dataset.variant='default';$('#feedback').append(note,' ',bc);}}catch{}}continuityOffer=null;}catch{ctx.message('Guardado confirmado. Pulsá Actualizar agenda para ver los cambios.',true);}
   if(cancelOffer?.request===request.p_request_id){ctx.appendWhatsApp?.($('#feedback'),cancelOffer.turn);cancelOffer=null;}
  }catch(e){
   if(e.uncertain){ctx.message(e.message,true);if(!$('#retry-agenda')){const retry=action('Verificar guardado',send);retry.id='retry-agenda';$('#feedback').append(retry);}}
   else{pending=null;cancelOffer=null;ctx.message(e.message,true);if(request.p_action==='book'){pendingReceipt=null;invalidate();}}
  }finally{if(!pending)$('#retry-agenda')?.remove();ctx.setBusy(false);if(confirmedBooking&&lastReceipt){$('#feedback').append(' ',action('Ver comprobante',showReceipt));showReceipt();}}
 }
 function applyFilter(date){return ctx.work(async()=>{filter={fecha:date||$('#agenda-date').value||today(),sede:$('#agenda-sede').value,prof:$('#agenda-prof').value,therapy:$('#agenda-therapy').value,view:$('#agenda-view').value,state:filter.state||''};$('#agenda-date').value=filter.fecha;page=0;pages=[null];savePrefs();await list();ctx.message('');});}
 function scheduleApply(){clearTimeout(autoTimer);autoTries=0;autoTimer=setTimeout(function tick(){if(ctx.isBusy()||pending){if(++autoTries<20)autoTimer=setTimeout(tick,250);return;}applyFilter();},200);}
 $('#agenda-filter').addEventListener('submit',e=>{e.preventDefault();clearTimeout(autoTimer);applyFilter();});
 for(const id of ['agenda-date','agenda-sede','agenda-prof','agenda-therapy','agenda-view'])$('#'+id).addEventListener('change',()=>{if(id==='agenda-prof')refreshAgendaTherapies();if($('#agenda-date').value)scheduleApply();});
 const step=()=>recurring.isCustom()?7:$('#agenda-view').value==='week'?7:1,base=()=>$('#agenda-date').value||filter.fecha||today();
 $('#agenda-prev-day').addEventListener('click',()=>{clearTimeout(autoTimer);applyFilter(DailyUI.dateAdd(base(),-step()));});
 $('#agenda-next-day').addEventListener('click',()=>{clearTimeout(autoTimer);applyFilter(DailyUI.dateAdd(base(),step()));});
 $('#agenda-today').addEventListener('click',()=>{clearTimeout(autoTimer);applyFilter(today());});
 $('#agenda-export').addEventListener('click',()=>ctx.work(async()=>{if(recurring.isCustom()){await recurring.exportView();return;}const date=$('#agenda-date').value;if(!date)return;const site=$('#agenda-sede').value,prof=$('#agenda-prof').value,therapy=$('#agenda-therapy').value,period=$('#agenda-view').value==='week'?DailyUI.week(date):{from:date,to:date};await ctx.exportTurns?.({...period,sede:site,prof,therapy,state:filter.state||''},{sede:options.sedes.find(s=>s.id===site)?.label,prof:options.professionals.find(p=>p.id===prof)?.label,therapy:options.therapies.find(t=>t.id===therapy)?.label});}));
 $('#agenda-new').addEventListener('click',()=>ctx.work(async()=>{options=await rpc('marathon_agenda_options');renderBooking();ctx.message('');}));
 $('#agenda-next').addEventListener('click',()=>ctx.work(async()=>{if(!next)return;pages=pages.slice(0,page+1);pages.push(next);page++;await list();}));
 $('#agenda-previous').addEventListener('click',()=>ctx.work(async()=>{if(page>0){page--;await list();}}));
 async function openFromWait(r){await open();renderBooking();waitContext=r;await choosePatient(await rpc('marathon_patient_get',{p_dni:r.dni}),true);$('#agenda-patient-search').hidden=true;$('#agenda-patient-selected').textContent=[patient.apellido,patient.nombre].join(' ')+' · DNI '+patient.dni+' · Preferencia: '+r.preference_label;$('#a-sede').value=r.sede;refreshBookingFilters();$('#a-therapy').value=r.terapia_id;refreshProfessionals();$('#a-prof').value=r.profesional_id||'';ctx.sync();maybeLoad();}
 return {open,renderRows,openPlan:id=>recurring.openPlan(id),openAt:async(date,site)=>{filter={fecha:date,sede:site||'',prof:'',therapy:'',view:'day'};pages=[null];page=0;await open();},startBooking:()=>{renderBooking();ctx.message('');},bookFor:async p=>{await open();renderBooking();await choosePatient(p);ctx.message('');$('#a-therapy')?.focus();},openFromWait,reload:list,sync,isPending:()=>!!pending||!!bulkPending||seriesUI.isPending()||patientEditor.isPending()||recurring.isPending(),reset:()=>{seriesUI.reset();recurring.reset();patientEditor.reset();availability.reset();pending=null;bulkPending=null;if(bulkDialog)bulkDialog._reviewData=null;if(bulkDialog?.open)bulkDialog.close();cancelOffer=null;pendingReceipt=null;lastReceipt=null;insuranceCatalog=[];if($('#turn-coverage-dialog')){$('#turn-coverage-dialog').close();$('#turn-coverage-dialog').replaceChildren();}if($('#agenda-receipt')){$('#agenda-receipt').close();$('#agenda-receipt').replaceChildren();}closeBooking(true);clearTimeout(autoTimer);prefsLoaded=false;collectOffer=null;continuityOffer=null;filter={fecha:'',sede:'',prof:'',therapy:'',view:'day'};options={sedes:[],therapies:[],professionals:[]};pages=[null];page=0;next=null;$('#agenda-list').replaceChildren();$('#agenda-recovery').replaceChildren();$('#agenda-info').textContent='';$('#agenda-page').textContent='';$('#agenda-date').value='';$('#agenda-sede').replaceChildren();$('#agenda-prof').replaceChildren();}};
}

