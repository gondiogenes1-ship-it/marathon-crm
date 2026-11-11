export const coverageTypes={PARTICULAR:'Particular',OBRA_SOCIAL:'Obra social',ART:'ART',CLUB:'Club'};
export function patientCoverages(p){
 return Array.isArray(p?.coberturas)?p.coberturas.map(c=>({obra_social_id:String(c.obra_social_id||''),afiliado:String(c.afiliado||'')})):p?.obra_social_id?[{obra_social_id:p.obra_social_id,afiliado:p.afiliado||''}]:[];
}
export function coverageLabel(c){return !c?.type?'Sin definir':c.type==='OBRA_SOCIAL'?c.name||'Obra social':(coverageTypes[c.type]||'Sin definir')+(c.name?' · '+c.name:'');}
const el=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
// Teléfono argentino: mismas reglas que PatientPhone de la referencia 27/10.
export function patientPhoneNumber(raw){
 const text=String(raw??'').trim();if(/[^\d\s()+.\-]/.test(text))return '';
 let d=text.replace(/\D/g,'').replace(/^00/,'');if(d.length>=12&&d.startsWith('54'))d=d.slice(2).replace(/^9/,'');d=d.replace(/^0+/,'');
 if(d.length===12){const areas=[2,3,4].filter(a=>d.slice(a,a+2)==='15');if(areas.length!==1)return '';const a=areas[0];d=d.slice(0,a)+d.slice(a+2);}
 return /^[1-9]\d{9}$/.test(d)?'549'+d:'';
}
export function patientPhoneParts(raw){const text=String(raw??'').trim(),m=text.match(/^\+54 9 (\d{2,4}) (\d{6,8})$/);return m&&m[1].length+m[2].length===10?{area:m[1],local:m[2],legacy:false}:{area:'',local:text,legacy:!!text};}
export function patientPhoneSave(areaRaw,localRaw,old=''){
 const areaText=String(areaRaw??'').trim(),localText=String(localRaw??'').trim();
 if(!areaText&&!localText)return '';if(!areaText&&localText===String(old??'').trim())return localText;
 if(!areaText||!localText)throw Error('Completá la característica de ciudad y el número, o dejá ambos vacíos.');
 if(/[^\d\s()+.\-]/.test(areaText+localText))throw Error('El teléfono solo admite números, espacios, paréntesis y guiones.');
 const area=areaText.replace(/\D/g,'').replace(/^0+/,'');let local=localText.replace(/\D/g,'');if(local.length+area.length===12&&local.startsWith('15'))local=local.slice(2);
 if(!/^[1-9]\d{1,3}$/.test(area)||!/^\d{6,8}$/.test(local)||area.length+local.length!==10)throw Error('La característica y el número deben sumar 10 dígitos, sin 0 ni 15.');
 return '+54 9 '+area+' '+local;
}
export function appendPatientPhone(parent,patient=null,prefix='patient'){
 const section=el('section');section.className='wide form-grid';section.dataset.patientPhone='';section.dataset.phoneOriginal=String(patient?.telefono??'');
 const parts=patientPhoneParts(patient?.telefono);const area=input(section,'Característica de ciudad',prefix+'-phone-area',parts.area,20);area.name='telefono_area';area.inputMode='numeric';area.placeholder='Ej.: 11 o 2474';
 const local=input(section,'Número de teléfono',prefix+'-phone-local',parts.local,10000);local.name='telefono_local';local.type='tel';local.placeholder='Sin característica';
 const hint=el('p');hint.className='wide subtitle';hint.setAttribute('role','status');section.append(hint);
 function update(){try{const value=patientPhoneSave(area.value,local.value,section.dataset.phoneOriginal);hint.textContent=parts.legacy&&!area.value&&local.value.trim()===parts.local?'Teléfono anterior conservado. Para corregirlo, completá la característica y el número.':value?'Se guardará: '+value:'Opcional. La característica y el número deben sumar 10 dígitos.';}catch(e){hint.textContent=e.message;}}
 area.addEventListener('input',update);local.addEventListener('input',update);update();parent.append(section);return section;
}
const btn=(text,fn)=>{const b=el('button',text);b.type='button';b.className='s';b.addEventListener('click',fn);return b;};
function select(parent,label,name,rows,value=''){
 const box=el('label',label),s=el('select');s.name=name;s.id=name;
 for(const row of rows){const o=el('option',row.label);o.value=row.id;s.append(o);}s.value=value;box.append(s);parent.append(box);return s;
}
function input(parent,label,name,value='',max=120){const box=el('label',label),i=el('input');i.type='text';i.name=name;i.id=name;i.value=value;i.maxLength=max;box.append(i);parent.append(box);return i;}
export function appendPatientCoverages(parent,catalog,patient=null,prefix='patient'){
 const section=el('section');section.className='patient-coverages wide';section.dataset.patientCoverages='';
 section.append(el('h3','Obras sociales del paciente'),el('p','Cada obra social conserva su número de afiliado. Particular, ART y Club se eligen al reservar.'));
 const rows=el('div');section.append(rows);let serial=0;
 const add=btn('Agregar otra obra social',()=>addRow());
 function addRow(c={}){
  if(rows.children.length>=20)return;
  const row=el('div');row.className='coverage-row';row.dataset.coverageRow='';const id=prefix+'-coverage-'+serial++;
  const options=catalog.filter(o=>o.status==='ACTIVO'||o.id===c.obra_social_id).map(o=>({id:o.id,label:o.name+(o.status==='INACTIVO'?' (inactiva)':'')}));
  if(c.obra_social_id&&!options.some(o=>o.id===c.obra_social_id))options.push({id:c.obra_social_id,label:c.obra_social_id+' (no disponible)'});
  const os=select(row,'Obra social',id+'-os',[{id:'',label:'Sin obra social'},...options],c.obra_social_id||'');os.dataset.coverageOs='';
  const affiliate=input(row,'N.º afiliado',id+'-afiliado',c.afiliado||'',500);affiliate.dataset.coverageAffiliate='';
  row.append(btn('Quitar obra social',()=>{row.remove();add.disabled=false;rows.dispatchEvent(new Event('change',{bubbles:true}));}));
  rows.append(row);add.disabled=rows.children.length>=20;rows.dispatchEvent(new Event('change',{bubbles:true}));
 }
 const existing=patientCoverages(patient);for(const c of existing.length?existing:[{}])addRow(c);
 section.append(add);parent.append(section);return section;
}
export function patientPayload(form){
 const data=Object.fromEntries(new FormData(form)),ids=new Set();
 const phone=form.querySelector('[data-patient-phone]');if(phone)data.telefono=patientPhoneSave(data.telefono_area,data.telefono_local,phone.dataset.phoneOriginal);
 for(const key of Object.keys(data))if(key.includes('-coverage-'))delete data[key];
 data.coberturas=[...form.querySelectorAll('[data-coverage-row]')].flatMap(row=>{
  const obra_social_id=row.querySelector('[data-coverage-os]').value.trim(),afiliado=row.querySelector('[data-coverage-affiliate]').value.trim();
  if(!obra_social_id){if(afiliado)throw Error('Elegí la obra social del número de afiliado.');return[];}
  if(ids.has(obra_social_id))throw Error('La misma obra social está repetida.');ids.add(obra_social_id);return[{obra_social_id,afiliado}];
 });
 if(data.coberturas.length>20)throw Error('Se admiten hasta 20 obras sociales.');
 data.obra_social_id=data.coberturas[0]?.obra_social_id||'';data.afiliado=data.coberturas[0]?.afiliado||'';return data;
}
export function createTurnCoverage(parent,patient,catalog,initial=null,prefix='booking'){
 const group=el('section');group.className='turn-coverage form-grid';
 const kind=select(group,'Modalidad de atención',prefix+'-coverage-type',[{id:'',label:'Elegir modalidad'},...Object.entries(coverageTypes).map(([id,label])=>({id,label}))],initial?.type||'');kind.required=true;
 const owned=patientCoverages(patient),active=owned.flatMap(c=>{const os=catalog.find(o=>o.id===c.obra_social_id&&o.status==='ACTIVO');return os?[{id:c.obra_social_id,label:os.name+(c.afiliado?' · '+c.afiliado:'')}]:[];});
 const os=select(group,'Obra social del paciente',prefix+'-coverage-os',[{id:'',label:'Elegir obra social'},...active],initial?.obra_social_id||'');
 const affiliate=input(group,'N.º afiliado de la ficha',prefix+'-coverage-affiliate');affiliate.readOnly=true;
 const name=input(group,'ART / club (opcional)',prefix+'-coverage-name',initial?.type==='ART'||initial?.type==='CLUB'?initial.name||'':'');
 const reference=input(group,'N.º de referencia (opcional)',prefix+'-coverage-reference',initial?.type==='ART'||initial?.type==='CLUB'?initial.affiliate||'':'');
 function sync(){
  const insurance=kind.value==='OBRA_SOCIAL',entity=['ART','CLUB'].includes(kind.value);
  os.parentElement.hidden=affiliate.parentElement.hidden=!insurance;os.required=insurance;
  name.parentElement.hidden=reference.parentElement.hidden=!entity;
  affiliate.value=owned.find(c=>c.obra_social_id===os.value)?.afiliado||'';
 }
 kind.addEventListener('change',sync);os.addEventListener('change',sync);sync();parent.append(group);
 return{read(){
  if(!Object.hasOwn(coverageTypes,kind.value))throw Error('Elegí obra social, Particular, ART o Club.');
  if(kind.value==='OBRA_SOCIAL'){
   if(!active.some(c=>c.id===os.value))throw Error('Elegí una obra social activa de la ficha del paciente.');
   return{type:kind.value,obra_social_id:os.value,name:catalog.find(c=>c.id===os.value).name,affiliate:affiliate.value};
  }
  return{type:kind.value,name:kind.value==='PARTICULAR'?'':name.value.trim(),affiliate:kind.value==='PARTICULAR'?'':reference.value.trim()};
 }};
}
