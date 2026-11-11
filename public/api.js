// Corrección 17/10/2026: fetch vinculado al contexto del navegador.
// Tokens y fichas solo en memoria. No se utiliza localStorage, sessionStorage ni cookies propias.
export class ApiError extends Error {
  constructor(message,code='',uncertain=false){super(message);this.code=code;this.uncertain=uncertain;}
}
export class MarathonApi {
  constructor(config,fetcher=globalThis.fetch){
    const url=new URL(config?.supabaseUrl||'https://invalid.example');
    if(url.protocol!=='https:'||!config?.publishableKey||config.publishableKey.includes('YOUR_')||url.hostname==='invalid.example') throw new Error('Completá config.js con la URL y la clave publicable del proyecto de prueba.');
    if(config.publishableKey.startsWith('sb_secret_'))throw new Error('Usá una clave publicable, nunca una clave secreta.');
    if(config.publishableKey.startsWith('eyJ')){try{const payload=JSON.parse(atob(config.publishableKey.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));if(payload.role!=='anon')throw new Error();}catch{throw new Error('La clave configurada no es una clave pública anon.');}}
    this.url=url.origin;this.key=config.publishableKey;this.fetcher=fetcher.bind(globalThis);this.session=null;this.refreshing=null;this.generation=0;this.onDenied=null;
  }
  async http(path,body,{token=null,write=false,method='POST'}={}){
    const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),20000);
    let response, data;
    try{response=await this.fetcher(this.url+path,{method,headers:{apikey:this.key,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:controller.signal,cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'});data=await response.json();}
    catch(error){
      const stage=path.includes('grant_type=password')?'ingreso':path.includes('refresh_token')?'renovación':path.includes('marathon_session')?'permisos':path.includes('catalog')?'catálogo':path.includes('search')?'búsqueda':'solicitud';
      const original=String(error?.message||'');
      const reason=error?.name==='AbortError'?'TIMEOUT':/illegal invocation/i.test(original)?'CLIENT_CONTEXT':/header|ISO-8859|character/i.test(original)?'HEADER_INVALID':'BROWSER_FETCH';
      const message=write?'No se confirmó el guardado ('+reason+'). Usá Verificar guardado.':'No se completó '+stage+' ('+reason+'). Revisión 0.11.0.';
      throw new ApiError(message,'NETWORK',write);
    }
    finally{clearTimeout(timer);}
    if(!response.ok){
      const code=String(data?.code||response.status);
      const known=['22023','23505','40001','P0002','PT409','PT404','55000'];
      const definite=known.includes(code)||code==='55P03'||code==='42501';
      const authMessages={invalid_credentials:'Correo o contraseña incorrectos.',email_not_confirmed:'El correo del usuario todavía no está confirmado.'};
      if(path.startsWith('/rest/')&&(code==='42501'||response.status===401))this.onDenied?.();
      const message=code==='55P03'?'Hay otro guardado en curso. Esperá unos segundos y volvé a intentar.':authMessages[code]||(known.includes(code)?data.message:response.status===401?'La sesión venció. Volvé a ingresar.':code==='42501'||response.status===403?'Tu cuenta no tiene acceso habilitado.':'No se pudo completar la operación (HTTP '+response.status+').');
      throw new ApiError(message,code,write&&response.status>=500&&!definite);
    }
    return data;
  }
  async signIn(email,password){
    const gen=++this.generation;
    const s=await this.http('/auth/v1/token?grant_type=password',{email,password});
    if(gen!==this.generation)throw new ApiError('Ingreso cancelado.');
    this.session={...s,expiresAt:Date.now()+s.expires_in*1000};
    try{return await this.rpc('marathon_session',{});}catch(e){await this.signOut();throw e;}
  }
  async refresh(){
    if(this.refreshing)return this.refreshing;
    const gen=this.generation;const token=this.session?.refresh_token;
    if(!token)throw new ApiError('Volvé a ingresar.','401');
    this.refreshing=(async()=>{
      const s=await this.http('/auth/v1/token?grant_type=refresh_token',{refresh_token:token});
      if(gen!==this.generation)throw new ApiError('La sesión se cerró.','401');
      this.session={...s,expiresAt:Date.now()+s.expires_in*1000};
    })().finally(()=>{this.refreshing=null;});
    return this.refreshing;
  }
  async rpc(name,args,write=false){
    name=({marathon_agenda_search:'marathon_agenda_flexible',marathon_patient_account:'marathon_agenda_patient_account'})[name]||name;
    if(!this.session)throw new ApiError('Volvé a ingresar.','401');
    if(this.session.expiresAt<Date.now()+30000)await this.refresh();
    return this.http('/rest/v1/rpc/'+name,args,{token:this.session.access_token,write});
  }
  async whatsapp(body){if(!this.session)throw new ApiError('Volvé a ingresar.','401');if(this.session.expiresAt<Date.now()+30000)await this.refresh();return this.http('/functions/v1/marathon-whatsapp',body,{token:this.session.access_token,write:true});}
  async provisionUser(body){if(!this.session)throw new ApiError('Volvé a ingresar.','401');if(this.session.expiresAt<Date.now()+30000)await this.refresh();return this.http('/functions/v1/marathon-users',body,{token:this.session.access_token,write:true});}
  async updatePassword(password){if(!this.session)throw new ApiError('Volvé a ingresar.','401');if(this.session.expiresAt<Date.now()+30000)await this.refresh();return this.http('/auth/v1/user',{password},{token:this.session.access_token,write:true,method:'PUT'});}
  async storageRequest(path,{body=null,mime=null}={}){
    if(!this.session)throw new ApiError('Volvé a ingresar.','401');
    if(this.session.expiresAt<Date.now()+30000)await this.refresh();
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),30000);
    try{
      const response=await this.fetcher(this.url+'/storage/v1/object/'+(body?'':'authenticated/')+'marathon-patient-docs/'+path.split('/').map(encodeURIComponent).join('/'),{method:body?'POST':'GET',headers:{apikey:this.key,Authorization:'Bearer '+this.session.access_token,...(body?{'Content-Type':mime,'x-upsert':'false'}:{})},...(body?{body}:{}),signal:controller.signal,cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'});
      if(!response.ok){let data={};try{data=await response.json();}catch{}
        // Un reintento sin reemplazo puede encontrar el objeto ya recibido. Finish verifica sus metadatos.
        if(body&&[400,409].includes(response.status)&&(/duplicate|already exists/i.test(String(data.error||'')+' '+String(data.message||''))||String(data.statusCode)==='409'))return;
        throw new ApiError(response.status===401?'La sesión venció. Volvé a ingresar.':response.status===403?'Tu cuenta no tiene acceso a ese documento.':'No se completó la transferencia (HTTP '+response.status+').',String(response.status),!!body&&response.status>=500);
      }
      return body?undefined:await response.blob();
    }catch(e){if(e instanceof ApiError)throw e;throw new ApiError('No se confirmó la transferencia. Volvé a verificar.','NETWORK',!!body);}finally{clearTimeout(timer);}
  }
  storageUpload(path,file,mime){return this.storageRequest(path,{body:file,mime});}
  storageDownload(path){return this.storageRequest(path);}
  async storageDelete(path){
    if(!this.session)throw new ApiError('Volvé a ingresar.','401');
    if(this.session.expiresAt<Date.now()+30000)await this.refresh();
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),30000);
    try{const response=await this.fetcher(this.url+'/storage/v1/object/marathon-patient-docs',{method:'DELETE',headers:{apikey:this.key,Authorization:'Bearer '+this.session.access_token,'Content-Type':'application/json'},body:JSON.stringify({prefixes:[path]}),signal:controller.signal,cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer'});
      if(!response.ok)throw new ApiError(response.status===403?'Tu cuenta no tiene permiso para eliminar este archivo.':'No se confirmó la eliminación (HTTP '+response.status+').',String(response.status),response.status>=500);
      // La RPC posterior confirma la ausencia del objeto; una respuesta vacía no basta.
    }catch(e){if(e instanceof ApiError)throw e;throw new ApiError('No se confirmó la eliminación. Usá Verificar eliminación.','NETWORK',true);}finally{clearTimeout(timer);}
  }
  async signOut(){
    const token=this.session?.access_token;this.session=null;++this.generation;
    if(token){try{await this.http('/auth/v1/logout',{},{token});}catch{/* Memoria local cerrada; avisar requiere red si se solicita revocación global. */}}
  }
}
