// Se ejecuta antes de la aplicación: nunca permitir un envío nativo con claves.
(() => {
 const sensitive=new Set(['email','correo','username','usuario','user','password','passwd','pass','clave','contrasena','contraseña']);
 try{
  const url=new URL(location.href);let changed=false;
  for(const key of [...url.searchParams.keys()])if(sensitive.has(key.toLowerCase())){url.searchParams.delete(key);changed=true;}
  if(url.username||url.password){url.username='';url.password='';changed=true;}
  if(changed)history.replaceState(history.state,'',url.pathname+url.search+url.hash);
 }catch{/* La protección del formulario sigue activa si no se puede limpiar la URL. */}
 document.addEventListener('submit',event=>{
  const form=event.target;if(!(form instanceof HTMLFormElement)||!form.querySelector('input[type=password]'))return;
  event.preventDefault();
  if(form.id==='login-form'&&form.dataset.loginReady!=='true'){
   event.stopImmediatePropagation();const status=document.querySelector('#login-error');if(status)status.textContent='El acceso todavía no está listo. Esperá la carga o recargá la página.';
  }
 },true);
})();
