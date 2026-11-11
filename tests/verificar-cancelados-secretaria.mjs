import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=await fs.readFile(new URL('../public/agenda.js',import.meta.url),'utf8');
const summary=source.slice(source.indexOf(' function summaryStrip('),source.indexOf(' const canChangeCoverage'));
const render=source.slice(source.indexOf(' function renderRows('),source.indexOf('  const blockKey=t=>'))+' }';
class E{constructor(tag){this.tag=tag;this.children=[];this.dataset={};}append(...c){this.children.push(...c);}setAttribute(){}addEventListener(){}replaceChildren(){this.children=[];}}
for(const role of ['SECRETARIA','ADMIN']){
 let summarized=[],selected=[];
 const context={ctx:{getUser:()=>({role})},document:{createTextNode:t=>({text:t})},el:(t,s,c)=>Object.assign(new E(t),{text:s,className:c}),DailyUI:{summarize:rows=>{summarized=rows;return {total:rows.length,PENDIENTE:1,PRESENTE:0,AUSENTE:0,CANCELADO:rows.length-1,debt:0};},money:String,table:()=>({closest:()=>({classList:{add(){}}})})},bulkControls:(panel,rows)=>{selected=rows;},locked:()=>false};
 vm.createContext(context);vm.runInContext(summary+render+';this.render=renderRows;this.summary=summaryStrip',context);
 const rows=[{id:'pending',estado:'PENDIENTE'},{id:'cancelled',estado:'CANCELADO'}];
 const panel=new E('div');context.render(panel,rows);
 assert.equal(summarized.length,role==='ADMIN'?2:1);assert.equal(selected.length,role==='ADMIN'?2:1);assert.equal(rows.length,2);
 const scope={summary:{total:2,PENDIENTE:1,PRESENTE:0,AUSENTE:0,CANCELADO:1,debt:0},state:'',onState(){}};
 const chips=context.summary(rows,false,scope).children;
 assert.equal(chips.some(c=>c.dataset?.turnState==='CANCELADO'),role==='ADMIN');
 assert(chips.some(c=>c.dataset?.turnState==='PENDIENTE'));
}
console.log('OK: secretaría excluye cancelados de filas, selección y filtros; administración conserva acceso.');
