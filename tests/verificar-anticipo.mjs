import {fileURLToPath} from 'node:url';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
const root=fileURLToPath(new URL('../public/',import.meta.url));
class E{
 constructor(tag){this.tagName=tag;this.children=[];this.dataset={};this.attrs={};this.listeners={};this.hidden=true;this.isConnected=true;this.value='';}
 append(...items){for(const i of items){i.isConnected=true;this.children.push(i);}}
 replaceChildren(...items){const disconnect=e=>{e.isConnected=false;e.children?.forEach(disconnect);};this.children.forEach(disconnect);this.children=[];this.append(...items);}
 setAttribute(k,v){this.attrs[k]=v;}
 addEventListener(k,fn){this.listeners[k]=fn;}
 querySelectorAll(selector){return this.children.flatMap(c=>[...(selector===c.tagName?[c]:[]),...(c.querySelectorAll?.(selector)||[])]);}
 showModal(){this.open=true;}
 close(){this.open=false;}
 remove(){this.isConnected=false;}
 reportValidity(){return true;}
}
const nodes=new Map();
const get=s=>{for(const n of nodes.values()){const all=[n,...walk(n)];const found=all.find(e=>'#'+e.id===s);if(found)return found;}if(!nodes.has(s))nodes.set(s,new E('div'));return nodes.get(s);};
function walk(e){return e.children.flatMap(c=>[c,...walk(c)]);}
const body=get('#operation-body'),dialog=get('#operation-dialog');
let busy=false,fail=false,rows=[{dni:'99000001',nombre:'Paciente',apellido:'Prueba'}],workPromise=Promise.resolve(),calls=[],writes=[],deferred=null;
const ctx={isBusy:()=>busy,isPending:()=>false,setBusy:v=>{busy=v;},message:()=>{},work:fn=>{if(busy)return;busy=true;workPromise=Promise.resolve().then(fn).finally(()=>busy=false);return workPromise;},getApi:()=>({rpc:async(n,a,w)=>{calls.push({n,a,w});if(n==='marathon_patient_search'){if(deferred)return deferred;if(fail)throw Error('Fallo simulado');return {rows,next:null};}if(n==='marathon_agenda_options')return {sedes:[{id:'Centro',label:'Centro'}],therapies:[],professionals:[]};if(n==='marathon_agenda_command'){writes.push(a);return {message:'Registrado'};}throw Error(n);}})};
const sandbox={document:{querySelector:get,createElement:t=>new E(t),createTextNode:t=>Object.assign(new E('text'),{textContent:t})},createSaldoUI:()=>({sync(){},reset(){},isPending:()=>false}),createCashPatientPicker:()=>({sync(){},isPending:()=>false,reset(){}}),DailyUI:{},Intl,Date,crypto:webcrypto};
vm.createContext(sandbox);vm.runInContext((await fs.readFile(root+'operations.js','utf8')).replace(/^import .*;\r?\n/gm,'').replace('export function createOperations','function createOperations')+'\nthis.factory=createOperations;',sandbox);
const ops=sandbox.factory(ctx),event={preventDefault(){}};
await ops.newAdvance();assert.equal(body.querySelectorAll('form').length,1);assert.equal(get('#advance-form').children.length,0);assert.equal(writes.length,0);
const submitSearch=async term=>{get('#o-advance-patient-query').value=term;body.querySelectorAll('form')[0].listeners.submit(event);await workPromise;};
await submitSearch('Prueba');let result=get('#advance-patient-results');assert.equal(result.children.length,1);assert.equal(writes.length,0);
result.children[0].listeners.click();await workPromise;
const advance=get('#advance-form');assert(advance.children.length);get('#o-advance-site').value='Centro';get('#o-advance-amount').value='12500';get('#o-advance-medium').value='TRANSFERENCIA';get('#o-advance-reason').value='Ejemplo';get('#o-advance-apply').checked=true;
advance.listeners.submit(event);await new Promise(r=>setImmediate(r));assert.equal(writes.length,1);assert.equal(writes[0].p_action,'advance_deposit');assert.equal(writes[0].p_data.dni,'99000001');assert.equal(writes[0].p_data.monto,12500);assert.equal(writes[0].p_data.medio,'TRANSFERENCIA');assert.equal(writes[0].p_data.apply_existing,true);assert(writes[0].p_request_id);
await ops.newAdvance();rows=[];await submitSearch('sin resultados');assert.equal(get('#advance-patient-results').children.length,0);assert.equal(writes.length,1);
await ops.newAdvance();fail=true;await submitSearch('error');assert(walk(body).some(e=>e.textContent?.includes('No se pudo buscar')));fail=false;
await ops.newAdvance();let resolve;deferred=new Promise(r=>resolve=r);get('#o-advance-patient-query').value='demorada';body.querySelectorAll('form')[0].listeners.submit(event);await Promise.resolve();dialog.close();resolve({rows:[{dni:'99000002',nombre:'Otro',apellido:'Prueba'}]});await workPromise;assert.equal(get('#advance-patient-results').children.length,0);assert.equal(writes.length,1);
assert(get('#cash-advance').listeners.click);
const html=await fs.readFile(root+'index.html','utf8');assert(html.includes('id="home-receive-advance"'));assert(html.includes('id="cash-advance"'));
console.log('OK: selección obligatoria; apertura del formulario existente; un único advance_deposit con DNI, importe y medio correctos; sin escritura al buscar/cancelar; errores, cero resultados y respuestas tardías controlados; botones integrados.');
