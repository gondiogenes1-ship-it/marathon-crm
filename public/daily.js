// Construcción segura de tablas operativas: los datos se insertan como texto.
export const DailyUI={
 table(parent,headers){const wrap=document.createElement('div');wrap.className='daily-table-wrap';wrap.tabIndex=0;const table=document.createElement('table');table.className='daily-table';const head=document.createElement('thead'),tr=document.createElement('tr');for(const text of headers){const th=document.createElement('th');th.scope='col';th.textContent=text;tr.append(th);}head.append(tr);const body=document.createElement('tbody');body.headers=headers;table.append(head,body);wrap.append(table);parent.append(wrap);return body;},
 row(body,values,data={}){const tr=document.createElement('tr');tr.className='turn-card';Object.assign(tr.dataset,data);values.forEach((value,i)=>{const td=document.createElement('td');if(body.headers?.[i])td.dataset.label=body.headers[i];if(value instanceof Node)td.append(value);else td.textContent=value??'—';tr.append(td);});body.append(tr);return tr;},
 options(input,rows,empty){const old=input.value;input.replaceChildren();for(const r of [{id:'',label:empty},...rows]){const o=document.createElement('option');o.value=r.id;o.textContent=r.label;input.append(o);}input.value=old;},
 dateAdd(date,n){const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);},
 week(date){const day=new Date(date+'T12:00:00Z').getUTCDay();const from=this.dateAdd(date,-((day+6)%7));return{from,to:this.dateAdd(from,6)};},
 period(from,to){return from===to?from:from+' al '+to;},
 money(n){return new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS'}).format(Number(n)||0);},
 today(){return new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());},
 dayLabel(date){const t=new Intl.DateTimeFormat('es-AR',{weekday:'long',day:'numeric',month:'long',timeZone:'UTC'}).format(new Date(date+'T12:00:00Z'));return t.charAt(0).toUpperCase()+t.slice(1);},
 // Resumen de una lista de turnos: cuenta por estado y suma el saldo exigible de las filas recibidas.
 summarize(rows){const s={total:rows.length,PENDIENTE:0,PRESENTE:0,AUSENTE:0,CANCELADO:0,debt:0};for(const r of rows){if(s[r.estado]!==undefined)s[r.estado]++;s.debt+=Number(r.debt)||0;}return s;},
 // Preferencias de trabajo (no clínicas): solo claves permitidas y valores de catálogo, por usuario. Nunca se guardan pacientes, DNI, importes ni sesiones.
 prefs:{
  keys:['homeSite','homeProf','agendaSede','agendaProf','agendaTherapy','agendaView','waitView','cashSede'],
  ok(key,value){return this.keys.includes(key)&&typeof value==='string'&&value.length<=80&&!/[\u0000-\u001f<>]/.test(value)&&(key!=='agendaView'&&key!=='waitView'||['day','week','list','kanban'].includes(value)||value==='');},
  name(uid){return uid?'marathon.prefs.v1.'+String(uid).replace(/[^0-9a-zA-Z-]/g,'').slice(0,64):null;},
  load(uid){const n=this.name(uid);if(!n)return{};try{const raw=JSON.parse(globalThis.localStorage.getItem(n)||'{}'),out={};for(const k of this.keys)if(this.ok(k,raw[k]))out[k]=raw[k];return out;}catch{return{};}},
  save(uid,patch){const n=this.name(uid);if(!n)return;try{const next={...this.load(uid)};for(const [k,v] of Object.entries(patch))if(this.ok(k,v))next[k]=v;globalThis.localStorage.setItem(n,JSON.stringify(next));}catch{}}
 }
};
