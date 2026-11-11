import {appendSharedSpace} from './shared-space.js?v=20261028-0131-espacio';
import {DailyUI} from './daily.js?v=20261019-0110';

export function createAgendaAvailability({getApi,container,onBook,isBusy=()=>false}){
 let generation=0;
 const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 function reset(){++generation;container.replaceChildren();}
 async function load(filters){
  const token=++generation;container.replaceChildren(el('h3','Horarios y lugares libres'));
  if(!filters.sede||!filters.prof||!filters.therapy){container.append(el('p','Elegí sede, profesional y terapia para consultar los cupos. La disponibilidad contempla los turnos del profesional en todas las sedes.','subtitle'));return;}
  const count=Math.round((new Date(filters.to+'T12:00:00Z')-new Date(filters.from+'T12:00:00Z'))/86400000)+1;
  if(!Number.isInteger(count)||count<1||count>7){container.append(el('p','La consulta de cupos admite hasta siete días.'));return;}
  const loading=el('p','Consultando disponibilidad…');loading.setAttribute('role','status');container.append(loading);
  const dates=Array.from({length:count},(_,i)=>DailyUI.dateAdd(filters.from,i));
  const results=await Promise.allSettled(dates.map(date=>getApi().rpc('marathon_agenda_slots',{p_fecha:date,p_sede:filters.sede,p_prof:filters.prof,p_therapy:filters.therapy})));
  if(token!==generation||!container.isConnected)return;loading.remove();
  results.forEach((result,i)=>{
   const day=document.createElement('details');day.open=count===1;day.append(el('summary',DailyUI.dayLabel(dates[i])));
   if(result.status==='rejected'){day.open=true;const error=el('p','No se pudo consultar la disponibilidad de este día. Usá Actualizar agenda.');error.setAttribute('role','alert');day.append(error);}
   else if(!result.value.length)day.append(el('p','Sin horarios de atención para esta selección.','subtitle'));
   else{const slots=el('div',undefined,'slots');for(const s of result.value){const slot=el('button',s.hora+(s.end_hour?'–'+s.end_hour:''),'slot'+(s.blocked||s.remaining<1?' x':s.remaining<s.capacity?' w':''));slot.type='button';slot.dataset.available=String(!s.blocked&&s.remaining>0);slot.disabled=isBusy()||slot.dataset.available!=='true';slot.setAttribute('aria-label',DailyUI.dayLabel(dates[i])+' · '+s.hora+(s.blocked||s.remaining<1?' · Sin disponibilidad':' · Reservar turno'));slot.addEventListener('click',()=>{if(isBusy()||s.blocked||s.remaining<1)return;onBook({date:dates[i],sede:filters.sede,prof:filters.prof,therapy:filters.therapy,hora:s.hora});});slot.append(el('small',s.blocked?'Superposición con otra atención':s.remaining<1?'Sin cupo':s.remaining+' de '+s.capacity+' lugares libres'));appendSharedSpace(slot,s);slots.append(slot);}day.append(slots);}
   container.append(day);
  });
  container.append(el('p','Pulsá un horario disponible para reservar. Al abrir la reserva se actualiza el cupo y se vuelve a comprobar antes de guardar.','subtitle'));
 }
 return{load,reset,sync(){container.querySelectorAll('button.slot').forEach(b=>b.disabled=isBusy()||b.dataset.available!=='true');}};
}
