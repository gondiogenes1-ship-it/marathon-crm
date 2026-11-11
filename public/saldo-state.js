// Estado por sesión, solo en memoria. Un servidor sin la mejora conserva el circuito vigente.
const states=new WeakMap();
export async function saldoEnabled(api,{fresh=false}={}){
 const key=api?.session?.access_token||api?.generation||'demo',cached=states.get(api);
 if(!fresh&&cached?.key===key&&Date.now()-cached.at<30000)return cached.enabled;
 try{const state=await api.rpc('marathon_saldo_estado',{});const enabled=state?.activo===true;states.set(api,{key,enabled,at:Date.now()});return enabled;}
 catch(error){if(!['PGRST202','42883'].includes(error.code))throw error;states.set(api,{key,enabled:false,at:Date.now()});return false;}
}
