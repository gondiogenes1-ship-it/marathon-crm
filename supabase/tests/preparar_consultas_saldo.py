"""Conserva contratos actuales de lectura; usa cargos netos sin inflar pagos."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
ref=json.loads((ROOT/'Documentacion/Caja_saldo_a_favor/Fase_2_aislada/referencia_servidor_actual.json').read_text(encoding='utf-8'))
def fn(name):
 f=[x['definition'] for x in ref['functions']if x['name']==name];assert len(f)==1;return f[0].replace('\r','')
parts=['begin;',"""
create function marathon.saldo_cargo_sesion(p_id text)returns numeric language sql stable set search_path=''as $$
 select greatest(0,t.importe-case when exists(select 1 from marathon.saldo_config where activo)then coalesce((select sum(monto)from marathon.saldo_ajustes_sesion where turno_id=t.id),0)else 0 end)from marathon.turnos t where t.id=p_id
$$;
revoke all on function marathon.saldo_cargo_sesion(text)from public,anon,authenticated;
"""
]
for name in ['marathon_patient_account','marathon_turn_account','marathon_patient_history']:
 text=fn(name)
 for old,new in [
 ('t.importe-marathon.turn_paid(t.id)','marathon.saldo_cargo_sesion(t.id)-marathon.turn_paid(t.id)'),
 ('t.importe>marathon.turn_paid(t.id)','marathon.saldo_cargo_sesion(t.id)>marathon.turn_paid(t.id)'),
 ('t.importe-paid','marathon.saldo_cargo_sesion(t.id)-paid'),
 ('t.importe-pay.paid','marathon.saldo_cargo_sesion(t.id)-pay.paid')]:text=text.replace(old,new)
 if name=='marathon_patient_history':
  marker=" if p_kind='clinic' then"
  assert text.count(marker)==1
  text=text.replace(marker,""" if exists(select 1 from marathon.saldo_config where activo)then
   summary=summary||jsonb_build_object('saldo_disponible',marathon.saldo_disponible(p_dni),'advance_available',marathon.saldo_disponible(p_dni),
   'clinical_debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)where tipo<>'bono'),0),
   'debt',coalesce((select sum(deuda)from marathon.saldo_deudas(p_dni)),0)+(summary->>'ortho_debt')::numeric);
  end if;
"""+marker)
 parts.append(text+';')
for name in ['marathon_agenda_plan','marathon_agenda_grilla','marathon_agenda_patient_account']:
 text=fn(name)
 assert 'perform marathon.agenda_cuotas_generar();'in text
 text=text.replace('perform marathon.agenda_cuotas_generar();','if not exists(select 1 from marathon.saldo_config where activo)then perform marathon.agenda_cuotas_generar();end if;')
 parts.append(text+';')
cash=next(v['definition'] for v in ref['views']if v['name']=='daily_cash').replace('\r','')
cash=cash.replace('COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id)','COALESCE(t.terapia_id, b.terapia_id, a.terapia_id, ap.terapia_id, m.terapia_asociada_id)')
parts.append('create or replace view marathon.daily_cash as '+cash)
turn=next(v['definition'] for v in ref['views']if v['name']=='daily_turns').replace('t.importe - marathon.turn_paid(t.id)','marathon.saldo_cargo_sesion(t.id) - marathon.turn_paid(t.id)')
parts.append('create or replace view marathon.daily_turns as '+turn)
# Control de payload nuevo sin cambiar la función original versionada.
command=(ROOT/'supabase/migrations/20261104234313_caja_saldo_unificado.sql').read_text(encoding='utf-8').split('create function public.marathon_saldo_command')[1].split('-- Mantener las funciones')[0]
command='create or replace function public.marathon_saldo_command'+command
marker=" if not exists(select 1 from marathon.saldo_config where activo)"
assert command.count(marker)==1
command=command.replace(marker,""" if exists(select 1 from jsonb_object_keys(p_data)k where k<>all(array['dni','subtipo','monto','medio','sede','fecha','observaciones','categoria','profesional','terapia','secretaria','turno_id','huella','version']))then raise exception 'La solicitud contiene campos no admitidos.'using errcode='22023';end if;
"""+marker)
parts.append(command)
parts[-1]=parts[-1].replace(' proposal=marathon.saldo_prever(p_data);'," if person is not null and p_data->>'version'is distinct from marathon.saldo_version(person)::text then raise exception 'La cuenta cambió. Revisá la nueva vista previa antes de confirmar.'using errcode='PT409';end if;\n proposal=marathon.saldo_prever(p_data);")
automatic=(ROOT/'supabase/migrations/20261104235643_caja_saldo_controles.sql').read_text(encoding='utf-8').split('create or replace function marathon.saldo_automatico()')[1].split('-- Validación')[0]
automatic='create or replace function marathon.saldo_automatico()'+automatic
marker=" request='saldo_auto_'"
assert automatic.count(marker)==1
automatic=automatic.replace(marker,""" -- El pase automático de pendiente a ausente sin pagos no tiene efecto financiero.
 if release_payment and not exists(select 1 from marathon.saldo_aplicaciones a where a.dni=person and marathon.saldo_aplicado(a.id)>0 and((tg_table_name='turnos'and a.turno_id=new.id::text)or(tg_table_name='bonos_serie'and a.bono_id=new.id::text)))then return new;end if;
"""+marker)
parts.append(automatic)
parts.append("""
create function public.marathon_saldo_preparar()returns jsonb language plpgsql security definer set search_path=''set lock_timeout='3s'as $$declare n int;begin
 if not marathon.active_user()then raise exception 'Acceso no autorizado.'using errcode='42501';end if;
 if not exists(select 1 from marathon.saldo_config where activo)then raise exception 'Circuito de saldo no habilitado.'using errcode='55000';end if;
 n=marathon.agenda_cuotas_generar();return jsonb_build_object('cuotas_generadas',n);
end$$;
revoke all on function public.marathon_saldo_preparar()from public,anon;
grant execute on function public.marathon_saldo_preparar()to authenticated;
commit;
""")
(ROOT/'supabase/migrations/20261105000334_caja_saldo_consultas.sql').write_text('\n'.join(parts),encoding='utf-8')
print('Consultas y preparación explícita generadas.')
