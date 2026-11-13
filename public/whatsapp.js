import {createWhatsAppTemplates} from './whatsapp-templates.js?v=20261029-0131-vinculos';
const META_ORIGINS=new Set(['https://www.facebook.com','https://web.facebook.com','https://business.facebook.com']);
export function createWhatsApp(ctx){
 const $=s=>document.querySelector(s),el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
 const nav=el('button');nav.type='button';nav.id='nav-whatsapp';nav.hidden=true;
 const icon=document.createElementNS('http://www.w3.org/2000/svg','svg');icon.setAttribute('class','nav-icon');icon.setAttribute('viewBox','0 0 24 24');icon.setAttribute('fill','none');icon.setAttribute('stroke','currentColor');icon.setAttribute('stroke-width','1.7');icon.setAttribute('stroke-linecap','round');icon.setAttribute('stroke-linejoin','round');icon.setAttribute('aria-hidden','true');icon.setAttribute('focusable','false');
 for(const d of ['M21 11.5a9 9 0 0 1-13.4 7.9L3 21l1.6-4.6A9 9 0 1 1 21 11.5Z','M8.2 6.9c-.4 0-1.2.9-1.2 2.1 0 2.8 4.1 6.9 6.9 6.9 1.2 0 2.1-.8 2.1-1.2v-1l-2.4-1.1-1 1c-1.5-.7-2.5-1.7-3.2-3.2l1-1L9.3 7Z']){const path=document.createElementNS(icon.namespaceURI,'path');path.setAttribute('d',d);icon.append(path);}
 nav.append(icon,el('span','WhatsApp'));$('#nav-masters').before(nav);
 const dialog=el('dialog');dialog.id='whatsapp-dialog';dialog.setAttribute('aria-labelledby','whatsapp-title');$('#workspace').append(dialog);
 const messages=createWhatsAppTemplates(ctx);let activeTab='messages';
 let config=null,pendingConfig=null,pendingFinish=null,attempt=null,sdkReady=false,sdkApp=null,sdkPromise=null,run=0,timer=null,code=null,session=null;
 const rpc=(name,args={},write=false)=>ctx.getApi().rpc(name,args,write),isPending=()=>!!pendingConfig||!!pendingFinish||messages.isPending();
 const endpoint=()=>new URL('/functions/v1/marathon-whatsapp-webhook',ctx.getApi().url).href;
 const status=(text,error=false)=>{const p=$('#wa-message');if(p){p.textContent=text;p.dataset.error=String(error);p.setAttribute('role',error?'alert':'status');}};
 function cancelFlow(){++run;clearTimeout(timer);window.removeEventListener('message',receive);code=null;session=null;}
 function sync(){nav.hidden=!ctx.getUser()||ctx.getUser()?.role==='SECRETARIA_ORTOPEDIA';const locked=ctx.isBusy()||isPending();dialog.querySelectorAll('input,button').forEach(e=>e.disabled=locked);if($('#wa-connect'))$('#wa-connect').disabled=locked||!config?.ready||!sdkReady||!attempt||location.protocol!=='https:';if($('#wa-save'))$('#wa-save').disabled=locked||config?.connected;for(const id of ['wa-verify-save','wa-verify-link'])if($('#'+id))$('#'+id).disabled=ctx.isBusy();messages.sync();}
 nav.onclick=()=>ctx.work(open);dialog.addEventListener('cancel',e=>{if(ctx.isBusy()||isPending())e.preventDefault();});dialog.addEventListener('close',()=>{cancelFlow();attempt=null;sdkReady=false;activeTab='messages';messages.reset();dialog.replaceChildren();});
 function action(text,fn,cls='s'){const b=el('button',text,cls);b.type='button';b.onclick=fn;return b;}
 function input(parent,label,id,value='',type='text'){const l=el('label',label),i=el('input');i.id=id;i.name=id;i.type=type;i.value=value;l.append(i);parent.append(l);return i;}
 async function open(){if(!ctx.getUser())throw Error('Volvé a ingresar.');await load();if(!dialog.open)dialog.showModal();}
 async function prepareConnection(){if(config?.ready&&location.protocol==='https:'){try{await loadSdk();attempt=(await rpc('marathon_whatsapp_begin')).attempt_id;sdkReady=true;status('Preparado. Podés autorizar el número desde esta computadora.');}catch(e){status(e.message,true);}}sync();}
 async function load(){cancelFlow();attempt=null;sdkReady=false;config=ctx.getUser()?.role==='ADMIN'?await rpc('marathon_whatsapp_status'):null;
  if(!$('#wa-templates-panel')){render();await messages.load();}else renderConnection();if(activeTab==='connection')await prepareConnection();sync();
 }
 function showTab(which){activeTab=which;$('#wa-templates-panel').hidden=which!=='messages';$('#wa-connection-panel').hidden=which!=='connection';for(const [id,name]of [['wa-tab-messages','messages'],['wa-tab-connection','connection']])if($('#'+id)){$('#'+id).className=which===name?'b':'s';$('#'+id).setAttribute('aria-pressed',String(which===name));}}
 function render(){dialog.replaceChildren();const head=el('div',undefined,'detail-head'),h=el('h2','WhatsApp Business');h.id='whatsapp-title';head.append(h,action('Cerrar',()=>{if(!ctx.isBusy()&&!isPending())dialog.close();}));dialog.append(head);const tabs=el('div',undefined,'form-actions');const msg=action('Mensajes automáticos',()=>showTab('messages'));msg.id='wa-tab-messages';tabs.append(msg);
  if(ctx.getUser()?.role==='ADMIN'){const setup=action('Vincular número',()=>{showTab('connection');if(!attempt)ctx.work(prepareConnection);});setup.id='wa-tab-connection';tabs.append(setup);}
  const panel=el('section');panel.id='wa-templates-panel';const connection=el('section');connection.id='wa-connection-panel';dialog.append(tabs,panel,connection);messages.mount(panel);renderConnection();showTab(activeTab);
 }
 function renderConnection(){const connection=$('#wa-connection-panel');if(!connection)return;connection.replaceChildren();if(!config)return;
  const state=el('p',config.connected?'Número autorizado: '+(config.phone_display||''):'Número pendiente de vinculación','pill');state.id='wa-state';connection.append(state);
  connection.append(el('p','Vinculá el WhatsApp Business de Marathon desde la computadora donde administrás la cuenta. La autorización se realiza en una ventana oficial de Meta y puede requerir confirmación en el celular.'));
  const steps=el('ol');for(const text of ['Preparar la cuenta de Meta y habilitar la conexión con WhatsApp Business.','Pulsar Vincular WhatsApp e ingresar con la cuenta que administra Marathon.','Elegir el número existente, revisar los permisos y confirmar en el celular.'])steps.append(el('li',text));connection.append(steps);
  const checks=el('ul',undefined,'wa-checks');for(const [label,ok]of [['Aplicación de Meta configurada',!!config.app_id&&!!config.config_id&&config.secret_set],['Modalidad para conservar WhatsApp Business habilitada',config.coexistence_enabled],['Recepción de eventos verificada por Meta',config.webhook_verified]])checks.append(el('li',(ok?'✓ ':'Pendiente · ')+label));connection.append(checks);
  const controls=el('div',undefined,'form-actions'),connect=action(config.connected?'Renovar autorización':'Vincular WhatsApp',launch,'b');connect.id='wa-connect';controls.append(connect,action('Revisar estado',()=>ctx.work(load)));connection.append(controls);
  if(!config.ready)connection.append(el('p','Falta la preparación inicial de Meta. La cuenta y sus permisos deben habilitarse una vez; después podrás autorizar el número desde esta ventana.','subtitle'));
  if(location.protocol!=='https:')connection.append(el('p','Para autorizar el número, abrí el CRM publicado en Vercel con dirección https. La versión local permite preparar la configuración.','subtitle'));
  if(config.connected)connection.append(el('p','La autorización del número quedó registrada. Este asistente prepara la conexión; la bandeja de chat y el envío dentro del CRM requieren su propia habilitación.','subtitle'));
  const message=el('p');message.id='wa-message';message.setAttribute('role','status');connection.append(message);
  const advanced=el('details',undefined,'wa-advanced');advanced.append(el('summary','Preparación inicial de Meta'));advanced.append(el('p','Para la persona que configura la integración. Se necesita una aplicación con registro insertado v4, permisos aprobados y modalidad de coexistencia habilitada por Meta o por un proveedor autorizado.'));
  const form=el('form');form.id='whatsapp-config-form';const grid=el('div',undefined,'form-grid');const app=input(grid,'ID de aplicación de Meta','wa-app-id',config.app_id),cfg=input(grid,'ID de configuración del registro insertado','wa-config-id',config.config_id);for(const i of [app,cfg]){i.required=true;i.pattern='[0-9]{5,30}';i.maxLength=30;i.inputMode='numeric';}
  const secret=input(grid,config.secret_set?'Nueva clave secreta de Meta (dejar vacío para conservar)':'Clave secreta de la aplicación de Meta','wa-app-secret','','password');secret.autocomplete='new-password';secret.maxLength=32;secret.required=!config.secret_set;secret.pattern='[0-9a-fA-F]{32}';
  const confirm=el('label'),coexist=el('input');coexist.id='wa-coexistence';coexist.name='wa-coexistence';coexist.type='checkbox';coexist.checked=config.coexistence_enabled;confirm.append(coexist,document.createTextNode('La aplicación o el proveedor tiene habilitada la coexistencia de WhatsApp Business.'));grid.append(confirm);form.append(grid);
  const save=el('button','Guardar preparación','b');save.id='wa-save';save.type='submit';form.append(el('p','La clave se guarda cifrada en el servidor. No se incluye en el instalador ni en el ZIP para Vercel.','subtitle'),save);form.onsubmit=e=>{e.preventDefault();if(ctx.isBusy()||isPending()||!form.reportValidity())return;pendingConfig={p_data:{app_id:app.value.trim(),config_id:cfg.value.trim(),app_secret:secret.value.trim(),coexistence_enabled:coexist.checked},p_version:config.version,p_request_id:crypto.randomUUID()};saveConfig();};advanced.append(form);
  const urls=el('div',undefined,'wa-setup-addresses');urls.append(el('h3','Direcciones para configurar en Meta'));
  for(const [label,value]of [['Dominio autorizado y URI OAuth',location.origin+'/'],['URL de devolución de eventos',endpoint()],['Token de verificación',config.verify_token]]){const box=el('label',label),field=el('input');field.value=value;field.readOnly=true;field.type=label==='Token de verificación'?'password':'text';box.append(field,action('Copiar '+label,()=>navigator.clipboard.writeText(value).then(()=>status('Copiado.')).catch(()=>status('Seleccioná el campo para copiarlo.',true))));urls.append(box);}advanced.append(urls);
  const docs=el('a','Abrir guía oficial de Meta');docs.href='https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users';docs.target='_blank';docs.rel='noopener noreferrer';advanced.append(docs);connection.append(advanced);sync();
 }
 async function saveConfig(){if(ctx.isBusy()||!pendingConfig)return;ctx.setBusy(true);try{config=await rpc('marathon_whatsapp_configure',pendingConfig,true);pendingConfig=null;renderConnection();status('Preparación guardada. Completá la verificación de eventos en Meta y pulsá Revisar estado.');}catch(e){status(e.message,true);if(e.uncertain){if(!$('#wa-verify-save')){const retry=action('Verificar guardado',saveConfig);retry.id='wa-verify-save';$('#wa-message').after(retry);}}else pendingConfig=null;}finally{ctx.setBusy(false);sync();}}
 function loadSdk(){
  if(sdkPromise)return sdkPromise;sdkPromise=new Promise((resolve,reject)=>{const initialize=()=>{if(!window.FB){reject(Error('No se pudo cargar la conexión con Meta.'));return;}if(sdkApp!==config.app_id){window.FB.init({appId:config.app_id,version:config.graph_version,autoLogAppEvents:false,xfbml:false});sdkApp=config.app_id;}resolve();};if(window.FB){initialize();return;}
   const script=el('script');script.src='https://connect.facebook.net/es_LA/sdk.js';script.async=true;script.crossOrigin='anonymous';script.onload=initialize;script.onerror=()=>{script.remove();reject(Error('No se pudo cargar Meta. Revisá la conexión o el bloqueador de contenido.'));};document.head.append(script);
  }).finally(()=>sdkPromise=null);return sdkPromise;
 }
 function receive(event){if(!META_ORIGINS.has(event.origin)||!attempt)return;let data;try{data=typeof event.data==='string'?JSON.parse(event.data):event.data;}catch{return;}if(data?.type!=='WA_EMBEDDED_SIGNUP')return;
  if(data.event==='FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING'){session=data.data;maybeFinish();}
  else if(data.event==='CANCEL'||data.event==='ERROR'){cancelFlow();status('La autorización no se completó. Pulsá Revisar estado antes de volver a iniciar.',true);}
 }
 function launch(){
  if(ctx.isBusy()||isPending()||!sdkReady||!attempt||!config.ready||location.protocol!=='https:')return;cancelFlow();const current=run;window.addEventListener('message',receive);status('Completá la autorización en la ventana de Meta.');
  timer=setTimeout(()=>{if(current===run){cancelFlow();status('No llegó una autorización completa. Revisá el estado y volvé a iniciar.',true);}},5*60*1000);
  window.FB.login(response=>{if(current!==run)return;if(!response.authResponse?.code){cancelFlow();status('No se autorizó la conexión. Podés volver a intentarlo.',true);return;}code=response.authResponse.code;clearTimeout(timer);timer=setTimeout(()=>{if(current===run&&!pendingFinish){cancelFlow();status('Meta no devolvió la información del número a tiempo. Revisá los dominios y volvé a iniciar.',true);}},5000);maybeFinish();},{config_id:config.config_id,response_type:'code',override_default_response_type:true,extras:{setup:{},featureType:'whatsapp_business_app_onboarding',sessionInfoVersion:'3',version:'v4'}});
 }
 function maybeFinish(){if(!code||!session?.waba_id||pendingFinish)return;pendingFinish={action:'finish',attempt_id:attempt,code,waba_id:session.waba_id,...(session.phone_number_id?{phone_id:session.phone_number_id}:{})};cancelFlow();sendFinish();}
 async function sendFinish(){
  if(ctx.isBusy()||!pendingFinish)return;ctx.setBusy(true);try{const result=await ctx.getApi().whatsapp(pendingFinish);pendingFinish=null;
   if(result.status==='linked'){attempt=null;config=await rpc('marathon_whatsapp_status');renderConnection();status('Número autorizado y conexión verificada.');}
   else if(result.status==='choose_phone'){status('Elegí el número que querés vincular.');const box=el('div',undefined,'form-actions');for(const p of result.phones){box.append(action(p.display_phone_number||p.id,()=>{pendingFinish={action:'select',attempt_id:attempt,phone_id:p.id};box.remove();sendFinish();}));}$('#wa-message').after(box);}
   else status('No se confirmó el resultado. Revisá el estado.',true);
  }catch(e){status(e.message,true);if(e.uncertain){if(!$('#wa-verify-link')){const retry=action('Verificar vinculación',sendFinish);retry.id='wa-verify-link';$('#wa-message').after(retry);}}else pendingFinish=null;}finally{if(!pendingFinish)$('#wa-verify-link')?.remove();ctx.setBusy(false);sync();}
 }
 return{sync,isPending,reset(){cancelFlow();messages.reset();activeTab='messages';config=null;pendingConfig=null;pendingFinish=null;attempt=null;sdkReady=false;if(dialog.open)dialog.close();dialog.replaceChildren();nav.hidden=true;}};
}

