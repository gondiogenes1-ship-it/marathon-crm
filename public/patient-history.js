import {DailyUI} from './daily.js?v=20261019-0110';
import {patientCoverages,coverageLabel,patientPhoneNumber} from './coverage.js?v=20261027-0120';

export function createPatientHistory(ctx){
 const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const button=(text,fn)=>{const b=el('button',text,'s');b.type='button';b.addEventListener('click',fn);return b;};
 let generation=0,parent=null,patient=null,kind='clinic',page=0,pages=[null],next=null,loading=false,view=null;
 const isSaldo=()=>ctx.saldoActive?.()===true;
 const locked=()=>loading||!!ctx.isBusy?.();
 function reset(){++generation;parent=null;patient=null;view=null;loading=false;}
 function age(birth){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(birth||''))return '';
  const today=DailyUI.today(),years=Number(today.slice(0,4))-Number(birth.slice(0,4))-(today.slice(5)<birth.slice(5)?1:0);
  return years>=0&&years<130?years+' años · '+birth.split('-').reverse().join('/'):birth;
 }
 function sync(){if(!view)return;view.previous.disabled=locked()||page===0;view.next.disabled=locked()||!next;view.refresh.disabled=locked();for(const [key,b]of Object.entries(view.tabs)){b.disabled=locked();b.setAttribute('aria-pressed',String(kind===key));}}
 function renderSummary(summary){
  view.summary.replaceChildren();
  const financial=isSaldo()?[['Deuda clínica total',DailyUI.money(Number(summary.clinical_debt||0)+Number(summary.bonus_debt||0))],['Saldo a favor',DailyUI.money(summary.saldo_disponible??summary.advance_available??0)],['Sesiones y cuotas',DailyUI.money(summary.clinical_debt)],['Bonos iniciales',DailyUI.money(summary.bonus_debt||0)],['Ortopedia · cuenta aparte',DailyUI.money(summary.ortho_debt)]]:[['Saldo total',DailyUI.money(summary.debt)],['Saldo clínico',DailyUI.money(summary.clinical_debt)],['Saldo ortopedia',DailyUI.money(summary.ortho_debt)],['Saldo bonos',DailyUI.money(summary.bonus_debt||0)],['Anticipos disponibles',DailyUI.money(summary.advance_available||0)]];
  for(const [label,value]of [...financial,['Sesiones presentes',summary.present],['Turnos futuros pendientes',summary.upcoming],['Unidades por devolver',summary.rental_units]]){
   const card=el('article',undefined,'patient-stat');card.append(el('span',label),el('strong',String(value??0)));view.summary.append(card);
  }
 }
 function renderRows(rows){
  view.rows.replaceChildren();
  if(!rows.length){view.rows.append(el('p',kind==='clinic'?'No hay turnos registrados para este paciente.':kind==='advance'?'No hay anticipos registrados para este paciente.':kind==='bonus'?'No hay bonos registrados para este paciente.':'No hay operaciones de ortopedia registradas para este paciente.'));return;}
  if(kind==='clinic'){
   const body=DailyUI.table(view.rows,['Fecha / hora','Terapia / profesional','Sede','Estado','Cobertura','Importe','Cobrado neto','Saldo exigible','Acción']);
   for(const t of rows){const therapy=el('div');therapy.append(el('strong',t.terapia),el('small',t.profesional));
    const debt=el('span',DailyUI.money(t.debt),Number(t.debt)>0?'ui-debt':'');
    DailyUI.row(body,[t.fecha+' · '+String(t.hora).slice(0,5),therapy,t.sede,t.estado+(t.attendance_auto?' · Automático':''),coverageLabel(t.coverage),DailyUI.money(t.importe),DailyUI.money(t.paid),debt,button('Ver en agenda',()=>ctx.onAgenda(t))],{id:t.id});
   }
  }else if(kind==='ortho'){
   const body=DailyUI.table(view.rows,['Fecha / hora','Operación','Producto','Sede','Cantidad','Por devolver','Devolución prevista','Importe','Cobrado neto','Saldo']);
   for(const o of rows)DailyUI.row(body,[o.fecha+' · '+String(o.hora).slice(0,5),o.tipo,o.producto,o.sede,o.cantidad,o.tipo==='ALQUILER'?o.pending:'—',o.devolucion_prevista||'—',DailyUI.money(o.importe_total)+(o.discount_rate!=null?' · Desc. '+o.discount_rate+'% ('+DailyUI.money(o.discount_amount)+')':''),DailyUI.money(o.paid),DailyUI.money(o.debt)],{id:o.id});

  }else if(kind==='advance'){
   view.rows.append(el('p',isSaldo()?'Este es el historial anterior a la conversión. El saldo actual se consulta en la cuenta del paciente.':'El anticipo se aplica a sesiones presentes de la misma sede y, si se indicaron, de la misma terapia y profesional. El ingreso ya figura en Caja; aplicarlo no duplica el cobro.','subtitle'));
   const body=DailyUI.table(view.rows,['Fecha / hora','Sede / destino','Recibido',isSaldo()?'Disponible al convertir':'Disponible','Acciones']);
   for(const a of rows){const actions=el('div',undefined,'row-actions');actions.append(button('Historial del anticipo',()=>ctx.onAdvance('history',a.id)));if(!isSaldo()&&Number(a.available)>0)actions.append(button('Reintegrar disponible',()=>ctx.onAdvance('refund',a.id)));DailyUI.row(body,[a.fecha+' · '+String(a.hora).slice(0,5),a.sede+' · '+a.terapia+' · '+a.profesional,DailyUI.money(a.importe),DailyUI.money(a.available),actions],{id:a.id});}


  }else{
   view.rows.append(el('p',isSaldo()?'Los pagos del bono se registran con el formulario único. Anular un bono libera su pago al saldo sin devolver dinero de Caja.':'Cancelar o reprogramar turnos no anula el bono. Los bonos se cobran por separado de las sesiones.','subtitle'));
   const body=DailyUI.table(view.rows,['Registro / primera sesión','Terapia / sede','Estado','Bono único','Cobrado neto','Saldo','Acciones']);
   for(const b of rows){const actions=el('div',undefined,'row-actions');if(b.estado==='ACTIVO'){if(Number(b.debt)>0)actions.append(button('Cobrar bono',()=>ctx.onBonus('pay',b.id)));if(!isSaldo()&&Number(b.paid)>0)actions.append(button('Reintegrar bono',()=>ctx.onBonus('refund',b.id)));if(isSaldo()||Number(b.paid)<=0)actions.append(button('Anular bono',()=>ctx.onBonus('cancel',b.id)));}actions.append(button('Historial del bono',()=>ctx.onBonus('history',b.id)));DailyUI.row(body,[b.fecha+' · Primera: '+b.primera_fecha+' · '+b.sesiones+' sesiones',b.terapia+' · '+b.sede+' · '+b.profesional,b.estado,DailyUI.money(b.importe),DailyUI.money(b.paid),DailyUI.money(b.debt),actions],{id:b.id});}
  }
 }
 async function load(){
  if(!parent||!patient)return;const token=++generation,target=parent,v=view;loading=true;v.error.textContent='';v.rows.replaceChildren(el('p','Cargando historial…'));v.info.textContent='';sync();
  try{
   const data=await ctx.getApi().rpc('marathon_patient_history',{p_dni:patient.dni,p_kind:kind,p_after:pages[page],p_limit:25});
   if(token!==generation||!target.isConnected)return;
   next=data.next;renderSummary(data.summary);renderRows(data.rows);
   v.info.textContent=data.rows.length+' registros en esta página. Los saldos incluyen todo el historial. Ausentes y cancelados no generan deuda clínica.';
   v.page.textContent='Página '+(page+1);
  }catch(e){if(token===generation&&target.isConnected){next=null;v.rows.replaceChildren();v.error.textContent='No se pudo cargar el historial. '+e.message;}}
  finally{if(token===generation){loading=false;sync();}}
 }
 async function mount(target,p){
  reset();parent=target;patient=p;kind='clinic';page=0;pages=[null];next=null;target.replaceChildren();
  const header=el('div',undefined,'detail-head'),identity=el('div');identity.append(el('h2',[p.apellido,p.nombre,p.segundo_nombre].filter(Boolean).join(' ')),el('p','DNI '+p.dni+(age(p.nacimiento)?' · '+age(p.nacimiento):''),'patient-id'));
  header.append(identity,button('Cerrar ficha',()=>ctx.onClose()));target.append(header);
  const actions=el('div',undefined,'patient-quick-actions');for(const [label,fn]of [['Editar ficha',()=>ctx.onEdit(p)],['Reservar turno',()=>ctx.onBook(p)],['Agregar a lista de espera',()=>ctx.onWait(p)],['Cuenta clínica',()=>ctx.onAccount(p.dni)],...(isSaldo()?[['Registrar movimiento',()=>ctx.onSaldo(p.dni)],['Historial de saldo',()=>ctx.onSaldoHistory(p.dni)]]:[['Recibir anticipo',()=>ctx.onAdvance('deposit',p.dni)],['Aplicar anticipos a deuda',()=>ctx.onAdvance('apply',p.dni)]]),['Documentos',()=>ctx.onDocuments(p.dni)]])actions.append(button(label,fn));target.append(actions);
  const ficha=el('dl',undefined,'patient-ficha-grid');
  const insurances=patientCoverages(p).map(c=>(ctx.getCatalog().find(o=>o.id===c.obra_social_id)?.name||c.obra_social_id)+(c.afiliado?' · N.º '+c.afiliado:''));
  for(const [label,value]of [['Obras sociales / afiliados',insurances.join(' / ')||'Sin obra social'],['Médico de cabecera',p.medico],['Teléfono',p.telefono],['Correo',p.email],['Domicilio',[p.domicilio,p.localidad,p.provincia].filter(Boolean).join(', ')],['Observaciones',p.observaciones]]){const box=el('div');box.append(el('dt',label),el('dd',value||'—'));ficha.append(box);}target.append(ficha);
  const whatsapp=patientPhoneNumber(p.telefono);if(whatsapp){const link=el('a','Abrir WhatsApp');link.href='https://wa.me/'+whatsapp;link.target='_blank';link.rel='noopener noreferrer';link.className='s';link.setAttribute('aria-label','Abrir WhatsApp del paciente');target.append(link);}
  const summary=el('div',undefined,'patient-stats');summary.setAttribute('aria-label','Resumen del paciente');target.append(summary);
  const controls=el('div',undefined,'patient-history-controls'),tabs={};
  for(const [key,label]of [['clinic','Historial clínico'],['ortho','Historial de ortopedia'],['bonus','Bonos iniciales'],['advance',isSaldo()?'Anticipos históricos':'Anticipos']]){tabs[key]=button(label,()=>{if(locked())return;kind=key;page=0;pages=[null];next=null;load();});controls.append(tabs[key]);}
  const refresh=button('Actualizar historial',()=>{if(locked())return;page=0;pages=[null];load();});controls.append(refresh);target.append(el('h3','Cuenta e historial'),controls);
  const error=el('p');error.setAttribute('role','alert');const info=el('p',undefined,'subtitle'),rows=el('div'),pager=el('div',undefined,'pager'),pageLabel=el('span','Página 1');
  const previous=button('Página anterior',()=>{if(!locked()&&page>0){page--;load();}}),nextButton=button('Página siguiente',()=>{if(!locked()&&next){pages=pages.slice(0,page+1);pages.push(next);page++;load();}});
  pager.append(previous,pageLabel,nextButton);target.append(error,info,rows,pager);view={summary,tabs,refresh,error,info,rows,previous,next:nextButton,page:pageLabel};
  await load();
 }
 return{mount,reset,sync,reload:()=>{page=0;pages=[null];return load();}};
}
