-- =====================================================================
--  SUINELECTRIC · Productos de la web desde el panel
--  (panel → Productos: directorio, agregar, editar y ocultar)
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--  Requiere haber corrido antes 01_esquema.sql.
--
--  · productos_web       → productos que agregas o corriges desde el panel.
--                          La tienda los muestra AL INSTANTE (se suman a los
--                          manuales; si el modelo ya existe en
--                          productos_manuales.json, gana la versión del panel).
--  · productos_ocultos   → modelos que no quieres mostrar en la web (vengan
--                          del proveedor, de productos_manuales.json o del panel).
--  · Storage "productos" → fotos que subes desde el panel (públicas).
--
--  Cada noche, la actualización del catálogo (GitHub Actions) los pasa a
--  catalogo-tienda.json: así tienen su página /p/ para Google y WhatsApp,
--  y sus fotos quedan servidas desde suinelectric.com.
--  Todos pueden LEER lo publicado (la tienda lo necesita); solo los
--  administradores pueden crear, cambiar u ocultar.
-- =====================================================================

create table if not exists public.productos_web (
  modelo              text primary key check (char_length(modelo) between 1 and 80),
  nombre              text check (char_length(nombre) <= 200),
  marca               text not null check (char_length(marca) between 1 and 80),
  categoria_principal text not null check (char_length(categoria_principal) between 1 and 120),
  subcategorias       text[] not null default '{}',
  descripcion         text check (char_length(descripcion) <= 4000),
  precio              numeric check (precio is null or precio >= 0),
  disponible          boolean not null default true,
  existencias         integer check (existencias is null or existencias >= 0),
  imagenes            text[] not null default '{}',
  notas               text check (char_length(notas) <= 1000),        -- solo para ti, no sale en la web
  activo              boolean not null default true,                  -- false = borrador (no sale en la web)
  creado              timestamptz not null default now(),
  actualizado         timestamptz not null default now(),
  creado_por          text
);

create table if not exists public.productos_ocultos (
  modelo  text primary key check (char_length(modelo) between 1 and 80),
  motivo  text check (char_length(motivo) <= 300),
  creado  timestamptz not null default now(),
  por     text
);

create or replace function public.productos_web_completar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.modelo := trim(new.modelo);
  new.marca := upper(trim(new.marca));
  new.actualizado := now();
  if tg_op = 'INSERT' then new.creado := now(); new.creado_por := public.mi_email(); end if;
  new.subcategorias := coalesce((select array_agg(trim(s)) from unnest(new.subcategorias) s where trim(s) <> ''), '{}');
  new.imagenes := coalesce((select array_agg(i) from unnest(new.imagenes[1:8]) i where i is not null and i <> ''), '{}');
  return new;
end $$;
drop trigger if exists productos_web_completar on public.productos_web;
create trigger productos_web_completar before insert or update on public.productos_web
  for each row execute function public.productos_web_completar();

create or replace function public.productos_ocultos_completar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.creado := now(); new.por := public.mi_email();
  return new;
end $$;
drop trigger if exists productos_ocultos_completar on public.productos_ocultos;
create trigger productos_ocultos_completar before insert or update on public.productos_ocultos
  for each row execute function public.productos_ocultos_completar();

alter table public.productos_web     enable row level security;
alter table public.productos_ocultos enable row level security;

drop policy if exists productos_web_leer     on public.productos_web;
drop policy if exists productos_web_admin    on public.productos_web;
drop policy if exists productos_ocultos_leer  on public.productos_ocultos;
drop policy if exists productos_ocultos_admin on public.productos_ocultos;
-- La tienda lee lo publicado; el panel lee todo (incluidos borradores).
create policy productos_web_leer  on public.productos_web for select to anon, authenticated using (activo or public.es_admin());
create policy productos_web_admin on public.productos_web for all to authenticated using (public.es_admin()) with check (public.es_admin());
create policy productos_ocultos_leer  on public.productos_ocultos for select to anon, authenticated using (true);
create policy productos_ocultos_admin on public.productos_ocultos for all to authenticated using (public.es_admin()) with check (public.es_admin());
grant select on public.productos_web, public.productos_ocultos to anon, authenticated;
grant insert, update, delete on public.productos_web, public.productos_ocultos to authenticated;

-- ---------------------------------------------------------------------
--  Fotos: carpeta pública "productos" en Supabase Storage
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('productos', 'productos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists productos_fotos_subir  on storage.objects;
drop policy if exists productos_fotos_cambiar on storage.objects;
drop policy if exists productos_fotos_borrar on storage.objects;
create policy productos_fotos_subir   on storage.objects for insert to authenticated with check (bucket_id = 'productos' and public.es_admin());
create policy productos_fotos_cambiar on storage.objects for update to authenticated using (bucket_id = 'productos' and public.es_admin());
create policy productos_fotos_borrar  on storage.objects for delete to authenticated using (bucket_id = 'productos' and public.es_admin());
