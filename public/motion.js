// Mejora progresiva: sin dependencias, temporizadores ni observadores sobre tablas.
export function createMotion(){
 const body=document.body,reduce=matchMedia('(prefers-reduced-motion: reduce)');
 let pointer=false,current=null;
 const cancel=()=>{current?.cancel();current=null;};
 const inputPointer=()=>{pointer=true;body.classList.add('motion-pointer');body.classList.remove('motion-keyboard');};
 const inputKeyboard=()=>{pointer=false;cancel();body.classList.remove('motion-pointer');body.classList.add('motion-keyboard');};
 const preference=()=>{if(reduce.matches)cancel();};
 document.addEventListener('pointerdown',inputPointer,{capture:true,passive:true});
 document.addEventListener('keydown',inputKeyboard,true);
 reduce.addEventListener('change',preference);
 function enter(section){
  cancel();if(!pointer||reduce.matches||document.visibilityState==='hidden')return;
  const heading=section?.querySelector('.topbar');if(!heading?.animate)return;
  // Solo el encabezado: no se desplazan controles, importes, pacientes ni filas.
  current=heading.animate([{opacity:.8},{opacity:1}],{duration:125,easing:'cubic-bezier(0.23,1,0.32,1)'});
 }
 return {enter,dispose(){cancel();document.removeEventListener('pointerdown',inputPointer,true);document.removeEventListener('keydown',inputKeyboard,true);reduce.removeEventListener('change',preference);body.classList.remove('motion-pointer','motion-keyboard');}};
}
