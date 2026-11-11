export function sessionCountLabel(turn){
 const e=document.createElement('small');e.className='patient-session-counts';e.dataset.sessionKey=JSON.stringify([turn.dni,turn.terapia_id]);e.textContent='Sesiones: consultando…';
 e.title='Historial de esta terapia, entre todas las sedes y profesionales. Realizadas: presentes hasta hoy. Restantes: pendientes agendadas desde hoy. No incluye ausentes ni cancelados.';return e;
}
export async function loadSessionCounts(panel,rows,api){
 const labels=[...panel.querySelectorAll('[data-session-key]')],pairs=[...new Map(rows.filter(t=>t.dni&&t.terapia_id).map(t=>[JSON.stringify([t.dni,t.terapia_id]),{dni:t.dni,therapy_id:t.terapia_id}])).values()];
 if(!pairs.length)return;
 try{
  const chunks=[];for(let i=0;i<pairs.length;i+=500)chunks.push(pairs.slice(i,i+500));
  const data=(await Promise.all(chunks.map(p_pairs=>api.rpc('marathon_patient_sessions',{p_pairs})))).flat();const map=new Map(data.map(c=>[JSON.stringify([c.dni,c.therapy_id]),c]));
  for(const label of labels){if(!label.isConnected)continue;const c=map.get(label.dataset.sessionKey);label.textContent=c&&Number.isInteger(c.completed)&&Number.isInteger(c.remaining)?'Sesiones · Realizadas: '+c.completed+' · Restantes: '+c.remaining:'Sesiones: sin dato confirmado';}
 }catch{for(const label of labels)if(label.isConnected)label.textContent='Sesiones: sin dato confirmado';}
}
