// Controles de cierre consistentes y avisos de error sobre cualquier formulario.
export function createModalUI(){
 const error=document.createElement('dialog');error.id='global-error-dialog';error.className='marathon-error-dialog';error.setAttribute('aria-labelledby','global-error-title');
 const title=document.createElement('h2');title.id='global-error-title';title.textContent='Revisá este dato';
 const body=document.createElement('p');body.id='global-error-text';body.setAttribute('role','alert');
 const close=document.createElement('button');close.type='button';close.className='s modal-close-x';close.dataset.modalX='true';close.setAttribute('aria-label','Cerrar aviso de error');close.textContent='×';close.addEventListener('click',()=>error.close());
 error.append(close,title,body);document.body.append(error);
 function decorate(dialog){
  if(dialog===error)return;
  let button=[...dialog.querySelectorAll('button')].find(b=>b.dataset.modalX==='true'||/^(Cerrar|Cerrar\s)/i.test(b.textContent.trim())||b.id.endsWith('-close'));
  if(!button){button=document.createElement('button');button.type='button';button.addEventListener('click',()=>dialog.close());}
  if(button.parentElement!==dialog)dialog.prepend(button);
  else if(button!==dialog.firstElementChild)dialog.prepend(button);
  button.classList.add('modal-close-x');button.dataset.modalX='true';if(button.textContent!=='×')button.textContent='×';button.setAttribute('aria-label','Cerrar '+(dialog.getAttribute('aria-label')||dialog.getAttribute('aria-labelledby')&&document.getElementById(dialog.getAttribute('aria-labelledby'))?.textContent||'formulario'));
  button.title='Cerrar';
 }
 const inline=new WeakMap();
 const observer=new MutationObserver(()=>{for(const d of document.querySelectorAll('dialog'))if(d!==error&&d.open)decorate(d);for(const node of document.querySelectorAll('#operation-error,#ortho-error,#login-error')){const value=node.textContent.trim();if(inline.get(node)!==value){inline.set(node,value);if(value)showError(value);}}});observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['open']});
 function showError(message){body.textContent=String(message||'No se pudo completar la operación.');if(!error.open)error.showModal();close.focus();}
 return {showError,closeError(){if(error.open)error.close();}};
}
