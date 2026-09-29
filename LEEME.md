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

## 7. Google (Search Console)
- Cada día se generan páginas reales por producto (`/p/…`) y categoría (`/c/…`) con datos para Google, más `sitemap.xml`.
- `robots.txt` le dice a Google dónde está el sitemap y que no entre a `/admin`.
- Alta en Google: search.google.com/search-console → Agregar propiedad → **Dominio** `suinelectric.com` → verificar con Cloudflare → Sitemaps → `https://suinelectric.com/sitemap.xml`.

## 8. Estadísticas (qué buscan, qué ven y qué cotizan)
Supabase → **SQL Editor** → pega todo `04_estadisticas.sql` → **Run**. Desde ese momento la tienda anota búsquedas, fichas vistas, productos agregados al carrito y clics en WhatsApp (también desde las páginas `/p/…`). Se ve en el panel → **Estadísticas**. No se anota lo que hacen los administradores y los datos de más de un año se borran solos.

## 9. Archivar, eliminar y ver pedidos en detalle
Supabase → **SQL Editor** → pega todo `05_pedidos_archivo.sql` → **Run** (se puede volver a correr).
En el panel → **Pedidos**, cada pedido tiene:
- **Ver detalle** (o toca el número `#`): cliente con teléfono/WhatsApp y RIF, cada producto con foto, descripción completa, precio de lista, descuento y subtotal, y el botón **Copiar lista**.
- **Archivar**: lo saca de la lista y de "por atender", sin borrarlo. Se ve en el filtro **Archivados** y se puede desarchivar. El cliente lo sigue viendo en "Mi cuenta".
- **Eliminar**: lo borra para siempre (también para el cliente). Pide confirmación.

## 10. Actividad por cliente (qué busca, mira y cotiza cada uno)
Supabase → **SQL Editor** → pega todo `06_actividad_clientes.sql` → **Run** (requiere haber corrido antes `04_estadisticas.sql`).
- Panel → **Estadísticas** → al final, **Clientes más activos** (toca uno para ver su detalle).
- Panel → **Clientes** → botón **Actividad** (o dentro de Editar → Ver actividad).
- El detalle muestra: última visita, días activo, lo que buscó (y qué no encontró), lo que cotizó o puso en el carrito, los productos que miró, sus pedidos y el paso a paso por día.
- Solo cuenta lo que el cliente hace con la sesión iniciada; los visitantes sin cuenta siguen en las estadísticas generales.

## 11. Chat con un asesor (burbuja en la tienda → tu Telegram)
El visitante escribe en la burbuja **¿Te ayudamos?** de la tienda (o en **💬 Preguntar a un asesor** dentro de un producto). Cada mensaje te llega a SuinBot como **💬 Chat #12**. Tú **respondes a ese mensaje** en Telegram (celular o PC) y la respuesta le aparece al cliente en la tienda. La conversación queda guardada en su navegador, así que si vuelve después la ve completa.

1. Supabase → **SQL Editor** → pega todo `08_chat.sql` → **Run** (requiere `07_notificaciones.sql`).
2. Cloudflare → **Workers & Pages** → proyecto de la tienda → **Settings → Variables and Secrets** → agrega en **Production** (tipo *Secret*):
   - `TELEGRAM_TOKEN` = token de SuinBot
   - `TELEGRAM_CHAT_ID` = tu chat_id (el mismo que guardaste en el Vault de Supabase)
   - `TELEGRAM_WEBHOOK_SECRET` = una clave inventada por ti, solo letras y números (ej. `suinChat2026xyz`)
   - `SUPABASE_URL` = `https://yqnlxhbjassrkudnhvpr.supabase.co`
   - `SUPABASE_SECRET_KEY` = la clave `sb_secret_…` (la misma de GitHub)
3. Publica (sube los cambios a `main`; la carpeta `functions/` la publica Cloudflare sola).
4. Conecta SuinBot abriendo una sola vez: `https://suinelectric.com/api/telegram?configurar=TU_WEBHOOK_SECRET` → debe decir **✅ Listo** y te llega un mensaje de SuinBot.

En Telegram:
- **Responder** (deslizar el mensaje o mantener presionado → Responder) al aviso *💬 Chat #12* → le llega al cliente. SuinBot marca tu mensaje con 👍.
- `#12 tu mensaje` → le escribe al chat 12 sin buscar el aviso.
- `/chats` → últimos 10 chats (🟡 = el cliente espera respuesta).

## 12. Asistente con IA en el chat (Gemini, gratis)
La IA contesta primero: hace 1 o 2 preguntas (potencia, voltaje, tipo de carga), busca en tu catálogo y recomienda hasta 3 productos **con su enlace**. **No da precios** (el precio está en el enlace). Si el cliente pide cotizar, descuentos, hablar con una persona, etc., te pasa el chat.

1. **Clave de Gemini**: aistudio.google.com → **Get API key** → **Create API key**. Guárdala en Cloudflare (Settings → Variables and Secrets, Production, tipo Secret) como `GEMINI_API_KEY`.
2. Supabase → **SQL Editor** → pega todo `09_asistente.sql` → **Run**.
3. GitHub → **Actions** → **Subir catálogo del asistente (chat)** → **Run workflow** (sube el catálogo sin precios a Supabase; después se actualiza solo cada día).

En Telegram:
- 🤖 **Chat #12**: la IA respondió (llega en silencio, salvo el primer mensaje de cada chat). Ves lo que preguntó el cliente y lo que contestó la IA.
- 🙋 **Chat #12 — pide asesor**: la IA te pasó el chat (con sonido). Desde ahí la IA no contesta en ese chat.
- ⚠️ **Chat #12**: la IA no pudo responder (sin clave, sin cupo gratis del día…). El cliente recibe "un asesor te escribirá" y el chat queda para ti.
- **Si respondes cualquier chat, la IA se calla en ese chat.** `/ia 12` la vuelve a encender; `/ia 12 off` la apaga.

## 13. Visitantes sin cuenta (cuántos entran, de dónde, cuándo, qué buscan y qué tarjetas ven)
1. Supabase → **SQL Editor** → pega todo `10_visitantes.sql` → **Run** (requiere `04_estadisticas.sql`; se puede volver a correr).
2. Publica (sube los cambios a `main`). Cloudflare publica `rastreo.js` y la función `functions/api/geo.js` (no necesita claves).
3. Panel → **Visitantes**:
   - Visitas, personas distintas, nuevas y cuántas hay **en la tienda ahora**.
   - Visitas por día, **a qué hora** y **qué días** entran (hora de Venezuela).
   - **País, ciudad y proveedor de internet** (CANTV, Movilnet, Digitel…), aproximados por la conexión.
   - **Cómo llegan** (Google, Instagram, Facebook, MercadoLibre, directo…) y por qué página entraron.
   - Equipo (celular o computadora), sistema y navegador.
   - Lo que buscan y las **tarjetas de producto que tuvieron en pantalla**, con cuántas veces abrieron la ficha.
   - **Visitas recientes**: toca una para ver todo lo que hizo esa persona, visita por visita (lo que buscó, qué tarjetas vio y dónde, qué fichas abrió, si agregó al pedido o escribió por WhatsApp).

Notas:
- Cada navegador recibe un código aleatorio; no se guardan nombres, correos ni la IP. Si la persona borra los datos del navegador o entra desde otro equipo, cuenta como nueva.
- Una tarjeta cuenta como "vista" si estuvo al menos a la mitad en pantalla casi un segundo (una vez por visita y por sección).
- No se cuenta a los administradores: al entrar al panel, ese navegador queda marcado para no contarse nunca más (aunque luego entre a la tienda sin sesión). Tampoco a robots como Google.
- Si todavía no corriste `10_visitantes.sql`, la tienda sigue anotando las estadísticas de antes, sin los datos nuevos.
