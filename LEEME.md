# Cuentas de clientes · Puesta en marcha

Archivos:
- `supabase/01_esquema.sql`: crea las tablas, la seguridad y te deja como administrador (manolo1496@gmail.com).
- `tienda.html`: tienda con el botón **Ingresar**, precios por cliente y pedidos guardados.
- `admin.html`: panel de administrador (pedidos, clientes, descuentos y tipos de cliente).

## 1. Crear la base de datos (una sola vez)
Supabase → **SQL Editor** → **New query** → pega todo `01_esquema.sql` → **Run**.
Se puede volver a correr sin perder datos.

## 2. Direcciones permitidas
Supabase → **Authentication → URL Configuration**
- **Site URL**: la dirección de tu tienda en Cloudflare, ej. `https://TU-SITIO.pages.dev/tienda`
- **Redirect URLs**: agrega `https://TU-SITIO.pages.dev/**` (y tu dominio propio si lo conectas, ej. `https://tienda.suinelectric.com/**`)

Sin esto, el enlace del correo lleva a `localhost` y no funciona.

## 3. Correo propio (obligatorio para clientes)
El correo que trae Supabase por defecto **solo envía a los miembros de tu equipo de Supabase** y máximo 2 por hora.
Para que les llegue a tus clientes:
Supabase → **Authentication → Emails → SMTP Settings** → activar **Custom SMTP**.

Opción rápida con Gmail:
1. En tu cuenta Google activa la verificación en 2 pasos y crea una **contraseña de aplicación** (myaccount.google.com → Seguridad → Contraseñas de aplicaciones).
2. En Supabase: Host `smtp.gmail.com`, Port `587`, User = tu Gmail, Password = la contraseña de aplicación, Sender email = tu Gmail, Sender name = `Suinelectric`.

(También sirven Brevo, Resend o Zoho, si prefieres un correo @suinelectric.)

## 4. Código de 6 dígitos en el correo (recomendado)
Así el cliente puede escribir el código en la tienda, aunque abra el correo en otro teléfono.
Supabase → **Authentication → Emails → Templates** → en **Magic Link** y en **Confirm signup** reemplaza el contenido por:

```html
<h2>Tu acceso a Suinelectric</h2>
<p>Tu código es: <strong style="font-size:22px">{{ .Token }}</strong></p>
<p>O entra directo con este enlace: <a href="{{ .ConfirmationURL }}">Entrar a la tienda</a></p>
```

## 5. Subir los archivos
Sube `tienda.html` y `admin.html` al repo (o como `tienda-prueba.html` para probar primero).
Cloudflare publica solo al detectar el cambio en GitHub. El panel queda en `https://TU-SITIO.pages.dev/admin`. Solo entran las cuentas marcadas como administrador.

## Cómo se calculan los precios
Gana la regla más específica (no se suman):

1. Modelo + cliente → 2. Modelo + tipo → 3. Modelo (todos)
4. Marca + cliente → 5. Cliente (todo)
6. Marca + tipo → 7. Tipo (todo)
8. Marca (todos) → 9. Descuento general (todos, todo el catálogo)

Los productos cargados a mano (`productos_manuales.json`) mantienen su precio de catálogo salvo que tengan una regla de su marca o modelo.
El precio fijo (en USD) solo se puede poner a un modelo.

## 6. Existencias reales solo para quien tú elijas
La tienda pública muestra "+10 disponibles", "Últimas unidades" o "Agotado". Las cantidades exactas solo las ven los administradores y los clientes (o tipos de cliente) a quienes les des permiso en el panel → **Existencias**.

1. Supabase → **SQL Editor** → pega todo `03_existencias.sql` → **Run** (se puede volver a correr).
2. Supabase → **Project Settings → API Keys** → copia una **Secret key** (empieza con `sb_secret_`).
3. GitHub → el repo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `SUPABASE_URL` = `https://yqnlxhbjassrkudnhvpr.supabase.co`
   - `SUPABASE_SECRET_KEY` = la clave del paso 2 (nunca la pongas en un archivo del repo)
4. Cada día, después del scraper, `subir-existencias.js` sube las cantidades a Supabase.
