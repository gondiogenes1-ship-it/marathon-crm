import {createPatientReports} from './patient-reports.js?v=20261111-obra-social';
import {createManagement} from './management.js?v=20261111-informes-tabs';
import {createTrends} from './trends.js?v=20261113-ausentismo-profesional';
import {createBilling} from './billing.js?v=20261111-facturacion';
import {BillingXlsx} from './xlsx.js?v=20261019-0110';
export function createReports(ctx){
 const $=s=>document.querySelector(s),el=(t,s)=>{const e=document.createElement(t);if(s!==undefined)e.textContent=s;return e;};
 const management=createManagement(ctx),patients=createPatientReports(ctx),trends=createTrends(ctx),billing=createBilling(ctx);
 let tab='patients',sub='resumen',patientOptions=null;
 let pages=[null],page=0,next=null,last=null,filters=null;
 const rpc=(n,a={})=>ctx.getApi().rpc(n,a);
 const money=n=>new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n||0));
 const currentMonth=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires'}).format(new Date()).slice(0,7);
 const columns={billing:[['dni','DNI'],['name','Nombre'],['surname','Apellido'],['affiliate','N.º afiliado'],['insurance','Obra social'],['done','Realizadas'],['next','Pendientes mes siguiente']],cash:[['fecha','Fecha'],['hora','Hora'],['sede','Sede'],['origen','Origen'],['tipo','Tipo'],['dni','DNI'],['monto','Importe'],['medio','Medio'],['concepto','Concepto'],['actor','Responsable']]};
 // Qué motor y vista corresponde a la pestaña/sub-pestaña activa.
 function mode(){
  if(tab==='ortho')return {engine:'management',view:'ortho'};
  if(tab==='cash'&&sub==='resumen')return {engine:'management',view:'cash'};
  if(tab==='cash'&&sub==='facturacion')return {engine:'billing'};
  return {engine:'report',kind:'cash'};
 }
 function applyFields(){
  const m=mode(),bill=m.engine==='billing';
  const showMonth=tab!=='ortho';
  const showTherapy=(m.engine==='management'&&m.view==='cash')||bill||(m.engine==='report'&&m.kind==='cash');
  const mod=$('#report-modality').value;
  const showInsurance=bill&&(mod===''||mod==='OBRA_SOCIAL');
  $('#report-month-label').hidden=!showMonth;
  $('#report-therapy-label').hidden=!showTherapy;
  $('#report-modality-label').hidden=!bill;
  $('#report-insurance-label').hidden=!showInsurance;
  $('#report-pagination').hidden=m.engine!=='report';
  $('#report-note').textContent=
   tab==='ortho'?'Inventario: foto actual por sede. El mes no aplica; se usa el corte de consulta. Validá existencias físicas y mínimos antes de reponer.'
   :m.engine==='management'?'Caja: usa el mes elegido. Saldos por cobrar: foto actual. Con terapia, Ortopedia queda fuera de la cobranza.'
   :bill?'Pacientes atendidos en el mes, según la cobertura de cada atención. Tildá "Cargado" a medida que cargás en la plataforma de la obra social; la marca es compartida entre secretarias. Filtrá por modalidad, obra social o terapia (algunas no se facturan por OS).'
   :'Movimientos del mes: clínica, ortopedia y caja manual. Con filtro de terapia, solo movimientos vinculados a turnos de esa terapia.';
 }
 const isAdmin=()=>ctx.getUser?.()?.role==='ADMIN';
 function show(){
  const admin=isAdmin(),legacy=tab==='ortho'||tab==='cash';
  $('#patient-reports').hidden=tab!=='patients';
  $('#report-trends').hidden=tab!=='trends';
  $('#report-legacy').hidden=!legacy;
  // Acceso por rol: SECRETARIA solo ve Caja -> Facturación.
  $('#report-tabs').hidden=!admin;
  $('#report-tab-patients').hidden=!admin;$('#report-tab-trends').hidden=!admin;$('#report-tab-ortho').hidden=!admin;
  $('#report-sub-resumen').hidden=!admin;$('#report-sub-movimientos').hidden=!admin;
  for(const [id,val]of [['report-tab-patients','patients'],['report-tab-trends','trends'],['report-tab-ortho','ortho'],['report-tab-cash','cash']]){const b=$('#'+id);const a=tab===val;b.className=a?'b':'s';b.setAttribute('aria-pressed',String(a));}
  $('#report-subtabs').hidden=tab!=='cash'||!admin;
  for(const [id,val]of [['report-sub-resumen','resumen'],['report-sub-facturacion','facturacion'],['report-sub-movimientos','movimientos']]){const b=$('#'+id);const a=sub===val;b.className=a?'b':'s';b.setAttribute('aria-pressed',String(a));}
  $('#report-export').hidden=!legacy;
  if(legacy)applyFields();
 }
 function sync(){patients.sync();const m=mode();$('#report-prev').disabled=ctx.isBusy()||!page;$('#report-next').disabled=ctx.isBusy()||!next;$('#report-export').disabled=ctx.isBusy()||(m.engine==='management'?!management.hasData():m.engine==='billing'?!billing.hasData():!last?.rows?.length);}
 function readFilters(){
  const m=mode(),month=$('#report-month').value||currentMonth(),f={month,sede:$('#report-sede').value};
  if(m.engine==='billing'){const mod=$('#report-modality').value;f.therapy=$('#report-therapy').value;f.modality=mod;f.insurance=(mod===''||mod==='OBRA_SOCIAL')?$('#report-insurance').value:'';return f;}
  f.therapy=$('#report-therapy').value;return f;
 }
 function drawTable(kind,r){last=r;next=r.next;$('#report-results').classList.remove('management-results');$('#report-results').replaceChildren();
  const s=r.summary||{};
  $('#report-summary').textContent=kind==='billing'?`${s.patients} pacientes · ${s.done} realizadas (${r.month}) · ${s.next} pendientes (${r.next_month}) · ${s.missing_affiliate} sin número de afiliado.`:`Ingresos: ${money(s.income)} · Egresos: ${money(s.expense)} · Neto: ${money(s.net)} · ${r.total} movimientos.`;
  $('#report-generated').textContent='Consultado: '+new Date(r.generated_at).toLocaleString('es-AR');
  const cols=columns[kind],table=el('table'),thead=el('thead'),hr=el('tr');for(const [,title]of cols)hr.append(el('th',title));thead.append(hr);table.append(thead);const body=el('tbody');for(const row of r.rows){const tr=el('tr');for(const [key]of cols)tr.append(el('td',key==='monto'?money(row[key]):row[key]??''));body.append(tr);}table.append(body);$('#report-results').append(table);if(!r.rows.length)$('#report-results').append(el('p','No hay datos con estos filtros.'));
  $('#report-page').textContent='Página '+(page+1);sync();
 }
 async function load(){
  const m=mode();filters=readFilters();
  if(m.engine==='billing'){await billing.load(filters);$('#report-summary').textContent='Facturación por cobertura · '+filters.month;$('#report-generated').textContent='';last=null;next=null;sync();return;}
  if(m.engine==='management'){
   const r=await rpc('marathon_management',{p_filters:filters});last=r;next=null;
   management.draw(r,filters,m.view);
   $('#report-summary').textContent=m.view==='ortho'?`Inventario · ${r.inventory.alerts} en mínimo · ${r.inventory.empty} agotados/neg · ${r.inventory.initialized} inicializados (foto actual).`:`Caja ${r.month} · Entradas ${money(r.cash.income)} · Salidas ${money(r.cash.expense)} · Neto ${money(r.cash.net)} · Saldo por cobrar ${money(r.balances.total)}.`;
   $('#report-generated').textContent='Corte Argentina: '+new Date(r.generated_at).toLocaleString('es-AR',{timeZone:'America/Argentina/Buenos_Aires'});
   sync();return;
  }
  drawTable(m.kind,await rpc('marathon_report',{p_kind:m.kind,p_filters:filters,p_after:pages[page],p_limit:100}));
 }
 async function go(){show();if(tab==='patients'){if(patientOptions)await patients.open(patientOptions);sync();return;}if(tab==='trends'){if(patientOptions)await trends.open(patientOptions);sync();return;}page=0;pages=[null];last=null;next=null;await load();}
 function resetResults(msg){management.invalidate();last=null;next=null;$('#report-results').replaceChildren();$('#report-summary').textContent=msg||'';sync();}
 function download(bytes,name,type){const url=URL.createObjectURL(new Blob([bytes],{type})),a=el('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
 $('#report-tab-patients').addEventListener('click',()=>ctx.work(async()=>{tab='patients';await go();}));
 $('#report-tab-trends').addEventListener('click',()=>ctx.work(async()=>{tab='trends';await go();}));
 $('#report-tab-ortho').addEventListener('click',()=>ctx.work(async()=>{tab='ortho';await go();}));
 $('#report-tab-cash').addEventListener('click',()=>ctx.work(async()=>{tab='cash';sub='resumen';await go();}));
 for(const [id,val]of [['report-sub-resumen','resumen'],['report-sub-facturacion','facturacion'],['report-sub-movimientos','movimientos']])$('#'+id).addEventListener('click',()=>ctx.work(async()=>{sub=val;await go();}));
 $('#report-filter').addEventListener('submit',e=>{e.preventDefault();ctx.work(async()=>{page=0;pages=[null];await load();});});
 $('#report-filter').addEventListener('change',()=>{if(tab==='ortho'||tab==='cash')applyFields();resetResults('Filtros modificados. Presioná Consultar.');});
 $('#report-next').addEventListener('click',()=>ctx.work(async()=>{if(next){pages=pages.slice(0,page+1);pages.push(next);page++;await load();}}));
 $('#report-prev').addEventListener('click',()=>ctx.work(async()=>{if(page){page--;await load();}}));
 $('#report-export').addEventListener('click',()=>ctx.work(async()=>{
  const m=mode();
  if(m.engine==='management'){management.exportFile(m.view);return;}
  if(m.engine==='billing'){billing.exportFile();return;}
  if(!filters||!last?.rows?.length)return;
  const r=await rpc('marathon_report',{p_kind:m.kind,p_filters:filters,p_after:null,p_limit:10000});
  if(r.next)throw Error('Reducí los filtros para exportar el informe completo.');
  const cols=columns[m.kind];
  const bytes=BillingXlsx.buildGrid({title:m.kind==='billing'?'Resumen mensual de obra social':'Caja mensual',sheetName:m.kind==='billing'?'Facturacion':'Caja',columns:cols.map(([key,name])=>({name,numeric:['done','next','monto'].includes(key),width:26})),rows:r.rows.map(row=>cols.map(([key])=>['done','next','monto'].includes(key)?Number(row[key]):String(row[key]??''))),metadata:[['Mes',r.month,'Siguiente',r.next_month||''],['Sede',filters.sede||'Todas','Terapia',filters.therapy||'Todas'],['Obra social',r.summary?.insurance||'','Consulta',r.generated_at]],note:$('#report-note').textContent});
  download(bytes,'Marathon_'+m.kind+'_'+filters.month+'.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');ctx.message('Informe completo descargado: '+r.rows.length+' filas.');
 }));
 return{sync,isPending:()=>false,open:async()=>{ctx.show('reports');if(!isAdmin()){tab='cash';sub='facturacion';}const opts=await rpc('marathon_catalog_options');const agendaOptions=await rpc('marathon_agenda_options');patientOptions={sedes:opts.sedes,therapies:opts.therapies,professionals:agendaOptions.professionals||[]};
  for(const [id,rows,initial]of [['report-sede',opts.sedes,'Todas las sedes'],['report-therapy',opts.therapies,'Todas las terapias'],['report-insurance',[{id:'__PARTICULAR__',label:'Particular'},...opts.insurances],'Todas las obras sociales']]){const v=$('#'+id).value;$('#'+id).replaceChildren();for(const [value,title]of [['',initial],...rows.map(r=>[r.id,r.label+(r.estado==='INACTIVO'?' (inactiva)':'')])]){const o=el('option',title);o.value=value;$('#'+id).append(o);}$('#'+id).value=v;}
  if(!$('#report-month').value)$('#report-month').value=currentMonth();
  await go();},
  reset:()=>{patients.reset();management.reset();trends.reset();billing.reset();tab='patients';sub='resumen';patientOptions=null;pages=[null];page=0;next=null;last=null;filters=null;$('#report-filter').reset();$('#report-results').replaceChildren();$('#report-summary').textContent='';$('#report-generated').textContent='';}};
}
