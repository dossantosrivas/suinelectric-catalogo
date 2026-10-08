-- =====================================================================
--  19 · CATÁLOGO ÚNICO: filtros técnicos en todas las categorías
--  Va después de 18. Probado primero en el proyecto beta.
--
--  cargar_atributos(json) aplica lo que arma scripts/recalcular-atributos-beta.js
--  (o lo mismo, en partes):
--    · atributos  → catalogo.atributos (nombre, tipo, unidad)
--    · filtros    → catalogo.atributos_categoria (qué filtros ve cada categoría, en orden)
--    · parches    → [[{clave: valor, …}, [codigo, codigo, …]], …]
--                   se suman a skus.specs (no borran lo que ya había)
--  Idempotente: se puede correr de nuevo.
-- =====================================================================

create or replace function catalogo.cargar_atributos(d jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare n_atr int := 0; n_fil int := 0; n_sku int := 0; r record; k int;
begin
  if d ? 'atributos' then
    insert into catalogo.atributos (clave, nombre, tipo, unidad)
    select x.clave, x.nombre, x.tipo, x.unidad from jsonb_to_recordset(d -> 'atributos') as x(clave text, nombre text, tipo text, unidad text)
    on conflict (clave) do update set nombre = excluded.nombre, tipo = excluded.tipo, unidad = excluded.unidad;
    get diagnostics n_atr = row_count;
  end if;

  if d ? 'filtros' then
    insert into catalogo.atributos_categoria (categoria_id, atributo_id, orden, obligatorio, define_variante)
    select c.id, a.id, x.orden, x.obligatorio, x.define_variante
    from jsonb_to_recordset(d -> 'filtros') as x(categoria text, clave text, orden int, obligatorio boolean, define_variante boolean)
    join catalogo.categorias c on c.ruta = x.categoria
    join catalogo.atributos a  on a.clave = x.clave
    on conflict (categoria_id, atributo_id) do update set orden = excluded.orden, obligatorio = excluded.obligatorio,
       define_variante = excluded.define_variante, es_filtro = true;
    get diagnostics n_fil = row_count;
  end if;

  if d ? 'parches' then
    for r in select p -> 0 as specs, array(select jsonb_array_elements_text(p -> 1)) as codigos
             from jsonb_array_elements(d -> 'parches') p loop
      update catalogo.skus set specs = specs || r.specs where codigo = any(r.codigos);
      get diagnostics k = row_count;
      n_sku := n_sku + k;
    end loop;
  end if;

  return jsonb_build_object('atributos', n_atr, 'filtros', n_fil, 'skus', n_sku);
end $$;
revoke all on function catalogo.cargar_atributos(jsonb) from public, anon, authenticated;
