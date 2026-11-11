-- Referencia del complemento incorporado a la migración de cierre durante su preparación local.
create function public.marathon_saldo_anular_prever(p_id text)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare f marathon.saldo_fuentes%rowtype;m marathon.movimientos%rowtype;blocked boolean;begin
 if not marathon.is_admin()then raise exception 'Solo ADMIN puede anular un ingreso.'using errcode='42501';end if;
 select *into f from marathon.saldo_fuentes where movimiento_id=p_id;
 if not found then raise exception 'Ingreso no encontrado.'using errcode='PT404';end if;
 select *into strict m from marathon.movimientos where id=p_id;
 blocked=exists(select 1 from marathon.saldo_eventos where fuente_id=f.id and tipo='DEVOLUCION')or exists(select 1 from marathon.movimientos where compensacion_de=p_id);
 return jsonb_build_object('id',m.id,'dni',f.dni,'importe',m.monto::text,'medio',m.medio,'sede',m.sede,'version',marathon.saldo_version(f.dni),'bloqueado',blocked,
 'motivo_bloqueo',case when blocked then'El ingreso tiene devoluciones o ya fue anulado. Requiere revisión administrativa.'end,
 'aplicaciones',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'turno_id',a.turno_id,'cuota_id',a.cuota_id,'bono_id',a.bono_id,'liberar',marathon.saldo_aplicado(a.id)::text)order by a.created_at,a.id)from marathon.saldo_aplicaciones a where a.fuente_id=f.id and marathon.saldo_aplicado(a.id)>0),'[]'));
end$$;
revoke all on function public.marathon_saldo_anular_prever(text)from public,anon;
grant execute on function public.marathon_saldo_anular_prever(text)to authenticated;

-- Un índice para consultas frecuentes del saldo por paciente; el resto ya se creó en estructura.
create index saldo_eventos_paciente_fecha on marathon.saldo_eventos(dni,created_at desc,id desc);
create index saldo_fuentes_paciente on marathon.saldo_fuentes(dni);
commit;
