import {fileURLToPath} from 'node:url';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../public/',import.meta.url));
class E{
 constructor(tag){this.tagName=tag;this.children=[];this.dataset={};this.listeners={};this.attrs={};this.isConnected=true;this.value='';}
 append(...items){items.forEach(i=>{i.isConnected=true;this.children.push(i);});}
 replaceChildren(...items){const detach=e=>{e.isConnected=false;e.children.forEach(detach);};this.children.forEach(detach);this.children=[];this.append(...items);}
 setAttribute(k,v){this.attrs[k]=v;}
 addEventListener(k,f){this.listeners[k]=f;}
 querySelectorAll(s){return walk(this).filter(e=>s===e.tagName);}
 reportValidity(){return true;}
 close(){this.open=false;}
}
const walk=n=>n.children.flatMap(c=>[c,...walk(c)]),nodes=new Map();
function get(s){for(const root of nodes.values()){const found=[root,...walk(root)].find(e=>'#'+e.id===s);if(found)return found;}if(!nodes.has(s))nodes.set(s,new E('div'));return nodes.get(s);}
let editorContext,editorPending=false,opened=[],resetCalled=false,busy=false,job=Promise.resolve(),rows=[{dni:'99000001',nombre:'Paciente',apellido:'Prueba'}],readCalls=[],fail=false,defer=null;
const ctx={getApi:()=>({rpc:async(n,a,w)=>{assert(!w,'El selector no debe registrar una venta ni guardar fichas por su cuenta');readCalls.push({n,a});if(n==='marathon_patient_get')return {dni:a.p_dni,nombre:'Paciente',apellido:'Guardado'};if(fail)throw Error('Fallo simulado');if(defer)return defer;return {rows,next:null};}}),isBusy:()=>busy,work:fn=>{if(busy)return;busy=true;job=Promise.resolve().then(fn).finally(()=>busy=false);return job;},getUser:()=>({role:'ADMIN'}),sync(){},message(){},setBusy:v=>busy=v};
const code=(await fs.readFile(root+'ortho.js','utf8')).replace(/^import .*;\r?\n/gm,'').replace('export function createOrtho','function createOrtho').replace('return{open,openReverse,sync,','return{testPicker:patientPicker,open,openReverse,sync,');
const sandbox={document:{querySelector:get,createElement:t=>new E(t)},DailyUI:{},Intl,Date,createAgendaPatientEditor:c=>{editorContext=c;return {open:async dni=>{opened.push(dni||null);},sync(){},isPending:()=>editorPending,reset:()=>{resetCalled=true;editorPending=false;}};}};
vm.createContext(sandbox);vm.runInContext(code+'\nthis.factory=createOrtho;',sandbox);
const ortho=sandbox.factory(ctx),panel=get('#ortho-body'),dialog=get('#ortho-dialog');dialog.open=true;
let readPatient=ortho.testPicker(panel);assert.equal(editorContext.prefix,'ortho-patient-edit');assert(get('#ortho-patient-edit').disabled);
get('#ortho-patient-create').listeners.click();await job;assert.equal(opened.at(-1),null);
const qty=new E('input');qty.id='r-cantidad';qty.value='3';panel.append(qty);
await editorContext.onSaved('99000002');assert.equal(readPatient().dni,'99000002');assert.equal(qty.value,'3');ortho.sync();assert.equal(get('#ortho-patient-edit').disabled,false);
get('#ortho-patient-edit').listeners.click();await job;assert.equal(opened.at(-1),'99000002');
const submit=async term=>{get('#r-patient-query').value=term;get('#ortho-patient-search').listeners.submit({preventDefault(){}});await job;};
get('#r-patient-query').listeners.input();assert.equal(readPatient(),null);ortho.sync();assert(get('#ortho-patient-edit').disabled);
await submit('Prueba');get('#ortho-patient-results').children[0].listeners.click();assert.equal(readPatient().dni,'99000001');
editorPending=true;assert(ortho.isPending());ortho.sync();assert(get('#ortho-patient-edit').disabled);const count=opened.length;get('#ortho-patient-create').listeners.click();assert.equal(opened.length,count);editorPending=false;
rows=[];await submit('no existe');assert.equal(get('#ortho-patient-results').children.length,0);assert.equal(readPatient(),null);assert(walk(panel).some(e=>e.textContent?.includes('nueva ficha')));
fail=true;await submit('error');assert(walk(panel).some(e=>e.textContent?.includes('No se pudo buscar')));fail=false;
let resolve;defer=new Promise(r=>resolve=r);get('#r-patient-query').value='lenta';get('#ortho-patient-search').listeners.submit({preventDefault(){}});await Promise.resolve();const oldResults=get('#ortho-patient-results');panel.replaceChildren();resolve({rows:[{dni:'999',nombre:'Tardío'}]});await job;assert.equal(oldResults.children.length,0);
const reads=readCalls.length;await editorContext.onSaved('123');assert.equal(readCalls.length,reads,'Una ficha guardada fuera del formulario no debe seleccionarse');
ortho.reset();assert(resetCalled);assert(!ortho.isPending());
console.log('OK: reutiliza editor de Reservar turno, crea y edita el DNI seleccionado, mantiene cantidad, exige selección vigente, bloquea durante guardados, controla búsquedas vacías/sin resultados/errores y descarta respuestas de formularios cerrados. Sin movimientos de stock ni caja.');
