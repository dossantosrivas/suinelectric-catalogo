-- =====================================================================
-- 14 · Precio para clientes registrados
-- Permite que cualquier visitante (incluso sin sesión) lea las reglas de
-- descuento del tipo "Cliente final" (el que reciben las cuentas nuevas),
-- para que la tienda le muestre "Precio para clientes registrados" y lo
-- invite a registrarse. Las reglas por cliente y las de otros tipos
-- (distribuidor, etc.) siguen siendo privadas.
-- Ejecutar una sola vez en Supabase → SQL Editor.
-- =====================================================================

drop policy if exists reglas_leer on public.reglas_descuento;
create policy reglas_leer on public.reglas_descuento for select to anon, authenticated
  using (
    activo and (
      (cliente_email is null and tipo_id is null)
      or cliente_email = public.mi_email()
      or (cliente_email is null and tipo_id = public.mi_tipo())
      or (cliente_email is null and tipo_id = 'final')   -- nuevo: precio de registro visible para todos
    )
    or public.es_admin()
  );
