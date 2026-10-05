-- =====================================================================
--  SUINELECTRIC · Cuentas de clientes, descuentos y pedidos (fase 1)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
-- =====================================================================

-- ---------- Tipos de cliente ----------
create table if not exists public.tipos_cliente (
  id     text primary key,                 -- ej. 'distribuidor'
  nombre text not null,                    -- ej. 'Distribuidor'
  orden  int  not null default 0
);
insert into public.tipos_cliente (id, nombre, orden) values
  ('distribuidor', 'Distribuidor', 1),
  ('instalador',   'Instalador',   2),
  ('final',        'Cliente final', 3)
on conflict (id) do nothing;

-- ---------- Clientes ----------
-- Se identifican por su correo. Puedes crear el cliente antes de que entre
-- por primera vez: cuando entre con ese correo, queda enlazado solo.
create table if not exists public.clientes (
  email       text primary key check (email = lower(email)),
  user_id     uuid unique references auth.users(id) on delete set null,
  nombre      text,
  empresa     text,
  rif         text,
  telefono    text,
  direccion   text,
  tipo_id     text default 'final' references public.tipos_cliente(id) on update cascade on delete set null,
  es_admin    boolean not null default false,
  activo      boolean not null default true,
  creado      timestamptz not null default now(),
  actualizado timestamptz not null default now()
);

-- ---------- Reglas de descuento ----------
-- Cada regla dice A QUIÉN (cliente, tipo de cliente o todos) y A QUÉ
-- (un modelo, una marca o todo), y el precio: % de descuento sobre la lista
-- O un precio fijo en USD. Siempre gana la regla más específica.
create table if not exists public.reglas_descuento (
  id            bigint generated always as identity primary key,
  cliente_email text references public.clientes(email) on update cascade on delete cascade,
  tipo_id       text references public.tipos_cliente(id) on update cascade on delete cascade,
  marca         text,            -- en MAYÚSCULAS, ej. 'SCHNEIDER' (vacío = todas)
  modelo        text,            -- ej. 'GD20-2R2G-S2' (vacío = todos)
  descuento_pct numeric(5,2) check (descuento_pct >= 0 and descuento_pct <= 100),
  precio_fijo   numeric(12,2) check (precio_fijo >= 0),
  activo        boolean not null default true,
  nota          text,
  creado        timestamptz not null default now(),
  constraint regla_un_precio  check ((descuento_pct is null) <> (precio_fijo is null)),
  constraint regla_un_destino check (not (cliente_email is not null and tipo_id is not null)),
  constraint regla_fijo_modelo check (precio_fijo is null or modelo is not null)
);
create index if not exists reglas_cliente_idx on public.reglas_descuento (cliente_email);
create index if not exists reglas_tipo_idx    on public.reglas_descuento (tipo_id);

-- Descuento general de la tienda (visitantes sin cuenta): una regla sin
-- cliente, sin tipo, sin marca y sin modelo.
insert into public.reglas_descuento (descuento_pct, nota)
select 60, 'Descuento general de la tienda'
where not exists (
  select 1 from public.reglas_descuento
  where cliente_email is null and tipo_id is null and marca is null and modelo is null
);

-- ---------- Pedidos ----------
create table if not exists public.pedidos (
  id            bigint generated always as identity primary key,
  cliente_email text not null references public.clientes(email) on update cascade,
  estado        text not null default 'enviado'
                check (estado in ('enviado','cotizado','aprobado','pagado','entregado','cancelado')),
  items         jsonb not null,          -- [{modelo, marca, descripcion, cantidad, precio_unit}]
  total         numeric(12,2),
  nota_cliente  text,
  nota_admin    text,                    -- comentario de Suinelectric (el cliente lo ve)
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now()
);
create index if not exists pedidos_cliente_idx on public.pedidos (cliente_email, creado desc);

-- ---------- Funciones de apoyo ----------
create or replace function public.mi_email() returns text
language sql stable as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

create or replace function public.es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.clientes
                 where email = public.mi_email() and es_admin and activo)
$$;

create or replace function public.mi_tipo() returns text
language sql stable security definer set search_path = public as $$
  select tipo_id from public.clientes where email = public.mi_email()
$$;

-- Fecha de "actualizado"
create or replace function public.tocar_actualizado() returns trigger
language plpgsql as $$
begin new.actualizado := now(); return new; end $$;

drop trigger if exists clientes_actualizado on public.clientes;
create trigger clientes_actualizado before update on public.clientes
  for each row execute function public.tocar_actualizado();
drop trigger if exists pedidos_actualizado on public.pedidos;
create trigger pedidos_actualizado before update on public.pedidos
  for each row execute function public.tocar_actualizado();

-- Un cliente solo puede cambiar sus datos de contacto; tipo, admin,
-- activo y correo solo los cambia un administrador.
-- (Solo aplica a cambios hechos desde la web; los internos, como enlazar la
-- cuenta al registrarse, pasan sin restricción.)
create or replace function public.proteger_cliente() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') and not public.es_admin() then
    new.email    := old.email;
    new.user_id  := old.user_id;
    new.tipo_id  := old.tipo_id;
    new.es_admin := old.es_admin;
    new.activo   := old.activo;
    new.creado   := old.creado;
  end if;
  return new;
end $$;
drop trigger if exists clientes_proteger on public.clientes;
create trigger clientes_proteger before update on public.clientes
  for each row execute function public.proteger_cliente();

-- Cuando alguien entra por primera vez, se crea (o se enlaza) su ficha.
create or replace function public.al_registrarse() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.clientes (email, user_id)
  values (lower(new.email), new.id)
  on conflict (email) do update set user_id = excluded.user_id;
  return new;
end $$;
drop trigger if exists al_registrarse on auth.users;
create trigger al_registrarse after insert on auth.users
  for each row execute function public.al_registrarse();

-- ---------- Seguridad (quién ve y cambia qué) ----------
alter table public.tipos_cliente    enable row level security;
alter table public.clientes         enable row level security;
alter table public.reglas_descuento enable row level security;
alter table public.pedidos          enable row level security;

drop policy if exists tipos_leer  on public.tipos_cliente;
drop policy if exists tipos_admin on public.tipos_cliente;
create policy tipos_leer  on public.tipos_cliente for select to anon, authenticated using (true);
create policy tipos_admin on public.tipos_cliente for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists clientes_leer   on public.clientes;
drop policy if exists clientes_editar on public.clientes;
drop policy if exists clientes_admin  on public.clientes;
create policy clientes_leer   on public.clientes for select to authenticated
  using (email = public.mi_email() or public.es_admin());
create policy clientes_editar on public.clientes for update to authenticated
  using (email = public.mi_email()) with check (email = public.mi_email());
create policy clientes_admin  on public.clientes for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- Reglas: cada quien ve solo las que le aplican (nunca las de otro cliente).
drop policy if exists reglas_leer  on public.reglas_descuento;
drop policy if exists reglas_admin on public.reglas_descuento;
create policy reglas_leer on public.reglas_descuento for select to anon, authenticated
  using (
    activo and (
      (cliente_email is null and tipo_id is null)
      or cliente_email = public.mi_email()
      or (cliente_email is null and tipo_id = public.mi_tipo())
    )
    or public.es_admin()
  );
create policy reglas_admin on public.reglas_descuento for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

drop policy if exists pedidos_leer  on public.pedidos;
drop policy if exists pedidos_crear on public.pedidos;
drop policy if exists pedidos_admin on public.pedidos;
create policy pedidos_leer  on public.pedidos for select to authenticated
  using (cliente_email = public.mi_email() or public.es_admin());
create policy pedidos_crear on public.pedidos for insert to authenticated
  with check (cliente_email = public.mi_email() and estado = 'enviado' and nota_admin is null);
create policy pedidos_admin on public.pedidos for all to authenticated
  using (public.es_admin()) with check (public.es_admin());

-- ---------- Administrador ----------
-- Cambia el correo si usarás otro para entrar como administrador.
insert into public.clientes (email, nombre, empresa, tipo_id, es_admin)
values ('manolo1496@gmail.com', 'Manuel', 'Suinelectric', null, true)
on conflict (email) do update set es_admin = true;

-- ---------- Permisos de acceso desde la web ----------
-- (Las políticas de arriba deciden qué filas ve cada quien.)
grant usage on schema public to anon, authenticated;
grant select on public.tipos_cliente, public.reglas_descuento to anon;
grant select, insert, update, delete on public.tipos_cliente, public.clientes,
      public.reglas_descuento, public.pedidos to authenticated;
grant usage, select on all sequences in schema public to authenticated;
