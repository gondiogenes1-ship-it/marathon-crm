import {BillingXlsx} from './xlsx.js?v=20261019-0110';

export async function exportCash(api,filters,labels={},download=downloadCash){
 const applied={...filters},records=[],seen=new Set();let cursor=null,totals={};
 do{
  const result=await api.rpc('marathon_cash_search',{p_filters:applied,p_after:cursor,p_limit:100});
  if(!cursor)totals=result.totals||{};
  records.push(...result.rows);cursor=result.next;
  if(records.length>100000)throw Error('La caja supera 100.000 movimientos. Reducí el período para descargar.');
  if(cursor){const key=JSON.stringify(cursor);if(seen.has(key))throw Error('No se pudo completar la descarga. Volvé a intentar.');seen.add(key);}
 }while(cursor);
 const columns=['Fecha','Hora','Concepto','Tipo','Terapia / categoría','Paciente','DNI','Medio','Sede','Secretaría que registra','Profesional / secretaría asociada','Ingreso','Egreso','Neto','Observaciones'];
 const detail=m=>(m.allocations||[]).map(p=>(p.associated||'Sin profesional')+' · '+p.category_label+' · $ '+Number(p.monto).toLocaleString('es-AR',{minimumFractionDigits:2,maximumFractionDigits:2})).join(' | ')||m.associated||'';
 const rows=records.map(m=>{const out=['EGRESO','REINTEGRO'].includes(m.tipo),amount=Number(m.monto)||0,notes=[m.observaciones_legacy,m.attribution_filtered?'Importe del filtro; movimiento completo: $ '+Number(m.monto_original).toLocaleString('es-AR'):null].filter(Boolean).join(' · ');return[m.fecha,String(m.hora).slice(0,5),m.concepto||m.tipo,m.tipo,m.category_label||'',m.paciente||'',m.dni||'',m.medio,m.sede,m.actor||'',detail(m),out?0:amount,out?amount:0,out?-amount:amount,notes];});
 for(const medium of ['EFECTIVO','TRANSFERENCIA']){const t=totals[medium]||{};rows.push(['','','TOTAL '+medium,'RESUMEN','','','',medium,'','','',Number(t.income)||0,Number(t.expense)||0,Number(t.net)||0,'']);}
 const sum=k=>Object.values(totals).reduce((n,t)=>n+Number(t[k]||0),0);
 rows.push(['','','TOTAL GENERAL','RESUMEN','','','','','','','',sum('income'),sum('expense'),sum('net'),'']);
 const bytes=BillingXlsx.buildGrid({title:'Marathon · Caja',sheetName:'Caja',columns:columns.map((name,i)=>({name,numeric:i>=11&&i<=13,width:i===2||i===5||i===10||i===14?40:22})),rows,metadata:[['Desde',applied.from,'Hasta',applied.to,'Sede',labels.sede||applied.sede||'Todas'],['Medio',applied.medium||'Todos','Terapia / categoría',labels.category||applied.category||'Todas'],['Profesional',labels.prof||applied.prof||'Todos','Secretaría',labels.actor||applied.actor||'Todas']],note:'Todos los movimientos de los filtros aplicados, incluidas todas las páginas. Profesional y terapia según aplicaciones vigentes a sesiones, bonos y cuotas. Al filtrar se suma solo el importe atribuido; el importe original se conserva. Filas RESUMEN: totales informativos, no son movimientos adicionales. Importes en ARS.'});
 download(bytes,'Marathon_Caja_'+applied.from+'_'+applied.to+'.xlsx');return records.length;
}
function downloadCash(bytes,name){const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
