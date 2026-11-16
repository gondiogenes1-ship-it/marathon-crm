-- Caja: un ingreso de saldo registrado con un profesional asociado debe contar
-- para ese profesional al filtrar, aunque todavia no se haya aplicado a ninguna
-- sesion presente (no quede como "Saldo sin aplicar" sin dueño).
-- Antes: la porcion sin aplicar de un ingreso de saldo siempre quedaba con
-- professional_key = null ("Saldo a favor sin aplicar"), aunque el movimiento
-- se hubiera registrado con un profesional asociado (campo "Profesional o
-- secretaria asociada" del alta de saldo). Eso hacia que, al filtrar Caja por
-- ese profesional, esa porcion no apareciera ni se sumara a los totales.
-- Ahora: la porcion sin aplicar hereda el professional_key (y el nombre para
-- mostrar) del profesional asociado al movimiento, si lo tiene. La categoria
-- sigue siendo "Saldo sin aplicar" (no cambia el filtro de categoria).
-- Aditiva y de solo lectura: no modifica registros operativos.
create or replace function marathon.cash_attribution(p_id text)
 returns table(monto numeric, professional_key text, category_key text, category_label text, associated text)
 language sql
 stable
 set search_path to ''
as $function$
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
 select b.monto-coalesce((select sum(applied)from targets),0)-r.amount,b.professional_key,'C:Saldo sin aplicar','Saldo sin aplicar',
 coalesce(nullif(b.associated,''),'Saldo a favor sin aplicar')
 from base b cross join returned r where exists(select 1 from source)and b.monto>coalesce((select sum(applied)from targets),0)+r.amount
 union all
 select b.monto,b.professional_key,b.category_key,b.category_label,b.associated
 from base b where not exists(select 1 from source))
 select sum(p.monto),p.professional_key,p.category_key,p.category_label,p.associated from pieces p
 group by p.professional_key,p.category_key,p.category_label,p.associated
$function$;
