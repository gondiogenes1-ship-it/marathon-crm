-- SOLO después de importar y ANTES de activar o registrar operaciones nuevas.
-- Uso: psql ... -v lote=ID_SOLICITUD_IMPORTACION -f saldo_conciliar.sql
\set ON_ERROR_STOP on
begin read only;
with baseline as(select resultado->'plan'plan from marathon.solicitudes where id=:'lote'),
expected as(select x from baseline,jsonb_array_elements(plan->'cuentas')x),
differences as(select x->>'dni'dni,(x->>'saldo')::numeric saldo_esperado,marathon.saldo_disponible(x->>'dni')saldo_obtenido,
 (x->>'deuda')::numeric deuda_esperada,coalesce((select sum(deuda)from marathon.saldo_deudas(x->>'dni')),0)deuda_obtenida from expected)
select jsonb_build_object('lote_encontrado',exists(select 1 from baseline),'caja_igual',(select plan->'caja'=marathon.saldo_caja_foto()from baseline),
 'diferencias',coalesce((select jsonb_agg(to_jsonb(d))from differences d where saldo_esperado<>saldo_obtenido or deuda_esperada<>deuda_obtenida),'[]'),
 'saldos_negativos',(select count(*)from marathon.saldo_fuentes where marathon.saldo_fuente_disponible(id)<0),
 'deudas_sobrepagadas',(select count(*)from marathon.saldo_base_legacy b where marathon.saldo_pagado(b.tipo,b.id)>b.pagado),
 'activo',(select activo from marathon.saldo_config))as conciliacion;
commit;
