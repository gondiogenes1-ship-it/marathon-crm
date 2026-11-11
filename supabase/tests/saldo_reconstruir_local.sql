-- SOLO la base vacía marathon_saldo_restauracion_20261104, recién creada para QA.
-- El volcado local inicial traía el borrador de estructura, sin registros.
\set ON_ERROR_STOP on
do $$begin
 if current_database()<>'marathon_saldo_restauracion_20261104'or exists(select 1 from marathon.pacientes)then raise exception 'Esta limpieza se limita a la copia vacía de QA.';end if;
end$$;
drop table marathon.saldo_eventos,marathon.saldo_aplicaciones,marathon.saldo_fuentes,marathon.saldo_cuentas,marathon.saldo_ajustes_sesion,marathon.saldo_importacion_map cascade;
drop function marathon.saldo_inmutable(),marathon.saldo_fuente_disponible(uuid),marathon.saldo_disponible(text),marathon.saldo_aplicado(uuid),marathon.saldo_validar_aplicacion(),marathon.saldo_validar_evento();
