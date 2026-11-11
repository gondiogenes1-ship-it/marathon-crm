import {BillingXlsx} from './xlsx.js?v=20261019-0110';
const number=n=>new Intl.NumberFormat('es-AR',{maximumFractionDigits:2}).format(Number(n??0));
const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n??0));
const percent=n=>n===null||n===undefined?'Sin base':number(n)+' %';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const localDay=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date());
export function previousWeek(){const d=new Date(localDay()+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7)-7);return d.toISOString().slice(0,10);}
export function createManagement(ctx){
 const $=s=>document.querySelector(s);let data=null,applied=null;
 const profLabel=el('label','Profesional'),prof=el('select');prof.id='management-professional';profLabel.append(prof);
 const weekLabel=el('label','Semana del tiempo profesional (lunes)'),week=el('input');week.id='management-week';week.type='date';week.max=previousWeek();week.value=week.max;weekLabel.append(week);
 const form=$('#report-filter');form.insertBefore(profLabel,form.lastElementChild);form.insertBefore(weekLabel,form.lastElementChild);
 function toggle(on){profLabel.hidden=weekLabel.hidden=!on;week.required=on;$('#report-prev').parentElement.hidden=on;$('#report-results').classList.toggle('management-results',on);}
 function options(rows){const value=prof.value;prof.replaceChildren();for(const r of [{id:'',label:'Todos los profesionales'},...rows]){const o=el('option',r.label);o.value=r.id;prof.append(o);}prof.value=value;}
 function read(){const date=new Date(week.value+'T12:00:00Z');if(!week.value||date.getUTCDay()!==1||week.value>previousWeek())throw Error('Elegí un lunes de una semana completa ya terminada.');return {professional:prof.value,week_start:week.value};}
 function stats(parent,rows){const grid=el('div',undefined,'management-stats');for(const [label,value,base]of rows){const box=el('div',undefined,'management-stat');box.append(el('span',label),el('strong',value),el('small',base));grid.append(box);}parent.append(grid);}
 function table(parent,columns,rows,empty='Sin registros para estos filtros.'){if(!rows.length){parent.append(el('p',empty,'subtitle'));return;}const wrap=el('div',undefined,'table-scroll'),t=el('table'),head=el('thead'),tr=el('tr');for(const [,label]of columns){const th=el('th',label);th.scope='col';tr.append(th);}head.append(tr);t.append(head);const body=el('tbody');for(const r of rows){const row=el('tr');for(const [key,,fmt]of columns)row.append(el('td',fmt?fmt(r[key],r):r[key]??'Sin dato'));body.append(row);}t.append(body);wrap.append(t);parent.append(wrap);}
 function block(parent,title,note){const section=el('section',undefined,'management-block');section.append(el('h2',title),el('p',note,'subtitle'));parent.append(section);return section;}
 function detail(parent,title){const d=el('details'),s=el('summary',title);d.append(s);parent.append(d);return d;}
 function inventoryChart(parent,rows){
  if(!rows.length)return;
  parent.append(el('p','Barras: proporción de artículos inicializados en el mínimo o por debajo, por sede. Semáforo: rojo con agotados o negativos, ámbar en mínimo, verde sin alertas.','subtitle'));
  const wrap=el('div',undefined,'mgmt-stock-chart');
  for(const r of rows){
   const alerts=Number(r.alerts)||0,empty=Number(r.empty)||0,init=Number(r.initialized)||0;
   const level=empty>0?'crit':alerts>0?'warn':'ok';
   const row=el('div',undefined,'mgmt-stock-row'),labelBox=el('div',undefined,'mgmt-stock-label');
   const dot=el('span',undefined,'mgmt-dot '+level),head=el('div',undefined,'mgmt-stock-head');
   head.append(el('strong',r.sede),el('span',number(alerts)+' en mínimo · '+number(empty)+' agotados/neg. · '+number(init)+' inicializados','mgmt-stock-sub'));
   labelBox.append(dot,head);
   const track=el('div',undefined,'mgmt-track'),fill=el('span',undefined,'mgmt-fill '+level);
   fill.style.width=(init?Math.min(100,100*alerts/init):0)+'%';track.append(fill);
   track.setAttribute('role','img');track.setAttribute('aria-label',r.sede+': '+alerts+' en mínimo de '+init+' inicializados'+(empty?', '+empty+' agotados o negativos':''));
   row.append(labelBox,track);wrap.append(row);
  }
  parent.append(wrap);
 }
 function draw(r,filters){data=r;applied={...filters};const host=$('#report-results');host.replaceChildren();
  host.append(el('div',window.MARATHON_CONFIG?.supabaseUrl==='https://marathon-demo.invalid'?'Demostración con cifras ficticias. Los filtros solo ilustran los controles en esta demostración; para calcular con datos reales usá el acceso normal al CRM.':'Registro en validación · Estos valores describen lo cargado en el CRM. Un cero registrado no demuestra ausencia de actividad real.','management-notice'));
  const a=r.activity,c=r.cash,b=r.balances,i=r.inventory,t=r.capacity;
  let section=block(host,'Atención y asistencia','Mes '+r.month+' · Solo turnos ya finalizados al corte de consulta. Filtros: sede, terapia y profesional.');
  stats(section,[['Personas atendidas',number(a.patients),'Pacientes distintos con Presente'],['Atenciones realizadas',number(a.present),'Reservas por paciente con Presente'],['Asistencia',percent(a.attendance),`${a.present} presentes / ${a.present+a.absent} con asistencia definida`],['Cobertura del registro',percent(a.coverage),`${a.present+a.absent} definidos / ${a.present+a.absent+a.pending} no cancelados finalizados`]]);
  section.append(el('p',`${a.total} turnos finalizados · ${a.pending} pendientes de registrar · ${a.cancelled} cancelados · ${a.absent-a.auto_absent} ausencias manuales · ${a.auto_absent} automáticas. Las automáticas requieren revisión.`));
  if(!a.present)section.append(el('p','0 atenciones registradas. Todavía no hay base para evaluar el volumen de atención.','management-note'));
  const byTherapy=detail(section,'Distribución por terapia');
  table(byTherapy,[['terapia','Terapia'],['patients','Personas',number],['present','Atenciones',number],['absent','Ausentes',number],['pending','Pendientes finalizados',number],['cancelled','Cancelados',number]],r.therapies);
  const byProf=detail(section,'Detalle por profesional y sede');table(byProf,[['profesional','Profesional'],['sede','Sede'],['personas','Personas',number],['atenciones','Atenciones',number]],r.professionals);
  section.append(el('p','Una persona puede aparecer en varios grupos. El total global se calcula nuevamente y no suma personas de los subtotales.','subtitle'));
  section=block(host,'Agenda y tiempo profesional',`Semana completa ${t.week_start} al ${t.week_end}. Aproximación por horarios actuales; no reconstruye la oferta histórica ni mide salas, equipos o cupos grupales. El mes y la terapia no se aplican a este bloque.`);
  stats(section,[['Minutos disponibles',number(t.available),`${t.professionals} profesionales con horario`],['Con turnos vigentes',number(t.used),percent(t.usage)+' del horario'],['Con atención registrada',number(t.attended),percent(t.attendance)+' del horario']]);
  if(!t.available)section.append(el('p','Sin capacidad configurada para estos filtros.','management-note'));
  section.append(el('p',`${t.outside} turnos total o parcialmente fuera de horario · ${t.site_conflicts} superposiciones de horarios entre sedes dentro del filtro. Los minutos simultáneos del mismo profesional se cuentan una sola vez.`));
  table(detail(section,'Minutos por profesional'),[['profesional','Profesional'],['available','Disponibles',number],['used','Vigentes',number],['attended','Con Presente',number],['usage','Tiempo vigente',percent]],t.rows);
  section=block(host,'Dinero registrado','Caja: mes '+r.month+'. Saldos: foto actual, independiente del mes. Sede, terapia y profesional se aplican según el vínculo del cargo; con terapia o profesional, Ortopedia queda fuera de la cobranza.');
  stats(section,[['Entradas',money(c.income),`${c.count} movimientos en el período`],['Salidas',money(c.expense),`${c.compensations} contrasientos incluidos`],['Flujo neto',money(c.net),'Entradas menos salidas; no es ganancia'],['Saldo actual por cobrar',money(b.total),`${b.count} cargos con saldo / ${b.charges} cargos elegibles`]]);
  if(!c.count)section.append(el('p','Sin movimientos registrados en el período.','management-note'));
  if(!b.charges)section.append(el('p','Sin cargos elegibles registrados. El cero no acredita que todos los pacientes hayan pagado.','management-note'));
  if(b.overpaid)section.append(el('p',`${b.overpaid} cargos con pagos superiores al importe: revisar conciliación.`, 'management-note'));
  table(detail(section,'Caja por medio y origen'),[['medio','Medio'],['origen','Origen'],['movimientos','Movimientos',number],['entradas','Entradas',money],['salidas','Salidas',money]],c.rows);
  table(detail(section,'Saldos por origen y antigüedad'),[['origen','Origen'],['age','Edad del cargo'],['cantidad','Cargos',number],['saldo','Saldo',money]],b.rows,'Sin cargos con saldo registrado.');
  section.append(el('p','Antigüedad no significa deuda vencida. Las sesiones futuras no se exigen. Las aplicaciones de anticipos reducen el saldo, sin generar un nuevo ingreso.','subtitle'));
  section=block(host,'Ortopedia e inventario','Foto actual · Solo artículos y sedes activos. Se aplica sede; mes, terapia y profesional no se aplican. Validar existencias físicas y mínimos antes de reponer.');
  stats(section,[['Inventarios inicializados',number(i.initialized),`${i.total} pares artículo-sede activos`],['En mínimo o por debajo',number(i.alerts),percent(i.percentage)+' de los inicializados'],['Agotados o negativos',number(i.empty),`${i.negative} con stock negativo`],['Sin inicializar',number(i.unknown),'Fuera del porcentaje de alertas; stock desconocido']]);
  inventoryChart(section,i.rows);
  table(section,[['sede','Sede'],['initialized','Inicializados',number],['unknown','Sin inicializar',number],['alerts','En mínimo o debajo',number],['empty','Agotados o negativos',number]],i.rows);
  const stock=detail(section,'Consultar artículos y alertas'),controls=el('div',undefined,'management-stock-filter'),searchLabel=el('label','Buscar artículo'),search=el('input');search.type='search';search.placeholder='Nombre o código';searchLabel.append(search);
  const stateLabel=el('label','Inventario'),state=el('select');for(const [value,label]of [['alerts','En mínimo o debajo'],['unknown','Sin inicializar'],['all','Todos']]){const o=el('option',label);o.value=value;state.append(o);}stateLabel.append(state);controls.append(searchLabel,stateLabel);stock.append(controls);const result=el('div');stock.append(result);
  const redraw=()=>{const query=search.value.trim().toLocaleLowerCase('es');const rows=i.details.filter(x=>(state.value==='all'||state.value==='unknown'&&!x.initial_loaded||state.value==='alerts'&&x.initial_loaded&&x.stock<=x.minimo)&&x.producto.toLocaleLowerCase('es').includes(query));result.replaceChildren();result.append(el('p',`${rows.length} artículos-sede · Se muestran hasta 100; usá la búsqueda para acotar.`,'subtitle'));table(result,[['producto','Artículo'],['sede','Sede'],['modalidad','Modalidad'],['stock','Stock',(v,row)=>row.initial_loaded?number(v):'Sin inicializar'],['minimo','Mínimo',number]],rows.slice(0,100));};search.addEventListener('input',redraw);state.addEventListener('change',redraw);redraw();
  section=block(host,'Cómo se calculan','Las definiciones se aplican al registro disponible, sin metas ni rankings automáticos.');
  const method=detail(section,'Definiciones y límites de los indicadores');for(const text of [
   'I1: personas distintas y reservas PRESENTE ya finalizadas, según fecha y duración del turno. No se usan altas de fichas como primeras atenciones.',
   'I2: asistencia = presentes / (presentes + ausentes). Cobertura = (presentes + ausentes) / (presentes + ausentes + pendientes finalizados). Sin denominador se muestra Sin base. Cancelados aparte.',
   'I3: unión de intervalos profesionales; los turnos vigentes y con Presente se intersectan con horarios configurados. Se deduplican también superposiciones entre sedes. No mide utilización física.',
   'I4: ingresos y pagos menos egresos y reintegros. Se incluye el movimiento original y su compensación, una sola vez por movimiento. No equivale a ganancia ni a saldo bancario.',
   'I5: máximo entre cero y cargo menos pagos netos y anticipos aplicados. Pagos y aplicaciones se agregan antes de relacionarlos con los cargos. Bonos activos emitidos; ventas y alquileres; sesiones PRESENTE finalizadas.',
   'I6: inicial + compras + ajustes positivos + devoluciones − ventas − alquileres − ajustes negativos. Los pares sin inicializar no entran en el porcentaje. Los negativos permanecen visibles.',
   'Sin rama validada, costos históricos, captación ni derivaciones registradas no se calculan rentabilidad, crecimiento por rama, conversión ni abandono. Los valores no prueban cobertura completa de la empresa.'
  ])method.append(el('p',text));
 }
 function exportFile(){if(!data)return;const r=data,rows=[];const add=(section,label,value,base)=>rows.push([section,label,value??'Sin base',base]);
  add('Atención','Personas',r.activity.patients,'PRESENTE finalizado; mes '+r.month);add('Atención','Atenciones',r.activity.present,'PRESENTE finalizado');add('Asistencia','Asistencia %',r.activity.attendance,'Presentes / (presentes + ausentes)');add('Asistencia','Cobertura %',r.activity.coverage,'Definidos / no cancelados finalizados');
  for(const key of ['present','absent','pending','cancelled','auto_absent'])add('Estados',key,r.activity[key],'Turnos finalizados del período');
  for(const [key,label]of [['income','Entradas'],['expense','Salidas'],['net','Neto']])add('Caja',label,r.cash[key],'ARS · mes '+r.month);
  add('Cobranza','Saldo actual',r.balances.total,'ARS · foto actual');add('Cobranza','Cargos con saldo',r.balances.count,'Cantidad');
  for(const x of r.balances.rows)add('Cobranza',x.origen+' · '+x.age,x.saldo,x.cantidad+' cargos');
  for(const key of ['available','used','attended','usage'])add('Tiempo profesional',key,r.capacity[key],r.capacity.week_start+' al '+r.capacity.week_end+' · horarios actuales');
  for(const x of r.capacity.rows)add('Tiempo profesional',x.profesional,x.used,x.available+' min disponibles; '+x.attended+' con Presente');
  for(const x of r.therapies){add('Atención por terapia',x.terapia,x.present,x.patients+' personas; no sumar distintos');}
  for(const x of r.inventory.details)add('Inventario',x.sede+' · '+x.producto,x.initial_loaded?x.stock:'Sin inicializar','Mínimo '+x.minimo+' · '+x.modalidad);
  const bytes=BillingXlsx.buildGrid({title:'Marathon · Gestión del registro',sheetName:'Gestion',columns:[{name:'Bloque',width:24},{name:'Indicador o grupo',width:50},{name:'Valor',width:22},{name:'Base y alcance',width:64}],rows,metadata:[['Mes de actividad y caja',r.month,'Corte Argentina',r.cut_local],['Sede',applied.sede||'Todas','Terapia',applied.therapy||'Todas'],['Profesional',applied.professional||'Todos','Semana',r.capacity.week_start]],note:'Registro en validación. Saldo e inventario son fotos actuales; el tiempo usa la semana indicada. Ceros registrados no prueban ausencia de actividad. No contiene identificadores de pacientes.'});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download='Marathon_Gestion_'+r.month+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message('Indicadores y detalle de inventario descargados.');
 }
 toggle(false);
 return {toggle,options,read,draw,exportFile,hasData:()=>!!data,reset:()=>{data=null;applied=null;prof.value='';week.max=previousWeek();week.value=week.max;},invalidate:()=>{data=null;applied=null;}};
}
