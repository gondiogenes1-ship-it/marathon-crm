"""Ediciones locales puntuales. No publica ni modifica bases."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def edit(name,changes):
 p=ROOT/'public'/name;t=p.read_text(encoding='utf-8')
 for old,new in changes:
  assert t.count(old)==1,(name,old[:100],t.count(old));t=t.replace(old,new)
 p.write_text(t,encoding='utf-8')
edit('operations.js',[
 ("import {createCashPatientPicker}","import {createSaldoUI} from './saldo.js?v=20261104-saldo';\nimport {createCashPatientPicker}"),
 (" const locked=()=>ctx.isBusy()||!!pending||cashPatientPicker.isPending();"," const isSaldo=()=>ctx.saldoActive?.()===true;\n const saldoUI=createSaldoUI({...ctx,modal,execute,refresh:refreshMoney,isPending:()=>!!pending});\n const locked=()=>ctx.isBusy()||!!pending||cashPatientPicker.isPending()||saldoUI.isPending();"),
 ('  cashPatientPicker.sync();','  cashPatientPicker.sync();saldoUI.sync();'),
 ('async function execute(name,args,after,notice){','async function execute(name,args,after,notice){'),
 ("else{pending=null;ctx.message(e.message,true);$('#operation-error').textContent=e.message;}","else{pending=null;ctx.message(e.message,true);$('#operation-error').textContent=e.message;task.notice?.onDefiniteError?.(e);}"),
 ('task.notice?.();',"if(typeof task.notice==='function')task.notice();"),
 (' function newAdvance(){'," async function newAdvance(){\n  if(isSaldo())return saldoUI.open();"),
 (" async function openAdvance(kind,id,after=null){"," async function openAdvance(kind,id,after=null){\n  if(isSaldo()){if(kind==='deposit'||kind==='apply')return saldoUI.open({dni:id});const a=await rpc('marathon_advance_get',{p_id:id,p_after:null,p_limit:1});return kind==='history'?saldoUI.history(a.advance.dni):saldoUI.open({dni:a.advance.dni,subtipo:'SALDO_DEVOLUCION'});}"),
 (" async function openBonus(kind,id,after=null){"," async function openBonus(kind,id,after=null){\n  if(isSaldo()){const r=await rpc('marathon_bonus_get',{p_id:id,p_after:null,p_limit:1});if(kind==='pay')return saldoUI.open({dni:r.bonus.dni});if(kind==='refund'||kind==='history')return saldoUI.history(r.bonus.dni);}"),
 ("if(kind==='cancel'&&Number(b.paid)!==0)","if(kind==='cancel'&&Number(b.paid)!==0&&!isSaldo())"),
 (" async function openMoney(id){"," async function openMoney(id){\n  if(isSaldo()){const t=await rpc('marathon_turn_account',{p_id:id});return saldoUI.open({dni:t.dni,sede:t.sede});}"),
 (" async function openCash(){show('cash');", " async function openCash(){show('cash');updateSaldoLabels();"),
 (" function openReverse(m){const panel=", " async function openReverse(m){if(isSaldo()&&m.dni&&m.tipo!=='EGRESO'){try{return await saldoUI.reverse(m.id);}catch(e){if(e.code!=='PT404')throw e;}}const panel="),
 (" async function newCash(){cashPatientPicker.reset();", " async function newCash(){if(isSaldo())return saldoUI.open({sede:cf.sede||''});cashPatientPicker.reset();"),
 (" async function loadAccount(){const data=", " async function loadAccount(){if(isSaldo())return loadSaldoAccount();const data="),
 (" return {openAdvance,newAdvance,", " function updateSaldoLabels(){for(const id of ['cash-new','home-new-cash']){const b=$('#'+id);if(b)b.textContent=isSaldo()?'Registrar movimiento':'Otro ingreso o egreso';}for(const id of ['cash-advance','home-receive-advance']){const b=$('#'+id);if(b)b.hidden=isSaldo();}let prepare=$('#cash-prepare-quotas');if(isSaldo()&&!prepare){prepare=action('Actualizar cuotas',()=>{if(locked())return;execute('marathon_saldo_preparar',{},refreshMoney);});prepare.id='cash-prepare-quotas';$('#cash-new').after(prepare);}if(prepare)prepare.hidden=!isSaldo();}\n async function loadSaldoAccount(){const a=await rpc('marathon_saldo_consultar',{p_dni:accountDni});an=null;ap=0;$('#account-summary').textContent=a.name+' · Deuda clínica: '+money(a.deuda)+' · Saldo a favor: '+money(a.saldo);const list=$('#account-list');list.replaceChildren();const actions=el('div',undefined,'form-actions');actions.append(action('Registrar movimiento',()=>ctx.work(()=>saldoUI.open({dni:accountDni})),'b'),action('Historial de saldo',()=>ctx.work(()=>saldoUI.history(accountDni))));list.append(actions);for(const d of a.deudas.filter(d=>Number(d.deuda)>0)){const row=el('article',undefined,'turn-card');row.append(el('h3',({sesion:'Sesión presente',cuota:'Cuota mensual',bono:'Bono inicial'}[d.tipo])+' · '+d.fecha),el('p',d.sede+' · Deuda: '+money(d.deuda)));list.append(row);}if(!a.deudas.some(d=>Number(d.deuda)>0))list.append(el('p','Sin deuda clínica pendiente.'));$('#account-page').textContent='Cuenta completa';sync();}\n return {openSaldo:p=>saldoUI.open(p),saldoHistory:dni=>saldoUI.history(dni),updateSaldoLabels,openAdvance,newAdvance,"),
 ("isPending:()=>!!pending||cashPatientPicker.isPending(),reset:()=>{cashExportFilters", "isPending:()=>!!pending||cashPatientPicker.isPending()||saldoUI.isPending(),reset:()=>{saldoUI.reset();cashExportFilters")
])
edit('app.js',[
 ("import {createWhatsApp}","import {saldoEnabled} from './saldo-state.js?v=20261104-saldo';\nimport {createWhatsApp}"),
 ('let api=null,user=null,','let saldoActive=false;\nlet api=null,user=null,'),
 ('const agenda=createAgenda({','const agenda=createAgenda({saldoActive:()=>saldoActive,openSaldo:p=>operations.openSaldo(p),'),
 ('const operations=createOperations({','const operations=createOperations({saldoActive:()=>saldoActive,'),
 ('const patientHistory=createPatientHistory({','const patientHistory=createPatientHistory({saldoActive:()=>saldoActive,onSaldo:dni=>work(()=>operations.openSaldo({dni})),onSaldoHistory:dni=>work(()=>operations.saldoHistory(dni)),'),
 ("user=await api.signIn($('#login-email').value,$('#login-password').value);form.reset();","user=await api.signIn($('#login-email').value,$('#login-password').value);form.reset();saldoActive=await saldoEnabled(api,{fresh:true});operations.updateSaldoLabels();"),
 ("  user=null;catalog=[];", "  saldoActive=false;operations.updateSaldoLabels();user=null;catalog=[];"),
 ("./operations.js?v=20261030-0140","./operations.js?v=20261104-saldo"),
 ("./api.js?v=20261030-0140","./api.js?v=20261104-saldo"),
 ("./patient-history.js?v=20261027-0127","./patient-history.js?v=20261104-saldo"),
 ("./agenda.js?v=20261102-cancelados","./agenda.js?v=20261104-saldo")
])
edit('api.js',[("'PT409','PT404'","'PT409','PT404','55000'")])
edit('index.html',[("</head><body",'<link rel="stylesheet" href="./saldo.css?v=20261104-saldo"></head><body'),('./app.js?v=20261102-cancelados','./app.js?v=20261104-saldo')])
print('Formulario conectado a Inicio, Caja y cuenta; estado de activación separado.')
