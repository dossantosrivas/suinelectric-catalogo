-- =====================================================================
--  28 · ESTADÍSTICAS POR RANGO DE FECHAS (Panel web → Estadísticas)
-- ---------------------------------------------------------------------
--  Las pestañas de Estadísticas (Búsquedas y clientes, Visitantes y
--  Página de enlaces) solo dejaban ver "últimos N días". Ahora además se
--  puede pedir desde qué fecha y hasta qué fecha (hora de Venezuela):
--
--    select public.resumen_visitantes(p_desde => '2026-10-01');
--    select public.resumen_visitantes(p_desde => '2026-10-01', p_hasta => '2026-10-15');
--
--  · p_desde: primer día incluido. Si no se manda, se usa "dias" como antes.
--  · p_hasta: último día incluido. Si no se manda, llega hasta ahora.
--
--  Se le agregan los dos parámetros a estas cuatro funciones, sin tocar
--  nada más de lo que calculan:
--    resumen_visitantes · resumen_estadisticas · resumen_links · clientes_activos
--  Las llamadas viejas (solo "dias") siguen funcionando igual.
--
--  Requiere 04, 06, 10 y 12. Seguro de correr varias veces (si la función
--  ya tiene los parámetros, no la toca).
-- =====================================================================

do $$
declare
  f text;
  d text;
  viejo_decl constant text := 'declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));';
  nuevo_decl constant text :=
    'declare desde timestamptz := coalesce(p_desde::timestamp at time zone ''America/Caracas'', now() - make_interval(days => greatest(1, least(dias, 365))));' || chr(10) ||
    '  hasta timestamptz := coalesce((p_hasta + 1)::timestamp at time zone ''America/Caracas'', ''infinity''::timestamptz);';
begin
  foreach f in array array['resumen_visitantes', 'resumen_estadisticas', 'resumen_links', 'clientes_activos'] loop
    select pg_get_functiondef(p.oid) into d
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.proname = f
      and pg_get_function_identity_arguments(p.oid) = 'dias integer';
    if d is null then continue; end if;   -- ya tiene el rango de fechas

    if position('(dias integer DEFAULT 30)' in d) = 0 or position(viejo_decl in d) = 0 or position('creado >= desde' in d) = 0 then
      raise exception 'La función % no tiene la forma esperada; no se cambió nada.', f;
    end if;

    d := replace(d, '(dias integer DEFAULT 30)', '(dias integer DEFAULT 30, p_desde date DEFAULT NULL, p_hasta date DEFAULT NULL)');
    d := replace(d, viejo_decl, nuevo_decl);
    d := replace(d, 'creado >= desde', 'creado >= desde and creado < hasta');

    execute format('drop function public.%I(integer)', f);
    execute d;
    execute format('revoke all on function public.%I(integer, date, date) from public, anon, authenticated', f);
    execute format('grant execute on function public.%I(integer, date, date) to authenticated, service_role', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
