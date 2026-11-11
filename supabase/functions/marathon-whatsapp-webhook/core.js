const ORIGINS=new Set(['https://marathon-crm-liart.vercel.app','http://127.0.0.1:8123','http://localhost:8123']);
const ID=/^[0-9]{5,30}$/,UUID=/^[0-9a-f-]{36}$/i;
const reply=(data,status=200,headers={})=>Response.json(data,{status,headers:{'Cache-Control':'no-store',...headers}});
async function readBody(req,max=5*1024*1024){
 if(Number(req.headers.get('content-length'))>max)throw Error('too_large');const reader=req.body?.getReader();if(!reader)return'';let total=0;const parts=[];
 for(;;){const {value,done}=await reader.read();if(done)break;total+=value.byteLength;if(total>max){await reader.cancel();throw Error('too_large');}parts.push(value);}
 const all=new Uint8Array(total);let at=0;for(const p of parts){all.set(p,at);at+=p.byteLength;}return new TextDecoder().decode(all);
}
function clients(env,fetcher){
 const base=env('SUPABASE_URL'),key=env('SUPABASE_SERVICE_ROLE_KEY');
 async function rpc(name,args,token=key){const r=await fetcher(base+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(15000)});const d=await r.json();if(!r.ok){const e=Error('database');e.code=d.code;throw e;}return d;}
 return{rpc,worker:(action,data={})=>rpc('marathon_wa_worker',{p_action:action,p_data:data}),async admin(req){const token=req.headers.get('Authorization')?.match(/^Bearer (.+)$/i)?.[1];if(!token)throw Error('unauthorized');const r=await fetcher(base+'/auth/v1/user',{headers:{apikey:key,Authorization:'Bearer '+token},signal:AbortSignal.timeout(15000)});if(!r.ok)throw Error('unauthorized');const u=await r.json(),s=await rpc('marathon_session',{},token);if(!u.id||s.role!=='ADMIN')throw Error('unauthorized');return u.id;}};
}
export function createOnboardingHandler({env,fetcher=fetch}){
 const client=clients(env,fetcher);
 return async req=>{
  const origin=req.headers.get('Origin'),cors={'Access-Control-Allow-Origin':origin||'','Vary':'Origin','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
  if(origin&&!ORIGINS.has(origin))return reply({message:'Origen no habilitado.'},403);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});if(req.method!=='POST')return reply({message:'Método no permitido.'},405,cors);
  let ids=null;
  try{
   const uid=await client.admin(req);const body=JSON.parse(await readBody(req,16384));if(!UUID.test(body.attempt_id||''))return reply({message:'Volvé a iniciar la vinculación.'},400,cors);
   ids={attempt_id:body.attempt_id,user_id:uid};const cfg=await client.worker('config');if(!cfg.app_secret||!cfg.webhook_verified)return reply({message:'Falta completar la preparación de Meta.'},409,cors);
   async function graph(part,{token,params={},data}={}){
    const url=new URL('https://graph.facebook.com/'+cfg.graph_version+'/'+part);for(const[k,v]of Object.entries(params))url.searchParams.set(k,v);
    const r=await fetcher(url.href,{method:data?'POST':'GET',headers:{...(token?{Authorization:'Bearer '+token}:{}),...(data?{'Content-Type':'application/json'}:{})},...(data?{body:JSON.stringify(data)}:{}),signal:AbortSignal.timeout(15000)});const d=await r.json();if(!r.ok||d.error){const e=Error('meta');e.metaCode=Number(d.error?.code)||0;throw e;}return d;
   }
   let phoneId=body.phone_id;
   if(body.action==='finish'){
    if(typeof body.code!=='string'||!body.code||body.code.length>4096||!ID.test(body.waba_id||''))return reply({message:'Meta no devolvió una autorización completa. Volvé a iniciar.'},400,cors);
    const claim=await client.worker('claim',ids);
    if(!claim.claimed){if(claim.status==='linked')return reply({status:'linked'},200,cors);if(claim.status==='choose_phone')return reply({status:'choose_phone',phones:claim.phones},200,cors);return reply({message:'No se confirmó el intento. Actualizá el estado; si sigue pendiente, iniciá una nueva vinculación.'},409,cors);}
    const exchanged=await graph('oauth/access_token',{params:{client_id:cfg.app_id,client_secret:cfg.app_secret,code:body.code}});if(!exchanged.access_token)throw Error('meta');
    const listed=await graph(body.waba_id+'/phone_numbers',{token:exchanged.access_token,params:{fields:'id,display_phone_number,verified_name,is_on_biz_app,platform_type',limit:'100'}});
    const phones=(listed.data||[]).filter(p=>ID.test(p.id)&&p.is_on_biz_app===true&&p.platform_type==='CLOUD_API').map(p=>({id:p.id,display_phone_number:String(p.display_phone_number||''),verified_name:String(p.verified_name||'')}));
    if(!phones.length)return await client.worker('fail',ids).then(()=>reply({message:'Meta no confirmó un número compatible con WhatsApp Business en el celular. No se registró ni migró ningún número.'},409,cors));
    await client.worker('stage',{...ids,token:exchanged.access_token,waba_id:body.waba_id,phones});
    if(phones.length!==1&&!phones.some(p=>p.id===phoneId))return reply({status:'choose_phone',phones},200,cors);
    if(!phoneId)phoneId=phones[0].id;
   }else if(body.action==='select'){
    if(!ID.test(phoneId||''))return reply({message:'Elegí un número autorizado.'},400,cors);
    const progress=await client.worker('claim',ids);if(progress.status==='linked')return reply({status:'linked'},200,cors);
   }else return reply({message:'Acción no disponible.'},400,cors);
   const credential=await client.worker('credentials',{...ids,phone_id:phoneId});
   const verified=await graph(phoneId,{token:credential.token,params:{fields:'id,is_on_biz_app,platform_type'}});
   if(verified.is_on_biz_app!==true||verified.platform_type!=='CLOUD_API')throw Error('not_coexistence');
   const subscribed=await graph(credential.waba_id+'/subscribed_apps',{token:credential.token,data:{}});if(subscribed.success!==true)throw Error('meta');
   const result=await client.worker('complete',{...ids,phone_id:phoneId});return reply(result,200,cors);
  }catch(e){
   if(ids)try{await client.worker('fail',ids);}catch{}
   const denied=e.message==='unauthorized';return reply({message:denied?'Solo Administración puede vincular WhatsApp.':e.message==='meta'?'Meta no pudo completar la conexión. Revisá los permisos y la preparación de la cuenta.':'No se confirmó la vinculación. Actualizá el estado antes de volver a intentar.',...(e.metaCode?{meta_code:e.metaCode}:{})},denied?403:409,cors);
  }
 };
}
export function createWebhookHandler({env,fetcher=fetch,cryptoApi=crypto}){
 const client=clients(env,fetcher),encoder=new TextEncoder();
 const same=(a,b)=>{if(a.length!==b.length)return false;let diff=0;for(let i=0;i<a.length;i++)diff|=a.charCodeAt(i)^b.charCodeAt(i);return diff===0;};
 return async req=>{
  if(!['GET','POST'].includes(req.method))return new Response('Method not allowed',{status:405});
  try{
   const cfg=await client.worker('config');if(!cfg.app_secret)return new Response('Not configured',{status:503});
   if(req.method==='GET'){const u=new URL(req.url),token=u.searchParams.get('hub.verify_token')||'',challenge=u.searchParams.get('hub.challenge')||'';
    if(u.searchParams.get('hub.mode')!=='subscribe'||!same(token,cfg.verify_token)||!/^\d{1,100}$/.test(challenge))return new Response('Forbidden',{status:403});
    await client.worker('webhook_verified');return new Response(challenge,{headers:{'Content-Type':'text/plain','Cache-Control':'no-store'}});
   }
   const signature=req.headers.get('X-Hub-Signature-256')||'';if(!/^sha256=[a-f0-9]{64}$/i.test(signature))return new Response('Forbidden',{status:403});
   const text=await readBody(req),key=await cryptoApi.subtle.importKey('raw',encoder.encode(cfg.app_secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
   const bytes=new Uint8Array(await cryptoApi.subtle.sign('HMAC',key,encoder.encode(text))),hex=[...bytes].map(x=>x.toString(16).padStart(2,'0')).join('');if(!same(signature.toLowerCase(),'sha256='+hex))return new Response('Forbidden',{status:403});
   const payload=JSON.parse(text);if(payload.object!=='whatsapp_business_account'||!Array.isArray(payload.entry))return new Response('Invalid event',{status:400});
   const hash=[...new Uint8Array(await cryptoApi.subtle.digest('SHA-256',encoder.encode(text)))].map(x=>x.toString(16).padStart(2,'0')).join('');
   await client.worker('event',{event_hash:hash,payload});return new Response('EVENT_RECEIVED');
  }catch{return new Response('Could not process event',{status:503});}
 };
}
