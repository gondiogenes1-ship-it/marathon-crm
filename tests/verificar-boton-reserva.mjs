class TestDate extends Date {constructor(...args){super(...(args.length?args:['2026-11-01T15:00:00Z']));}}
import {fileURLToPath} from 'node:url';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const file=fileURLToPath(new URL('../public/agenda-recurrente.js',import.meta.url));
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.dataset={};this.attrs={};this.className='';this.value='';this.hidden=false;this.handlers={};this.parentElement={hidden:false};this.classList={add:(s)=>this.className+=' '+s};}
 append(...items){this.children.push(...items);}
 before(){}
 replaceChildren(...items){this.children=items;}
 setAttribute(k,v){this.attrs[k]=v;}
 addEventListener(k,fn){this.handlers[k]=fn;}
 querySelectorAll(tag){return this.children.flatMap(c=>[...(c.tagName===tag?[c]:[]),...c.querySelectorAll(tag)]);}
}
const nodes=new Map();const get=s=>{if(!nodes.has(s))nodes.set(s,new Element('div'));return nodes.get(s);};
get('#agenda-date').value='2026-11-02';get('#agenda-sede').value='Centro';get('#agenda-prof').value='prof-1';
const source=(await fs.readFile(file,'utf8')).replace(/^import .*;\r?\n/gm,'').replace('export function createRecurringAgenda','function createRecurringAgenda');
const sandbox={document:{querySelector:get,createElement:t=>new Element(t)},DailyUI:{money:x=>String(x)},Intl,Date:TestDate,console};
vm.createContext(sandbox);vm.runInContext(source+'\nthis.factory=createRecurringAgenda;',sandbox);
let selected=null,busy=false,slots=[];
const agenda=sandbox.factory({getApi:()=>({rpc:async()=>({slots,plans:[]})}),getOptions:()=>({therapies:[],professionals:[]}),isBusy:()=>busy,work:fn=>fn(),bookAt:data=>{selected=data;}});
const slot=(fecha,remaining=15,blocked=false)=>({fecha,hora:'12:00',therapy:'kine',meta:{remaining,capacity:15,blocked,shared_space_count:0},patients:[]});
const buttons=()=>get('#agenda-list').unused;
// El panel es insertado junto a la lista mediante before().
let panel;
get('#agenda-list').before=p=>{panel=p;};
// Recrear para capturar el panel renderizado.
const tested=sandbox.factory({getApi:()=>({rpc:async()=>({slots,plans:[]})}),getOptions:()=>({therapies:[],professionals:[]}),isBusy:()=>busy,work:fn=>fn(),bookAt:data=>{selected=data;}});
slots=[slot('2026-11-02')];await tested.refresh(true);
let reserve=panel.querySelectorAll('button').find(b=>b.className.includes('recurring-add'));
assert.equal(reserve.textContent,'Reservar turno');assert.equal(reserve.disabled,false);
await reserve.handlers.click();assert.equal(selected.date,'2026-11-02');assert.equal(selected.hora,'12:00');assert.equal(selected.sede,'Centro');assert.equal(selected.prof,'prof-1');assert.equal(selected.therapy,'kine');
selected=null;busy=true;await reserve.handlers.click();assert.equal(selected,null);busy=false;
get('#agenda-date').value='2026-10-26';slots=[slot('2026-10-26')];await tested.refresh(true);
reserve=panel.querySelectorAll('button').find(b=>b.className.includes('recurring-add'));assert.equal(reserve.disabled,true);await reserve.handlers.click();assert.equal(selected,null);
get('#agenda-date').value='2026-11-02';slots=[slot('2026-11-02',0),slot('2026-11-03',15,true)];await tested.refresh(true);
assert.equal(panel.querySelectorAll('button').filter(b=>b.className.includes('recurring-add')).length,0);
console.log('OK: botón visible, reserva con fecha/hora/sede/profesional/terapia, bloqueo mientras está ocupado, fecha pasada deshabilitada y sin reserva para cupos completos o bloqueados.');
