begin;
-- Solo cambia la lectura de Caja. Ningún cobro, aplicación o medio se reescribe.
lock table marathon.movimientos, marathon.saldo_fuentes, marathon.saldo_aplicaciones, marathon.saldo_eventos in share mode;
create temporary table caja_datos_antes on commit drop as
select 'movimientos' tabla,md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text) huella from marathon.movimientos x
union all select 'fuentes',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text) from marathon.saldo_fuentes x
union all select 'aplicaciones',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text) from marathon.saldo_aplicaciones x
union all select 'eventos',md5(coalesce(jsonb_agg(to_jsonb(x)order by id),'[]')::text) from marathon.saldo_eventos x;

create or replace function marathon.cash_attribution(p_id text)
returns table(monto numeric,professional_key text,category_key text,category_label text,associated text)
language sql stable set search_path='' as $function$
 with base as(select * from marathon.daily_cash where id=p_id),
 source as(select f.id from marathon.saldo_fuentes f where f.movimiento_id=p_id),
 returned as(select coalesce(sum(e.monto),0) amount from marathon.saldo_eventos e join source s on s.id=e.fuente_id where e.tipo='DEVOLUCION'),
 applications as(
 select a.*,marathon.saldo_aplicado(a.id) applied
 from marathon.saldo_aplicaciones a join source s on s.id=a.fuente_id),
 targets as(
 select a.applied,coalesce(t.profesional_id,b.profesional_id,qp.prof) prof,
 coalesce(t.terapia_id,b.terapia_id,pl.terapia_id) therapy,
 a.cuota_id is not null and qp.providers>1 ambiguous
 from applications a
 left join marathon.turnos t on t.id=a.turno_id
 left join marathon.bonos_serie b on b.id=a.bono_id
 left join marathon.agenda_cuotas q on q.id=a.cuota_id
 left join marathon.agenda_planes pl on pl.id=q.plan_id
 left join lateral(
  select case when count(distinct profesional_id)=1 then min(profesional_id)end prof,count(distinct profesional_id) providers
  from(select h.profesional_id,dense_rank()over(order by
   case when h.desde<=q.fecha and(h.hasta is null or q.fecha<h.hasta)then 0 when h.desde>q.fecha then 1 else 2 end,
   case when h.desde>q.fecha then h.desde end) priority
   from marathon.agenda_horarios h where h.plan_id=q.plan_id and(h.hasta is null or h.hasta>h.desde))hs where priority=1
 )qp on q.id is not null where a.applied>0),
 pieces as(
 select t.applied monto,t.prof professional_key,coalesce('T:'||t.therapy,'C:Otros') category_key,
 coalesce(th.nombre,'Otros') category_label,
 coalesce(nullif(concat_ws(' ',pr.nombre,nullif(pr.segundo_nombre,''),pr.apellido),''),
 case when t.ambiguous then 'Cuota con varios profesionales'else 'Sin profesional identificado'end) associated
 from targets t left join marathon.profesionales pr on pr.id=t.prof left join marathon.terapias th on th.id=t.therapy
 union all
 select r.amount,null,'C:Saldo devuelto','Saldo devuelto','Devuelto al paciente'
 from returned r where r.amount>0
 union all
 select b.monto-coalesce((select sum(applied)from targets),0)-r.amount,null,'C:Saldo sin aplicar','Saldo sin aplicar','Saldo a favor sin aplicar'
 from base b cross join returned r where exists(select 1 from source)and b.monto>coalesce((select sum(applied)from targets),0)+r.amount
 union all
 select b.monto,b.professional_key,b.category_key,b.category_label,b.associated
 from base b where not exists(select 1 from source))
 select sum(p.monto),p.professional_key,p.category_key,p.category_label,p.associated from pieces p
 group by p.professional_key,p.category_key,p.category_label,p.associated
$function$;
revoke all on function marathon.cash_attribution(text) from public,anon,authenticated;
comment on function marathon.cash_attribution(text) is 'Lectura privada: distribuye el ingreso original según aplicaciones vigentes; remanente sin profesional. No crea ni modifica movimientos.';

create or replace function public.marathon_cash_search(p_filters jsonb,p_after jsonb default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $function$
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
 select m.id,m.fecha,m.hora,m.medio,m.tipo,a.amount monto,
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
 sums as(select medio,coalesce(sum(monto)filter(where tipo in('PAGO','INGRESO')),0)income,coalesce(sum(monto)filter(where tipo in('EGRESO','REINTEGRO')),0)expense from filtered group by medio)
 select coalesce((select jsonb_agg(data order by fecha,hora,id)from page),'[]'::jsonb),
 coalesce((select jsonb_object_agg(medio,jsonb_build_object('income',income,'expense',expense,'net',income-expense))from sums),'{}'::jsonb)into rows,totals;
 if jsonb_array_length(rows)>p_limit then rows=rows-p_limit;nxt=jsonb_build_object('fecha',rows->(p_limit-1)->>'fecha','hora',rows->(p_limit-1)->>'hora','id',rows->(p_limit-1)->>'id');end if;
 return jsonb_build_object('rows',rows,'next',nxt,'totals',totals);
end $function$;
revoke all on function public.marathon_cash_search(jsonb,jsonb,integer) from public,anon;
grant execute on function public.marathon_cash_search(jsonb,jsonb,integer) to authenticated;

-- Guardia: la instalación debe conservar íntegros los registros financieros.
do $guard$declare after_hash text;r record;begin
 for r in select * from caja_datos_antes loop
 execute format('select md5(coalesce(jsonb_agg(to_jsonb(x)order by id),''[]'')::text)from marathon.%I x',
 case r.tabla when 'fuentes'then 'saldo_fuentes'when 'aplicaciones'then 'saldo_aplicaciones'when 'eventos'then 'saldo_eventos'else 'movimientos'end)into after_hash;
 if after_hash<>r.huella then raise exception 'La instalación modificó datos de %',r.tabla;end if;
 end loop;
end $guard$;
commit;
