create sequence if not exists public.scraping_ejecuciones_id_seq as bigint start 1 increment 1 minvalue 1 maxvalue 9223372036854775807;
create sequence if not exists public.scraping_movimientos_id_seq as bigint start 1 increment 1 minvalue 1 maxvalue 9223372036854775807;
create sequence if not exists public.scraping_precios_id_seq as bigint start 1 increment 1 minvalue 1 maxvalue 9223372036854775807;
create table public.adm_registros (coleccion text not null, id text not null, data jsonb not null, borrado boolean default false not null, actualizado timestamp with time zone default now() not null, actualizado_por uuid default auth.uid());
create table public.adm_usuarios (email text not null);
create table public.avisos_eventos (clave text not null, nombre text not null, detalle text, activo boolean default false not null, orden integer default 0 not null);
create table public.chat_conversaciones (id bigint generated always as identity not null, token uuid not null, nombre text, contacto text, email text, pagina text, estado text default 'abierta'::text not null, creado timestamp with time zone default now() not null, ultimo timestamp with time zone default now() not null, ia_activa boolean default true not null, ia_ocupada_hasta timestamp with time zone);
create table public.chat_mensajes (id bigint generated always as identity not null, conversacion_id bigint not null, autor text not null, texto text not null, creado timestamp with time zone default now() not null);
create table public.clientes (email text not null, user_id uuid, nombre text, empresa text, rif text, telefono text, direccion text, tipo_id text default 'final'::text, es_admin boolean default false not null, activo boolean default true not null, creado timestamp with time zone default now() not null, actualizado timestamp with time zone default now() not null, ver_existencias boolean default false not null);
create table public.en_linea (visitante text not null, visita text, cliente_email text, pagina text, titulo text, accion text, accion_en timestamp with time zone, paginas integer default 1 not null, pais text, region text, ciudad text, proveedor text, dispositivo text, navegador text, sistema text, referencia text, activo boolean default true not null, entro timestamp with time zone default now() not null, visto timestamp with time zone default now() not null);
create table public.eventos (id bigint generated always as identity not null, tipo text not null, texto text, modelo text, resultados integer, cantidad integer, cliente_email text, origen text, creado timestamp with time zone default now() not null, visitante text, visita text, pais text, region text, ciudad text, proveedor text, dispositivo text, navegador text, sistema text, referencia text, pagina text, modelos text[]);
create table public.existencias (modelo text not null, cantidad integer not null, actualizado timestamp with time zone default now() not null);
create table public.inventario_web (modelo text not null, marca text, nombre text, descripcion text, categoria text, precio numeric, stock text not null, actualizado timestamp with time zone default now() not null);
create table public.inventario_web_cant (modelo text not null, cantidad integer not null);
create table public.ml_questions (question_id bigint not null, item_id text, item_title text, question_text text, buyer_id bigint, tg_message_id bigint, status text default 'pending'::text not null, answer_text text, created_at timestamp with time zone default now() not null, answered_at timestamp with time zone);
create table public.ml_tokens (id integer default 1 not null, access_token text not null, refresh_token text not null, expires_at timestamp with time zone not null, user_id bigint not null, updated_at timestamp with time zone default now() not null);
create table public.pedidos (id bigint generated always as identity not null, cliente_email text not null, estado text default 'enviado'::text not null, items jsonb not null, total numeric(12,2), nota_cliente text, nota_admin text, creado timestamp with time zone default now() not null, actualizado timestamp with time zone default now() not null, archivado boolean default false not null, archivado_en timestamp with time zone);
create table public.productos_busqueda (modelo text not null, marca text, categoria text, descripcion text, disponible boolean default true not null, disponibilidad text, url text, texto text not null);
create table public.productos_ocultos (modelo text not null, motivo text, creado timestamp with time zone default now() not null, por text);
create table public.productos_web (modelo text not null, nombre text, marca text not null, categoria_principal text not null, subcategorias text[] default '{}'::text[] not null, descripcion text, precio numeric, disponible boolean default true not null, existencias integer, imagenes text[] default '{}'::text[] not null, notas text, activo boolean default true not null, creado timestamp with time zone default now() not null, actualizado timestamp with time zone default now() not null, creado_por text);
create table public.reglas_descuento (id bigint generated always as identity not null, cliente_email text, tipo_id text, marca text, modelo text, descuento_pct numeric(5,2), precio_fijo numeric(12,2), activo boolean default true not null, nota text, creado timestamp with time zone default now() not null);
create table public.scraping_ejecuciones (id bigint default nextval('scraping_ejecuciones_id_seq'::regclass) not null, fecha timestamp with time zone default now() not null, generado timestamp with time zone, productos integer default 0 not null, bajaron integer default 0 not null, subieron integer default 0 not null, nuevos integer default 0 not null, desaparecidos integer default 0 not null, agotados integer default 0 not null, unidades_restadas integer default 0 not null, unidades_sumadas integer default 0 not null, primera boolean default false not null, nota text, precios_subieron integer default 0 not null, precios_bajaron integer default 0 not null);
create table public.scraping_movimientos (id bigint default nextval('scraping_movimientos_id_seq'::regclass) not null, ejecucion_id bigint not null, fecha timestamp with time zone default now() not null, modelo text not null, marca text, nombre text, precio numeric, antes integer, despues integer, diferencia integer, tipo text not null);
create table public.scraping_precios (id bigint default nextval('scraping_precios_id_seq'::regclass) not null, ejecucion_id bigint not null, fecha timestamp with time zone default now() not null, modelo text not null, marca text, nombre text, precio_antes numeric not null, precio_despues numeric not null, diferencia numeric not null, porcentaje numeric);
create table public.scraping_ultimo (modelo text not null, cantidad integer not null, marca text, nombre text, precio numeric);
create table public.tipos_cliente (id text not null, nombre text not null, orden integer default 0 not null, ver_existencias boolean default false not null);
alter sequence public.scraping_ejecuciones_id_seq owned by public.scraping_ejecuciones.id;
alter sequence public.scraping_movimientos_id_seq owned by public.scraping_movimientos.id;
alter sequence public.scraping_precios_id_seq owned by public.scraping_precios.id;
CREATE OR REPLACE FUNCTION public.actividad_cliente(p_email text, dias integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
  em text := lower(trim(p_email));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (
        select tipo, count(*) n from eventos where cliente_email = em and creado >= desde group by tipo) t),
    'envios', (select count(distinct date_trunc('minute', creado)) from eventos
               where cliente_email = em and creado >= desde and tipo = 'pedido_whatsapp'),
    'dias_activos', (select count(distinct (creado at time zone 'America/Caracas')::date) from eventos
                     where cliente_email = em and creado >= desde),
    'primera', (select min(creado) from eventos where cliente_email = em),
    'ultima',  (select max(creado) from eventos where cliente_email = em),
    'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, min(resultados) resultados, max(creado) ultima from eventos
        where cliente_email = em and creado >= desde and tipo = 'busqueda' and texto is not null
        group by texto order by count(*) desc, max(creado) desc limit 40) x),
    'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo, count(*) veces, max(creado) ultima from eventos
        where cliente_email = em and creado >= desde and tipo = 'ver_producto' and modelo is not null
        group by modelo order by count(*) desc, max(creado) desc limit 40) x),
    'cotizados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo,
               count(*) filter (where tipo = 'agregar_carrito')  carrito,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(*) filter (where tipo = 'pedido_whatsapp')  pedidos,
               max(cantidad) cantidad, max(creado) ultima
        from eventos
        where cliente_email = em and creado >= desde and modelo is not null
          and tipo in ('agregar_carrito','cotizar_whatsapp','pedido_whatsapp')
        group by modelo order by count(*) desc, max(creado) desc limit 40) x),
    'recientes', (select coalesce(jsonb_agg(x order by x.creado desc), '[]'::jsonb) from (
        select tipo, texto, modelo, resultados, cantidad, origen, creado from eventos
        where cliente_email = em and creado >= desde
        order by creado desc limit 80) x)
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.actividad_visitante(p_visitante text, dias integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (select * from eventos where visitante = p_visitante and creado >= desde)
    select jsonb_build_object(
      'primera', (select min(creado) from eventos where visitante = p_visitante),
      'ultima',  (select max(creado) from eventos where visitante = p_visitante),
      'correos', (select coalesce(jsonb_agg(distinct cliente_email), '[]'::jsonb) from eventos
                  where visitante = p_visitante and cliente_email is not null),
      'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (select tipo, count(*) n from ev group by tipo) t),
      'n_tarjetas', (select coalesce(sum(cardinality(modelos)), 0) from ev where tipo = 'ver_tarjetas'),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select ev.visita, min(creado) inicio, max(creado) fin, count(*) eventos,
                 (array_agg(pais order by creado)        filter (where tipo = 'visita'))[1] pais,
                 (array_agg(region order by creado)      filter (where tipo = 'visita'))[1] region,
                 (array_agg(ciudad order by creado)      filter (where tipo = 'visita'))[1] ciudad,
                 (array_agg(proveedor order by creado)   filter (where tipo = 'visita'))[1] proveedor,
                 (array_agg(dispositivo order by creado) filter (where tipo = 'visita'))[1] dispositivo,
                 (array_agg(navegador order by creado)   filter (where tipo = 'visita'))[1] navegador,
                 (array_agg(sistema order by creado)     filter (where tipo = 'visita'))[1] sistema,
                 (array_agg(referencia order by creado)  filter (where tipo = 'visita'))[1] referencia,
                 (array_agg(pagina order by creado)      filter (where tipo = 'visita'))[1] pagina
          from ev where ev.visita is not null group by ev.visita order by min(creado) desc limit 60) x),
      'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) veces, min(resultados) resultados, max(creado) ultima from ev
          where tipo = 'busqueda' and texto is not null group by texto order by count(*) desc, max(creado) desc limit 40) x),
      'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select modelo, count(*) veces, max(creado) ultima from ev
          where tipo = 'ver_producto' and modelo is not null group by modelo order by count(*) desc, max(creado) desc limit 40) x),
      'tarjetas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select m modelo, count(*) veces, max(creado) ultima from ev, unnest(modelos) m
          where tipo = 'ver_tarjetas' group by m order by count(*) desc, max(creado) desc limit 60) x),
      'recientes', (select coalesce(jsonb_agg(x order by x.creado desc), '[]'::jsonb) from (
          select tipo, texto, modelo, modelos, resultados, cantidad, origen, pagina, visita, cliente_email, creado from ev
          order by creado desc limit 300) x)
    )
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.adm_es_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(public.es_admin(), false)
      or exists (select 1 from public.adm_usuarios u where lower(u.email) = lower(auth.jwt() ->> 'email'));
$function$
;
CREATE OR REPLACE FUNCTION public.adm_tocar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin new.actualizado := now(); new.actualizado_por := auth.uid(); return new; end $function$
;
CREATE OR REPLACE FUNCTION public.al_registrarse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.clientes (email, user_id)
  values (lower(new.email), new.id)
  on conflict (email) do update set user_id = excluded.user_id;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.avisar_chat()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c        public.chat_conversaciones;
  primero  boolean;
  wa       text;
begin
  if new.autor <> 'cliente' then return new; end if;
  select * into c from public.chat_conversaciones where id = new.conversacion_id;
  if c.ia_activa then return new; end if;
  primero := not exists (select 1 from public.chat_mensajes
                          where conversacion_id = new.conversacion_id and id < new.id);
  wa := public.tg_wa(c.contacto);

  perform public.notificar_telegram(
    '💬 <b>Chat #' || c.id || '</b> · ' || coalesce(public.tg_esc(c.nombre), 'Visitante') ||
    case when primero then
      coalesce(chr(10) || '📱 ' || public.tg_esc(c.contacto), '') ||
      coalesce(chr(10) || '✉️ ' || public.tg_esc(c.email), '') ||
      coalesce(chr(10) || '📄 ' || public.tg_esc(c.pagina), '')
    else '' end ||
    chr(10) || chr(10) || public.tg_esc(new.texto) ||
    case when primero then
      chr(10) || chr(10) || '<i>↩️ Responde a este mensaje para contestarle en la tienda.</i>' ||
      coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', '')
    else '' end);
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.avisar_cliente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  wa text;
begin
  -- Cuenta nueva: la ficha queda enlazada a un usuario que acaba de entrar.
  -- (Los clientes que tú precargas desde el panel no avisan hasta que entren.)
  if new.user_id is not null
     and (tg_op = 'INSERT' or old.user_id is null) then
    perform public.notificar_telegram(
      '🆕 <b>Cuenta nueva en la tienda</b>' || chr(10) ||
      public.tg_esc(new.email) || chr(10) ||
      coalesce(public.tg_esc(new.nombre) || chr(10), '') ||
      '🕒 ' || public.tg_hora());
  end if;

  -- Registro completo: el cliente escribió su nombre por primera vez.
  if tg_op = 'UPDATE' and coalesce(old.nombre, '') = '' and coalesce(new.nombre, '') <> '' then
    wa := public.tg_wa(new.telefono);
    perform public.notificar_telegram(
      '✍️ <b>Cliente completó su registro</b>' || chr(10) ||
      '<b>' || public.tg_esc(new.nombre) || '</b>' || chr(10) ||
      public.tg_esc(new.email) ||
      coalesce(chr(10) || 'RIF: ' || public.tg_esc(nullif(new.rif, '')), '') ||
      coalesce(chr(10) || 'Tel: ' || public.tg_esc(nullif(new.telefono, '')), '') ||
      coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', ''));
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.avisar_evento()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  quien text;
  lugar text;
  c     clientes;
  prod  text;
  txt   text;
  url   text := 'https://suinelectric.com/admin.html#envivo';
begin
  -- Lo que hacen los administradores no avisa.
  if new.cliente_email is not null then
    select * into c from clientes where email = new.cliente_email;
    if c.es_admin then return null; end if;
  end if;
  if new.tipo = 'ver_tarjetas' or new.tipo = 'ver_producto' then return null; end if;

  quien := case when c.email is not null
                then '👤 <b>' || tg_esc(coalesce(nullif(c.nombre, ''), nullif(c.empresa, ''), c.email)) || '</b>' ||
                     coalesce(' · ' || tg_esc(nullif(c.empresa, '')), '')
                else '🌐 Visitante ' || upper(left(replace(coalesce(new.visitante, ''), '-', ''), 6)) end;
  lugar := case when new.tipo = 'visita'
                then nullif(concat_ws(' · ',
                       nullif(concat_ws(', ', new.ciudad, case when new.region is distinct from new.ciudad then new.region end,
                                        case when new.pais is distinct from 'VE' then new.pais end), ''),
                       new.dispositivo, case when new.referencia is not null then 'llegó por ' || new.referencia end), '')
                else tg_lugar(new.visita) end;
  prod := tg_esc(new.modelo);

  if new.tipo = 'agregar_carrito' and aviso_activo('carrito')
     and not exists (select 1 from eventos where visita = new.visita and tipo = 'agregar_carrito' and id <> new.id) then
    txt := '🛒 <b>Agregó al pedido</b> ' || coalesce(new.cantidad || ' × ', '') || coalesce(prod, '');

  elsif (new.tipo = 'cotizar_whatsapp' or (new.tipo = 'clic_enlace' and new.texto ilike 'whatsapp%')
         -- el carrito enviado llega como un evento por producto: un solo aviso; y si tiene cuenta ya avisa el pedido (07)
         or (new.tipo = 'pedido_whatsapp' and new.cliente_email is null
             and not exists (select 1 from eventos where visita = new.visita and tipo = 'pedido_whatsapp' and id <> new.id
                             and creado >= now() - interval '10 minutes')))
     and aviso_activo('whatsapp')
     and (new.tipo = 'pedido_whatsapp'
          or not exists (select 1 from eventos where visita = new.visita and id <> new.id and tipo = new.tipo
                         and modelo is not distinct from new.modelo and texto is not distinct from new.texto)) then
    txt := '💬 <b>' || case new.tipo
             when 'cotizar_whatsapp' then 'Pidió precio por WhatsApp</b> de ' || coalesce(prod, 'un producto')
             when 'pedido_whatsapp'  then 'Envió su pedido por WhatsApp</b>' || coalesce(' (' || prod || '…)', '')
             else 'Tocó ' || tg_esc(new.texto) || '</b> en la página de enlaces' end;

  elsif new.tipo = 'busqueda' and coalesce(new.resultados, -1) = 0 and new.texto is not null and aviso_activo('sin_resultados')
     and not exists (select 1 from eventos where tipo = 'busqueda' and resultados = 0 and texto = new.texto
                     and id <> new.id and creado >= now() - interval '1 day') then
    txt := '🔎 <b>Buscó y no encontró:</b> “' || tg_esc(new.texto) || '”';

  elsif new.tipo = 'visita' and new.cliente_email is not null and aviso_activo('cliente_entra') then
    txt := '🟢 <b>Entró a la tienda</b>' || case when new.pagina ~ '^/p/' then ' (página de ' || tg_esc(substr(new.pagina, 4)) || ')' else '' end;

  elsif new.tipo = 'visita' and new.origen = 'links' and aviso_activo('links') then
    txt := '🔗 <b>Entró a la página de enlaces</b>';

  elsif new.tipo = 'visita' and aviso_activo('visita') then
    txt := '👀 <b>Visita nueva</b>' || coalesce(' en ' || tg_esc(new.pagina), '');
  end if;

  if txt is not null then
    perform notificar_telegram(txt || chr(10) || quien || coalesce(chr(10) || '📍 ' || tg_esc(lugar), '') || chr(10) ||
      '🕒 ' || tg_hora() || ' · <a href="' || url || '">Ver en vivo</a>');
  end if;
  return null;
exception when others then
  raise warning 'avisar_evento: %', sqlerrm;   -- nunca impide guardar el evento
  return null;
end $function$
;
CREATE OR REPLACE FUNCTION public.avisar_pedido()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c       public.clientes;
  lineas  text;
  n       int;
  wa      text;
begin
  select * into c from public.clientes where email = new.cliente_email;
  n := coalesce(jsonb_array_length(new.items), 0);

  select string_agg(
           '• ' || coalesce(it->>'cantidad', '1') || ' × ' || coalesce(public.tg_esc(it->>'modelo'), '?') ||
           coalesce(' — $' || to_char((it->>'precio_unit')::numeric, 'FM999G999G990'), ''),
           chr(10) order by ord)
    into lineas
    from jsonb_array_elements(new.items) with ordinality as x(it, ord)
   where ord <= 12;
  if n > 12 then lineas := lineas || chr(10) || '… y ' || (n - 12) || ' más'; end if;

  wa := public.tg_wa(c.telefono);
  perform public.notificar_telegram(
    '🛒 <b>Pedido #' || new.id || '</b>' || chr(10) ||
    '<b>' || public.tg_esc(coalesce(nullif(c.nombre, ''), new.cliente_email)) || '</b>' ||
    coalesce(' · ' || public.tg_esc(nullif(c.empresa, '')), '') || chr(10) ||
    public.tg_esc(new.cliente_email) || chr(10) || chr(10) ||
    coalesce(lineas, '(sin artículos)') || chr(10) || chr(10) ||
    '<b>Total: $' || coalesce(to_char(new.total, 'FM999G999G990D00'), '—') || '</b>' ||
    coalesce(chr(10) || '<a href="' || wa || '">Escribirle por WhatsApp</a>', '') || chr(10) ||
    '🕒 ' || public.tg_hora(new.creado));
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.aviso_activo(k text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select activo from avisos_eventos where clave = k), false)
$function$
;
CREATE OR REPLACE FUNCTION public.borrar_cliente(p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_email text := lower(trim(p_email));
  v_pedidos int := 0;
  v_acceso boolean := false;
begin
  if not public.es_admin() then
    raise exception 'Solo un administrador puede borrar clientes';
  end if;
  if v_email = public.mi_email() then
    raise exception 'No puedes borrar tu propia cuenta de administrador';
  end if;
  delete from public.pedidos where cliente_email = v_email;
  get diagnostics v_pedidos = row_count;
  delete from public.clientes where email = v_email;   -- sus reglas se borran solas
  begin
    delete from auth.users where lower(email) = v_email;
    v_acceso := found;
  exception when others then
    v_acceso := false;  -- si no se pudo, la ficha igual quedó borrada
  end;
  return json_build_object('pedidos_borrados', v_pedidos, 'acceso_borrado', v_acceso);
end $function$
;
CREATE OR REPLACE FUNCTION public.buscar_productos(p_terminos text[], p_marca text DEFAULT NULL::text, p_limite integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with t as (
    select distinct lower(btrim(x)) as x from unnest(coalesce(p_terminos, '{}'::text[])) x
     where length(btrim(x)) >= 2 limit 10
  ), r as (
    select p.*,
           (select count(*) from t where position(' ' || t.x in p.texto) > 0)            -- palabra que empieza así
           + case when exists (select 1 from t where left(p.texto, length(t.x) + 2) = ' ' || t.x || ' ')
                  then 5 else 0 end as puntos                                            -- es el modelo exacto
      from public.productos_busqueda p
     where p_marca is null or p_marca = '' or p.marca ilike p_marca
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'modelo', modelo, 'marca', marca, 'categoria', categoria,
           'descripcion', left(descripcion, 400), 'disponibilidad', disponibilidad, 'url', url)
         order by puntos desc, disponible desc, modelo), '[]'::jsonb)
    from (select * from r where puntos > 0
           order by puntos desc, disponible desc, modelo
           limit greatest(1, least(coalesce(p_limite, 8), 15))) z
$function$
;
CREATE OR REPLACE FUNCTION public.cargar_existencias(datos jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  delete from public.existencias where true;
  insert into public.existencias (modelo, cantidad)
  select key, greatest(0, round((value)::text::numeric))::int
  from jsonb_each(datos)
  where jsonb_typeof(value) = 'number';
  get diagnostics n = row_count;
  return n;
end $function$
;
CREATE OR REPLACE FUNCTION public.cargar_productos_busqueda(datos jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  if jsonb_typeof(datos) <> 'array' or jsonb_array_length(datos) < 100 then
    raise exception 'Catálogo vacío o incompleto: no se reemplaza';
  end if;
  delete from public.productos_busqueda where true;
  insert into public.productos_busqueda (modelo, marca, categoria, descripcion, disponible, disponibilidad, url, texto)
  select distinct on (x->>'modelo')
         x->>'modelo', x->>'marca', x->>'categoria', x->>'descripcion',
         coalesce((x->>'disponible')::boolean, true), x->>'disponibilidad', x->>'url', coalesce(x->>'texto', '')
    from jsonb_array_elements(datos) x
   where coalesce(x->>'modelo', '') <> '';
  get diagnostics n = row_count;
  return n;
end $function$
;
CREATE OR REPLACE FUNCTION public.chat_enviar(p_token uuid, p_texto text, p_nombre text DEFAULT NULL::text, p_contacto text DEFAULT NULL::text, p_pagina text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_conv  public.chat_conversaciones;
  v_texto text := left(btrim(coalesce(p_texto, '')), 1000);
  v_id    bigint;
begin
  if p_token is null or v_texto = '' then
    raise exception 'Mensaje vacío';
  end if;

  select * into v_conv from public.chat_conversaciones where token = p_token;

  if not found then
    -- Freno contra abusos: máximo 40 chats nuevos por hora en toda la tienda.
    if (select count(*) from public.chat_conversaciones where creado > now() - interval '1 hour') >= 40 then
      raise exception 'El chat está muy ocupado, escríbenos por WhatsApp';
    end if;
    insert into public.chat_conversaciones (token, nombre, contacto, email, pagina)
    values (p_token,
            nullif(left(btrim(coalesce(p_nombre, '')), 80), ''),
            nullif(left(btrim(coalesce(p_contacto, '')), 40), ''),
            nullif(public.mi_email(), ''),
            nullif(left(coalesce(p_pagina, ''), 300), ''))
    returning * into v_conv;
  else
    -- Freno por visitante: 6 mensajes por minuto y 60 por hora.
    if (select count(*) from public.chat_mensajes
         where conversacion_id = v_conv.id and autor = 'cliente' and creado > now() - interval '1 minute') >= 6
       or (select count(*) from public.chat_mensajes
         where conversacion_id = v_conv.id and autor = 'cliente' and creado > now() - interval '1 hour') >= 60 then
      raise exception 'Vas muy rápido, espera un momento';
    end if;
    update public.chat_conversaciones
       set nombre   = coalesce(nullif(left(btrim(coalesce(p_nombre, '')), 80), ''), nombre),
           contacto = coalesce(nullif(left(btrim(coalesce(p_contacto, '')), 40), ''), contacto),
           email    = coalesce(email, nullif(public.mi_email(), '')),
           estado   = 'abierta',
           ultimo   = now()
     where id = v_conv.id
     returning * into v_conv;
  end if;

  insert into public.chat_mensajes (conversacion_id, autor, texto)
  values (v_conv.id, 'cliente', v_texto)
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'chat', v_conv.id);
end $function$
;
CREATE OR REPLACE FUNCTION public.chat_guardar_ia(p_chat bigint, p_texto text, p_pasar boolean DEFAULT false, p_hasta bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if coalesce(btrim(p_texto), '') <> '' then
    insert into public.chat_mensajes (conversacion_id, autor, texto)
    values (p_chat, 'asistente', left(btrim(p_texto), 2000));
  end if;
  update public.chat_conversaciones
     set ia_ocupada_hasta = null,
         ia_activa = case when p_pasar then false else ia_activa end,
         ultimo = now()
   where id = p_chat;
  return jsonb_build_object('ok', true,
    'pendiente', exists (select 1 from public.chat_mensajes
                          where conversacion_id = p_chat and autor = 'cliente' and id > coalesce(p_hasta, 0)));
end $function$
;
CREATE OR REPLACE FUNCTION public.chat_ia(p_chat bigint, p_activa boolean)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.chat_conversaciones set ia_activa = p_activa, ia_ocupada_hasta = null where id = p_chat
  returning jsonb_build_object('ok', true, 'chat', id, 'ia', ia_activa, 'nombre', nombre)
$function$
;
CREATE OR REPLACE FUNCTION public.chat_leer(p_token uuid, p_desde bigint DEFAULT 0)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'autor', m.autor, 'texto', m.texto, 'creado', m.creado) order by m.id), '[]'::jsonb)
    from (select m.* from public.chat_mensajes m
            join public.chat_conversaciones c on c.id = m.conversacion_id
           where c.token = p_token and m.id > coalesce(p_desde, 0)
           order by m.id
           limit 200) m
$function$
;
CREATE OR REPLACE FUNCTION public.chat_recientes(p_limite integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(x order by x.ultimo desc), '[]'::jsonb) from (
    select c.id, c.nombre, c.contacto, c.ultimo,
           (select m.autor from public.chat_mensajes m where m.conversacion_id = c.id order by m.id desc limit 1) as ultimo_autor,
           (select left(m.texto, 80) from public.chat_mensajes m where m.conversacion_id = c.id order by m.id desc limit 1) as ultimo_texto
      from public.chat_conversaciones c
     order by c.ultimo desc
     limit greatest(1, least(coalesce(p_limite, 10), 30))
  ) x
$function$
;
CREATE OR REPLACE FUNCTION public.chat_responder(p_chat bigint, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_conv public.chat_conversaciones;
  v_texto text := left(btrim(coalesce(p_texto, '')), 2000);
begin
  select * into v_conv from public.chat_conversaciones where id = p_chat;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'No existe el chat #' || p_chat);
  end if;
  if v_texto = '' then
    return jsonb_build_object('ok', false, 'error', 'Mensaje vacío');
  end if;
  insert into public.chat_mensajes (conversacion_id, autor, texto) values (v_conv.id, 'suinelectric', v_texto);
  update public.chat_conversaciones set ultimo = now(), ia_activa = false, ia_ocupada_hasta = null where id = v_conv.id;
  return jsonb_build_object('ok', true, 'chat', v_conv.id, 'nombre', v_conv.nombre, 'contacto', v_conv.contacto);
end $function$
;
CREATE OR REPLACE FUNCTION public.chat_turno_ia(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c public.chat_conversaciones;
  v_ultimo public.chat_mensajes;
  v_hist jsonb;
begin
  select * into c from public.chat_conversaciones where token = p_token for update;
  if not found or not c.ia_activa then return jsonb_build_object('ok', false, 'motivo', 'ia_apagada'); end if;
  if c.ia_ocupada_hasta is not null and c.ia_ocupada_hasta > now() then
    return jsonb_build_object('ok', false, 'motivo', 'ocupada');
  end if;
  select * into v_ultimo from public.chat_mensajes where conversacion_id = c.id order by id desc limit 1;
  if not found or v_ultimo.autor <> 'cliente' then return jsonb_build_object('ok', false, 'motivo', 'nada_pendiente'); end if;

  update public.chat_conversaciones set ia_ocupada_hasta = now() + interval '45 seconds' where id = c.id;

  select coalesce(jsonb_agg(jsonb_build_object('autor', autor, 'texto', texto) order by id), '[]'::jsonb) into v_hist
    from (select * from public.chat_mensajes where conversacion_id = c.id order by id desc limit 16) m;

  return jsonb_build_object('ok', true, 'chat', c.id, 'nombre', c.nombre, 'contacto', c.contacto,
    'email', c.email, 'pagina', c.pagina, 'hasta', v_ultimo.id,
    'primero', (select count(*) from public.chat_mensajes where conversacion_id = c.id and autor = 'cliente') = 1,
    'historial', v_hist);
end $function$
;
CREATE OR REPLACE FUNCTION public.clientes_activos(dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'con_cuenta', (select count(*) from eventos e where creado >= desde and cliente_email is not null
                     and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)),
    'sin_cuenta', (select count(*) from eventos where creado >= desde and cliente_email is null),
    'clientes', (select coalesce(jsonb_agg(x order by x.total desc, x.ultima desc), '[]'::jsonb) from (
        select cliente_email email,
               count(*) total,
               count(*) filter (where tipo = 'busqueda')         busquedas,
               count(*) filter (where tipo = 'ver_producto')     vistas,
               count(*) filter (where tipo = 'agregar_carrito')  carrito,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(distinct date_trunc('minute', creado)) filter (where tipo = 'pedido_whatsapp') pedidos,
               count(distinct (creado at time zone 'America/Caracas')::date) dias_activos,
               max(creado) ultima
        from eventos e
        where creado >= desde and cliente_email is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by cliente_email
        order by count(*) desc limit 100) x)
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.es_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.clientes
                 where email = public.mi_email() and es_admin and activo)
$function$
;
CREATE OR REPLACE FUNCTION public.estado_existencias()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.es_admin() then return null; end if;
  return (select jsonb_build_object('modelos', count(*), 'actualizado', max(actualizado)) from public.existencias);
end $function$
;
CREATE OR REPLACE FUNCTION public.eventos_completar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.cliente_email := nullif(public.mi_email(), '');
  new.creado := now();
  -- Las búsquedas se guardan en minúsculas (para agruparlas); el resto tal cual.
  new.texto := nullif(case when new.tipo = 'busqueda' then lower(trim(new.texto)) else trim(new.texto) end, '');
  if new.modelos is not null then
    new.modelos := (select array_agg(left(m, 80)) from (select distinct m from unnest(new.modelos[1:100]) m where m is not null and m <> '') x);
  end if;
  if new.tipo <> 'visita' then     -- el lugar y el equipo solo van en el evento "visita"
    new.pais := null; new.region := null; new.ciudad := null; new.proveedor := null;
    new.dispositivo := null; new.navegador := null; new.sistema := null; new.referencia := null;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.existencias_reales()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.puede_ver_existencias() then return null; end if;
  return (select coalesce(jsonb_object_agg(modelo, cantidad), '{}'::jsonb) from public.existencias);
end $function$
;
CREATE OR REPLACE FUNCTION public.inventario_cantidades()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.puede_ver_existencias() then return null; end if;
  return (select coalesce(jsonb_object_agg(modelo, cantidad), '{}'::jsonb) from public.inventario_web_cant);
end $function$
;
CREATE OR REPLACE FUNCTION public.limpiar_eventos()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  if not public.es_admin() then return 0; end if;
  delete from public.eventos where creado < now() - interval '365 days';
  get diagnostics n = row_count;
  return n;
end $function$
;
CREATE OR REPLACE FUNCTION public.marcar_en_linea(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_vis   text := left(nullif(trim(p->>'visitante'), ''), 40);
  v_email text := nullif(public.mi_email(), '');
  v_pag   text := left(nullif(p->>'pagina', ''), 200);
begin
  if v_vis is null then return; end if;
  -- Los administradores no cuentan (tus pruebas no salen en vivo).
  if v_email is not null and exists (select 1 from clientes where email = v_email and es_admin) then return; end if;

  insert into en_linea as e (visitante, visita, cliente_email, pagina, titulo, accion, accion_en, pais, region, ciudad,
                             proveedor, dispositivo, navegador, sistema, referencia, activo, entro, visto)
  values (v_vis, left(p->>'visita', 40), v_email, v_pag, left(nullif(p->>'titulo', ''), 160),
          left(nullif(p->>'accion', ''), 200), case when nullif(p->>'accion', '') is not null then now() end,
          left(nullif(p->>'pais', ''), 60), left(nullif(p->>'region', ''), 80), left(nullif(p->>'ciudad', ''), 80),
          left(nullif(p->>'proveedor', ''), 100), left(nullif(p->>'dispositivo', ''), 20), left(nullif(p->>'navegador', ''), 40),
          left(nullif(p->>'sistema', ''), 40), left(nullif(p->>'referencia', ''), 120),
          not coalesce((p->>'salir')::boolean, false), now(), now())
  on conflict (visitante) do update set
    -- Visita nueva: empieza de cero (entrada, origen y contador de páginas).
    entro      = case when e.visita is distinct from excluded.visita then now() else e.entro end,
    paginas    = case when e.visita is distinct from excluded.visita then 1
                      when excluded.pagina is not null and excluded.pagina is distinct from e.pagina then e.paginas + 1
                      else e.paginas end,
    referencia = case when e.visita is distinct from excluded.visita then excluded.referencia else coalesce(e.referencia, excluded.referencia) end,
    accion     = case when e.visita is distinct from excluded.visita then excluded.accion else coalesce(excluded.accion, e.accion) end,
    accion_en  = case when e.visita is distinct from excluded.visita then excluded.accion_en else coalesce(excluded.accion_en, e.accion_en) end,
    visita        = coalesce(excluded.visita, e.visita),
    cliente_email = coalesce(excluded.cliente_email, e.cliente_email),
    pagina        = coalesce(excluded.pagina, e.pagina),
    titulo        = case when excluded.pagina is not null then excluded.titulo else e.titulo end,
    pais        = coalesce(excluded.pais, e.pais),
    region      = coalesce(excluded.region, e.region),
    ciudad      = coalesce(excluded.ciudad, e.ciudad),
    proveedor   = coalesce(excluded.proveedor, e.proveedor),
    dispositivo = coalesce(excluded.dispositivo, e.dispositivo),
    navegador   = coalesce(excluded.navegador, e.navegador),
    sistema     = coalesce(excluded.sistema, e.sistema),
    activo      = excluded.activo,
    visto       = now();

  -- Limpieza de vez en cuando: quien no da señales hace más de 2 días se borra.
  if random() < 0.02 then
    delete from en_linea where visto < now() - interval '2 days';
  end if;
end $function$
;
CREATE OR REPLACE FUNCTION public.mi_activo()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select activo from public.clientes where email = public.mi_email()), true)
$function$
;
CREATE OR REPLACE FUNCTION public.mi_email()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
$function$
;
CREATE OR REPLACE FUNCTION public.mi_tipo()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select tipo_id from public.clientes where email = public.mi_email()
$function$
;
CREATE OR REPLACE FUNCTION public.movimientos_scraping(p_ejecucion bigint DEFAULT NULL::bigint, p_modelo text DEFAULT NULL::text, dias integer DEFAULT 30, p_tipo text DEFAULT NULL::text, limite integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.es_admin() then return null; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(m) order by m.fecha desc, m.diferencia nulls last)
    from (
      select id, ejecucion_id, fecha, modelo, marca, nombre, precio, antes, despues, diferencia, tipo
      from public.scraping_movimientos
      where (p_ejecucion is null or ejecucion_id = p_ejecucion)
        and (p_modelo is null or modelo = p_modelo)
        and (p_ejecucion is not null or p_modelo is not null
             or fecha >= now() - make_interval(days => greatest(1, least(dias, 400))))
        and (p_tipo is null or tipo = p_tipo)
      order by fecha desc, diferencia nulls last
      limit greatest(1, least(limite, 5000))
    ) m), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.notificar_telegram(texto text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_token text;
  v_chat  text;
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'telegram_token';
  select decrypted_secret into v_chat  from vault.decrypted_secrets where name = 'telegram_chat_id';
  if v_token is null or v_chat is null or coalesce(texto, '') = '' then
    return;
  end if;
  perform net.http_post(
    url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body    := jsonb_build_object(
                 'chat_id', v_chat,
                 'text', left(texto, 4000),
                 'parse_mode', 'HTML',
                 'disable_web_page_preview', true),
    timeout_milliseconds := 20000
  );
exception when others then
  raise warning 'notificar_telegram: %', sqlerrm;
end $function$
;
CREATE OR REPLACE FUNCTION public.precios_scraping(p_ejecucion bigint DEFAULT NULL::bigint, p_modelo text DEFAULT NULL::text, dias integer DEFAULT 30, p_sentido text DEFAULT NULL::text, limite integer DEFAULT 1000)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.es_admin() then return null; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(p) order by p.fecha desc, abs(p.porcentaje) desc nulls last)
    from (
      select id, ejecucion_id, fecha, modelo, marca, nombre, precio_antes, precio_despues, diferencia, porcentaje
      from public.scraping_precios
      where (p_ejecucion is null or ejecucion_id = p_ejecucion)
        and (p_modelo is null or modelo = p_modelo)
        and (p_ejecucion is not null or p_modelo is not null
             or fecha >= now() - make_interval(days => greatest(1, least(dias, 400))))
        and (p_sentido is null or (p_sentido = 'subio' and diferencia > 0) or (p_sentido = 'bajo' and diferencia < 0))
      order by fecha desc, abs(porcentaje) desc nulls last
      limit greatest(1, least(limite, 5000))
    ) p), '[]'::jsonb);
end $function$
;
CREATE OR REPLACE FUNCTION public.productos_ocultos_completar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.creado := now(); new.por := public.mi_email();
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.productos_web_completar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  new.modelo := trim(new.modelo);
  new.marca := upper(trim(new.marca));
  new.actualizado := now();
  if tg_op = 'INSERT' then new.creado := now(); new.creado_por := public.mi_email(); end if;
  new.subcategorias := coalesce((select array_agg(trim(s)) from unnest(new.subcategorias) s where trim(s) <> ''), '{}');
  new.imagenes := coalesce((select array_agg(i) from unnest(new.imagenes[1:8]) i where i is not null and i <> ''), '{}');
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.proteger_cliente()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if current_user in ('anon', 'authenticated') and not public.es_admin() then
    new.email           := old.email;
    new.user_id         := old.user_id;
    new.tipo_id         := old.tipo_id;
    new.es_admin        := old.es_admin;
    new.activo          := old.activo;
    new.creado          := old.creado;
    new.ver_existencias := old.ver_existencias;
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.publicar_inventario_web(datos jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  if not public.adm_es_admin() then raise exception 'Sin permiso'; end if;
    if jsonb_typeof(datos) <> 'array' then raise exception 'Formato inválido'; end if;

      create temp table _inv on commit drop as
        select distinct on (lower(trim(x->>'modelo')))
                 left(trim(x->>'modelo'), 80)                                   as modelo,
                          nullif(left(upper(trim(coalesce(x->>'marca', ''))), 80), '')    as marca,
                                   nullif(left(trim(coalesce(x->>'nombre', '')), 200), '')         as nombre,
                                            nullif(left(trim(coalesce(x->>'descripcion', '')), 4000), '')   as descripcion,
                                                     nullif(left(trim(coalesce(x->>'categoria', '')), 120), '')      as categoria,
                                                              case when jsonb_typeof(x->'precio') = 'number' and (x->>'precio')::numeric > 0
                                                                            then (x->>'precio')::numeric end                           as precio,
                                                                                     greatest(0, round((x->>'cantidad')::numeric))::int              as cantidad
                                                                                       from jsonb_array_elements(datos) x
                                                                                         where coalesce(trim(x->>'modelo'), '') <> ''
                                                                                             and jsonb_typeof(x->'cantidad') = 'number'
                                                                                                 and (x->>'cantidad')::numeric >= 0;

                                                                                                   delete from public.inventario_web w where not exists (select 1 from _inv i where i.modelo = w.modelo);

                                                                                                     insert into public.inventario_web as w (modelo, marca, nombre, descripcion, categoria, precio, stock, actualizado)
                                                                                                       select modelo, marca, nombre, descripcion, categoria, precio,
                                                                                                                case when cantidad > 10 then '+10' when cantidad >= 1 then 'pocas' else 'pedido' end, now()
                                                                                                                  from _inv
                                                                                                                    on conflict (modelo) do update set
                                                                                                                        marca = excluded.marca, nombre = excluded.nombre, descripcion = excluded.descripcion,
                                                                                                                            categoria = excluded.categoria, precio = excluded.precio, stock = excluded.stock,
                                                                                                                                actualizado = case when (w.marca, w.nombre, w.descripcion, w.categoria, w.precio, w.stock)
                                                                                                                                                         is distinct from
                                                                                                                                                                                 (excluded.marca, excluded.nombre, excluded.descripcion, excluded.categoria, excluded.precio, excluded.stock)
                                                                                                                                                                                                        then now() else w.actualizado end;

                                                                                                                                                                                                          insert into public.inventario_web_cant (modelo, cantidad)
                                                                                                                                                                                                            select modelo, cantidad from _inv
                                                                                                                                                                                                              on conflict (modelo) do update set cantidad = excluded.cantidad;

                                                                                                                                                                                                                select count(*) into n from _inv;
                                                                                                                                                                                                                  return n;
                                                                                                                                                                                                                  end $function$
;
CREATE OR REPLACE FUNCTION public.puede_ver_existencias()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.clientes c
    left join public.tipos_cliente t on t.id = c.tipo_id
    where c.email = public.mi_email()
      and c.activo
      and (c.es_admin or c.ver_existencias or coalesce(t.ver_existencias, false))
  )
$function$
;
CREATE OR REPLACE FUNCTION public.registrar_scraping(p_productos jsonb, p_generado timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  eid       bigint;
  n_nuevo   integer;
  n_antes   integer;
  es_primera boolean;
  r         public.scraping_ejecuciones;
begin
  create temp table if not exists _scr_nuevo (modelo text primary key, cantidad integer, marca text, nombre text, precio numeric) on commit drop;
  truncate _scr_nuevo;
  insert into _scr_nuevo
  select distinct on (x.modelo) x.modelo, greatest(0, x.cantidad), x.marca, x.nombre, x.precio
  from jsonb_to_recordset(coalesce(p_productos, '[]'::jsonb)) as x(modelo text, cantidad integer, marca text, nombre text, precio numeric)
  where x.modelo is not null and x.modelo <> '' and x.cantidad is not null
  order by x.modelo;

  select count(*) into n_nuevo from _scr_nuevo;
  select count(*) into n_antes from public.scraping_ultimo;
  es_primera := n_antes = 0;

  -- Protección: si el scraping trajo muy pocos productos (falló a medias),
  -- no se compara ni se reemplaza la foto, para no registrar bajas falsas.
  if n_nuevo = 0 or (not es_primera and n_nuevo < n_antes * 0.6) then
    insert into public.scraping_ejecuciones (generado, productos, nota)
    values (p_generado, n_nuevo,
            'Omitido: llegaron ' || n_nuevo || ' productos y la corrida anterior tenía ' || n_antes || '. Parece un scraping incompleto.')
    returning * into r;
    return to_jsonb(r);
  end if;

  insert into public.scraping_ejecuciones (generado, productos, primera)
  values (p_generado, n_nuevo, es_primera)
  returning id into eid;

  if not es_primera then
    insert into public.scraping_movimientos (ejecucion_id, modelo, marca, nombre, precio, antes, despues, diferencia, tipo)
    select eid,
           coalesce(n.modelo, u.modelo),
           coalesce(n.marca, u.marca),
           coalesce(n.nombre, u.nombre),
           coalesce(n.precio, u.precio),
           u.cantidad, n.cantidad,
           case when u.modelo is not null and n.modelo is not null then n.cantidad - u.cantidad end,
           case when u.modelo is null then 'nuevo'
                when n.modelo is null then 'desaparecio'
                when n.cantidad < u.cantidad then 'bajo'
                else 'subio' end
    from _scr_nuevo n
    full join public.scraping_ultimo u on u.modelo = n.modelo
    where u.modelo is null or n.modelo is null or n.cantidad <> u.cantidad;

    -- Cambios de precio (solo si hay precio antes y después; se ignoran diferencias de centavos por redondeo).
    insert into public.scraping_precios (ejecucion_id, modelo, marca, nombre, precio_antes, precio_despues, diferencia, porcentaje)
    select eid, n.modelo, coalesce(n.marca, u.marca), coalesce(n.nombre, u.nombre),
           u.precio, n.precio, round(n.precio - u.precio, 2),
           case when u.precio > 0 then round(100 * (n.precio - u.precio) / u.precio, 1) end
    from _scr_nuevo n
    join public.scraping_ultimo u on u.modelo = n.modelo
    where n.precio is not null and u.precio is not null
      and abs(n.precio - u.precio) >= 0.01;
  end if;

  -- Si esta vez un producto vino sin precio, conserva el anterior para la próxima comparación.
  update _scr_nuevo n set precio = u.precio
  from public.scraping_ultimo u
  where u.modelo = n.modelo and n.precio is null;

  -- Reemplaza la foto con la de ahora.
  delete from public.scraping_ultimo where true;
  insert into public.scraping_ultimo (modelo, cantidad, marca, nombre, precio)
  select modelo, cantidad, marca, nombre, precio from _scr_nuevo;

  -- Totales de la corrida.
  update public.scraping_ejecuciones e set
    bajaron           = s.bajaron,
    subieron          = s.subieron,
    nuevos            = s.nuevos,
    desaparecidos     = s.desaparecidos,
    agotados          = s.agotados,
    unidades_restadas = s.restadas,
    unidades_sumadas  = s.sumadas,
    precios_subieron  = (select count(*) from public.scraping_precios where ejecucion_id = eid and diferencia > 0),
    precios_bajaron   = (select count(*) from public.scraping_precios where ejecucion_id = eid and diferencia < 0)
  from (
    select count(*) filter (where tipo = 'bajo')                      as bajaron,
           count(*) filter (where tipo = 'subio')                     as subieron,
           count(*) filter (where tipo = 'nuevo')                     as nuevos,
           count(*) filter (where tipo = 'desaparecio')               as desaparecidos,
           count(*) filter (where tipo = 'bajo' and despues = 0)      as agotados,
           coalesce(-sum(diferencia) filter (where diferencia < 0), 0) as restadas,
           coalesce(sum(diferencia)  filter (where diferencia > 0), 0) as sumadas
    from public.scraping_movimientos where ejecucion_id = eid
  ) s
  where e.id = eid
  returning e.* into r;

  -- Se guarda un año de historial.
  delete from public.scraping_ejecuciones where fecha < now() - interval '400 days';

  return to_jsonb(r);
end $function$
;
CREATE OR REPLACE FUNCTION public.resumen_estadisticas(dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  -- No se cuenta lo que hacen los administradores (tus propias pruebas).
  return jsonb_build_object(
    'totales', (select coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb) from (
        select tipo, count(*) n from eventos e
        where creado >= desde and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by tipo) t),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'vistas', vistas, 'cotiza', cotiza) order by dia), '[]'::jsonb) from (
        select date_trunc('day', creado at time zone 'America/Caracas')::date dia,
               count(*) filter (where tipo = 'ver_producto') vistas,
               count(*) filter (where tipo in ('cotizar_whatsapp','pedido_whatsapp','agregar_carrito')) cotiza
        from eventos e
        where creado >= desde and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by 1) d),
    'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, max(resultados) resultados from eventos e
        where tipo = 'busqueda' and creado >= desde and texto is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by texto order by count(*) desc, texto limit 30) x),
    'sin_resultados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select texto, count(*) veces, max(creado) ultima from eventos e
        where tipo = 'busqueda' and coalesce(resultados, 0) = 0 and creado >= desde and texto is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by texto order by count(*) desc, max(creado) desc limit 30) x),
    'vistos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo, count(*) veces from eventos e
        where tipo = 'ver_producto' and creado >= desde and modelo is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by modelo order by count(*) desc limit 30) x),
    'cotizados', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select modelo,
               count(*) filter (where tipo = 'cotizar_whatsapp') whatsapp,
               count(*) filter (where tipo = 'agregar_carrito') carrito,
               count(*) filter (where tipo = 'pedido_whatsapp') pedidos,
               count(distinct cliente_email) filter (where cliente_email is not null) clientes
        from eventos e
        where tipo in ('cotizar_whatsapp','agregar_carrito','pedido_whatsapp') and creado >= desde and modelo is not null
          and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
        group by modelo order by count(*) desc limit 30) x)
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.resumen_links(dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (      -- todo lo del período (sin los administradores)
      select * from eventos e
      where creado >= desde and visitante is not null and visita is not null
        and not exists (select 1 from clientes c where c.email = e.cliente_email and c.es_admin)
    ),
    vl as (           -- visitas que pasaron por la página de enlaces
      select distinct visita from ev where origen = 'links'
    ),
    cab as (          -- datos de entrada de cada visita
      select distinct on (visita) visita, pais, region, ciudad, proveedor, dispositivo, navegador, sistema, referencia, pagina
      from ev where tipo = 'visita' and visita in (select visita from vl) order by visita, creado
    ),
    vis as (
      select ev.visita, min(ev.visitante) visitante,
             min(ev.creado) filter (where origen = 'links') inicio, max(ev.creado) fin,
             count(*) filter (where tipo = 'clic_enlace') clics,
             bool_or(origen in ('tienda', 'pagina')) a_tienda,
             bool_or(tipo in ('cotizar_whatsapp', 'pedido_whatsapp') or (tipo = 'clic_enlace' and texto ilike 'whatsapp%')) whatsapp,
             max(cliente_email) cliente_email
      from ev where visita in (select visita from vl) group by ev.visita
    ),
    primeras as (
      select visitante, min(creado) primera from eventos
      where visitante in (select distinct visitante from vis) group by visitante
    ),
    v as (
      select vis.*, cab.pais, cab.region, cab.ciudad, cab.proveedor, cab.dispositivo, cab.navegador, cab.sistema, cab.referencia, cab.pagina,
             (p.primera >= vis.inicio - interval '1 minute') nuevo
      from vis left join cab using (visita) left join primeras p using (visitante)
    ),
    cl as (select * from ev where tipo = 'clic_enlace' and origen = 'links')
    select jsonb_build_object(
      'totales', (select jsonb_build_object(
          'visitas', count(*),
          'visitantes', count(distinct visitante),
          'nuevos', count(distinct visitante) filter (where nuevo),
          'clics', coalesce(sum(clics), 0),
          'con_clic', count(*) filter (where clics > 0),
          'a_tienda', count(*) filter (where a_tienda),
          'whatsapp', count(*) filter (where whatsapp))
        from v),
      'ahora', (select count(distinct visitante) from eventos
                where creado >= now() - interval '15 minutes' and origen = 'links' and visitante is not null),
      'botones', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) clics, count(distinct visitante) personas, max(creado) ultima
          from cl where texto is not null group by texto order by count(*) desc, texto limit 40) x),
      'por_dia', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select d dia,
                 (select count(*) from v where (v.inicio at time zone 'America/Caracas')::date = d) visitas,
                 (select count(*) from cl where (cl.creado at time zone 'America/Caracas')::date = d) clics
          from (select distinct (inicio at time zone 'America/Caracas')::date d from v
                union select distinct (creado at time zone 'America/Caracas')::date from cl) dd) x),
      'por_hora', (select coalesce(jsonb_agg(x order by x.hora), '[]'::jsonb) from (
          select extract(hour from inicio at time zone 'America/Caracas')::int hora, count(*) visitas from v group by 1) x),
      'origenes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select referencia, count(*) visitas, count(*) filter (where clics > 0) con_clic from v
          group by referencia order by count(*) desc limit 15) x),
      'paises', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, count(*) visitas, count(distinct visitante) visitantes from v
          group by pais order by count(*) desc limit 15) x),
      'ciudades', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, region, ciudad, count(*) visitas, count(distinct visitante) visitantes from v
          where ciudad is not null or region is not null
          group by pais, region, ciudad order by count(*) desc limit 20) x),
      'dispositivos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select dispositivo, count(*) visitas from v group by dispositivo order by count(*) desc) x),
      'navegadores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select navegador, count(*) visitas from v group by navegador order by count(*) desc limit 10) x),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select v.*,
                 (select string_agg(texto, ' · ' order by primero) from (
                    select texto, min(creado) primero from cl where cl.visita = v.visita and texto is not null group by texto) b) botones
          from v order by inicio desc limit 150) x)
    )
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.resumen_scraping(dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 400)));
begin
  if not public.es_admin() then return null; end if;
  return jsonb_build_object(
    'ejecuciones', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.fecha desc)
      from (select * from public.scraping_ejecuciones where fecha >= desde order by fecha desc limit 200) e), '[]'::jsonb),
    'totales', (
      select jsonb_build_object(
        'corridas',          count(*) filter (where nota is null),
        'unidades_restadas', coalesce(sum(unidades_restadas), 0),
        'unidades_sumadas',  coalesce(sum(unidades_sumadas), 0),
        'bajaron',           coalesce(sum(bajaron), 0),
        'agotados',          coalesce(sum(agotados), 0),
        'precios_subieron',  coalesce(sum(precios_subieron), 0),
        'precios_bajaron',   coalesce(sum(precios_bajaron), 0))
      from public.scraping_ejecuciones where fecha >= desde),
    'mas_restados', coalesce((
      select jsonb_agg(t order by t.unidades desc)
      from (
        select modelo, max(marca) as marca, max(nombre) as nombre, max(precio) as precio,
               -sum(diferencia) as unidades, count(*) as veces, max(fecha) as ultima,
               (select u.cantidad from public.scraping_ultimo u where u.modelo = m.modelo) as queda
        from public.scraping_movimientos m
        where fecha >= desde and tipo = 'bajo'
        group by modelo
        order by -sum(diferencia) desc
        limit 50
      ) t), '[]'::jsonb)
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.resumen_visitantes(dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare desde timestamptz := now() - make_interval(days => greatest(1, least(dias, 365)));
begin
  if not public.es_admin() then return null; end if;
  return (
    with ev as (      -- lo que hicieron sin iniciar sesión
      select * from eventos
      where creado >= desde and cliente_email is null and visitante is not null and visita is not null
    ),
    cab as (          -- datos de entrada de cada visita
      select distinct on (visita) visita, pais, region, ciudad, proveedor, dispositivo, navegador, sistema, referencia, pagina
      from ev where tipo = 'visita' order by visita, creado
    ),
    vis as (          -- una fila por visita
      select ev.visita, min(ev.visitante) visitante, min(ev.creado) inicio, max(ev.creado) fin,
             count(*) filter (where tipo = 'busqueda')        busquedas,
             count(*) filter (where tipo = 'ver_producto')    fichas,
             coalesce(sum(cardinality(modelos)) filter (where tipo = 'ver_tarjetas'), 0) tarjetas,
             count(*) filter (where tipo = 'agregar_carrito') carrito,
             count(*) filter (where tipo in ('cotizar_whatsapp','pedido_whatsapp')) whatsapp
      from ev group by ev.visita
    ),
    primeras as (     -- primera vez que se vio a cada visitante (en todo el historial)
      select visitante, min(creado) primera from eventos
      where visitante in (select distinct visitante from vis) group by visitante
    ),
    v as (
      select vis.*, cab.pais, cab.region, cab.ciudad, cab.proveedor, cab.dispositivo, cab.navegador, cab.sistema, cab.referencia, cab.pagina,
             (p.primera >= vis.inicio - interval '1 minute') nuevo
      from vis left join cab using (visita) left join primeras p using (visitante)
    ),
    tarj as (
      select m modelo, count(*) veces, count(distinct visitante) personas
      from ev, unnest(modelos) m where tipo = 'ver_tarjetas' group by m
    ),
    fich as (
      select modelo, count(*) abiertas from ev where tipo = 'ver_producto' and modelo is not null group by modelo
    )
    select jsonb_build_object(
      'totales', (select jsonb_build_object(
          'visitas', count(*),
          'visitantes', count(distinct visitante),
          'nuevos', count(distinct visitante) filter (where nuevo),
          'busquedas', coalesce(sum(busquedas), 0),
          'fichas', coalesce(sum(fichas), 0),
          'tarjetas', coalesce(sum(tarjetas), 0),
          'carrito', coalesce(sum(carrito), 0),
          'whatsapp', coalesce(sum(whatsapp), 0),
          'con_interes', count(*) filter (where carrito > 0 or whatsapp > 0),
          'duracion_media', round(coalesce(avg(extract(epoch from fin - inicio)) filter (where fin > inicio), 0)))
        from v),
      'ahora', (select count(distinct visitante) from eventos
                where creado >= now() - interval '15 minutes' and cliente_email is null and visitante is not null),
      'por_dia', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select (inicio at time zone 'America/Caracas')::date dia, count(*) visitas, count(distinct visitante) visitantes
          from v group by 1) x),
      'por_hora', (select coalesce(jsonb_agg(x order by x.hora), '[]'::jsonb) from (
          select extract(hour from inicio at time zone 'America/Caracas')::int hora, count(*) visitas from v group by 1) x),
      'por_semana', (select coalesce(jsonb_agg(x order by x.dia), '[]'::jsonb) from (
          select extract(isodow from inicio at time zone 'America/Caracas')::int dia, count(*) visitas from v group by 1) x),
      'paises', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, count(*) visitas, count(distinct visitante) visitantes from v
          group by pais order by count(*) desc limit 20) x),
      'ciudades', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pais, region, ciudad, count(*) visitas, count(distinct visitante) visitantes from v
          where ciudad is not null or region is not null
          group by pais, region, ciudad order by count(*) desc limit 25) x),
      'proveedores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select proveedor, count(*) visitas from v where proveedor is not null
          group by proveedor order by count(*) desc limit 15) x),
      'dispositivos', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select dispositivo, count(*) visitas from v group by dispositivo order by count(*) desc) x),
      'sistemas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select sistema, count(*) visitas from v group by sistema order by count(*) desc limit 10) x),
      'navegadores', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select navegador, count(*) visitas from v group by navegador order by count(*) desc limit 10) x),
      'origenes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select referencia, count(*) visitas from v group by referencia order by count(*) desc limit 15) x),
      'entradas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select pagina, count(*) visitas from v where pagina is not null group by pagina order by count(*) desc limit 15) x),
      'buscado', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select texto, count(*) veces, count(distinct visitante) personas, min(resultados) resultados from ev
          where tipo = 'busqueda' and texto is not null group by texto order by count(*) desc, texto limit 30) x),
      'tarjetas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
          select tarj.modelo, tarj.veces, tarj.personas, coalesce(fich.abiertas, 0) abiertas
          from tarj left join fich using (modelo) order by tarj.veces desc limit 40) x),
      'visitas', (select coalesce(jsonb_agg(x order by x.inicio desc), '[]'::jsonb) from (
          select v.*, (select count(*) from vis v2 where v2.visitante = v.visitante) visitas_periodo,
                 (select string_agg(texto, ' · ') from (select distinct texto from ev e2
                    where e2.visita = v.visita and e2.tipo = 'busqueda' and e2.texto is not null limit 4) b) buscado
          from v order by inicio desc limit 150) x)
    )
  );
end $function$
;
CREATE OR REPLACE FUNCTION public.tg_esc(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select replace(replace(replace(nullif(t, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$function$
;
CREATE OR REPLACE FUNCTION public.tg_hora(t timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select to_char(t at time zone 'America/Caracas', 'DD/MM HH24:MI')
$function$
;
CREATE OR REPLACE FUNCTION public.tg_lugar(p_visita text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select nullif(concat_ws(' · ',
           nullif(concat_ws(', ', ciudad, case when region is distinct from ciudad then region end,
                            case when pais is distinct from 'VE' then pais end), ''),
           dispositivo,
           case when referencia is not null then 'llegó por ' || referencia end), '')
  from eventos where visita = p_visita and tipo = 'visita' order by creado limit 1
$function$
;
CREATE OR REPLACE FUNCTION public.tg_wa(tel text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when tel is null or regexp_replace(tel, '\D', '', 'g') = '' then null
    when regexp_replace(tel, '\D', '', 'g') ~ '^0' then 'https://wa.me/58' || substr(regexp_replace(tel, '\D', '', 'g'), 2)
    else 'https://wa.me/' || regexp_replace(tel, '\D', '', 'g')
  end
$function$
;
CREATE OR REPLACE FUNCTION public.tocar_actualizado()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin new.actualizado := now(); return new; end $function$
;
alter table public.adm_registros add constraint adm_registros_pkey PRIMARY KEY (coleccion, id);
alter table public.adm_usuarios add constraint adm_usuarios_pkey PRIMARY KEY (email);
alter table public.avisos_eventos add constraint avisos_eventos_pkey PRIMARY KEY (clave);
alter table public.chat_conversaciones add constraint chat_conversaciones_estado_check CHECK ((estado = ANY (ARRAY['abierta'::text, 'cerrada'::text])));
alter table public.chat_conversaciones add constraint chat_conversaciones_pkey PRIMARY KEY (id);
alter table public.chat_conversaciones add constraint chat_conversaciones_token_key UNIQUE (token);
alter table public.chat_mensajes add constraint chat_mensajes_autor_check CHECK ((autor = ANY (ARRAY['cliente'::text, 'suinelectric'::text, 'asistente'::text])));
alter table public.chat_mensajes add constraint chat_mensajes_pkey PRIMARY KEY (id);
alter table public.clientes add constraint clientes_email_check CHECK ((email = lower(email)));
alter table public.clientes add constraint clientes_pkey PRIMARY KEY (email);
alter table public.clientes add constraint clientes_user_id_key UNIQUE (user_id);
alter table public.en_linea add constraint en_linea_accion_check CHECK ((char_length(accion) <= 200));
alter table public.en_linea add constraint en_linea_ciudad_check CHECK ((char_length(ciudad) <= 80));
alter table public.en_linea add constraint en_linea_dispositivo_check CHECK ((char_length(dispositivo) <= 20));
alter table public.en_linea add constraint en_linea_navegador_check CHECK ((char_length(navegador) <= 40));
alter table public.en_linea add constraint en_linea_pagina_check CHECK ((char_length(pagina) <= 200));
alter table public.en_linea add constraint en_linea_pais_check CHECK ((char_length(pais) <= 60));
alter table public.en_linea add constraint en_linea_pkey PRIMARY KEY (visitante);
alter table public.en_linea add constraint en_linea_proveedor_check CHECK ((char_length(proveedor) <= 100));
alter table public.en_linea add constraint en_linea_referencia_check CHECK ((char_length(referencia) <= 120));
alter table public.en_linea add constraint en_linea_region_check CHECK ((char_length(region) <= 80));
alter table public.en_linea add constraint en_linea_sistema_check CHECK ((char_length(sistema) <= 40));
alter table public.en_linea add constraint en_linea_titulo_check CHECK ((char_length(titulo) <= 160));
alter table public.en_linea add constraint en_linea_visita_check CHECK ((char_length(visita) <= 40));
alter table public.en_linea add constraint en_linea_visitante_check CHECK ((char_length(visitante) <= 40));
alter table public.eventos add constraint eventos_ciudad_check CHECK ((char_length(ciudad) <= 80));
alter table public.eventos add constraint eventos_dispositivo_check CHECK ((char_length(dispositivo) <= 20));
alter table public.eventos add constraint eventos_modelo_check CHECK ((char_length(modelo) <= 80));
alter table public.eventos add constraint eventos_navegador_check CHECK ((char_length(navegador) <= 40));
alter table public.eventos add constraint eventos_origen_check CHECK ((char_length(origen) <= 20));
alter table public.eventos add constraint eventos_pagina_check CHECK ((char_length(pagina) <= 200));
alter table public.eventos add constraint eventos_pais_check CHECK ((char_length(pais) <= 60));
alter table public.eventos add constraint eventos_pkey PRIMARY KEY (id);
alter table public.eventos add constraint eventos_proveedor_check CHECK ((char_length(proveedor) <= 100));
alter table public.eventos add constraint eventos_referencia_check CHECK ((char_length(referencia) <= 120));
alter table public.eventos add constraint eventos_region_check CHECK ((char_length(region) <= 80));
alter table public.eventos add constraint eventos_sistema_check CHECK ((char_length(sistema) <= 40));
alter table public.eventos add constraint eventos_texto_check CHECK ((char_length(texto) <= 120));
alter table public.eventos add constraint eventos_tipo_check CHECK ((tipo = ANY (ARRAY['busqueda'::text, 'ver_producto'::text, 'agregar_carrito'::text, 'cotizar_whatsapp'::text, 'pedido_whatsapp'::text, 'visita'::text, 'ver_tarjetas'::text, 'clic_enlace'::text])));
alter table public.eventos add constraint eventos_visita_check CHECK ((char_length(visita) <= 40));
alter table public.eventos add constraint eventos_visitante_check CHECK ((char_length(visitante) <= 40));
alter table public.existencias add constraint existencias_pkey PRIMARY KEY (modelo);
alter table public.inventario_web_cant add constraint inventario_web_cant_cantidad_check CHECK ((cantidad >= 0));
alter table public.inventario_web_cant add constraint inventario_web_cant_pkey PRIMARY KEY (modelo);
alter table public.inventario_web add constraint inventario_web_categoria_check CHECK ((char_length(categoria) <= 120));
alter table public.inventario_web add constraint inventario_web_descripcion_check CHECK ((char_length(descripcion) <= 4000));
alter table public.inventario_web add constraint inventario_web_marca_check CHECK ((char_length(marca) <= 80));
alter table public.inventario_web add constraint inventario_web_modelo_check CHECK (((char_length(modelo) >= 1) AND (char_length(modelo) <= 80)));
alter table public.inventario_web add constraint inventario_web_nombre_check CHECK ((char_length(nombre) <= 200));
alter table public.inventario_web add constraint inventario_web_pkey PRIMARY KEY (modelo);
alter table public.inventario_web add constraint inventario_web_precio_check CHECK (((precio IS NULL) OR (precio >= (0)::numeric)));
alter table public.inventario_web add constraint inventario_web_stock_check CHECK ((stock = ANY (ARRAY['+10'::text, 'pocas'::text, 'pedido'::text])));
alter table public.ml_questions add constraint ml_questions_pkey PRIMARY KEY (question_id);
alter table public.ml_questions add constraint ml_questions_tg_message_id_key UNIQUE (tg_message_id);
alter table public.ml_tokens add constraint ml_tokens_pkey PRIMARY KEY (id);
alter table public.ml_tokens add constraint ml_tokens_single_row CHECK ((id = 1));
alter table public.pedidos add constraint pedidos_estado_check CHECK ((estado = ANY (ARRAY['enviado'::text, 'cotizado'::text, 'aprobado'::text, 'pagado'::text, 'entregado'::text, 'cancelado'::text])));
alter table public.pedidos add constraint pedidos_pkey PRIMARY KEY (id);
alter table public.productos_busqueda add constraint productos_busqueda_pkey PRIMARY KEY (modelo);
alter table public.productos_ocultos add constraint productos_ocultos_modelo_check CHECK (((char_length(modelo) >= 1) AND (char_length(modelo) <= 80)));
alter table public.productos_ocultos add constraint productos_ocultos_motivo_check CHECK ((char_length(motivo) <= 300));
alter table public.productos_ocultos add constraint productos_ocultos_pkey PRIMARY KEY (modelo);
alter table public.productos_web add constraint productos_web_categoria_principal_check CHECK (((char_length(categoria_principal) >= 1) AND (char_length(categoria_principal) <= 120)));
alter table public.productos_web add constraint productos_web_descripcion_check CHECK ((char_length(descripcion) <= 4000));
alter table public.productos_web add constraint productos_web_existencias_check CHECK (((existencias IS NULL) OR (existencias >= 0)));
alter table public.productos_web add constraint productos_web_marca_check CHECK (((char_length(marca) >= 1) AND (char_length(marca) <= 80)));
alter table public.productos_web add constraint productos_web_modelo_check CHECK (((char_length(modelo) >= 1) AND (char_length(modelo) <= 80)));
alter table public.productos_web add constraint productos_web_nombre_check CHECK ((char_length(nombre) <= 200));
alter table public.productos_web add constraint productos_web_notas_check CHECK ((char_length(notas) <= 1000));
alter table public.productos_web add constraint productos_web_pkey PRIMARY KEY (modelo);
alter table public.productos_web add constraint productos_web_precio_check CHECK (((precio IS NULL) OR (precio >= (0)::numeric)));
alter table public.reglas_descuento add constraint regla_fijo_modelo CHECK (((precio_fijo IS NULL) OR (modelo IS NOT NULL)));
alter table public.reglas_descuento add constraint regla_un_destino CHECK ((NOT ((cliente_email IS NOT NULL) AND (tipo_id IS NOT NULL))));
alter table public.reglas_descuento add constraint regla_un_precio CHECK (((descuento_pct IS NULL) <> (precio_fijo IS NULL)));
alter table public.reglas_descuento add constraint reglas_descuento_descuento_pct_check CHECK (((descuento_pct >= (0)::numeric) AND (descuento_pct <= (100)::numeric)));
alter table public.reglas_descuento add constraint reglas_descuento_pkey PRIMARY KEY (id);
alter table public.reglas_descuento add constraint reglas_descuento_precio_fijo_check CHECK ((precio_fijo >= (0)::numeric));
alter table public.scraping_ejecuciones add constraint scraping_ejecuciones_pkey PRIMARY KEY (id);
alter table public.scraping_movimientos add constraint scraping_movimientos_pkey PRIMARY KEY (id);
alter table public.scraping_movimientos add constraint scraping_movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['bajo'::text, 'subio'::text, 'nuevo'::text, 'desaparecio'::text])));
alter table public.scraping_precios add constraint scraping_precios_pkey PRIMARY KEY (id);
alter table public.scraping_ultimo add constraint scraping_ultimo_pkey PRIMARY KEY (modelo);
alter table public.tipos_cliente add constraint tipos_cliente_pkey PRIMARY KEY (id);
alter table public.chat_mensajes add constraint chat_mensajes_conversacion_id_fkey FOREIGN KEY (conversacion_id) REFERENCES chat_conversaciones(id) ON DELETE CASCADE;
alter table public.clientes add constraint clientes_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES tipos_cliente(id) ON UPDATE CASCADE ON DELETE SET NULL;
alter table public.clientes add constraint clientes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.inventario_web_cant add constraint inventario_web_cant_modelo_fkey FOREIGN KEY (modelo) REFERENCES inventario_web(modelo) ON DELETE CASCADE;
alter table public.pedidos add constraint pedidos_cliente_email_fkey FOREIGN KEY (cliente_email) REFERENCES clientes(email) ON UPDATE CASCADE;
alter table public.reglas_descuento add constraint reglas_descuento_cliente_email_fkey FOREIGN KEY (cliente_email) REFERENCES clientes(email) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.reglas_descuento add constraint reglas_descuento_tipo_id_fkey FOREIGN KEY (tipo_id) REFERENCES tipos_cliente(id) ON UPDATE CASCADE ON DELETE CASCADE;
alter table public.scraping_movimientos add constraint scraping_movimientos_ejecucion_id_fkey FOREIGN KEY (ejecucion_id) REFERENCES scraping_ejecuciones(id) ON DELETE CASCADE;
alter table public.scraping_precios add constraint scraping_precios_ejecucion_id_fkey FOREIGN KEY (ejecucion_id) REFERENCES scraping_ejecuciones(id) ON DELETE CASCADE;
CREATE INDEX adm_registros_actualizado ON public.adm_registros USING btree (actualizado);
CREATE INDEX chat_conv_ultimo_idx ON public.chat_conversaciones USING btree (ultimo DESC);
CREATE INDEX chat_mensajes_conv_idx ON public.chat_mensajes USING btree (conversacion_id, id);
CREATE INDEX en_linea_visto ON public.en_linea USING btree (visto DESC);
CREATE INDEX eventos_cliente_idx ON public.eventos USING btree (cliente_email, creado DESC) WHERE (cliente_email IS NOT NULL);
CREATE INDEX eventos_creado_idx ON public.eventos USING btree (creado DESC);
CREATE INDEX eventos_origen_idx ON public.eventos USING btree (origen, creado DESC);
CREATE INDEX eventos_tipo_idx ON public.eventos USING btree (tipo, creado DESC);
CREATE INDEX eventos_visita_idx ON public.eventos USING btree (visita) WHERE (visita IS NOT NULL);
CREATE INDEX eventos_visitante_idx ON public.eventos USING btree (visitante, creado DESC) WHERE (visitante IS NOT NULL);
CREATE INDEX pedidos_cliente_idx ON public.pedidos USING btree (cliente_email, creado DESC);
CREATE INDEX reglas_cliente_idx ON public.reglas_descuento USING btree (cliente_email);
CREATE INDEX reglas_tipo_idx ON public.reglas_descuento USING btree (tipo_id);
CREATE INDEX scraping_ejecuciones_fecha ON public.scraping_ejecuciones USING btree (fecha DESC);
CREATE INDEX scraping_mov_ejecucion ON public.scraping_movimientos USING btree (ejecucion_id);
CREATE INDEX scraping_mov_fecha ON public.scraping_movimientos USING btree (fecha DESC);
CREATE INDEX scraping_mov_modelo ON public.scraping_movimientos USING btree (modelo, fecha DESC);
CREATE INDEX scraping_precios_ejecucion ON public.scraping_precios USING btree (ejecucion_id);
CREATE INDEX scraping_precios_fecha ON public.scraping_precios USING btree (fecha DESC);
CREATE INDEX scraping_precios_modelo ON public.scraping_precios USING btree (modelo, fecha DESC);
CREATE TRIGGER adm_registros_tocar BEFORE INSERT OR UPDATE ON public.adm_registros FOR EACH ROW EXECUTE FUNCTION adm_tocar();
CREATE TRIGGER al_registrarse AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION al_registrarse();
CREATE TRIGGER chat_mensajes_avisar AFTER INSERT ON public.chat_mensajes FOR EACH ROW EXECUTE FUNCTION avisar_chat();
CREATE TRIGGER clientes_actualizado BEFORE UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();
CREATE TRIGGER clientes_avisar AFTER INSERT OR UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION avisar_cliente();
CREATE TRIGGER clientes_proteger BEFORE UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION proteger_cliente();
CREATE TRIGGER eventos_avisar AFTER INSERT ON public.eventos FOR EACH ROW EXECUTE FUNCTION avisar_evento();
CREATE TRIGGER eventos_completar BEFORE INSERT ON public.eventos FOR EACH ROW EXECUTE FUNCTION eventos_completar();
CREATE TRIGGER pedidos_actualizado BEFORE UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION tocar_actualizado();
CREATE TRIGGER pedidos_avisar AFTER INSERT ON public.pedidos FOR EACH ROW EXECUTE FUNCTION avisar_pedido();
CREATE TRIGGER productos_ocultos_completar BEFORE INSERT OR UPDATE ON public.productos_ocultos FOR EACH ROW EXECUTE FUNCTION productos_ocultos_completar();
CREATE TRIGGER productos_web_completar BEFORE INSERT OR UPDATE ON public.productos_web FOR EACH ROW EXECUTE FUNCTION productos_web_completar();
alter table public.adm_registros enable row level security;
alter table public.adm_usuarios enable row level security;
alter table public.avisos_eventos enable row level security;
alter table public.chat_conversaciones enable row level security;
alter table public.chat_mensajes enable row level security;
alter table public.clientes enable row level security;
alter table public.en_linea enable row level security;
alter table public.eventos enable row level security;
alter table public.existencias enable row level security;
alter table public.inventario_web enable row level security;
alter table public.inventario_web_cant enable row level security;
alter table public.ml_questions enable row level security;
alter table public.ml_tokens enable row level security;
alter table public.pedidos enable row level security;
alter table public.productos_busqueda enable row level security;
alter table public.productos_ocultos enable row level security;
alter table public.productos_web enable row level security;
alter table public.reglas_descuento enable row level security;
alter table public.scraping_ejecuciones enable row level security;
alter table public.scraping_movimientos enable row level security;
alter table public.scraping_precios enable row level security;
alter table public.scraping_ultimo enable row level security;
alter table public.tipos_cliente enable row level security;
create policy adm_todo on public.adm_registros as PERMISSIVE for ALL to authenticated using (adm_es_admin()) with check (adm_es_admin());
create policy adm_yo on public.adm_usuarios as PERMISSIVE for SELECT to authenticated using ((lower(email) = lower((auth.jwt() ->> 'email'::text))));
create policy avisos_eventos_cambiar on public.avisos_eventos as PERMISSIVE for UPDATE to authenticated using (es_admin()) with check (es_admin());
create policy avisos_eventos_leer on public.avisos_eventos as PERMISSIVE for SELECT to authenticated using (es_admin());
create policy chat_conv_admin on public.chat_conversaciones as PERMISSIVE for SELECT to public using (es_admin());
create policy chat_msj_admin on public.chat_mensajes as PERMISSIVE for SELECT to public using (es_admin());
create policy clientes_admin on public.clientes as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy clientes_editar on public.clientes as PERMISSIVE for UPDATE to authenticated using (((email = mi_email()) AND mi_activo())) with check ((email = mi_email()));
create policy clientes_leer on public.clientes as PERMISSIVE for SELECT to authenticated using (((email = mi_email()) OR es_admin()));
create policy en_linea_leer on public.en_linea as PERMISSIVE for SELECT to authenticated using (es_admin());
create policy eventos_anotar on public.eventos as PERMISSIVE for INSERT to anon,authenticated with check (true);
create policy eventos_borrar on public.eventos as PERMISSIVE for DELETE to authenticated using (es_admin());
create policy eventos_leer on public.eventos as PERMISSIVE for SELECT to authenticated using (es_admin());
create policy inventario_web_leer on public.inventario_web as PERMISSIVE for SELECT to anon,authenticated using (true);
create policy pedidos_admin on public.pedidos as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy pedidos_crear on public.pedidos as PERMISSIVE for INSERT to authenticated with check (((cliente_email = mi_email()) AND (estado = 'enviado'::text) AND (nota_admin IS NULL) AND (archivado = false)));
create policy pedidos_leer on public.pedidos as PERMISSIVE for SELECT to authenticated using (((cliente_email = mi_email()) OR es_admin()));
create policy productos_fotos_borrar on storage.objects as PERMISSIVE for DELETE to authenticated using (((bucket_id = 'productos'::text) AND es_admin()));
create policy productos_fotos_cambiar on storage.objects as PERMISSIVE for UPDATE to authenticated using (((bucket_id = 'productos'::text) AND es_admin()));
create policy productos_fotos_subir on storage.objects as PERMISSIVE for INSERT to authenticated with check (((bucket_id = 'productos'::text) AND es_admin()));
create policy productos_ocultos_admin on public.productos_ocultos as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy productos_ocultos_leer on public.productos_ocultos as PERMISSIVE for SELECT to anon,authenticated using (true);
create policy productos_web_admin on public.productos_web as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy productos_web_leer on public.productos_web as PERMISSIVE for SELECT to anon,authenticated using ((activo OR es_admin()));
create policy reglas_admin on public.reglas_descuento as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy reglas_leer on public.reglas_descuento as PERMISSIVE for SELECT to anon,authenticated using (((activo AND (((cliente_email IS NULL) AND (tipo_id IS NULL)) OR (cliente_email = mi_email()) OR ((cliente_email IS NULL) AND (tipo_id = mi_tipo())) OR ((cliente_email IS NULL) AND (tipo_id = 'final'::text)))) OR es_admin()));
create policy tipos_admin on public.tipos_cliente as PERMISSIVE for ALL to authenticated using (es_admin()) with check (es_admin());
create policy tipos_leer on public.tipos_cliente as PERMISSIVE for SELECT to anon,authenticated using (true);
revoke all on function public.actividad_cliente(p_email text, dias integer) from public, anon, authenticated; grant execute on function public.actividad_cliente(p_email text, dias integer) to authenticated; grant execute on function public.actividad_cliente(p_email text, dias integer) to service_role;
revoke all on function public.actividad_visitante(p_visitante text, dias integer) from public, anon, authenticated; grant execute on function public.actividad_visitante(p_visitante text, dias integer) to authenticated; grant execute on function public.actividad_visitante(p_visitante text, dias integer) to service_role;
revoke all on function public.adm_es_admin() from public, anon, authenticated; grant execute on function public.adm_es_admin() to anon; grant execute on function public.adm_es_admin() to authenticated; grant execute on function public.adm_es_admin() to service_role; grant execute on function public.adm_es_admin() to public;
revoke all on function public.adm_tocar() from public, anon, authenticated; grant execute on function public.adm_tocar() to anon; grant execute on function public.adm_tocar() to authenticated; grant execute on function public.adm_tocar() to service_role; grant execute on function public.adm_tocar() to public;
revoke all on function public.al_registrarse() from public, anon, authenticated; grant execute on function public.al_registrarse() to anon; grant execute on function public.al_registrarse() to authenticated; grant execute on function public.al_registrarse() to service_role; grant execute on function public.al_registrarse() to public;
revoke all on function public.avisar_chat() from public, anon, authenticated; grant execute on function public.avisar_chat() to anon; grant execute on function public.avisar_chat() to authenticated; grant execute on function public.avisar_chat() to service_role; grant execute on function public.avisar_chat() to public;
revoke all on function public.avisar_cliente() from public, anon, authenticated; grant execute on function public.avisar_cliente() to anon; grant execute on function public.avisar_cliente() to authenticated; grant execute on function public.avisar_cliente() to service_role; grant execute on function public.avisar_cliente() to public;
revoke all on function public.avisar_evento() from public, anon, authenticated; grant execute on function public.avisar_evento() to anon; grant execute on function public.avisar_evento() to authenticated; grant execute on function public.avisar_evento() to service_role; grant execute on function public.avisar_evento() to public;
revoke all on function public.avisar_pedido() from public, anon, authenticated; grant execute on function public.avisar_pedido() to anon; grant execute on function public.avisar_pedido() to authenticated; grant execute on function public.avisar_pedido() to service_role; grant execute on function public.avisar_pedido() to public;
revoke all on function public.aviso_activo(k text) from public, anon, authenticated; grant execute on function public.aviso_activo(k text) to anon; grant execute on function public.aviso_activo(k text) to authenticated; grant execute on function public.aviso_activo(k text) to service_role; grant execute on function public.aviso_activo(k text) to public;
revoke all on function public.borrar_cliente(p_email text) from public, anon, authenticated; grant execute on function public.borrar_cliente(p_email text) to authenticated; grant execute on function public.borrar_cliente(p_email text) to service_role;
revoke all on function public.buscar_productos(p_terminos text[], p_marca text, p_limite integer) from public, anon, authenticated; grant execute on function public.buscar_productos(p_terminos text[], p_marca text, p_limite integer) to service_role;
revoke all on function public.cargar_existencias(datos jsonb) from public, anon, authenticated; grant execute on function public.cargar_existencias(datos jsonb) to service_role;
revoke all on function public.cargar_productos_busqueda(datos jsonb) from public, anon, authenticated; grant execute on function public.cargar_productos_busqueda(datos jsonb) to service_role;
revoke all on function public.chat_enviar(p_token uuid, p_texto text, p_nombre text, p_contacto text, p_pagina text) from public, anon, authenticated; grant execute on function public.chat_enviar(p_token uuid, p_texto text, p_nombre text, p_contacto text, p_pagina text) to anon; grant execute on function public.chat_enviar(p_token uuid, p_texto text, p_nombre text, p_contacto text, p_pagina text) to authenticated; grant execute on function public.chat_enviar(p_token uuid, p_texto text, p_nombre text, p_contacto text, p_pagina text) to service_role;
revoke all on function public.chat_guardar_ia(p_chat bigint, p_texto text, p_pasar boolean, p_hasta bigint) from public, anon, authenticated; grant execute on function public.chat_guardar_ia(p_chat bigint, p_texto text, p_pasar boolean, p_hasta bigint) to service_role;
revoke all on function public.chat_ia(p_chat bigint, p_activa boolean) from public, anon, authenticated; grant execute on function public.chat_ia(p_chat bigint, p_activa boolean) to service_role;
revoke all on function public.chat_leer(p_token uuid, p_desde bigint) from public, anon, authenticated; grant execute on function public.chat_leer(p_token uuid, p_desde bigint) to anon; grant execute on function public.chat_leer(p_token uuid, p_desde bigint) to authenticated; grant execute on function public.chat_leer(p_token uuid, p_desde bigint) to service_role;
revoke all on function public.chat_recientes(p_limite integer) from public, anon, authenticated; grant execute on function public.chat_recientes(p_limite integer) to service_role;
revoke all on function public.chat_responder(p_chat bigint, p_texto text) from public, anon, authenticated; grant execute on function public.chat_responder(p_chat bigint, p_texto text) to service_role;
revoke all on function public.chat_turno_ia(p_token uuid) from public, anon, authenticated; grant execute on function public.chat_turno_ia(p_token uuid) to service_role;
revoke all on function public.clientes_activos(dias integer) from public, anon, authenticated; grant execute on function public.clientes_activos(dias integer) to authenticated; grant execute on function public.clientes_activos(dias integer) to service_role;
revoke all on function public.es_admin() from public, anon, authenticated; grant execute on function public.es_admin() to anon; grant execute on function public.es_admin() to authenticated; grant execute on function public.es_admin() to service_role; grant execute on function public.es_admin() to public;
revoke all on function public.estado_existencias() from public, anon, authenticated; grant execute on function public.estado_existencias() to authenticated; grant execute on function public.estado_existencias() to service_role;
revoke all on function public.eventos_completar() from public, anon, authenticated; grant execute on function public.eventos_completar() to anon; grant execute on function public.eventos_completar() to authenticated; grant execute on function public.eventos_completar() to service_role; grant execute on function public.eventos_completar() to public;
revoke all on function public.existencias_reales() from public, anon, authenticated; grant execute on function public.existencias_reales() to authenticated; grant execute on function public.existencias_reales() to service_role;
revoke all on function public.inventario_cantidades() from public, anon, authenticated; grant execute on function public.inventario_cantidades() to authenticated; grant execute on function public.inventario_cantidades() to service_role;
revoke all on function public.limpiar_eventos() from public, anon, authenticated; grant execute on function public.limpiar_eventos() to authenticated; grant execute on function public.limpiar_eventos() to service_role;
revoke all on function public.marcar_en_linea(p jsonb) from public, anon, authenticated; grant execute on function public.marcar_en_linea(p jsonb) to anon; grant execute on function public.marcar_en_linea(p jsonb) to authenticated; grant execute on function public.marcar_en_linea(p jsonb) to service_role;
revoke all on function public.mi_activo() from public, anon, authenticated; grant execute on function public.mi_activo() to anon; grant execute on function public.mi_activo() to authenticated; grant execute on function public.mi_activo() to service_role; grant execute on function public.mi_activo() to public;
revoke all on function public.mi_email() from public, anon, authenticated; grant execute on function public.mi_email() to anon; grant execute on function public.mi_email() to authenticated; grant execute on function public.mi_email() to service_role; grant execute on function public.mi_email() to public;
revoke all on function public.mi_tipo() from public, anon, authenticated; grant execute on function public.mi_tipo() to anon; grant execute on function public.mi_tipo() to authenticated; grant execute on function public.mi_tipo() to service_role; grant execute on function public.mi_tipo() to public;
revoke all on function public.movimientos_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_tipo text, limite integer) from public, anon, authenticated; grant execute on function public.movimientos_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_tipo text, limite integer) to authenticated; grant execute on function public.movimientos_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_tipo text, limite integer) to service_role;
revoke all on function public.notificar_telegram(texto text) from public, anon, authenticated; grant execute on function public.notificar_telegram(texto text) to service_role;
revoke all on function public.precios_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_sentido text, limite integer) from public, anon, authenticated; grant execute on function public.precios_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_sentido text, limite integer) to authenticated; grant execute on function public.precios_scraping(p_ejecucion bigint, p_modelo text, dias integer, p_sentido text, limite integer) to service_role;
revoke all on function public.productos_ocultos_completar() from public, anon, authenticated; grant execute on function public.productos_ocultos_completar() to anon; grant execute on function public.productos_ocultos_completar() to authenticated; grant execute on function public.productos_ocultos_completar() to service_role; grant execute on function public.productos_ocultos_completar() to public;
revoke all on function public.productos_web_completar() from public, anon, authenticated; grant execute on function public.productos_web_completar() to anon; grant execute on function public.productos_web_completar() to authenticated; grant execute on function public.productos_web_completar() to service_role; grant execute on function public.productos_web_completar() to public;
revoke all on function public.proteger_cliente() from public, anon, authenticated; grant execute on function public.proteger_cliente() to anon; grant execute on function public.proteger_cliente() to authenticated; grant execute on function public.proteger_cliente() to service_role; grant execute on function public.proteger_cliente() to public;
revoke all on function public.publicar_inventario_web(datos jsonb) from public, anon, authenticated; grant execute on function public.publicar_inventario_web(datos jsonb) to authenticated; grant execute on function public.publicar_inventario_web(datos jsonb) to service_role;
revoke all on function public.puede_ver_existencias() from public, anon, authenticated; grant execute on function public.puede_ver_existencias() to anon; grant execute on function public.puede_ver_existencias() to authenticated; grant execute on function public.puede_ver_existencias() to service_role; grant execute on function public.puede_ver_existencias() to public;
revoke all on function public.registrar_scraping(p_productos jsonb, p_generado timestamp with time zone) from public, anon, authenticated; grant execute on function public.registrar_scraping(p_productos jsonb, p_generado timestamp with time zone) to service_role;
revoke all on function public.resumen_estadisticas(dias integer) from public, anon, authenticated; grant execute on function public.resumen_estadisticas(dias integer) to authenticated; grant execute on function public.resumen_estadisticas(dias integer) to service_role;
revoke all on function public.resumen_links(dias integer) from public, anon, authenticated; grant execute on function public.resumen_links(dias integer) to authenticated; grant execute on function public.resumen_links(dias integer) to service_role;
revoke all on function public.resumen_scraping(dias integer) from public, anon, authenticated; grant execute on function public.resumen_scraping(dias integer) to authenticated; grant execute on function public.resumen_scraping(dias integer) to service_role;
revoke all on function public.resumen_visitantes(dias integer) from public, anon, authenticated; grant execute on function public.resumen_visitantes(dias integer) to authenticated; grant execute on function public.resumen_visitantes(dias integer) to service_role;
revoke all on function public.tg_esc(t text) from public, anon, authenticated; grant execute on function public.tg_esc(t text) to anon; grant execute on function public.tg_esc(t text) to authenticated; grant execute on function public.tg_esc(t text) to service_role; grant execute on function public.tg_esc(t text) to public;
revoke all on function public.tg_hora(t timestamp with time zone) from public, anon, authenticated; grant execute on function public.tg_hora(t timestamp with time zone) to anon; grant execute on function public.tg_hora(t timestamp with time zone) to authenticated; grant execute on function public.tg_hora(t timestamp with time zone) to service_role; grant execute on function public.tg_hora(t timestamp with time zone) to public;
revoke all on function public.tg_lugar(p_visita text) from public, anon, authenticated; grant execute on function public.tg_lugar(p_visita text) to anon; grant execute on function public.tg_lugar(p_visita text) to authenticated; grant execute on function public.tg_lugar(p_visita text) to service_role; grant execute on function public.tg_lugar(p_visita text) to public;
revoke all on function public.tg_wa(tel text) from public, anon, authenticated; grant execute on function public.tg_wa(tel text) to anon; grant execute on function public.tg_wa(tel text) to authenticated; grant execute on function public.tg_wa(tel text) to service_role; grant execute on function public.tg_wa(tel text) to public;
revoke all on function public.tocar_actualizado() from public, anon, authenticated; grant execute on function public.tocar_actualizado() to anon; grant execute on function public.tocar_actualizado() to authenticated; grant execute on function public.tocar_actualizado() to service_role; grant execute on function public.tocar_actualizado() to public;
revoke all on public.adm_registros from anon, authenticated; grant INSERT on public.adm_registros to anon; grant SELECT on public.adm_registros to anon; grant UPDATE on public.adm_registros to anon; grant DELETE on public.adm_registros to anon; grant TRUNCATE on public.adm_registros to anon; grant REFERENCES on public.adm_registros to anon; grant TRIGGER on public.adm_registros to anon; grant MAINTAIN on public.adm_registros to anon; grant INSERT on public.adm_registros to authenticated; grant SELECT on public.adm_registros to authenticated; grant UPDATE on public.adm_registros to authenticated; grant DELETE on public.adm_registros to authenticated; grant TRUNCATE on public.adm_registros to authenticated; grant REFERENCES on public.adm_registros to authenticated; grant TRIGGER on public.adm_registros to authenticated; grant MAINTAIN on public.adm_registros to authenticated;
revoke all on public.adm_usuarios from anon, authenticated; grant INSERT on public.adm_usuarios to anon; grant SELECT on public.adm_usuarios to anon; grant UPDATE on public.adm_usuarios to anon; grant DELETE on public.adm_usuarios to anon; grant TRUNCATE on public.adm_usuarios to anon; grant REFERENCES on public.adm_usuarios to anon; grant TRIGGER on public.adm_usuarios to anon; grant MAINTAIN on public.adm_usuarios to anon; grant INSERT on public.adm_usuarios to authenticated; grant SELECT on public.adm_usuarios to authenticated; grant UPDATE on public.adm_usuarios to authenticated; grant DELETE on public.adm_usuarios to authenticated; grant TRUNCATE on public.adm_usuarios to authenticated; grant REFERENCES on public.adm_usuarios to authenticated; grant TRIGGER on public.adm_usuarios to authenticated; grant MAINTAIN on public.adm_usuarios to authenticated;
revoke all on public.avisos_eventos from anon, authenticated; grant INSERT on public.avisos_eventos to authenticated; grant SELECT on public.avisos_eventos to authenticated; grant UPDATE on public.avisos_eventos to authenticated; grant DELETE on public.avisos_eventos to authenticated; grant TRUNCATE on public.avisos_eventos to authenticated; grant REFERENCES on public.avisos_eventos to authenticated; grant TRIGGER on public.avisos_eventos to authenticated; grant MAINTAIN on public.avisos_eventos to authenticated;
revoke all on public.chat_conversaciones from anon, authenticated; grant INSERT on public.chat_conversaciones to anon; grant SELECT on public.chat_conversaciones to anon; grant UPDATE on public.chat_conversaciones to anon; grant DELETE on public.chat_conversaciones to anon; grant TRUNCATE on public.chat_conversaciones to anon; grant REFERENCES on public.chat_conversaciones to anon; grant TRIGGER on public.chat_conversaciones to anon; grant MAINTAIN on public.chat_conversaciones to anon; grant INSERT on public.chat_conversaciones to authenticated; grant SELECT on public.chat_conversaciones to authenticated; grant UPDATE on public.chat_conversaciones to authenticated; grant DELETE on public.chat_conversaciones to authenticated; grant TRUNCATE on public.chat_conversaciones to authenticated; grant REFERENCES on public.chat_conversaciones to authenticated; grant TRIGGER on public.chat_conversaciones to authenticated; grant MAINTAIN on public.chat_conversaciones to authenticated;
revoke all on public.chat_conversaciones_id_seq from anon, authenticated; grant SELECT on public.chat_conversaciones_id_seq to anon; grant UPDATE on public.chat_conversaciones_id_seq to anon; grant USAGE on public.chat_conversaciones_id_seq to anon; grant SELECT on public.chat_conversaciones_id_seq to authenticated; grant UPDATE on public.chat_conversaciones_id_seq to authenticated; grant USAGE on public.chat_conversaciones_id_seq to authenticated;
revoke all on public.chat_mensajes from anon, authenticated; grant INSERT on public.chat_mensajes to anon; grant SELECT on public.chat_mensajes to anon; grant UPDATE on public.chat_mensajes to anon; grant DELETE on public.chat_mensajes to anon; grant TRUNCATE on public.chat_mensajes to anon; grant REFERENCES on public.chat_mensajes to anon; grant TRIGGER on public.chat_mensajes to anon; grant MAINTAIN on public.chat_mensajes to anon; grant INSERT on public.chat_mensajes to authenticated; grant SELECT on public.chat_mensajes to authenticated; grant UPDATE on public.chat_mensajes to authenticated; grant DELETE on public.chat_mensajes to authenticated; grant TRUNCATE on public.chat_mensajes to authenticated; grant REFERENCES on public.chat_mensajes to authenticated; grant TRIGGER on public.chat_mensajes to authenticated; grant MAINTAIN on public.chat_mensajes to authenticated;
revoke all on public.chat_mensajes_id_seq from anon, authenticated; grant SELECT on public.chat_mensajes_id_seq to anon; grant UPDATE on public.chat_mensajes_id_seq to anon; grant USAGE on public.chat_mensajes_id_seq to anon; grant SELECT on public.chat_mensajes_id_seq to authenticated; grant UPDATE on public.chat_mensajes_id_seq to authenticated; grant USAGE on public.chat_mensajes_id_seq to authenticated;
revoke all on public.clientes from anon, authenticated; grant INSERT on public.clientes to anon; grant SELECT on public.clientes to anon; grant UPDATE on public.clientes to anon; grant DELETE on public.clientes to anon; grant TRUNCATE on public.clientes to anon; grant REFERENCES on public.clientes to anon; grant TRIGGER on public.clientes to anon; grant MAINTAIN on public.clientes to anon; grant INSERT on public.clientes to authenticated; grant SELECT on public.clientes to authenticated; grant UPDATE on public.clientes to authenticated; grant DELETE on public.clientes to authenticated; grant TRUNCATE on public.clientes to authenticated; grant REFERENCES on public.clientes to authenticated; grant TRIGGER on public.clientes to authenticated; grant MAINTAIN on public.clientes to authenticated;
revoke all on public.en_linea from anon, authenticated; grant INSERT on public.en_linea to authenticated; grant SELECT on public.en_linea to authenticated; grant UPDATE on public.en_linea to authenticated; grant DELETE on public.en_linea to authenticated; grant TRUNCATE on public.en_linea to authenticated; grant REFERENCES on public.en_linea to authenticated; grant TRIGGER on public.en_linea to authenticated; grant MAINTAIN on public.en_linea to authenticated;
revoke all on public.eventos from anon, authenticated; grant INSERT on public.eventos to anon; grant SELECT on public.eventos to anon; grant UPDATE on public.eventos to anon; grant DELETE on public.eventos to anon; grant TRUNCATE on public.eventos to anon; grant REFERENCES on public.eventos to anon; grant TRIGGER on public.eventos to anon; grant MAINTAIN on public.eventos to anon; grant INSERT on public.eventos to authenticated; grant SELECT on public.eventos to authenticated; grant UPDATE on public.eventos to authenticated; grant DELETE on public.eventos to authenticated; grant TRUNCATE on public.eventos to authenticated; grant REFERENCES on public.eventos to authenticated; grant TRIGGER on public.eventos to authenticated; grant MAINTAIN on public.eventos to authenticated;
revoke all on public.eventos_id_seq from anon, authenticated; grant SELECT on public.eventos_id_seq to anon; grant UPDATE on public.eventos_id_seq to anon; grant USAGE on public.eventos_id_seq to anon; grant SELECT on public.eventos_id_seq to authenticated; grant UPDATE on public.eventos_id_seq to authenticated; grant USAGE on public.eventos_id_seq to authenticated;
revoke all on public.existencias from anon, authenticated;
revoke all on public.inventario_web from anon, authenticated; grant SELECT on public.inventario_web to anon; grant TRUNCATE on public.inventario_web to anon; grant REFERENCES on public.inventario_web to anon; grant TRIGGER on public.inventario_web to anon; grant MAINTAIN on public.inventario_web to anon; grant SELECT on public.inventario_web to authenticated; grant TRUNCATE on public.inventario_web to authenticated; grant REFERENCES on public.inventario_web to authenticated; grant TRIGGER on public.inventario_web to authenticated; grant MAINTAIN on public.inventario_web to authenticated;
revoke all on public.inventario_web_cant from anon, authenticated;
revoke all on public.ml_questions from anon, authenticated; grant INSERT on public.ml_questions to anon; grant SELECT on public.ml_questions to anon; grant UPDATE on public.ml_questions to anon; grant DELETE on public.ml_questions to anon; grant TRUNCATE on public.ml_questions to anon; grant REFERENCES on public.ml_questions to anon; grant TRIGGER on public.ml_questions to anon; grant MAINTAIN on public.ml_questions to anon; grant INSERT on public.ml_questions to authenticated; grant SELECT on public.ml_questions to authenticated; grant UPDATE on public.ml_questions to authenticated; grant DELETE on public.ml_questions to authenticated; grant TRUNCATE on public.ml_questions to authenticated; grant REFERENCES on public.ml_questions to authenticated; grant TRIGGER on public.ml_questions to authenticated; grant MAINTAIN on public.ml_questions to authenticated;
revoke all on public.ml_tokens from anon, authenticated; grant INSERT on public.ml_tokens to anon; grant SELECT on public.ml_tokens to anon; grant UPDATE on public.ml_tokens to anon; grant DELETE on public.ml_tokens to anon; grant TRUNCATE on public.ml_tokens to anon; grant REFERENCES on public.ml_tokens to anon; grant TRIGGER on public.ml_tokens to anon; grant MAINTAIN on public.ml_tokens to anon; grant INSERT on public.ml_tokens to authenticated; grant SELECT on public.ml_tokens to authenticated; grant UPDATE on public.ml_tokens to authenticated; grant DELETE on public.ml_tokens to authenticated; grant TRUNCATE on public.ml_tokens to authenticated; grant REFERENCES on public.ml_tokens to authenticated; grant TRIGGER on public.ml_tokens to authenticated; grant MAINTAIN on public.ml_tokens to authenticated;
revoke all on public.pedidos from anon, authenticated; grant INSERT on public.pedidos to anon; grant SELECT on public.pedidos to anon; grant UPDATE on public.pedidos to anon; grant DELETE on public.pedidos to anon; grant TRUNCATE on public.pedidos to anon; grant REFERENCES on public.pedidos to anon; grant TRIGGER on public.pedidos to anon; grant MAINTAIN on public.pedidos to anon; grant INSERT on public.pedidos to authenticated; grant SELECT on public.pedidos to authenticated; grant UPDATE on public.pedidos to authenticated; grant DELETE on public.pedidos to authenticated; grant TRUNCATE on public.pedidos to authenticated; grant REFERENCES on public.pedidos to authenticated; grant TRIGGER on public.pedidos to authenticated; grant MAINTAIN on public.pedidos to authenticated;
revoke all on public.pedidos_id_seq from anon, authenticated; grant SELECT on public.pedidos_id_seq to anon; grant UPDATE on public.pedidos_id_seq to anon; grant USAGE on public.pedidos_id_seq to anon; grant SELECT on public.pedidos_id_seq to authenticated; grant UPDATE on public.pedidos_id_seq to authenticated; grant USAGE on public.pedidos_id_seq to authenticated;
revoke all on public.productos_busqueda from anon, authenticated; grant INSERT on public.productos_busqueda to anon; grant SELECT on public.productos_busqueda to anon; grant UPDATE on public.productos_busqueda to anon; grant DELETE on public.productos_busqueda to anon; grant TRUNCATE on public.productos_busqueda to anon; grant REFERENCES on public.productos_busqueda to anon; grant TRIGGER on public.productos_busqueda to anon; grant MAINTAIN on public.productos_busqueda to anon; grant INSERT on public.productos_busqueda to authenticated; grant SELECT on public.productos_busqueda to authenticated; grant UPDATE on public.productos_busqueda to authenticated; grant DELETE on public.productos_busqueda to authenticated; grant TRUNCATE on public.productos_busqueda to authenticated; grant REFERENCES on public.productos_busqueda to authenticated; grant TRIGGER on public.productos_busqueda to authenticated; grant MAINTAIN on public.productos_busqueda to authenticated;
revoke all on public.productos_ocultos from anon, authenticated; grant INSERT on public.productos_ocultos to anon; grant SELECT on public.productos_ocultos to anon; grant UPDATE on public.productos_ocultos to anon; grant DELETE on public.productos_ocultos to anon; grant TRUNCATE on public.productos_ocultos to anon; grant REFERENCES on public.productos_ocultos to anon; grant TRIGGER on public.productos_ocultos to anon; grant MAINTAIN on public.productos_ocultos to anon; grant INSERT on public.productos_ocultos to authenticated; grant SELECT on public.productos_ocultos to authenticated; grant UPDATE on public.productos_ocultos to authenticated; grant DELETE on public.productos_ocultos to authenticated; grant TRUNCATE on public.productos_ocultos to authenticated; grant REFERENCES on public.productos_ocultos to authenticated; grant TRIGGER on public.productos_ocultos to authenticated; grant MAINTAIN on public.productos_ocultos to authenticated;
revoke all on public.productos_web from anon, authenticated; grant INSERT on public.productos_web to anon; grant SELECT on public.productos_web to anon; grant UPDATE on public.productos_web to anon; grant DELETE on public.productos_web to anon; grant TRUNCATE on public.productos_web to anon; grant REFERENCES on public.productos_web to anon; grant TRIGGER on public.productos_web to anon; grant MAINTAIN on public.productos_web to anon; grant INSERT on public.productos_web to authenticated; grant SELECT on public.productos_web to authenticated; grant UPDATE on public.productos_web to authenticated; grant DELETE on public.productos_web to authenticated; grant TRUNCATE on public.productos_web to authenticated; grant REFERENCES on public.productos_web to authenticated; grant TRIGGER on public.productos_web to authenticated; grant MAINTAIN on public.productos_web to authenticated;
revoke all on public.reglas_descuento from anon, authenticated; grant INSERT on public.reglas_descuento to anon; grant SELECT on public.reglas_descuento to anon; grant UPDATE on public.reglas_descuento to anon; grant DELETE on public.reglas_descuento to anon; grant TRUNCATE on public.reglas_descuento to anon; grant REFERENCES on public.reglas_descuento to anon; grant TRIGGER on public.reglas_descuento to anon; grant MAINTAIN on public.reglas_descuento to anon; grant INSERT on public.reglas_descuento to authenticated; grant SELECT on public.reglas_descuento to authenticated; grant UPDATE on public.reglas_descuento to authenticated; grant DELETE on public.reglas_descuento to authenticated; grant TRUNCATE on public.reglas_descuento to authenticated; grant REFERENCES on public.reglas_descuento to authenticated; grant TRIGGER on public.reglas_descuento to authenticated; grant MAINTAIN on public.reglas_descuento to authenticated;
revoke all on public.reglas_descuento_id_seq from anon, authenticated; grant SELECT on public.reglas_descuento_id_seq to anon; grant UPDATE on public.reglas_descuento_id_seq to anon; grant USAGE on public.reglas_descuento_id_seq to anon; grant SELECT on public.reglas_descuento_id_seq to authenticated; grant UPDATE on public.reglas_descuento_id_seq to authenticated; grant USAGE on public.reglas_descuento_id_seq to authenticated;
revoke all on public.scraping_ejecuciones from anon, authenticated;
revoke all on public.scraping_ejecuciones_id_seq from anon, authenticated; grant SELECT on public.scraping_ejecuciones_id_seq to anon; grant UPDATE on public.scraping_ejecuciones_id_seq to anon; grant USAGE on public.scraping_ejecuciones_id_seq to anon; grant SELECT on public.scraping_ejecuciones_id_seq to authenticated; grant UPDATE on public.scraping_ejecuciones_id_seq to authenticated; grant USAGE on public.scraping_ejecuciones_id_seq to authenticated;
revoke all on public.scraping_movimientos from anon, authenticated;
revoke all on public.scraping_movimientos_id_seq from anon, authenticated; grant SELECT on public.scraping_movimientos_id_seq to anon; grant UPDATE on public.scraping_movimientos_id_seq to anon; grant USAGE on public.scraping_movimientos_id_seq to anon; grant SELECT on public.scraping_movimientos_id_seq to authenticated; grant UPDATE on public.scraping_movimientos_id_seq to authenticated; grant USAGE on public.scraping_movimientos_id_seq to authenticated;
revoke all on public.scraping_precios from anon, authenticated;
revoke all on public.scraping_precios_id_seq from anon, authenticated; grant SELECT on public.scraping_precios_id_seq to anon; grant UPDATE on public.scraping_precios_id_seq to anon; grant USAGE on public.scraping_precios_id_seq to anon; grant SELECT on public.scraping_precios_id_seq to authenticated; grant UPDATE on public.scraping_precios_id_seq to authenticated; grant USAGE on public.scraping_precios_id_seq to authenticated;
revoke all on public.scraping_ultimo from anon, authenticated;
revoke all on public.tipos_cliente from anon, authenticated; grant INSERT on public.tipos_cliente to anon; grant SELECT on public.tipos_cliente to anon; grant UPDATE on public.tipos_cliente to anon; grant DELETE on public.tipos_cliente to anon; grant TRUNCATE on public.tipos_cliente to anon; grant REFERENCES on public.tipos_cliente to anon; grant TRIGGER on public.tipos_cliente to anon; grant MAINTAIN on public.tipos_cliente to anon; grant INSERT on public.tipos_cliente to authenticated; grant SELECT on public.tipos_cliente to authenticated; grant UPDATE on public.tipos_cliente to authenticated; grant DELETE on public.tipos_cliente to authenticated; grant TRUNCATE on public.tipos_cliente to authenticated; grant REFERENCES on public.tipos_cliente to authenticated; grant TRIGGER on public.tipos_cliente to authenticated; grant MAINTAIN on public.tipos_cliente to authenticated;
alter publication supabase_realtime add table public.adm_registros;
alter publication supabase_realtime add table public.en_linea;
alter publication supabase_realtime add table public.eventos;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values ('productos','productos',true,5242880,'{image/jpeg,image/png,image/webp}') on conflict do nothing;