-- =====================================================================
--  32 · ESTADÍSTICAS SIN BOTS, VENEZUELA PRIMERO (Panel web → Estadísticas)
-- ---------------------------------------------------------------------
--  Muchas visitas de otros países son bots: entran a 1 página, sin cuenta
--  y se van en segundos (en 30 días, ~500 visitas de bots frente a ~770
--  reales). Inflaban Visitantes, Búsquedas y clientes, y Página de enlaces.
--
--  · public.visitas_bot(desde, hasta): las visitas de bots del período.
--    Bot = fuera de Venezuela, sin cuenta, 1 sola página y <=10 s.
--    Mismo criterio que la vista en_linea_clasificada, el filtro de SuinBot
--    y la pantalla En vivo.
--
--  · resumen_visitantes · resumen_estadisticas · resumen_links reciben un
--    parámetro nuevo p_sin_bots (por defecto false = igual que antes):
--      - con p_sin_bots => true no cuentan los eventos de esas visitas;
--      - devuelven además "bots": cuántas visitas de bots se dejaron fuera;
--      - "¿De qué país?" y "¿De qué ciudad?" ponen Venezuela primero.
--
--  Las llamadas viejas (dias, p_desde, p_hasta) siguen funcionando igual.
--  Requiere 28. Seguro de correr varias veces (si ya está, no toca nada).
-- =====================================================================

create or replace function public.visitas_bot(desde timestamptz, hasta timestamptz)
returns setof text
language sql stable security definer
set search_path to 'public'
as $$
  select visita from eventos
   where creado >= desde and creado < hasta and visita is not null
   group by visita
  having not coalesce(bool_or(pais = 'VE'), false)
     and not coalesce(bool_or(cliente_email is not null), false)
     and count(distinct pagina) <= 1
     and max(creado) - min(creado) <= interval '10 seconds'
     and max(creado) < now() - interval '1 minute'    -- una visita que acaba de empezar todavía no se juzga
$$;
revoke all on function public.visitas_bot(timestamptz, timestamptz) from public, anon, authenticated;

do $$
declare
  f text;
  d text;
  antes text;
  firma_vieja constant text := '(dias integer DEFAULT 30, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date)';
  firma_nueva constant text := '(dias integer DEFAULT 30, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_sin_bots boolean DEFAULT false)';
  decl_hasta  constant text := $t$'infinity'::timestamptz);$t$;
  decl_bots   constant text := $t$'infinity'::timestamptz);
  v_bots text[] := case when p_sin_bots then array(select public.visitas_bot(desde, hasta)) else '{}'::text[] end;$t$;
begin
  foreach f in array array['resumen_visitantes', 'resumen_estadisticas', 'resumen_links'] loop
    select pg_get_functiondef(p.oid) into d
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = f
       and pg_get_function_identity_arguments(p.oid) = 'dias integer, p_desde date, p_hasta date';
    if d is null then continue; end if;   -- ya tiene p_sin_bots (o falta la 28)

    if position(firma_vieja in d) = 0 or position(decl_hasta in d) = 0 then
      raise exception 'La función % no tiene la forma esperada; no se cambió nada.', f;
    end if;
    d := replace(d, firma_vieja, firma_nueva);
    d := replace(d, decl_hasta, decl_bots);

    antes := d;
    if f = 'resumen_estadisticas' then
      d := replace(d, 'and c.es_admin)', 'and c.es_admin) and not coalesce(e.visita = any(v_bots), false)');
      d := replace(d, 'return jsonb_build_object(', $t$return jsonb_build_object('bots', cardinality(v_bots)) || jsonb_build_object($t$);
    elsif f = 'resumen_visitantes' then
      d := replace(d, 'and cliente_email is null and visitante is not null and visita is not null',
                      'and cliente_email is null and visitante is not null and visita is not null and not (visita = any(v_bots))');
      d := replace(d, 'return (', $t$return jsonb_build_object('bots', cardinality(v_bots)) || ($t$);
    else -- resumen_links
      d := replace(d, 'and creado < hasta and visitante is not null and visita is not null',
                      'and creado < hasta and visitante is not null and visita is not null and not (visita = any(v_bots))');
      d := replace(d, 'return (', $t$return jsonb_build_object('bots', cardinality(v_bots)) || ($t$);
    end if;
    if position('v_bots)' in d) = 0 or position('any(v_bots)' in d) = 0 then
      raise exception 'La función % no tiene la forma esperada; no se cambió nada.', f;
    end if;

    -- Venezuela primero en países y ciudades (solo cuando se piden sin bots)
    d := replace(d, 'group by pais order by count(*) desc', $t$group by pais order by (p_sin_bots and pais = 'VE') desc, count(*) desc$t$);
    d := replace(d, 'group by pais, region, ciudad order by count(*) desc', $t$group by pais, region, ciudad order by (p_sin_bots and pais = 'VE') desc, count(*) desc$t$);

    execute format('drop function public.%I(integer, date, date)', f);
    execute d;
    execute format('revoke all on function public.%I(integer, date, date, boolean) from public, anon, authenticated', f);
    execute format('grant execute on function public.%I(integer, date, date, boolean) to authenticated, service_role', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
