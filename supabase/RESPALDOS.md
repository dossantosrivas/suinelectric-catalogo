# Respaldos de Supabase y verificación del catálogo

## 1. Respaldo diario de Supabase

El flujo **"Respaldo diario de Supabase"** (`.github/workflows/respaldo-supabase.yml`)
corre todos los días a las 3:52 a.m. (hora de Venezuela) y guarda una copia completa
de la base de datos principal: clientes, ventas, ofertas, notas, inventario, cuentas
de la tienda, políticas de seguridad (RLS) y funciones.

- Se guarda **cifrado** durante **90 días** en GitHub → Actions → la corrida → *Artifacts*.
- Los **domingos** también te llega el archivo por Telegram (SuinBot), así tienes
  una copia fuera de GitHub que no vence.
- Si falla, SuinBot te avisa.
- El repo es público: el respaldo **nunca** se sube al repo y sin `RESPALDO_CLAVE`
  nadie puede abrirlo.

### Configuración (una sola vez)

En GitHub → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Qué poner |
|---|---|
| `SUPABASE_DB_URL` | Supabase → tu proyecto → botón **Connect** → **Session pooler** → copia la cadena `postgresql://postgres.yqnlxhbjassrkudnhvpr:[YOUR-PASSWORD]@…pooler.supabase.com:5432/postgres` y reemplaza `[YOUR-PASSWORD]` por la contraseña de la base de datos. Si no la recuerdas: Project Settings → Database → *Reset database password* (no afecta la tienda ni las apps, que usan las claves de API). |
| `RESPALDO_CLAVE` | Una frase larga que inventes (ej. 5–6 palabras). **Guárdala en un lugar seguro fuera de GitHub**: sin ella los respaldos no se pueden abrir. |

Usa *Session pooler* y no *Direct connection*: los servidores de GitHub no tienen IPv6.

Prueba: Actions → "Respaldo diario de Supabase" → **Run workflow**.

### Abrir un respaldo

Necesitas `gpg` (en Windows viene con Git Bash o Gpg4win).

```sh
gpg -d suinelectric-respaldo-2026-10-11.tar.gz.gpg > respaldo.tar.gz   # pide RESPALDO_CLAVE
tar xzf respaldo.tar.gz
# quedan roles.sql, esquema.sql y datos.sql
```

(El archivo descargado de *Artifacts* viene dentro de un .zip: descomprímelo primero.)

### Restaurar

**Recuperar algo borrado** (lo más común): abre `datos.sql`, busca la tabla
(`COPY public.nombre_tabla`) y copia las filas que necesites; o restaura todo en un
proyecto Supabase nuevo/vacío (como el beta) y de ahí copias lo que falte.

**Restaurar completo en un proyecto nuevo:**

```sh
psql --single-transaction --variable ON_ERROR_STOP=1 \
  --file roles.sql \
  --file esquema.sql \
  --command 'SET session_replication_role = replica' \
  --file datos.sql \
  --dbname "postgresql://postgres.[REF-NUEVO]:[CLAVE]@…pooler.supabase.com:5432/postgres"
```

No restaures encima del proyecto en uso sin respaldar antes el estado actual.
Después de restaurar en un proyecto nuevo hay que activar Realtime en las tablas
que lo usaban (Database → Publications) y cambiar la URL/claves en las webs.

## 2. Verificación del catálogo antes de publicar

`verificar-catalogo.js` corre en "Actualizar catálogo diario" justo después del
scraper y antes de subir nada a Supabase o a la tienda. Compara contra lo publicado
ayer y **no publica** si:

| Revisión | Límite |
|---|---|
| El scraper no terminó o está en modo prueba | — |
| Menos de N productos | 1.500 |
| Menos productos que ayer | más de 10 % de caída |
| El scraper leyó pocos de los que esperaba | menos de 95 % |
| Productos que perdieron el precio | más de 5 % |
| Productos con salto de precio de ±40 % o más | más de 3 % de los productos |
| Caída de las unidades totales en existencia | más de 50 % |

Si frena, la tienda queda con los datos de ayer y SuinBot te manda el detalle.
Si solo unos pocos productos cambian de precio más de ±40 %, publica igual y te
manda la lista para revisar.

**Si el cambio es real** (por ejemplo, el distribuidor subió todos los precios):
Actions → "Actualizar catálogo diario" → **Run workflow** → marca
*"Publicar aunque la verificación falle"*.

Los límites se cambian al inicio de `verificar-catalogo.js` (o con variables
`VERIF_*` en el flujo).
