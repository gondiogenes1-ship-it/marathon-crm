import {BillingXlsx} from './xlsx.js?v=20261019-0110';
import {patientPhoneNumber,coverageLabel} from './coverage.js?v=20261027-0120';

export function turnWhatsAppUrl(t,body){
 const phone=patientPhoneNumber(t.telefono);if(!phone||typeof body!=='string'||!body.trim())return '';
 const values={paciente:t.paciente||'',fecha:/^\d{4}-\d{2}-\d{2}$/.test(t.fecha||'')?t.fecha.split('-').reverse().join('/'):String(t.fecha||''),hora:String(t.hora||'').slice(0,5),sede:t.sede||'',terapia:t.terapia||'',profesional:t.profesional||''};
 const text=body.replace(/\{([^{}]+)\}/g,(token,key)=>{if(!Object.hasOwn(values,key))throw Error('El mensaje contiene un dato no admitido. Revisalo en WhatsApp → Mensajes automáticos.');return values[key];});
 return 'https://wa.me/'+phone+'?text='+encodeURIComponent(text);
}
export function appendTurnWhatsApp(parent,t,ctx={}){
 const kind=ctx.kind||(t.estado==='CANCELADO'?'cancellation':'reminder'),labels={confirmation:'Enviar confirmación por WhatsApp',reschedule:'Avisar reprogramación por WhatsApp',cancellation:'Avisar cancelación por WhatsApp',reminder:'WhatsApp'},label=labels[kind];
 if(!label)throw Error('Tipo de aviso de WhatsApp inválido.');
 if(!patientPhoneNumber(t.telefono)){const hint=document.createElement('span');hint.className='subtitle turn-phone-missing';hint.textContent='WhatsApp: teléfono incompleto';hint.title='Completá el teléfono y la característica de ciudad en la ficha del paciente.';parent.append(hint);return null;}
 const button=document.createElement('button');button.type='button';button.className='s turn-whatsapp';button.textContent=label;button.setAttribute('aria-label',label+' · '+(t.paciente||'')+' · '+String(t.hora||'').slice(0,5));button.title='Abrir WhatsApp con el texto guardado y los datos del turno, para revisar y enviar';let opening=false;
 button.addEventListener('click',async()=>{
  if(opening||ctx.isBusy?.())return;opening=true;button.disabled=true;let popup=null;
  try{
   popup=window.open('about:blank','_blank');if(!popup)throw Error('El navegador bloqueó la ventana de WhatsApp. Permití abrirla y volvé a pulsar el botón.');popup.opener=null;popup.document.title='Preparando mensaje de Marathon';popup.document.body.textContent='Consultando el texto guardado…';
   const records=await ctx.getApi().rpc('marathon_whatsapp_templates',{}),record=records.find(r=>r.id===kind);
   const href=turnWhatsAppUrl(t,record?.body);if(!href)throw Error('No se pudo confirmar el mensaje guardado. Revisalo en WhatsApp → Mensajes automáticos.');
   if(popup.closed)throw Error('Se cerró la ventana antes de preparar el mensaje. Volvé a pulsar WhatsApp.');popup.location.replace(href);
  }catch(error){if(popup&&!popup.closed)popup.close();ctx.onError?.(error.message);}
  finally{opening=false;if(button.isConnected)button.disabled=!!ctx.isBusy?.();}
 });parent.append(button);return button;
}
export function buildTurnsExcel(result,filters,labels={}){
 if(!Array.isArray(result?.rows)||!result.rows.length)throw Error('No hay turnos para exportar con estos filtros.');
 if(result.next)throw Error('El listado supera el límite de exportación. Reducí los filtros para descargarlo completo.');
 const columns=[
  ['fecha','Fecha',false,14],['hora','Hora',false,10],['paciente','Paciente',false,30],['dni','DNI',false,16],['telefono','Teléfono',false,22],['sede','Sede',false,22],['terapia','Terapia',false,26],['profesional','Profesional',false,28],['estado','Estado',false,18],
  ['agenda_mode','Modalidad',false,22],['sessions','Sesiones del tratamiento',false,26],['monthly_debt','Saldo cuotas (una vez por tratamiento)',true,24],['coverage','Cobertura',false,26],['affiliate','Afiliado / referencia',false,22],['importe','Importe',true,16],['paid','Pagado / anticipos aplicados',true,20],['debt','Saldo exigible',true,18],['attendance_auto','Ausencia automática',false,18],['observaciones','Observaciones',false,45],['id','ID de turno',false,40]
 ];
 const seenPlans=new Set();
 const rowValue=(t,key,numeric)=>key==='agenda_mode'?(t.plan?.modalidad==='sessions'?'Cantidad de sesiones':t.plan?.modalidad==='monthly'?'Mensual':t.plan?'Indefinido':'Reserva anterior'):key==='sessions'?(t.plan?.modalidad==='sessions'?t.plan.done+'/'+t.plan.total:''):key==='monthly_debt'?(t.plan&&!seenPlans.has(t.plan.id)?(seenPlans.add(t.plan.id),Number(t.plan.debt||0)):0):key==='estado'&&t.paused?'PAUSADO':numeric?Number(t[key]||0):key==='hora'?String(t.hora||'').slice(0,5):key==='coverage'?coverageLabel(t.coverage):key==='affiliate'?String(t.coverage?.affiliate||''):key==='attendance_auto'?(t.attendance_auto?'Sí':'No'):key==='observaciones'?['Reserva: '+(t.booking_notes||''),'Ficha del paciente: '+(t.patient_notes||'')].join('\n'):String(t[key]??'');
 return BillingXlsx.buildGrid({title:'Marathon · Lista de turnos',sheetName:'Turnos',columns:columns.map(([,name,numeric,width])=>({name,numeric,width})),rows:result.rows.map(t=>columns.map(([key,,numeric])=>rowValue(t,key,numeric))),
  metadata:[['Desde',filters.from,'Hasta',filters.to],['Sede',labels.sede||filters.sede||'Todas','Profesional',labels.prof||filters.prof||'Todos'],['Estado',filters.state||'Todos','Terapia',labels.therapy||filters.therapy||'Todas','Paciente',filters.query||'Todos']],
  note:'Listado completo del período y los filtros indicados. '+result.rows.length+' turnos. Consulta: '+String(result.generated_at||new Date().toISOString())+'. Pagado incluye anticipos aplicados. Cancelados y ausentes no generan deuda por sesión. El saldo de cuotas corresponde al tratamiento y se informa una sola vez.'});
}
export async function exportTurns(api,filters,labels={},download=downloadExcel){
 const asked=structuredClone(filters),result=await api.rpc('marathon_agenda_search',{p_filters:asked,p_after:null,p_limit:10000});
 const bytes=buildTurnsExcel(result,asked,labels);
 download(bytes,'Marathon_turnos_'+asked.from+(asked.to!==asked.from?'_al_'+asked.to:'')+(asked.state?'_'+asked.state:'')+'.xlsx');
 return result.rows.length;
}
function downloadExcel(bytes,filename){
 const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'}));
 const a=document.createElement('a');a.href=url;a.download=filename;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}

