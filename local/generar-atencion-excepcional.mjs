import fs from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const defs=JSON.parse(await fs.readFile(new URL('local/excepcional-funciones-anteriores.json',root),'utf8'));
const rep=(s,a,b)=>{if(!a||!s.includes(a))throw Error('No se encontró '+a);return s.replaceAll(a,()=>b);};
let cupo=defs.find(x=>x.proname==='agenda_cupo').definition;
cupo=rep(cupo,'marathon.agenda_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, exclude_plan uuid DEFAULT NULL::uuid, exclude_turn text DEFAULT NULL::text)','marathon.excepcion_cupo(d date, site text, prof text, therapy text, at_hour time without time zone, requested integer, exclude_turn text DEFAULT NULL::text)');
cupo=rep(cupo,'declare cap int;','declare exclude_plan uuid:=null;cap int;');
const check=cupo.slice(cupo.indexOf(' if cap is null or not exists('),cupo.indexOf(' select greatest(cap,'));
cupo=rep(cupo,check,` if cap is null or requested is null or requested<=0 or extract(epoch from at_hour)/60+requested>1440 then return jsonb_build_object('remaining',0,'capacity',coalesce(cap,0),'blocked',true);end if;
 dur=requested;
`);
let guard=defs.find(x=>x.proname==='agenda_turno_guard').definition;
guard=rep(guard,"if tg_op='INSERT' and new.recovered_from",`if new.excepcional and(new.plan_id is not null or new.original_id is not null or new.fixed_until is not null or new.series_pattern is not null)then raise exception 'La atención excepcional corresponde a un único turno.'using errcode='22023';end if;
 if tg_op='UPDATE'and new.excepcional is distinct from old.excepcional then raise exception 'No se puede cambiar el tipo de una reserva existente.'using errcode='22023';end if;
 if tg_op='INSERT' and new.recovered_from`);
guard=rep(guard,'q=marathon.agenda_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.plan_id,new.id);',`if new.excepcional then q=marathon.excepcion_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.duracion_min,new.id);
  else q=marathon.agenda_cupo(new.fecha,new.sede,new.profesional_id,new.terapia_id,new.hora,new.plan_id,new.id);end if;`);
let command=defs.find(x=>x.proname==='marathon_agenda_command').definition;
const restoreStart=command.indexOf("   select * into slot from marathon.agenda_slots(old.fecha");
const restore=command.slice(restoreStart,command.indexOf("   if slot.hora is null or slot.remaining<1 or slot.blocked then",restoreStart));
command=rep(command,restore,`   if old.excepcional then
    select to_char(old.hora,'HH24:MI')hora,(q->>'remaining')::int remaining,(q->>'blocked')::boolean blocked into slot from(select marathon.excepcion_cupo(old.fecha,old.sede,old.profesional_id,old.terapia_id,old.hora,old.duracion_min,old.id)q)x;
   else
${restore}   end if;
`);
const source=await fs.readFile(new URL('supabase/migrations/20261105141935_nueva_serie_desde_reserva_anterior.sql',root),'utf8');
const snapshot=source.match(/create temporary table _continue_before on commit drop as ([\s\S]*?);\r?\n/)[1].replaceAll('to_jsonb(x)',"(to_jsonb(x)-'excepcional')");
const run=await fs.readFile(new URL('local/atencion-excepcional-run.sql',root),'utf8');
const sql=`-- Instala una opción puntual; no cambia horarios ni movimientos existentes.
begin;
set local lock_timeout='5s';
select pg_advisory_xact_lock(hashtextextended('marathon:master-write:v1',0));
create temporary table _exception_before on commit drop as ${snapshot};
alter table marathon.turnos add column excepcional boolean;
${cupo};
${guard};
${command};
${run}
revoke all on function marathon.excepcion_cupo(date,text,text,text,time,integer,text),marathon.excepcion_run(text,jsonb),marathon.agenda_turno_guard()from public,anon,authenticated;
revoke all on function public.marathon_excepcion_prever(jsonb),public.marathon_excepcion_guardar(text,jsonb)from public,anon;
grant execute on function public.marathon_excepcion_prever(jsonb),public.marathon_excepcion_guardar(text,jsonb)to authenticated;
do $guard$declare actual jsonb;begin select snapshot into actual from(${snapshot})s;if actual is distinct from(select snapshot from _exception_before)then raise exception 'La instalación cambió datos existentes. Actualización revertida.';end if;end$guard$;
notify pgrst,'reload schema';
commit;
`;
await fs.writeFile(new URL('supabase/migrations/20261106204407_atencion_excepcional_puntual.sql',root),sql);
console.log('Generada migración de atención excepcional',sql.length);
