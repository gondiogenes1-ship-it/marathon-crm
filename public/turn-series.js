const node=(tag,text)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;return n;};
export function createTurnSeriesUI(ctx){
 let dialog=null,current=null,pending=null,generation=0;
 const rpc=(name,args,write=false)=>ctx.getApi().rpc(name,args,write);
 const button=(label,fn,variant='secondary')=>{const b=node('button',label);b.type='button';b.className=variant==='destructive'?'s':'b';b.dataset.variant=variant;b.addEventListener('click',fn);return b;};
 function field(parent,label,type,value){const l=node('label',label),i=node(type==='select'?'select':type==='textarea'?'textarea':'input');if(!['select','textarea'].includes(type))i.type=type;i.value=value||'';l.append(i);parent.append(l);return i;}
 function choices(select,rows,value){select.replaceChildren();for(const r of rows){const o=node('option',r.label);o.value=r.id;select.append(o);}select.value=value;}
 function sync(){if(!current)return;const disabled=ctx.isBusy()||!!pending;current.form.querySelectorAll('input,select,textarea,button').forEach(n=>n.disabled=disabled);current.following.disabled=disabled||!current.info.can_following;current.confirm.disabled=disabled||!current.reviewed;current.close.disabled=disabled;if(current.retry)current.retry.disabled=ctx.isBusy();}
 function reset(){++generation;current=null;pending=null;if(dialog?.open)dialog.close();}
 async function open(turn,kind){
  if(pending)return;const token=++generation;
  const [info,options]=await Promise.all([rpc('marathon_turn_series_context',{p_id:turn.id}),kind==='edit'?rpc('marathon_agenda_options',{}):Promise.resolve(null)]);
  if(token!==generation)return;
  if(!dialog){dialog=node('dialog');dialog.id='turn-series-dialog';dialog.className='recurring-dialog';document.querySelector('#workspace').append(dialog);dialog.addEventListener('cancel',e=>{if(pending||ctx.isBusy())e.preventDefault();});}
  const t=info.target;dialog.replaceChildren();dialog.setAttribute('aria-labelledby','turn-series-title');
  const head=node('div');head.className='detail-head';const title=node('h2',kind==='edit'?'Editar turno':'Cancelar turno');title.id='turn-series-title';const close=button('Cerrar',()=>{if(!pending&&!ctx.isBusy())dialog.close();});head.append(title,close);dialog.append(head,node('p',(turn.paciente||'Paciente')+' · '+t.fecha+' · '+String(t.hora).slice(0,5)));
  const form=node('form'),fieldset=node('fieldset');fieldset.append(node('legend','¿Qué sesiones querés modificar?'));form.append(fieldset);
  const singleLabel=node('label'),single=node('input');single.type='radio';single.name='scope';single.value='single';single.checked=true;singleLabel.append(single,document.createTextNode('Solo este turno'));fieldset.append(singleLabel);
  const followingLabel=node('label'),following=node('input');following.type='radio';following.name='scope';following.value='following';followingLabel.append(following,document.createTextNode(kind==='edit'?'Este turno y las sesiones siguientes de la misma serie':'Este turno y todas las sesiones siguientes de la misma serie'));fieldset.append(followingLabel);
  const note=node('p');note.className='subtitle';form.append(note);const fields=node('div');fields.className='form-grid';form.append(fields);
  let date=null,time=null,site=null,prof=null;
  if(kind==='edit'){
   date=field(fields,'Nueva fecha','date',t.fecha);date.required=true;date.min=new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Argentina/Buenos_Aires',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
   time=field(fields,'Nueva hora','time',String(t.hora).slice(0,5));time.required=true;time.step=60;
   site=field(fields,'Sede','select');choices(site,options.sedes,t.sede);site.required=true;
   prof=field(fields,'Profesional','select');choices(prof,options.professionals.filter(p=>p.therapy_ids.includes(t.terapia_id)),t.profesional_id);prof.required=true;
   form.append(node('p','En la serie, el cambio de fecha desplaza los próximos días por la misma cantidad. El horario, la sede y el profesional elegidos se aplican al conjunto. Se conservan terapia, importes y coberturas.'));
  }
  const reason=field(form,'Motivo (opcional)','textarea','');reason.maxLength=1000;reason.addEventListener('input',()=>reason.setCustomValidity(reason.value.trim()&&reason.value.trim().length<3?'Escribí al menos tres caracteres o dejá el motivo vacío.':''));
  const review=node('section');review.setAttribute('aria-live','polite');const error=node('p');error.setAttribute('role','alert');const actions=node('div');actions.className='form-actions';
  const preview=button('Revisar cambio',()=>void check()),confirm=button(kind==='edit'?'Confirmar edición':'Confirmar cancelación',()=>void save(),kind==='cancel'?'destructive':'default');confirm.disabled=true;actions.append(preview,confirm);form.append(review,error,actions);dialog.append(form);
  const v={form,info,following,confirm,close,review,error,reviewed:null,retry:null,turn,kind};current=v;
  const proposal=()=>({id:t.id,action:kind,scope:following.checked?'following':'single',huella:info.huella,...(kind==='edit'?{date:date.value,time:time.value,site:site.value,prof:prof.value}:{}),reason:reason.value.trim()});
  const describe=()=>{note.textContent=following.checked?(info.plan?kind==='cancel'?'Se dará de baja esta asignación desde '+t.fecha+'. Se liberarán sus cupos y no se generarán más sesiones de esta serie. Las cuotas ya generadas y los movimientos de Caja se conservan.':'También se cambiará la regla de repetición futura de esta asignación. Se conservan las sesiones anteriores y las cancelaciones ya registradas.':'Se modificarán solo las sesiones de esta reserva desde '+t.fecha+'. No afecta otras series del paciente.'):'Las demás sesiones de la serie conservarán sus fechas y horarios.';if(!info.can_following)note.textContent+=' El cambio de serie se habilita en turnos pendientes de hoy en adelante que pertenezcan a una serie.';};
  function invalidate(){v.reviewed=null;review.replaceChildren();error.textContent='';describe();sync();}
  form.addEventListener('input',invalidate);form.addEventListener('change',invalidate);form.addEventListener('submit',e=>{e.preventDefault();void check();});
  async function check(){if(ctx.isBusy()||pending||!form.reportValidity())return;const data=proposal(),signature=JSON.stringify(data);ctx.setBusy(true);sync();error.textContent='';try{const result=await rpc('marathon_turn_series_preview',{p_data:data});if(current!==v||signature!==JSON.stringify(proposal()))return;review.replaceChildren(node('h3','Revisá antes de confirmar'),node('p',result.count+' turno(s) ya cargados.'),node('p',following.checked&&info.plan?'El alcance incluye también las sesiones futuras que se generan automáticamente.':''),node('p',kind==='edit'?date.value+' · '+time.value+' · '+site.selectedOptions[0].textContent+' · '+prof.selectedOptions[0].textContent:'La cancelación no entrega dinero al paciente. Si corresponde un reintegro o devolución, se gestiona desde su cuenta.'));v.reviewed=signature;}catch(e){v.reviewed=null;error.textContent=e.message;}finally{ctx.setBusy(false);sync();}}
  async function save(){if(ctx.isBusy()||pending||!form.reportValidity())return;const data=proposal();if(v.reviewed!==JSON.stringify(data))return;pending={p_request_id:crypto.randomUUID(),p_data:data};await send();}
  async function send(){if(!pending||ctx.isBusy())return;const request=pending;ctx.setBusy(true);sync();error.textContent='';try{const result=await rpc('marathon_turn_series_save',request,true);pending=null;dialog.close();await ctx.onChanged();ctx.message(result.message);}catch(e){if(e.uncertain){error.textContent=e.message;if(!v.retry){v.retry=button('Verificar guardado',()=>void send());actions.append(v.retry);}}else{pending=null;v.reviewed=null;error.textContent=e.message;}}finally{ctx.setBusy(false);sync();}}
  invalidate();dialog.showModal();
 }
 return{open,sync,reset,isPending:()=>!!pending};
}
