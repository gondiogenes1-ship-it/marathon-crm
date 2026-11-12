-- Marathon CRM — Traslado de ortopedia: habilitar la sede destino automáticamente.
-- Correr en el SQL Editor de Supabase (una sola vez).
--
-- Qué hace: modifica public.marathon_ortho_command (acción 'transfer') para que,
-- al trasladar stock a otra sede activa, si el producto no estaba habilitado allí
-- se cree su configuración (stock_config, mínimo 0) automáticamente, en vez de
-- exigir habilitarlo antes. El resto de la función queda idéntico.
--
-- Método seguro: toma la definición ACTUAL de la función, le aplica un reemplazo
-- puntual y la recrea. Si el patrón no está (ya aplicado o cambió la función), aborta
-- sin tocar nada.
--
-- Nota: el traslado no es exclusivo de ADMIN, así que con esto una secretaria también
-- puede habilitar una sede al trasladar. Es el comportamiento pedido.

do $$
declare src text; newsrc text;
begin
  src := pg_get_functiondef('public.marathon_ortho_command(text,text,jsonb)'::regprocedure);
  newsrc := replace(src,
    $old$or not exists(select 1 from marathon.stock_config where producto_id=product and sede=destination)then raise sqlstate '22023' using message='Elegí otra sede activa y habilitá allí el producto.';end if;$old$,
    $new$then raise sqlstate '22023' using message='Elegí otra sede activa.';end if;
 insert into marathon.stock_config(producto_id,sede,minimo,initial_loaded,created_by,updated_by)values(product,destination,0,true,auth.uid(),auth.uid())on conflict on constraint stock_config_pkey do nothing;$new$);
  if newsrc = src then
    raise exception 'No se encontro el patron a reemplazar (ya aplicado o cambio la funcion).';
  end if;
  execute newsrc;
end $$;
