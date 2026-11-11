import fs from 'node:fs/promises';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const originals=JSON.parse(await fs.readFile(path.join(root,'Documentacion/Condiciones_20261105/funciones_anteriores.json'),'utf8'));
const get=name=>originals.find(x=>x.proname===name).definition.replaceAll('\r','');
function replace(text,from,to){if(text.split(from).length!==2)throw Error('Reemplazo no único: '+from.slice(0,90));return text.replace(from,()=>to);}
let context=get('turn_series_context');
context=replace(context,'members jsonb;rules jsonb;','members jsonb;rules jsonb;tarifas jsonb;quotas jsonb;');
context=replace(context,"select to_jsonb(x)into p from marathon.agenda_planes x where x.id=t.plan_id;","select to_jsonb(x)||jsonb_build_object('importe',case when x.facturacion='monthly'then marathon.agenda_tarifa(x.id,t.fecha)else t.importe end)into p from marathon.agenda_planes x where x.id=t.plan_id;\n  select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into tarifas from marathon.agenda_tarifas x where x.plan_id=t.plan_id;\n  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('paid',marathon.agenda_cuota_pagado(x.id))order by x.id),'[]')into quotas from marathon.agenda_cuotas x where x.plan_id=t.plan_id;");
context=replace(context,"'plan',p,'rules',rules)","'plan',p,'rules',rules,'tarifas',tarifas,'quotas',quotas)");

let run=get('turn_series_run');
run=replace(run,'config jsonb;schedules jsonb;','config jsonb;schedules jsonb;fee numeric;cov jsonb;memo text;qrow marathon.agenda_cuotas%rowtype;quotes_changed int:=0;quotes_kept int:=0;');
run=replace(run,"'reason','schedules']","'reason','schedules','amount','coverage','notes']");
run=replace(run,"  new_date=marathon.agenda_date(p_data->>'date');",`  new_date=marathon.agenda_date(p_data->>'date');
  if t.plan_id is not null then select *into strict p from marathon.agenda_planes where id=t.plan_id;end if;
  if p_data?'amount'then
   if coalesce(p_data->>'amount','')!~'^[0-9]{1,10}(\\.[0-9]{1,2})?$'then raise exception 'Indicá un importe válido, con hasta dos decimales.'using errcode='22023';end if;
   fee=(p_data->>'amount')::numeric;
   if(p.facturacion='none'and fee<>0)or(p.facturacion='monthly'and fee<=0)then raise exception 'El importe debe respetar la modalidad de pago.'using errcode='22023';end if;
   if p.facturacion='monthly'and scope='single'and fee<>marathon.agenda_tarifa(p.id,t.fecha)then raise exception 'El importe mensual se modifica para la serie. Elegí este turno y los siguientes.'using errcode='22023';end if;
  end if;
  if p_data?'coverage'then cov=marathon.normalize_turn_coverage(t.dni,p_data->'coverage');end if;
  if p_data?'notes'then
   if jsonb_typeof(p_data->'notes')<>'string'or length(p_data->>'notes')>1000 then raise exception 'Las observaciones admiten hasta 1000 caracteres.'using errcode='22023';end if;
   memo=p_data->>'notes';
  end if;`);
run=replace(run,'insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde,hasta)', 'insert into marathon.agenda_horarios(plan_id,sede,profesional_id,dia,hora,duracion_min,desde,hasta,importe_override,coverage_override,observaciones_override)');
run=replace(run,'case when rule.hasta is null then null else rule.hasta+delta end)returning id into new_rule;',"case when rule.hasta is null then null else rule.hasta+delta end,case when p.facturacion in('class','bonus_class')then coalesce(fee,rule.importe_override)else rule.importe_override end,coalesce(cov,rule.coverage_override),coalesce(memo,rule.observaciones_override))returning id into new_rule;");
run=replace(run,"duracion_min=duration,estado='PENDIENTE',", "duracion_min=duration,estado='PENDIENTE',importe=case when p.facturacion in('monthly','none')then member.importe else coalesce(fee,member.importe)end,coverage=coalesce(cov,member.coverage),booking_notes=coalesce(memo,member.booking_notes),");
run=replace(run,"   update marathon.agenda_planes set updated_at=now()where id=t.plan_id;",`   if p.facturacion='monthly'and fee is not null then
    update marathon.agenda_tarifas set vigente=false where plan_id=t.plan_id and vigente and desde>=t.fecha;
    insert into marathon.agenda_tarifas(plan_id,desde,importe,request_id,created_by)values(t.plan_id,t.fecha,fee,p_request_id,auth.uid());
    for qrow in select *from marathon.agenda_cuotas q where q.plan_id=t.plan_id and q.hasta>t.fecha order by q.fecha for update loop
     if marathon.agenda_cuota_pagado(qrow.id)>0 or exists(select 1 from marathon.agenda_ajustes a where a.cuota_id=qrow.id)then
      quotes_kept=quotes_kept+1;
     elsif qrow.importe<>fee then
      update marathon.agenda_cuotas set importe=fee where id=qrow.id;
      insert into marathon.operation_audit(request_id,actor,entity,entity_id,action,before_data,after_data)
      select p_request_id,auth.uid(),'agenda-cuota',qrow.id::text,'importe_desde_turno',to_jsonb(qrow),to_jsonb(x)from marathon.agenda_cuotas x where x.id=qrow.id;
      quotes_changed=quotes_changed+1;
     end if;
    end loop;
   end if;
   update marathon.agenda_planes set updated_at=now()where id=t.plan_id;`);
run=replace(run,"'message',case when kind='cancel'", "'cuotas_actualizadas',quotes_changed,'cuotas_conservadas',quotes_kept,'message',case when kind='cancel'");
run=replace(run,"else''end);\n update marathon.solicitudes", "else''end||case when quotes_changed>0 then' Se actualizó la cuota sin pagos.'else''end||case when quotes_kept>0 then' Las cuotas con pagos o ajustes conservaron su importe; el nuevo valor se aplica a las próximas.'else''end);\n update marathon.solicitudes");

let materialize=get('agenda_materializar');
materialize=replace(materialize,"then p.importe else 0 end,'PENDIENTE',p.coverage,p.observaciones", "then coalesce(h.importe_override,p.importe)else 0 end,'PENDIENTE',coalesce(h.coverage_override,p.coverage),coalesce(h.observaciones_override,p.observaciones)");
materialize=replace(materialize,'from marathon.agenda_planes p where p.id=v.plan_id', 'from marathon.agenda_planes p join marathon.agenda_horarios h on h.id=v.horario_id where p.id=v.plan_id');
let quotas=get('agenda_cuotas_generar');
quotas=replace(quotas,'::date,p.importe,h.sede', '::date,marathon.agenda_tarifa(p.id,(s.inicio+make_interval(months=>g.n))::date),h.sede');
const functions=[context,run,materialize,quotas].join(';\n\n')+';\n';
const migration=path.join(root,'supabase/migrations/20261105135154_agenda_condiciones_desde_fecha.sql');
const template=await fs.readFile(migration,'utf8');
await fs.writeFile(migration,replace(template,'-- FUNCIONES_GENERADAS',functions));
await fs.writeFile(path.join(root,'local/condiciones-iteracion.sql'),'begin;\n'+functions+'\ncommit;\n');
console.log('Generadas funciones de contexto, edición, materialización y cuotas.');
