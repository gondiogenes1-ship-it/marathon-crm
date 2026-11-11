import {BillingXlsx} from './xlsx.js?v=20261019-0110';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const count=n=>Number(n??0).toLocaleString('es-AR',{maximumFractionDigits:1});
const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS',maximumFractionDigits:0}).format(Number(n||0));
const moneyShort=n=>{const v=Number(n||0);return Math.abs(v)>=1000?('$'+Math.round(v/1000)+'k'):('$'+Math.round(v));};
export function createTrends(ctx){
 const $=s=>document.querySelector(s);let data=null,observers=[],generation=0,optionsCache=null;
 const rpc=(n,a)=>ctx.getApi().rpc(n,a);
 const host=()=>$('#trends-results');
 function cleanup(){for(const o of observers)o.disconnect();observers=[];}
 function panel(title,note){const box=el('section',undefined,'management-block');box.append(el('h2',title));if(note)box.append(el('p',note,'subtitle'));return box;}
 function lineChart({title,note,points,lines,fmt,pct}){
  const box=panel(title,note);
  const legend=el('div',undefined,'trend-legend');for(const l of lines)legend.append(el('span','━ '+l.label,'trend-key '+l.cls));box.append(legend);
  const canvas=el('div',undefined,'trend-canvas');box.append(canvas);
  const draw=()=>{
   const w=Math.max(280,Math.floor(canvas.getBoundingClientRect().width||620)),h=220,left=52,right=16,top=16,bottom=32;
   let max=Math.max(1,...points.flatMap(p=>lines.map(l=>Number(p[l.key])||0)));if(pct)max=100;else max=Math.ceil(max/4)*4||4;
   const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox',`0 0 ${w} ${h}`);svg.setAttribute('role','img');svg.setAttribute('aria-label',title);
   const add=(tag,attrs,text)=>{const n=document.createElementNS(svg.namespaceURI,tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,String(v));if(text!==undefined)n.textContent=text;svg.append(n);return n;};
   const x=i=>left+(w-left-right)*(points.length<2?.5:i/(points.length-1)),y=v=>h-bottom-(h-top-bottom)*v/max;
   for(let i=0;i<=4;i++){const v=max*i/4;add('line',{x1:left,x2:w-right,y1:y(v),y2:y(v),class:'trend-grid'});add('text',{x:left-8,y:y(v)+4,'text-anchor':'end',class:'trend-axis'},fmt?fmt(v):String(Math.round(v)));}
   for(const l of lines){
    add('polyline',{points:points.map((p,i)=>`${x(i)},${y(Number(p[l.key])||0)}`).join(' '),class:'trend-line '+l.cls,fill:'none','stroke-width':2.5});
    points.forEach((p,i)=>{const c=add('circle',{cx:x(i),cy:y(Number(p[l.key])||0),r:3,class:'trend-dot '+l.cls});const ti=document.createElementNS(svg.namespaceURI,'title');ti.textContent=`${p.month} · ${l.label}: ${fmt?fmt(p[l.key]):p[l.key]}`+(p.partial?' (mes en curso)':'');c.append(ti);});
   }
   points.forEach((p,i)=>{if(points.length>9&&i%2&&i!==points.length-1)return;add('text',{x:x(i),y:h-9,'text-anchor':i===0?'start':i===points.length-1?'end':'middle',class:'trend-axis'},p.month.slice(2)+(p.partial?'*':''));});
   canvas.replaceChildren(svg);
  };
  requestAnimationFrame(draw);const ob=new ResizeObserver(draw);ob.observe(canvas);observers.push(ob);return box;
 }
 function tile(label,value,delta,note){const box=el('article',undefined,'management-stat');box.append(el('span',label),el('strong',value));if(delta)box.append(el('small',delta,'trend-delta '+(delta.startsWith('▲')?'up':delta.startsWith('▼')?'down':'flat')));if(note)box.append(el('small',note));return box;}
 function deltaCount(cur,prev,unit){if(prev===null||prev===undefined)return '';const d=(Number(cur)||0)-(Number(prev)||0);const a=d>0?'▲ +':d<0?'▼ ':'= ';return a+count(Math.abs(d)<1e-9?0:d)+(unit?' '+unit:'')+' vs mes previo';}
 function tiles(parent,s){
  const cur=s[s.length-1],prev=s.length>1?s[s.length-2]:null;
  const grid=el('div',undefined,'management-stats');
  grid.append(
   tile('Atenciones',count(cur.present),prev?deltaCount(cur.present,prev.present):'',cur.partial?'Mes en curso':''),
   tile('Pacientes nuevos',count(cur.new_patients),prev?deltaCount(cur.new_patients,prev.new_patients):'','Primera atención observada'),
   tile('Asistencia',count(cur.attendance)+'%',prev?deltaCount(cur.attendance,prev.attendance,'pts'):'','Presentes / presentes + ausentes'),
   tile('Ausentismo',count(cur.absenteeism)+'%',prev?deltaCount(cur.absenteeism,prev.absenteeism,'pts'):'',cur.auto_absent?count(cur.auto_absent)+' automáticas':''),
   tile('Flujo neto',money(cur.net),prev?(()=>{const d=(Number(cur.net)||0)-(Number(prev.net)||0);return (d>0?'▲ +':d<0?'▼ ':'= ')+money(Math.abs(d))+' vs mes previo';})():'','Ingresos menos egresos del mes')
  );
  parent.append(grid);
 }
 function noticeEl(){const d=el('div',undefined,'management-notice');d.append(el('strong',window.MARATHON_CONFIG?.supabaseUrl==='https://marathon-demo.invalid'?'Demostración · Datos ficticios. ':'Registro en validación. '),el('span','La evolución describe lo cargado mes a mes. El último mes (*) está en curso y no es comparable a un mes completo.'));return d;}
 function table(parent,s){
  const cols=[['month','Mes'],['present','Atenciones'],['patients','Pacientes'],['new_patients','Nuevos'],['absent','Ausentes'],['attendance','Asistencia %'],['absenteeism','Ausentismo %'],['net','Neto']];
  const wrap=el('div',undefined,'table-scroll'),t=el('table'),head=el('thead'),hr=el('tr');for(const[,l]of cols){const th=el('th',l);th.scope='col';hr.append(th);}head.append(hr);t.append(head);
  const body=el('tbody');for(const p of s){const tr=el('tr');for(const[key]of cols)tr.append(el('td',key==='net'?money(p[key]):key==='month'?p.month+(p.partial?' *':''):String(p[key]??'')));body.append(tr);}t.append(body);wrap.append(t);parent.append(wrap);
 }
 function exportFile(s){
  const cols=[['month','Mes'],['present','Atenciones'],['patients','Pacientes'],['new_patients','Nuevos'],['absent','Ausentes'],['attendance','Asistencia %'],['absenteeism','Ausentismo %'],['income','Ingresos'],['expense','Egresos'],['net','Neto']];
  const bytes=BillingXlsx.buildGrid({title:'Marathon · Tendencias mensuales',sheetName:'Tendencias',columns:cols.map(([key,name])=>({name,numeric:key!=='month',width:18})),rows:s.map(p=>cols.map(([key])=>key==='month'?p.month+(p.partial?' *':''):Number(p[key])||0)),metadata:[['Período',data.from+' a '+data.to,'Meses',String(data.months)],['Consulta',data.generated_at,'Nota','El último mes puede estar en curso (*)']],note:'Registro en validación. Series mensuales de demanda, ausentismo y caja. No contiene identificadores de pacientes.'});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download='Marathon_Tendencias_'+data.to+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message('Tendencias descargadas.');
 }
 function draw(){
  cleanup();const h=host();h.replaceChildren();if(!data)return;
  let s=data.series.slice();const firstActive=s.findIndex(p=>Number(p.present)||Number(p.movimientos)||Number(p.income));if(firstActive>0)s=s.slice(firstActive);
  if(s.length<2){h.append(el('p','Todavía no hay al menos dos meses con actividad cargada para mostrar una tendencia. Volvé cuando haya más historia.','subtitle'));return;}
  h.append(noticeEl());tiles(h,s);
  const cols=el('div',undefined,'trend-columns');
  cols.append(lineChart({title:'Demanda mensual',note:'Atenciones realizadas (Presente) y pacientes nuevos observados por mes.',points:s,lines:[{key:'present',label:'Atenciones',cls:'c1'},{key:'new_patients',label:'Pacientes nuevos',cls:'c2'}],fmt:v=>count(v)}));
  cols.append(lineChart({title:'Asistencia y ausentismo',note:'Porcentaje sobre turnos con resultado definido (presentes + ausentes).',points:s,lines:[{key:'attendance',label:'Asistencia %',cls:'c3'},{key:'absenteeism',label:'Ausentismo %',cls:'c4'}],pct:true,fmt:v=>count(v)+'%'}));
  h.append(cols);
  h.append(lineChart({title:'Dinero: flujo neto mensual',note:'Ingresos menos egresos de cada mes. No es ganancia ni saldo bancario.',points:s,lines:[{key:'net',label:'Neto',cls:'c5'}],fmt:v=>moneyShort(v)}));
  const d=el('details');d.append(el('summary','Ver tabla y descargar Excel'));table(d,s);const bar=el('div',undefined,'trend-actions'),b=el('button','Descargar Excel','s');b.type='button';b.addEventListener('click',()=>ctx.work(()=>exportFile(s)));bar.append(b);d.append(bar);h.append(d);
 }
 function fillSites(rows){const sel=$('#trends-sede'),v=sel.value;sel.replaceChildren();for(const[value,label]of [['','Todas las sedes'],...rows.map(r=>[r.id,r.label+(r.estado==='INACTIVO'?' (inactiva)':'')])]){const o=el('option',label);o.value=value;sel.append(o);}sel.value=v;}
 async function run(){const task=++generation;data=null;cleanup();host().replaceChildren();$('#trends-status').textContent='Calculando la evolución mensual…';
  try{const r=await rpc('marathon_trends',{p_filters:{sede:$('#trends-sede').value,months:$('#trends-months').value||'12'}});if(task!==generation)return;data=r;$('#trends-status').textContent=`${r.from} a ${r.to} · ${r.months} meses · Actualizado ${new Date(r.generated_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'})}`;draw();}
  catch(e){if(task===generation){$('#trends-status').textContent='No se pudo calcular la evolución. '+e.message;}throw e;}
 }
 $('#trends-filter').addEventListener('submit',e=>{e.preventDefault();ctx.work(run);});
 $('#trends-filter').addEventListener('change',()=>ctx.work(run));
 return {open:async options=>{optionsCache=options;fillSites(options?.sedes||[]);if(!data)await run();},sync:()=>{},isPending:()=>false,reset:()=>{generation++;data=null;cleanup();host().replaceChildren();$('#trends-status').textContent='';}};
}
