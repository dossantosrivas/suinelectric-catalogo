-- =====================================================================
--  SUINELECTRIC · Bloqueo de visitantes (por navegador y por IP)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 13_en_vivo.sql.
--
--  · bloqueos           → lista de bloqueados. tipo 'codigo' = el código
--                         de navegador del visitante; tipo 'ip' = su
--                         dirección IP (en IPv6, el bloque /64 de su red).
--  · en_linea.ip        → la IP de cada visitante que está (o estuvo en
--                         los últimos 2 días) en la web. Solo se guarda
--                         aquí, para poder bloquear; no va al historial.
--  · acceso_bloqueado() → la web pregunta si este visitante está
--                         bloqueado (rastreo.js) y, si lo está, muestra
--                         "página no disponible".
--  · bloquear_visitante() → lo usa el panel (En vivo → Bloquear).
--
--  Quién NO se bloquea nunca: los administradores con su sesión abierta.
--  El bloqueo por IP no afecta a clientes con su cuenta abierta (varias
--  personas pueden compartir una misma IP); el bloqueo por código sí.
--  Solo los administradores pueden ver y cambiar la lista.
-- =====================================================================

-- ---------------------------------------------------------------------
--  IP de quien hace la petición (la entrega Cloudflare/Supabase)
-- ---------------------------------------------------------------------
create or replace function public.ip_peticion() returns text
language plpgsql stable set search_path = public as $$
declare
  h json;
  v text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then return null;
  end;
  if h is null then return null; end if;
  v := coalesce(nullif(trim(h->>'cf-connecting-ip'), ''),
                nullif(trim(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)), ''),
                nullif(trim(h->>'x-real-ip'), ''));
  if v is null then return null; end if;
  begin
    return host(v::inet);
  exception when others then return null;
  end;
end $$;

-- Con qué se compara una IP: IPv4 tal cual; IPv6 por su red /64
-- (en IPv6 el equipo cambia de dirección a cada rato dentro de su red).
create or replace function public.ip_clave(p text) returns text
language plpgsql immutable set search_path = public as $$
declare
  i inet;
begin
  if p is null or trim(p) = '' then return null; end if;
  i := split_part(trim(p), '/', 1)::inet;
  if family(i) = 6 then return host(network(set_masklen(i, 64))) || '/64'; end if;
  return host(i);
exception when others then return null;
end $$;

-- ---------------------------------------------------------------------
--  La IP de quien está en línea
-- ---------------------------------------------------------------------
alter table public.en_linea add column if not exists ip text check (char_length(ip) <= 45);
-- ip_red: lo que se compara con la lista de bloqueos (IPv4 = la misma IP; IPv6 = su red /64).
alter table public.en_linea add column if not exists ip_red text check (char_length(ip_red) <= 60);

create or replace function public.en_linea_poner_ip() returns trigger
language plpgsql set search_path = public as $$
begin
  new.ip := coalesce(public.ip_peticion(), new.ip);
  new.ip_red := public.ip_clave(new.ip);
  return new;
end $$;
drop trigger if exists en_linea_poner_ip on public.en_linea;
create trigger en_linea_poner_ip before insert or update on public.en_linea
  for each row execute function public.en_linea_poner_ip();

-- ---------------------------------------------------------------------
--  Lista de bloqueados
-- ---------------------------------------------------------------------
create table if not exists public.bloqueos (
  id             bigint generated always as identity primary key,
  tipo           text not null check (tipo in ('codigo', 'ip')),
  valor          text not null check (char_length(valor) between 1 and 60),
  nota           text check (char_length(nota) <= 200),       -- por qué lo bloqueaste
  detalle        text check (char_length(detalle) <= 200),    -- lugar y equipo al bloquear
  creado         timestamptz not null default now(),
  creado_por     text,
  intentos       integer not null default 0,                  -- veces que intentó entrar estando bloqueado
  ultimo_intento timestamptz,
  unique (tipo, valor)
);

alter table public.bloqueos enable row level security;
drop policy if exists bloqueos_admin on public.bloqueos;
create policy bloqueos_admin on public.bloqueos for all to authenticated
  using (public.es_admin()) with check (public.es_admin());
revoke all on public.bloqueos from anon;
grant select, insert, update, delete on public.bloqueos to authenticated;

-- ---------------------------------------------------------------------
--  ¿Este visitante está bloqueado? (lo pregunta la web)
-- ---------------------------------------------------------------------
create or replace function public.acceso_bloqueado(p_visitante text, p_contar boolean default true) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_email text := nullif(public.mi_email(), '');
  v_ip    text := public.ip_clave(public.ip_peticion());
  v_cod   text := left(nullif(trim(p_visitante), ''), 40);
  v_id    bigint;
begin
  -- Los administradores nunca quedan bloqueados.
  if v_email is not null and exists (select 1 from clientes where email = v_email and es_admin) then return false; end if;

  select id into v_id from bloqueos
  where (tipo = 'codigo' and v_cod is not null and valor = v_cod)
     or (tipo = 'ip' and v_email is null and v_ip is not null and valor = v_ip)
  order by tipo limit 1;
  if v_id is null then return false; end if;

  if coalesce(p_contar, true) then
    update bloqueos set intentos = intentos + 1, ultimo_intento = now() where id = v_id;
  end if;
  return true;
end $$;
revoke all on function public.acceso_bloqueado(text, boolean) from public;
grant execute on function public.acceso_bloqueado(text, boolean) to anon, authenticated;

-- ---------------------------------------------------------------------
--  Bloquear desde el panel
--  Devuelve {ok, id, valor, propia}: propia = true si la IP que se
--  bloqueó es la misma desde la que estás usando el panel.
-- ---------------------------------------------------------------------
create or replace function public.bloquear_visitante(p_tipo text, p_valor text, p_nota text default null, p_detalle text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_valor text;
  v_id    bigint;
begin
  if not public.es_admin() then raise exception 'Solo los administradores pueden bloquear'; end if;
  if p_tipo = 'ip' then
    v_valor := public.ip_clave(p_valor);
    if v_valor is null then raise exception 'La dirección IP no es válida'; end if;
  elsif p_tipo = 'codigo' then
    v_valor := left(nullif(trim(p_valor), ''), 40);
    if v_valor is null then raise exception 'Falta el código del visitante'; end if;
  else
    raise exception 'Tipo de bloqueo desconocido';
  end if;

  insert into bloqueos (tipo, valor, nota, detalle, creado_por)
  values (p_tipo, v_valor, left(nullif(trim(p_nota), ''), 200), left(nullif(trim(p_detalle), ''), 200), public.mi_email())
  on conflict (tipo, valor) do update set
    nota = coalesce(excluded.nota, bloqueos.nota),
    detalle = coalesce(excluded.detalle, bloqueos.detalle)
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id, 'valor', v_valor,
    'propia', p_tipo = 'ip' and v_valor = public.ip_clave(public.ip_peticion()));
end $$;
revoke all on function public.bloquear_visitante(text, text, text, text) from public;
grant execute on function public.bloquear_visitante(text, text, text, text) to authenticated;

-- La IP desde la que está el administrador (para avisarle si va a bloquear la suya).
create or replace function public.mi_ip_clave() returns text
language sql stable security definer set search_path = public as $$
  select case when public.es_admin() then public.ip_clave(public.ip_peticion()) end
$$;
revoke all on function public.mi_ip_clave() from public;
grant execute on function public.mi_ip_clave() to authenticated;
