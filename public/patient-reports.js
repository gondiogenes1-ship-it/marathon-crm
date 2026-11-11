import {buildPatientReportWorkbook,patientReportTabs} from './patient-report-workbook.js?v=20261105-informes-excel-3';
const el=(tag,text,cls)=>{const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(cls)node.className=cls;return node;};
const count=n=>Number(n??0).toLocaleString('es-AR',{maximumFractionDigits:1});
const percent=n=>n===null||n===undefined?'Sin base':count(n)+' %';
const day=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date());
export const shift=(d,n)=>new Date(Date.parse(d+'T12:00:00Z')+n*86400000).toISOString().slice(0,10);
const date=d=>String(d||'').split('-').reverse().join('/');
export function validatePatientPeriod(f,today=day()){
 const valid=d=>/^\d{4}-\d{2}-\d{2}$/.test(d)&&Number.isFinite(Date.parse(d))&&shift(d,0)===d;
 if(!valid(f.from)||!valid(f.to)||f.from>f.to||f.to>today||f.from<'2000-01-01')throw Error('Elegí un período válido, sin fechas futuras.');
 const days=Math.round((Date.parse(f.to)-Date.parse(f.from))/86400000)+1;
 if(days>93||shift(f.from,-days)<'2000-01-01')throw Error('Consultá hasta 93 días con comparación anterior desde el año 2000.');
 return days;
}
function button(label,action,primary=false){const b=el('button',label,primary?'b':'s');b.type='button';if(action)b.addEventListener('click',action);return b;}
function stat(label,value,note,context){const box=el('article',undefined,'pps-stat');box.append(el('h3',label),el('strong',value),el('p',note));if(context)box.append(el('small',context));return box;}
function panel(title,note){const box=el('section',undefined,'card pps-panel');box.append(el('h2',title));if(note)box.append(el('p',note,'subtitle'));return box;}
function metricBand(rows){const box=el('div',undefined,'pps-stats');for(const row of rows)box.append(stat(...row));return box;}
function table(columns,rows,empty='No hay registros para este período y filtros.'){
 if(!rows.length)return el('p',empty,'pps-empty');
 const wrap=el('div',undefined,'table-scroll'),tab=el('table'),head=el('thead'),hr=el('tr');
 for(const [,label]of columns){const th=el('th',label);th.scope='col';hr.append(th);}head.append(hr);tab.append(head);
 const body=el('tbody');for(const record of rows){const row=el('tr');for(const [key,,format]of columns)row.append(el('td',format?format(record[key],record):record[key]??'Sin dato'));body.append(row);}tab.append(body);wrap.append(tab);return wrap;
}
function bars(title,note,rows,format=count,ceiling=null){
 const box=panel(title,note),max=ceiling??Math.max(1,...rows.map(r=>Number(r.value)||0));
 if(!rows.length||rows.every(r=>r.value===null||r.value===0)){box.append(el('p','No hay valores registrados para comparar en este conjunto.','pps-empty'));return box;}
 for(const r of rows.slice(0,12)){
  const row=el('div',undefined,'pps-bar'),label=el('div',undefined,'pps-bar-label');label.append(el('span',r.label),el('strong',r.value===null?'Sin base':format(r.value)));
  const track=el('div',undefined,'pps-track'),fill=el('span');fill.style.width=Math.max(0,Math.min(100,100*Number(r.value||0)/max))+'%';track.append(fill);track.setAttribute('role','img');track.setAttribute('aria-label',r.label+': '+(r.value===null?'Sin base':format(r.value)));row.append(label,track);box.append(row);
 }
 if(rows.length>12)box.append(el('p','El gráfico muestra 12 grupos. El detalle incluye todos.','subtitle'));return box;
}
function states(s){
 const box=panel('Estado de los turnos','Turnos finalizados al corte. Las cancelaciones y los pendientes no entran en el porcentaje de asistencia.');
 const parts=[['present','Presentes'],['absent','Ausentes'],['pending','Sin resultado'],['cancelled','Cancelados']];
 const total=parts.reduce((n,[key])=>n+Number(s[key]),0),stack=el('div',undefined,'pps-stack');stack.setAttribute('role','img');stack.setAttribute('aria-label',parts.map(([k,l])=>`${l}: ${s[k]}`).join(', '));
 for(const [key]of parts){const mark=el('span',undefined,'pps-state-'+key);mark.style.width=(total?100*s[key]/total:0)+'%';stack.append(mark);}box.append(stack);
 const list=el('dl',undefined,'pps-state-list');for(const [key,label]of parts){const row=el('div'),term=el('dt',label),dot=el('i',undefined,'pps-state-'+key);term.prepend(dot);row.append(term,el('dd',count(s[key])));list.append(row);}box.append(list);return box;
}
export function createPatientReports(ctx){
 const $=s=>document.querySelector(s);let report=null,tab='overview',dimension='specialty',generation=0,observers=[],optionCatalog=null,baseOptions=null;
 const titles={overview:['Gestión de pacientes','Actividad, acceso y calidad del registro para orientar las decisiones.'],activity:['Actividad','Personas, primeras atenciones observadas y frecuencia de atención.'],agenda:['Agenda y acceso','Asistencia, tiempo profesional y pedidos en espera.'],profile:['Perfil y experiencia','Coberturas utilizadas y datos necesarios para conocer la experiencia.'],quality:['Control del registro','Qué se puede interpretar y qué falta completar antes de decidir.']};
 const rpc=(n,a)=>ctx.getApi().rpc(n,a);
 const filterForm=$('#pps-filter'),host=$('#pps-results');
 const filters=()=>({from:$('#pps-from').value,to:$('#pps-to').value,sede:$('#pps-site').value,specialty:$('#pps-specialty').value,therapy:$('#pps-therapy').value,professional:$('#pps-professional').value});
 function fillOptions(selector,rows,blank){const node=$(selector),previous=node.value;node.replaceChildren();for(const r of [{id:'',label:blank},...rows]){const o=el('option',r.label);o.value=r.id;node.append(o);}node.value=rows.some(r=>r.id===previous)?previous:'';}
 function syncOptions(){
  if(!optionCatalog)return;const chosen=$('#pps-specialty').value;
  fillOptions('#pps-therapy',optionCatalog.therapies.filter(t=>!chosen||t.specialty===chosen),'Todas las prestaciones');
 }
 function cleanup(){for(const observer of observers)observer.disconnect();observers=[];}
 function invalidate(){generation++;report=null;cleanup();host.replaceChildren();$('#pps-status').textContent='Filtros modificados. Consultá para actualizar el informe.';$('#pps-export').disabled=true;$('#pps-export-all').disabled=true;}
 function setTab(next){tab=next;draw();ctx.sync();}
 async function run(){
  const f=filters();validatePatientPeriod(f);const task=++generation;report=null;cleanup();host.replaceChildren();$('#pps-export').disabled=true;$('#pps-export-all').disabled=true;
  $('#pps-status').textContent='Calculando el conjunto completo de registros…';host.setAttribute('aria-busy','true');
  try{
   const data=await rpc('marathon_patient_dashboard',{p_filters:f});if(task!==generation)return;
   if(!data?.summary||!Array.isArray(data.groups)||!Array.isArray(data.coverage))throw Error('El informe devolvió una respuesta incompleta. Volvé a consultar.');
   ctx.message('');report=data;optionCatalog=data.catalog;const selected=$('#pps-specialty').value;
   fillOptions('#pps-specialty',data.catalog.specialties.map(s=>({id:s,label:s})),'Todas las especialidades');$('#pps-specialty').value=selected;
   if(Array.isArray(data.catalog.professionals))fillOptions('#pps-professional',data.catalog.professionals,'Todos los profesionales');syncOptions();draw();
  }catch(error){if(task===generation){report=null;host.replaceChildren();$('#pps-status').textContent='No se pudo calcular el informe. '+error.message;}throw error;}
  finally{host.removeAttribute('aria-busy');}
 }
 function graphTrend(data){
  const box=panel('Evolución de la atención','Atenciones y pacientes distintos de cada día. Los pacientes diarios no se suman para obtener el total de personas del período.');
  const legend=el('div',undefined,'pps-legend');legend.append(el('span','━ Atenciones','pps-series-primary'),el('span','┄ Pacientes','pps-series-secondary'));box.append(legend);
  const canvas=el('div',undefined,'pps-trend');box.append(canvas);
  const draw=()=>{
   const width=Math.max(260,Math.floor(canvas.getBoundingClientRect().width||600)),height=210,left=36,right=16,top=16,bottom=32;
   const max=Math.max(4,Math.ceil(Math.max(...data.map(p=>Number(p.present)||0),...data.map(p=>Number(p.patients)||0),0)/4)*4);
   const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');svg.setAttribute('viewBox',`0 0 ${width} ${height}`);svg.setAttribute('role','img');svg.setAttribute('aria-label','Evolución diaria de atenciones realizadas y pacientes distintos. Detalle disponible debajo.');
   const add=(tag,attrs,text)=>{const node=document.createElementNS(svg.namespaceURI,tag);for(const [k,v]of Object.entries(attrs))node.setAttribute(k,String(v));if(text!==undefined)node.textContent=text;svg.append(node);return node;};
   const x=i=>left+(width-left-right)*(data.length<2?.5:i/(data.length-1)),y=v=>height-bottom-(height-top-bottom)*v/max;
   for(let i=0;i<=4;i++){const value=max*i/4;add('line',{x1:left,x2:width-right,y1:y(value),y2:y(value),class:'pps-gridline'});add('text',{x:left-7,y:y(value)+4,'text-anchor':'end'},String(value));}
   for(const [key,cls]of [['present','pps-line-primary'],['patients','pps-line-secondary']]){
    add('polyline',{points:data.map((p,i)=>`${x(i)},${y(p[key])}`).join(' '),class:cls,fill:'none','stroke-width':2});
    data.forEach((p,i)=>{const mark=add('circle',{cx:x(i),cy:y(p[key]),r:2.5,class:cls});const title=document.createElementNS(svg.namespaceURI,'title');title.textContent=`${date(p.date)} · ${key==='present'?'Atenciones':'Pacientes'}: ${p[key]}`;mark.append(title);});
   }
   const ticks=[...new Set([0,Math.floor((data.length-1)/2),data.length-1])];for(const i of ticks){if(!data[i])continue;add('text',{x:x(i),y:height-8,'text-anchor':i===0?'start':i===data.length-1?'end':'middle'},date(data[i].date).slice(0,5));}canvas.replaceChildren(svg);
  };
  requestAnimationFrame(draw);const observer=new ResizeObserver(draw);observer.observe(canvas);observers.push(observer);
  const details=el('details'),summary=el('summary','Ver valores diarios');details.append(summary,table([['date','Fecha',date],['present','Atenciones',count],['patients','Pacientes',count]],data));box.append(details);return box;
 }
 function distributionControls(){
  const label=el('label','Comparar por'),select=el('select');select.id='pps-dimension';for(const [id,title]of [['specialty','Especialidad'],['therapy','Prestación'],['site','Sede'],['professional','Profesional']]){const o=el('option',title);o.value=id;select.append(o);}select.value=dimension;select.addEventListener('change',()=>{dimension=select.value;draw();ctx.sync();});label.append(select);return label;
 }
 function distribution(){return report.groups.filter(g=>g.kind===dimension);}
 function distributionPanel(){const box=bars('Distribución de pacientes','Personas con al menos una atención realizada en cada grupo. Las categorías pueden compartir pacientes.',distribution().map(g=>({label:g.label,value:g.patients})));box.insertBefore(distributionControls(),box.children[2]||null);return box;}
 function decisionNotes(){
  const s=report.summary,w=report.waiting,missing=report.quality.missing_coverage,box=panel('Qué conviene revisar','Señales del registro para orientar el trabajo; no son un diagnóstico del desempeño real de Marathon.');
  const list=el('ul',undefined,'pps-decisions');
  if(s.pending)list.append(el('li',`Completar el resultado de ${count(s.pending)} turnos ya finalizados antes de interpretar la asistencia.`));
  if(missing)list.append(el('li',`Confirmar la modalidad de cobertura de ${count(missing)} atenciones realizadas.`));
  if(w.requests)list.append(el('li',`Revisar ${count(w.requests)} pedidos abiertos y contrastarlos con la disponibilidad de las prestaciones solicitadas.`));
  if(!s.present)list.append(el('li','No hay atenciones realizadas registradas para estos filtros. Confirmá la cobertura de carga antes de evaluar actividad.'));
  if(!list.children.length)list.append(el('li','Comparar la distribución de atención con la oferta vigente y validar que el período esté completamente cargado.'));
  box.append(list);return box;
 }
 function overview(){
  const s=report.summary,p=report.previous,f=report.firsts;
  const compare=(v,b,unit='')=>v===null||v===undefined||b===null||b===undefined?'Sin base comparable':`${count(v-b)}${unit} frente al período anterior`;
  host.append(metricBand([
   ['Pacientes atendidos',count(s.patients),'Personas distintas con atención realizada.',compare(s.patients,p.patients)],
   ['Atenciones realizadas',count(s.present),'Una persona puede recibir varias sesiones.',compare(s.present,p.present)],
   ['Primeras observadas',count(f.observed),'Primera atención registrada en esta base.','Historia incompleta: no confirma un paciente nuevo.'],
   ['Asistencia',percent(s.attendance),`${count(s.present)} presentes de ${count(s.present+s.absent)} resultados definidos.`,s.pending?`${count(s.pending)} turnos finalizados aún sin resultado.`:compare(s.attendance,p.attendance,' puntos')]
  ]));
  const charts=el('div',undefined,'pps-columns');charts.append(distributionPanel(),graphTrend(report.trend));host.append(charts,decisionNotes());
 }
 function activity(){
  const s=report.summary,f=report.firsts;
  host.append(metricBand([
   ['Personas atendidas',count(s.patients),'No suma personas repetidas entre grupos.'],['Atenciones',count(s.present),'Sesiones con Presente ya finalizadas.'],
   ['Atenciones por paciente',s.frequency===null?'Sin base':count(s.frequency),`Promedio en ${report.period.days} días; no es frecuencia indicada del tratamiento.`],
   ['Primera observada',count(f.observed),'Primera atención encontrada en la base, con los filtros aplicados.']
  ]));
  const charts=el('div',undefined,'pps-columns');charts.append(distributionPanel(),graphTrend(report.trend));host.append(charts);
  const detail=panel('Detalle de la actividad','Una persona puede aparecer en varios profesionales, sedes o especialidades. El total institucional se calcula por separado.');
  detail.append(table([['label','Grupo'],['patients','Pacientes',count],['present','Atenciones',count],['absent','Ausentes',count],['pending','Sin resultado',count],['cancelled','Cancelados',count],['attendance','Asistencia',percent]],distribution()));host.append(detail);
  const first=panel('Cómo leer las primeras atenciones','La historia anterior puede no estar completa. No se utilizan altas de fichas ni bonos para contar primeras atenciones.');
  first.append(el('p',`${count(f.observed)} pacientes tuvieron su primera atención observada en el período; ${count(f.returning)} ya tenían una atención anterior registrada.`));
  if(f.first_site!==null)first.append(el('p',`${count(f.first_site)} primeras atenciones observadas en la sede elegida. No equivalen necesariamente a nuevos pacientes en Marathon.`));
  if(f.first_specialty!==null)first.append(el('p',`${count(f.first_specialty)} primeras observadas en la especialidad elegida.`));host.append(first);
 }
 function heatmap(){
  const box=panel('Concentración por día y horario','Inicios de turnos Pendiente o Presente en el período transcurrido. Es cantidad de reservas registradas, no porcentaje de ocupación ni simultaneidad física.');
  if(!report.flow.length){box.append(el('p','No hay turnos de estos estados para mostrar.','pps-empty'));return box;}
  const hours=[...new Set(report.flow.map(c=>c.hour))].sort((a,b)=>a-b),max=Math.max(1,...report.flow.map(c=>c.count));
  const records=hours.map(h=>{const row={hour:String(h).padStart(2,'0')+':00'};for(let d=1;d<=7;d++)row['d'+d]=report.flow.find(c=>c.hour===h&&c.weekday===d)?.count||0;return row;});
  const wrap=table([['hour','Franja'],...['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map((label,i)=>['d'+(i+1),label,count])],records);
  wrap.classList.add('pps-heat');wrap.querySelectorAll('tbody tr').forEach((row,i)=>{[...row.children].slice(1).forEach((cell,j)=>{const value=records[i]['d'+(j+1)];cell.style.setProperty('--pps-density',String(value?0.08+0.25*value/max:0));cell.setAttribute('aria-label',`${records[i].hour} · ${['lunes','martes','miércoles','jueves','viernes','sábado','domingo'][j]}: ${value} turnos`);});});box.append(wrap);return box;
 }
 function agenda(){
  const s=report.summary,c=report.capacity,w=report.waiting;
  host.append(metricBand([
   ['Asistencia',percent(s.attendance),`${count(s.present)} presentes / ${count(s.present+s.absent)} definidos.`],
   ['Resultado registrado',percent(s.completeness),`${count(s.pending)} pendientes finalizados; cancelados aparte.`],
   ['Pedidos abiertos · hoy',count(w.requests),`${count(w.patients)} personas distintas. La espera es una foto actual.`],
   ['Antigüedad de espera',w.median_days===null?'Sin base':count(w.median_days)+' días','Mediana de pedidos abiertos; no es demora hasta primera oferta.']
  ]));
  const columns=el('div',undefined,'pps-columns');columns.append(states(s),panel('Tiempo profesional registrado','Aproximación con horarios vigentes. Minutos simultáneos cuentan una sola vez; no mide cupos grupales, salas ni equipos.'));
  const time=columns.lastElementChild;
  if(!c.available)time.append(el('p','Sin horario configurado para este conjunto.','pps-empty'));
  else{
   const trackRows=[{label:'Horario disponible transcurrido',value:100},{label:'Con turnos vigentes',value:c.reserved_pct},{label:'Con atención registrada',value:c.effective_pct}];
   for(const row of trackRows){const div=el('div',undefined,'pps-bar'),label=el('div',undefined,'pps-bar-label');label.append(el('span',row.label),el('strong',percent(row.value)));const track=el('div',undefined,'pps-track'),fill=el('span');fill.style.width=Math.min(100,Math.max(0,row.value||0))+'%';track.append(fill);div.append(label,track);time.append(div);}
   time.append(el('p',`${count(c.available)} min disponibles · ${count(c.reserved)} min con turnos · ${count(c.effective)} min con Presente.`, 'subtitle'));
  }
  time.append(el('p','Con filtro de especialidad o prestación, el horario del profesional puede compartirse con otras actividades; no es oferta exclusiva. Los estados son los actuales, no una foto histórica de reservas.','subtitle'));host.append(columns);
  const timeRows=panel('Uso del tiempo por profesional','Interpretá cada porcentaje junto con sus minutos disponibles y la cobertura del registro. No es un ranking de calidad.');
  timeRows.append(table([['label','Profesional'],['available','Disponibles (min)',count],['reserved','Con turnos (min)',count],['effective','Con Presente (min)',count],['effective_pct','Con atención',percent]],c.rows));host.append(timeRows);
  const demand=panel('Demanda en espera','Pedidos Pendiente o Contactado por especialidad, respetando sede, prestación y profesional. Los pedidos sin profesional solo aparecen al elegir Todos.');
  demand.append(table([['label','Especialidad'],['requests','Pedidos abiertos',count],['patients','Personas',count],['median_days','Antigüedad mediana',v=>v===null?'Sin base':count(v)+' días']],w.rows,'Sin pedidos abiertos registrados. Esto no demuestra que toda la demanda esté resuelta.'));
  if(w.linked_count)demand.append(el('p',`En ${count(w.linked_count)} pedidos resueltos del período vinculados a un turno, la mediana entre fecha del pedido y fecha del turno asignado es ${count(w.linked_median_days)} días. No mide la primera oferta ni incluye pedidos todavía abiertos.`));
  demand.append(el('p','Para medir el acceso completo se necesita registrar toda solicitud, incluso las resueltas en el primer contacto, y su primera oferta compatible.','subtitle'));host.append(demand,heatmap());
 }
 function coverageEntities(){
  const rows=report.coverage_entities||[];
  const box=panel('Distribución por obra social','Atenciones realizadas con cobertura Obra social, desagregadas por entidad. "Sin entidad identificada" agrupa las atenciones de obra social sin entidad cargada: completá ese dato antes de preparar la facturación. Una persona puede aparecer en más de una entidad.');
  if(!rows.length){box.append(el('p','No hay atenciones con cobertura de obra social para este período y filtros.','pps-empty'));return box;}
  const total=rows.reduce((n,r)=>n+Number(r.attentions||0),0),max=Math.max(1,...rows.map(r=>Number(r.attentions)||0));
  const identified=rows.filter(r=>r.identified).length,unidentified=rows.find(r=>!r.identified);
  const controls=el('div',undefined,'management-stock-filter'),searchLabel=el('label','Buscar entidad'),search=el('input');search.type='search';search.placeholder='Nombre de la obra social';searchLabel.append(search);controls.append(searchLabel);box.append(controls);
  const result=el('div');box.append(result);
  const redraw=()=>{
   const q=search.value.trim().toLocaleLowerCase('es'),shown=rows.filter(r=>String(r.label).toLocaleLowerCase('es').includes(q));
   result.replaceChildren();
   result.append(el('p',`${count(total)} atenciones con obra social · ${count(identified)} entidades identificadas${unidentified?` · ${count(unidentified.attentions)} sin entidad identificada (${percent(unidentified.percent)})`:''}.`,'subtitle'));
   if(!shown.length){result.append(el('p','Ninguna entidad coincide con la búsqueda.','pps-empty'));}
   for(const r of shown.slice(0,12)){
    const row=el('div',undefined,'pps-bar'),label=el('div',undefined,'pps-bar-label');
    label.append(el('span',r.label+(r.state==='INACTIVO'?' (inactiva)':'')),el('strong',count(r.attentions)));
    const track=el('div',undefined,'pps-track'),fill=el('span');fill.style.width=Math.max(0,Math.min(100,100*Number(r.attentions||0)/max))+'%';track.append(fill);
    track.setAttribute('role','img');track.setAttribute('aria-label',`${r.label}: ${count(r.attentions)} atenciones, ${count(r.patients)} personas`);
    row.append(label,track);result.append(row);
   }
   if(shown.length>12)result.append(el('p','El gráfico muestra 12 entidades. La tabla incluye todas.','subtitle'));
   const details=el('details');details.append(el('summary','Ver tabla por entidad'),table([['label','Entidad'],['attentions','Atenciones',count],['patients','Personas',count],['percent','Participación',percent]],shown));result.append(details);
  };
  search.addEventListener('input',redraw);redraw();return box;
 }
 function profile(){
  const s=report.summary,known=s.present-report.quality.missing_coverage;
  host.append(metricBand([['Atenciones del perfil',count(s.present),'Atenciones realizadas, no personas únicas.'],['Modalidad registrada',s.present?percent(100*known/s.present):'Sin base',`${count(known)} de ${count(s.present)} atenciones.`],['Sin modalidad',count(report.quality.missing_coverage),'No se reclasifican como Particular.']]));
  const box=panel('Modalidades de cobertura','Distribución según la cobertura elegida en cada atención. No es el medio de pago ni la cobertura actual de la ficha.');
  const stack=el('div',undefined,'pps-stack pps-coverage');report.coverage.forEach((row,index)=>{const fill=el('span',undefined,'pps-cover-'+index);fill.style.width=(row.percent||0)+'%';fill.title=row.label+': '+count(row.attentions);stack.append(fill);});box.append(stack,table([['label','Modalidad'],['attentions','Atenciones',count],['percent','Participación',percent]],report.coverage));host.append(box);host.append(coverageEntities());
  const columns=el('div',undefined,'pps-columns');
  const experience=panel('Experiencia del paciente','Pendiente de registro · Se conserva como objetivo de la PPS, sin generar un puntaje ficticio.');experience.append(el('p','Para conocer la facilidad de solicitar y acceder a la atención hacen falta invitaciones y respuestas válidas, con participación informada. La cantidad de turnos o la asistencia no sustituyen esa medición.'));
  const clinical=panel('Diagnósticos frecuentes','No disponible con los datos actuales.');clinical.append(el('p','No se infieren diagnósticos a partir de la terapia, las observaciones o los documentos. Se incorporarán cuando exista información clínica estructurada y validada.'));columns.append(experience,clinical);host.append(columns);
 }
 function quality(){
  const s=report.summary,q=report.quality;
  host.append(metricBand([['Pendientes finalizados',count(s.pending),'Revisar recepción y confirmación de realización.'],['Sin cobertura de atención',count(q.missing_coverage),'Completar modalidad por turno.'],['Ausencias automáticas',count(s.auto_absent),'Deben revisarse; no prueban por sí solas una inasistencia confirmada.'],['Turnos aún no iniciados',count(q.future),'Excluidos de los resultados de atención.']]));
  host.append(decisionNotes());
  const methods=panel('Qué información puede usarse para decidir','Cada medida conserva su unidad, fecha y alcance. Los valores describen el registro disponible, no acreditan que toda la empresa esté cargada.');
  methods.append(table([['metric','Medida'],['status','Alcance'],['action','Cómo interpretarla']],
   [{metric:'Pacientes y atenciones',status:'Calculable sobre registros',action:'Pacientes distintos y sesiones Presente finalizadas; no sumar personas entre grupos.'},
    {metric:'Primeras atenciones',status:'Primera observada',action:'No confirma ingreso nuevo si falta historia previa.'},
    {metric:'Frecuencia',status:'Promedio en el período',action:'Comparar ventanas iguales; no es la frecuencia prescrita.'},
    {metric:'Asistencia',status:s.pending?'Registro incompleto':'Resultados definidos según base',action:'Presentes / presentes + ausentes. Cancelados y pendientes se explican aparte.'},
    {metric:'Tiempo profesional',status:'Horarios actuales',action:'Unión de minutos dentro de horario; no cupos físicos ni productividad clínica.'},
    {metric:'Lista de espera',status:'Foto actual',action:'Pedidos abiertos, no toda la demanda ni primera oferta.'},
    {metric:'Experiencia y diagnósticos',status:'Requieren registros',action:'Sin puntuaciones ni inferencias a partir de otras medidas.'}]));host.append(methods);
 }
 function draw(){
  cleanup();host.replaceChildren();$('#pps-heading').textContent=titles[tab][0];$('#pps-description').textContent=titles[tab][1];
  for(const b of $('#pps-tabs').querySelectorAll('button')){const active=b.dataset.ppsTab===tab;b.className=active?'b':'s';b.setAttribute('aria-pressed',String(active));}
  if(!report){$('#pps-export').disabled=true;$('#pps-export-all').disabled=true;return;}
  const r=report;$('#pps-export').disabled=ctx.isBusy();$('#pps-export-all').disabled=ctx.isBusy();
  $('#pps-status').textContent=`${date(r.period.from)} al ${date(r.period.to)} · Comparación: ${date(r.period.previous_from)} al ${date(r.period.previous_to)} · Actualizado ${new Date(r.generated_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'})}${r.period.partial_day?' · Día actual parcial; comparación al mismo avance horario.':''}`;
  const notice=el('div',undefined,'pps-notice');notice.append(el('strong',window.MARATHON_CONFIG?.supabaseUrl==='https://marathon-demo.invalid'?'Demostración · Datos ficticios':'Registro en validación'),el('span',' Los resultados describen lo registrado. Confirmá su cobertura antes de evaluar el desempeño de Marathon.'));host.append(notice);
  ({overview,activity,agenda,profile,quality})[tab]();
 }
 filterForm.addEventListener('submit',event=>{event.preventDefault();if(filterForm.reportValidity())ctx.work(run);});
 filterForm.addEventListener('change',event=>{if(event.target.id==='pps-specialty')syncOptions();invalidate();});
 $('#pps-tabs').addEventListener('click',event=>{const b=event.target.closest('[data-pps-tab]');if(b)setTab(b.dataset.ppsTab);});
 $('#pps-presets').addEventListener('click',event=>{const b=event.target.closest('[data-pps-range]');if(!b)return;const today=day();$('#pps-to').value=today;$('#pps-from').value=b.dataset.ppsRange==='month'?today.slice(0,7)+'-01':shift(today,b.dataset.ppsRange==='week'?-6:-27);invalidate();ctx.work(run);});
 function exportFile(all=false){
  if(!report)return;
  const label=id=>$('#'+id).selectedOptions[0]?.textContent||'';
  const bytes=buildPatientReportWorkbook(report,{tab:all?null:tab,dimension,labels:{sede:label('pps-site'),specialty:label('pps-specialty'),therapy:label('pps-therapy'),professional:label('pps-professional')}});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download=`Marathon_Informes_${all?'Completo':patientReportTabs[tab].replaceAll(' ','_')}_${report.period.from}_${report.period.to}.xlsx`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message(all?'Informe completo descargado: cinco hojas con tablas y gráficos editables.':'Pestaña descargada con tablas y gráficos editables.');
 }
 $('#pps-export').addEventListener('click',()=>ctx.work(()=>exportFile(false)));
 $('#pps-export-all').addEventListener('click',()=>ctx.work(()=>exportFile(true)));
 return {open:async options=>{baseOptions=options;if(!$('#pps-from').value){$('#pps-to').value=day();$('#pps-from').value=shift(day(),-27);}$('#pps-to').max=day();$('#pps-from').max=day();
  fillOptions('#pps-site',options.sedes,'Todas las sedes');fillOptions('#pps-professional',optionCatalog?.professionals||options.professionals,'Todos los profesionales');
  if(!optionCatalog){fillOptions('#pps-specialty',[],'Todas las especialidades');fillOptions('#pps-therapy',options.therapies,'Todas las prestaciones');}
  draw();if(!report)await run();},sync:()=>{$('#pps-export').disabled=ctx.isBusy()||!report;$('#pps-export-all').disabled=ctx.isBusy()||!report;},reset:()=>{generation++;report=null;optionCatalog=null;baseOptions=null;tab='overview';dimension='specialty';cleanup();filterForm.reset();host.replaceChildren();$('#pps-status').textContent='';$('#pps-export').disabled=true;$('#pps-export-all').disabled=true;}};
}
