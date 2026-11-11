"""Genera adaptaciones verificables desde las funciones leídas del servidor.
Solo preparación local; no conecta ni publica en Supabase.
"""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
reference = json.loads((ROOT/'Documentacion/Caja_saldo_a_favor/Fase_2_aislada/referencia_servidor_actual.json').read_text(encoding='utf-8'))
def fn(schema, name):
    found = [f['definition'] for f in reference['functions'] if f['schema']==schema and f['name']==name]
    assert len(found)==1, (schema,name)
    return found[0].replace('\r\n','\n')
def change(text, old, new):
    assert text.count(old)==1, old
    return text.replace(old,new)
parts = ['-- Adaptación de funciones vigentes; circuito apagado hasta conciliación.\nbegin;']
agenda=fn('public','marathon_agenda_command')
agenda=change(agenda,"if state<>'PRESENTE' and paid>0 then", "if state<>'PRESENTE' and paid>0 and not exists(select 1 from marathon.saldo_config where activo) then")
parts.append(agenda+';')
advance=fn('marathon','advance_apply')
advance=change(advance,'begin\n select * into t',"begin\n if exists(select 1 from marathon.saldo_config where activo)then return 0;end if;\n select * into t")
parts.append(advance+';')
for schema,name,condition in [
 ('public','marathon_cash_command',"p_action<>'reverse' or exists(select 1 from marathon.saldo_fuentes where movimiento_id=p_data->>'id')"),
 ('marathon','advance_change','true'),
 ('marathon','bonus_change',"action<>'bonus_cancel'"),
 ('public','marathon_agenda_plan_command',"p_action in('quota_pay','quota_refund')")]:
    text=fn(schema,name)
    # Conservar auth/idempotencia originales. La validación no tiene efectos persistentes al fallar.
    idx=text.index('\nbegin\n')+len('\nbegin\n')
    text=text[:idx]+f" if exists(select 1 from marathon.saldo_config where activo)and({condition})then raise exception 'Usá Registrar movimiento del nuevo circuito de Caja.'using errcode='55000';end if;\n"+text[idx:]
    if name=='bonus_change':
        text=change(text,"if paid<>0 then", "if paid<>0 and not exists(select 1 from marathon.saldo_config where activo)then")
    parts.append(text+';')
bonus=fn('marathon','bonus_create')
bonus=change(bonus,"if paid and amount<=0 then", "if paid and exists(select 1 from marathon.saldo_config where activo)then raise exception 'Reservá el bono sin cobrar y usá Registrar movimiento.'using errcode='55000';end if;\n if paid and amount<=0 then")
parts.append(bonus+';')
view=next(v['definition'] for v in reference['views'] if v['name']=='daily_bonus')
start=view.index('CROSS JOIN LATERAL')
view=view[:start]+"CROSS JOIN LATERAL (select case when exists(select 1 from marathon.saldo_config where activo)then marathon.saldo_pagado('bono',b.id)else marathon.saldo_legacy_pagado('bono',b.id)end as paid)pay;"
parts.append('create or replace view marathon.daily_bonus as '+view)
parts.append('commit;')
(ROOT/'supabase/migrations/20261104235514_caja_saldo_integracion.sql').write_text('\n'.join(parts),encoding='utf-8')
print('Integración preparada a partir de las funciones vigentes.')
