-- =====================================================================
--  SUINELECTRIC · Archivar pedidos
--  Cómo usarlo: Supabase → SQL Editor → New query → pega TODO este
--  archivo → Run. Se puede volver a correr sin perder datos.
--
--  · Un pedido archivado sale de la lista normal del panel (y no cuenta
--    como "por atender"), pero no se borra: lo ves en el filtro
--    "Archivados" y lo puedes desarchivar cuando quieras.
--  · El cliente lo sigue viendo en "Mi cuenta" como siempre.
--  · Eliminar sí borra el pedido para siempre (ya lo permitía la
--    seguridad de 01_esquema.sql, solo para administradores).
-- =====================================================================

alter table public.pedidos add column if not exists archivado    boolean not null default false;
alter table public.pedidos add column if not exists archivado_en timestamptz;

-- Un cliente no puede crear pedidos ya archivados.
drop policy if exists pedidos_crear on public.pedidos;
create policy pedidos_crear on public.pedidos for insert to authenticated
  with check (cliente_email = public.mi_email() and estado = 'enviado'
              and nota_admin is null and archivado = false);
