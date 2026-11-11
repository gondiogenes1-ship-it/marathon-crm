import {BillingXlsx} from './xlsx.js?v=20261019-0110';
const number=n=>new Intl.NumberFormat('es-AR',{maximumFractionDigits:2}).format(Number(n??0));
const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n??0));
const percent=n=>n===null||n===undefined?'Sin base':number(n)+' %';
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const localDay=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date());
export function previousWeek(){const d=new Date(localDay()+'T12:00:00Z');d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7)-7);return d.toISOString().slice(0,10);}
export function createManagement(ctx){
 const $=s=>document.querySelector(s);let data=null,applied=null,view='cash';
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
 function methodSection(host,texts){const section=block(host,'Cómo se calculan','Las definiciones se aplican al registro disponible, sin metas ni rankings automáticos.');const method=detail(section,'Definiciones y límites de los indicadores');for(const t of texts)method.append(el('p',t));}
 function notice(host){host.append(el('div',window.MARATHON_CONFIG?.supabaseUrl==='https://marathon-demo.invalid'?'Demostración con cifras ficticias. Los filtros solo ilustran los controles en esta demostración; para calcular con datos reales usá el acceso normal al CRM.':'Registro en validación · Estos valores describen lo cargado en el CRM. Un cero registrado no demuestra ausencia de actividad real.','management-notice'));}
 function cashSection(host,r){
  const c=r.cash,b=r.balances;
  const section=block(host,'Dinero registrado','Caja: mes '+r.month+'. Saldos: foto actual, independiente del mes. Sede y terapia se aplican según el vínculo del cargo; con terapia, Ortopedia queda fuera de la cobranza.');
  stats(section,[['Entradas',money(c.income),`${c.count} movimientos en el período`],['Salidas',money(c.expense),`${c.compensations} contrasientos incluidos`],['Flujo neto',money(c.net),'Entradas menos salidas; no es ganancia'],['Saldo actual por cobrar',money(b.total),`${b.count} cargos con saldo / ${b.charges} cargos elegibles`]]);
  if(!c.count)section.append(el('p','Sin movimientos registrados en el período.','management-note'));
  if(!b.charges)section.append(el('p','Sin cargos elegibles registrados. El cero no acredita que todos los pacientes hayan pagado.','management-note'));
  if(b.overpaid)section.append(el('p',`${b.overpaid} cargos con pagos superiores al importe: revisar conciliación.`,'management-note'));
  table(detail(section,'Caja por medio y origen'),[['medio','Medio'],['origen','Origen'],['movimientos','Movimientos',number],['entradas','Entradas',money],['salidas','Salidas',money]],c.rows);
  table(detail(section,'Saldos por origen y antigüedad'),[['origen','Origen'],['age','Edad del cargo'],['cantidad','Cargos',number],['saldo','Saldo',money]],b.rows,'Sin cargos con saldo registrado.');
  section.append(el('p','Antigüedad no significa deuda vencida. Las sesiones futuras no se exigen. Las aplicaciones de anticipos reducen el saldo, sin generar un nuevo ingreso.','subtitle'));
 }
 function orthoSection(host,r){
  const i=r.inventory;
  const section=block(host,'Ortopedia e inventario','Foto actual · Solo artículos y sedes activos. Se aplica sede; mes, terapia y profesional no se aplican. Validar existencias físicas y mínimos antes de reponer.');
  stats(section,[['Inventarios inicializados',number(i.initialized),`${i.total} pares artículo-sede activos`],['En mínimo o por debajo',number(i.alerts),percent(i.percentage)+' de los inicializados'],['Agotados o negativos',number(i.empty),`${i.negative} con stock negativo`],['Sin inicializar',number(i.unknown),'Fuera del porcentaje de alertas; stock desconocido']]);
  inventoryChart(section,i.rows);
  table(section,[['sede','Sede'],['initialized','Inicializados',number],['unknown','Sin inicializar',number],['alerts','En mínimo o debajo',number],['empty','Agotados o negativos',number]],i.rows);
  const stock=detail(section,'Consultar artículos y alertas'),controls=el('div',undefined,'management-stock-filter'),searchLabel=el('label','Buscar artículo'),search=el('input');search.type='search';search.placeholder='Nombre o código';searchLabel.append(search);
  const stateLabel=el('label','Inventario'),state=el('select');for(const [value,label]of [['alerts','En mínimo o debajo'],['unknown','Sin inicializar'],['all','Todos']]){const o=el('option',label);o.value=value;state.append(o);}stateLabel.append(state);controls.append(searchLabel,stateLabel);stock.append(controls);const result=el('div');stock.append(result);
  const redraw=()=>{const query=search.value.trim().toLocaleLowerCase('es');const rows=i.details.filter(x=>(state.value==='all'||state.value==='unknown'&&!x.initial_loaded||state.value==='alerts'&&x.initial_loaded&&x.stock<=x.minimo)&&x.producto.toLocaleLowerCase('es').includes(query));result.replaceChildren();result.append(el('p',`${rows.length} artículos-sede · Se muestran hasta 100; usá la búsqueda para acotar.`,'subtitle'));table(result,[['producto','Artículo'],['sede','Sede'],['modalidad','Modalidad'],['stock','Stock',(v,row)=>row.initial_loaded?number(v):'Sin inicializar'],['minimo','Mínimo',number]],rows.slice(0,100));};search.addEventListener('input',redraw);state.addEventListener('change',redraw);redraw();
 }
 function draw(r,filtersArg,viewArg){data=r;applied={...filtersArg};if(viewArg)view=viewArg;const host=$('#report-results');host.classList.add('management-results');host.replaceChildren();notice(host);
  if(view==='ortho'){orthoSection(host,r);methodSection(host,['I6: inicial + compras + ajustes positivos + devoluciones − ventas − alquileres − ajustes negativos. Los pares sin inicializar no entran en el porcentaje. Los negativos permanecen visibles.']);}
  else{cashSection(host,r);methodSection(host,['I4: ingresos y pagos menos egresos y reintegros. Se incluye el movimiento original y su compensación, una sola vez por movimiento. No equivale a ganancia ni a saldo bancario.','I5: máximo entre cero y cargo menos pagos netos y anticipos aplicados. Pagos y aplicaciones se agregan antes de relacionarlos con los cargos. Bonos activos emitidos; ventas y alquileres; sesiones PRESENTE finalizadas.']);}
 }
 function exportFile(viewArg){if(!data)return;const r=data,v=viewArg||view,rows=[];const add=(section,label,value,base)=>rows.push([section,label,value??'Sin base',base]);
  if(v==='ortho'){
   add('Inventario','Inicializados',r.inventory.initialized,`${r.inventory.total} pares artículo-sede activos`);add('Inventario','En mínimo o debajo',r.inventory.alerts,percent(r.inventory.percentage)+' de los inicializados');add('Inventario','Agotados o negativos',r.inventory.empty,`${r.inventory.negative} con stock negativo`);add('Inventario','Sin inicializar',r.inventory.unknown,'Stock desconocido');
   for(const x of r.inventory.rows)add('Por sede',x.sede,x.alerts+' en mínimo',`${x.empty} agotados/neg · ${x.initialized} inicializados`);
   for(const x of r.inventory.details)add('Detalle',x.sede+' · '+x.producto,x.initial_loaded?x.stock:'Sin inicializar','Mínimo '+x.minimo+' · '+x.modalidad);
  }else{
   for(const [key,label]of [['income','Entradas'],['expense','Salidas'],['net','Neto']])add('Caja',label,r.cash[key],'ARS · mes '+r.month);
   add('Caja','Movimientos',r.cash.count,'En el período');
   for(const x of r.cash.rows)add('Caja por medio',x.medio+' · '+x.origen,x.entradas,'Entradas ARS · '+x.movimientos+' mov.');
   add('Cobranza','Saldo actual',r.balances.total,'ARS · foto actual');add('Cobranza','Cargos con saldo',r.balances.count,'Cantidad');
   for(const x of r.balances.rows)add('Cobranza',x.origen+' · '+x.age,x.saldo,x.cantidad+' cargos');
  }
  const title=v==='ortho'?'Marathon · Ortopedia e inventario':'Marathon · Caja';const sheet=v==='ortho'?'Ortopedia':'Caja';
  const bytes=BillingXlsx.buildGrid({title,sheetName:sheet,columns:[{name:'Bloque',width:24},{name:'Indicador o grupo',width:50},{name:'Valor',width:22},{name:'Base y alcance',width:64}],rows,metadata:[['Mes de caja',r.month,'Corte Argentina',r.cut_local],['Sede',applied.sede||'Todas','Terapia',applied.therapy||'Todas']],note:'Registro en validación. Saldo e inventario son fotos actuales. Ceros registrados no prueban ausencia de actividad. No contiene identificadores de pacientes.'});
  const url=URL.createObjectURL(new Blob([bytes],{type:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'})),a=el('a');a.href=url;a.download=(v==='ortho'?'Marathon_Ortopedia_':'Marathon_Caja_')+r.month+'.xlsx';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.message(v==='ortho'?'Inventario descargado.':'Caja descargada.');
 }
 return {draw,exportFile,hasData:()=>!!data,reset:()=>{data=null;applied=null;view='cash';},invalidate:()=>{data=null;applied=null;}};
}
