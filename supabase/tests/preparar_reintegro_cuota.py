"""Extensión aprobada: reintegro de cuota a crédito, sin egreso físico."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
first=(ROOT/'supabase/migrations/20261104234313_caja_saldo_unificado.sql').read_text(encoding='utf-8')
preview='create or replace function marathon.saldo_prever'+first.split('create function marathon.saldo_prever')[1].split('create function public.marathon_saldo_consultar')[0]
preview=preview.replace("'REINTEGRO_SESION'","'REINTEGRO_SESION','REINTEGRO_CUOTA'",2)
preview=preview.replace("if kind='REINTEGRO_SESION'then","if kind in('REINTEGRO_SESION','REINTEGRO_CUOTA')then")
preview=preview.replace("x.tipo='sesion'and x.id=p_data->>'turno_id'","x.tipo=case when kind='REINTEGRO_SESION'then 'sesion'else 'cuota'end and x.id=case when kind='REINTEGRO_SESION'then p_data->>'turno_id'else p_data->>'cuota_id'end")
preview=preview.replace('Elegí una sesión presente con pago recuperable.','Elegí una sesión presente o una cuota con pago recuperable.')
preview=preview.replace("'tipo','sesion','id',d.id","'tipo',d.tipo,'id',d.id")
command=(ROOT/'supabase/migrations/20261105000334_caja_saldo_consultas.sql').read_text(encoding='utf-8').split('create or replace function public.marathon_saldo_command')[1].split('create or replace function marathon.saldo_automatico')[0]
command='create or replace function public.marathon_saldo_command'+command
command=command.replace('turno marathon.turnos%rowtype;reply','turno marathon.turnos%rowtype;quota marathon.agenda_cuotas%rowtype;reply')
command=command.replace("'turno_id','huella'","'turno_id','cuota_id','huella'")
marker=" if kind='REINTEGRO_SESION'then"
assert command.count(marker)==1
command=command.replace(marker,""" if kind='REINTEGRO_CUOTA'then
  if length(btrim(coalesce(p_data->>'observaciones','')))<3 or length(p_data->>'observaciones')>1000 then raise exception 'Indicá el motivo del reintegro de cuota (3 a 1000 caracteres).'using errcode='22023';end if;
  select q.*into strict quota from marathon.agenda_cuotas q join marathon.agenda_planes p on p.id=q.plan_id where q.id=(p_data->>'cuota_id')::uuid and p.dni=person for update of q;
  for a in select sa.*,marathon.saldo_aplicado(sa.id)actual from marathon.saldo_aplicaciones sa where sa.cuota_id=quota.id and marathon.saldo_aplicado(sa.id)>0 order by sa.created_at,sa.id loop
   insert into marathon.saldo_eventos(dni,fuente_id,tipo,monto,aplicacion_id,request_id,actor,efecto)values(person,a.fuente_id,'REVERSO_APLICACION',a.actual,a.id,p_request_id,auth.uid(),'reintegro_cuota:'||a.id);
  end loop;
  if marathon.saldo_pagado('cuota',quota.id::text)<>0 then raise exception 'La cuota histórica requiere completar la importación antes de reintegrarla.'using errcode='55000';end if;
  insert into marathon.agenda_ajustes(cuota_id,importe,motivo,created_by)values(quota.id,quota.importe-(select coalesce(sum(importe),0)from marathon.agenda_ajustes where cuota_id=quota.id),p_data->>'observaciones',auth.uid());
 elsif kind='REINTEGRO_SESION'then""")
command=command.replace("'message','Movimiento registrado.'","'message',case when kind='REINTEGRO_CUOTA'then 'Cuota reintegrada al saldo a favor del paciente. No se devolvió dinero de Caja. Para devolver dinero, registrá una Devolución de saldo.'else 'Movimiento registrado.'end")
output='-- Decisión confirmada: cuota sin deuda; pago liberado al saldo, sin egreso.\nbegin;\n'+preview+'\n'+command+'\ncommit;\n'
(ROOT/'supabase/migrations/20261105002908_caja_saldo_reintegro_cuota.sql').write_text(output,encoding='utf-8')
print('Reintegro de cuota a saldo preparado.')
