-- Caja: los totales (Ingresos, Egresos, Efectivo neto, Transferencia neta) ahora
-- suman el monto TOTAL de cada movimiento asociado al filtro (profesional/categoria),
-- no solo la porcion ya aplicada/cobrada. Un ingreso de saldo que todavia tiene
-- parte sin aplicar (queda a favor del paciente) cuenta completo si el movimiento
-- esta asociado a ese profesional.
-- Aditiva y de solo lectura: no modifica registros operativos, solo el calculo de
-- los totales devueltos por marathon_cash_search. La fila individual de cada
-- movimiento no cambia (ya mostraba el monto total desde el cambio anterior).
create or replace function public.marathon_cash_search(p_filters jsonb, p_after jsonb default null::jsonb, p_limit integer default 50)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare d date;e date;rows jsonb;nxt jsonb;totals jsonb;begin
 if not marathon.active_user()then raise sqlstate '42501'using message='Acceso no autorizado.';end if;
 perform marathon.daily_validate(p_filters,array['from','to','sede','medium','category','prof','actor'],p_limit,p_after);
 d=marathon.agenda_date(p_filters->>'from');e=marathon.agenda_date(p_filters->>'to');
 if e<d or e-d>3660 or coalesce(p_filters->>'medium','')not in('','EFECTIVO','TRANSFERENCIA')or(p_after is not null and not(p_after?&array['fecha','hora','id']))then raise sqlstate '22023'using message='Período o filtros de caja inválidos.';end if;
 with base as materialized(
 select * from marathon.daily_cash where fecha between d and e and origen in('CLINICA','CAJA','ORTOPEDIA','BONO','ANTICIPO')
 and(coalesce(p_filters->>'sede','')=''or sede=p_filters->>'sede')
 and(coalesce(p_filters->>'medium','')=''or medio=p_filters->>'medium')
 and(coalesce(p_filters->>'actor','')=''or actor_key=p_filters->>'actor')),
 filtered as materialized(
 select m.id,m.fecha,m.hora,m.medio,m.tipo,a.amount monto,m.monto full_monto,
 to_jsonb(m)||jsonb_build_object('monto',a.amount,'monto_original',m.monto,
 'attribution_filtered',a.amount<>m.monto,'allocations',a.parts,
 'category_label',a.categories,'associated',a.names,
 'professional_key',a.prof,'profesional',a.names) data
 from base m cross join lateral(
 select sum(p.monto)amount,jsonb_agg(to_jsonb(p)order by p.associated,p.category_key)parts,
 string_agg(distinct p.associated,' · 'order by p.associated)names,
 string_agg(distinct p.category_label,' · 'order by p.category_label)categories,
 case when count(distinct p.professional_key)=1 and bool_and(p.professional_key is not null)then min(p.professional_key)end prof
 from marathon.cash_attribution(m.id)p
 where(coalesce(p_filters->>'category','')=''or p.category_key=p_filters->>'category')
 and(coalesce(p_filters->>'prof','')=''or p.professional_key=p_filters->>'prof'
 or(p_filters->>'prof'='__SIN_PROFESIONAL__'and p.professional_key is null))
 )a where a.amount is not null),
 page as(select *from filtered where p_after is null or(fecha,hora,id)>(marathon.agenda_date(p_after->>'fecha'),(p_after->>'hora')::time,p_after->>'id')order by fecha,hora,id limit p_limit+1),
 sums as(select medio,coalesce(sum(full_monto)filter(where tipo in('PAGO','INGRESO')),0)income,coalesce(sum(full_monto)filter(where tipo in('EGRESO','REINTEGRO')),0)expense from filtered group by medio)
 select coalesce((select jsonb_agg(data order by fecha,hora,id)from page),'[]'::jsonb),
 coalesce((select jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense))from sums),'{}'::jsonb)into rows,totals;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $function$;
