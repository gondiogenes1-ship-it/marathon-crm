import {BillingXlsx} from './xlsx.js?v=20261019-0110';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const date=d=>String(d||'').split('-').reverse().join('/');
const when=iso=>{try{return new Date(iso).toLocaleDateString('es-AR',{timeZone:'America/Argentina/Buenos_Aires',day:'2-digit',month:'2-digit'});}catch{return'';}};
export function createBilling(ctx){
 const $=s=>document.querySelector(s);const rpc=(n,a)=>ctx.getApi().rpc(n,a);
 let data=null;
 const host=()=>$('#report-results');
 function metaText(row){return row.marked?('Cargado'+(row.marked_by?' por '+row.marked_by:'')+(row.marked_at?' · '+when(row.marked_at):'')):'';}
 function updateCount(){const t=$('#billing-progress');if(!t)return;const marked=data.rows.filter(r=>r.marked).length,total=data.rows.length,pct=total?Math.round(100*marked/total):0;t.textContent=marked+' de '+total+' cargados en la plataforma de la obra social';const fill=$('#billing-progress-fill');if(fill)fill.style.width=pct+'%';const track=$('#billing-progress-track');if(track)track.setAttribute('aria-label',marked+' de '+total+' pacientes cargados ('+pct+'%)');}
 async function toggleMark(row,input,metaEl,cardEl){
  input.disabled=true;
  try{const r=await rpc('marathon_billing_mark',{p_periodo:data.month,p_modality:row.modality,p_os_id:row.os_id||'',p_dni:row.dni,p_marked:input.checked});
   row.marked=!!r.marked;row.marked_by=r.by||'';row.marked_at=r.at||null;
   cardEl.classList.toggle('billing-done',row.marked);metaEl.textContent=metaText(row);updateCount();}
  catch(e){input.checked=!input.checked;ctx.message('No se pudo guardar la marca. '+(e.message||''),true);}
  finally{input.disabled=false;}
 }
 function sessionsTable(sessions){const wrap=el('div',undefined,'table-scroll'),t=el('table'),head=el('thead'),hr=el('tr');for(const hdr of ['Fecha','Terapia','Profesional','Sede']){const th=el('th',hdr);th.scope='col';hr.append(th);}head.append(hr);t.append(head);const b=el('tbody');for(const s of sessions){const tr=el('tr');tr.append(el('td',date(s.fecha)),el('td',s.terapia||''),el('td',s.profesional||''),el('td',s.sede||''));b.append(tr);}t.append(b);wrap.append(t);return wrap;}
 function card(row){
  const c=el('div',undefined,'billing-row'+(row.marked?' billing-done':''));
  const check=el('label',undefined,'billing-check'),input=el('input');input.type='checkbox';input.checked=!!row.marked;input.setAttribute('aria-label','Marcar como cargado a '+row.surname+' '+row.name);check.append(input,el('span','Cargado'));
  const main=el('div',undefined,'billing-main');main.append(el('strong',row.surname+', '+row.name));
  const sub=el('div',undefined,'billing-sub');sub.append(el('span','DNI '+row.dni),el('span','Afiliado '+(row.affiliate||'—')),el('span',row.cobertura),el('span',row.done+(row.done===1?' realizada':' realizadas')));
  if(row.modality==='OBRA_SOCIAL'&&!row.affiliate)sub.append(el('span','Falta afiliado','billing-flag'));
  main.append(sub);
  const meta=el('small',metaText(row),'billing-meta');main.append(meta);
  const det=el('details',undefined,'billing-detail');det.append(el('summary','Ver sesiones ('+row.done+')'),sessionsTable(row.sessions||[]));
  input.addEventListener('change',()=>ctx.work(()=>toggleMark(row,input,meta,c)));
  c.append(check,main,det);return c;
 }
 function draw(){
  const h=host();h.classList.remove('management-results');h.replaceChildren();if(!data)return;
  const s=data.summary||{};
  const band=el('div',undefined,'management-stats');
  const tile=(l,v,n,alert)=>{const b=el('article',undefined,'management-stat'+(alert?' stat-alert':''));b.append(el('span',l),el('strong',v));if(n)b.append(el('small',n));return b;};
  band.append(tile('Pacientes',String(s.patients??0),(s.lines??0)+' líneas de cobertura'),tile('Atenciones',String(s.sessions??0),'Realizadas en el mes'),tile('Sin afiliado',String(s.missing_affiliate??0),'Obra social o ART a completar',Number(s.missing_affiliate)>0));
  h.append(band);
  const progWrap=el('div',undefined,'billing-progress-wrap');
  const prog=el('p','','subtitle billing-progress');prog.id='billing-progress';
  const track=el('div',undefined,'mgmt-track');track.id='billing-progress-track';track.setAttribute('role','img');
  const fill=el('span',undefined,'mgmt-fill ok');fill.id='billing-progress-fill';track.append(fill);
  progWrap.append(prog,track);h.append(progWrap);
  if(!data.rows.length){h.append(el('p','No hay atenciones realizadas con estos filtros.','subtitle'));updateCount();return;}
  h.append(el('p','Pendientes de cargar primero; ya cargados al final.','subtitle'));
  const sorted=data.rows.slice().sort((a,b)=>(a.marked?1:0)-(b.marked?1:0));
  const list=el('div',undefined,'billing-list');for(const row of sorted)list.append(card(row));h.append(list);
  updateCount();
 }
 async function load(f){data=await rpc('marathon_billing',{p_filters:f});draw();}
 function exportFile(){
  if(!data||!data.rows.length)return;
  const rows=[];for(const r of data.rows)for(const s of (r.sessions||[]))rows.push([date(s.fecha),r.surname+', '+r.name,r.dni,r.affiliate||'',r.cobertura,s.terapia||'',s.profesional||'',s.sede||'',r.marked?'Sí':'No']);
  const cols=[{name:'Fecha',width:12},{name:'Paciente',width:34},{name:'DNI',width:14},{name:'Afiliado',width:18},{name:'Cobertura',width:26},{name:'Terapia',width:24},{name:'Profesional',width:28},{name:'Sede',width:16},{name:'Cargado',width:10}];
  const bytes=BillingXlsx.buildGrid({title:'Marathon · Facturación por cobertura',sheetName:'Facturacion',columns:cols,rows,metadata:[['Mes',data.month,'Modalidad',data.summary?.modality||'Todas'],['Obra social',data.summary?.insurance||'Todas','Consulta',data.generated_at]],note:'Una fila por sesión realizada. La columna Cargado refleja el checklist compartido. No contiene datos clínicos.'});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download='Marathon_Facturacion_'+data.month+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message('Facturación descargada (una fila por sesión).');
 }
 return {load,exportFile,hasData:()=>!!(data&&data.rows.length),reset:()=>{data=null;}};
}
