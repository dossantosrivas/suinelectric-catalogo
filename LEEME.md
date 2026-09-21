# Catálogo sincronizado de grupo-electricos.com

## Archivos
- `scraper.py` — lee el catálogo de grupo-electricos.com y genera `productos.json`.
- `productos.json` — datos de ejemplo (8 productos reales tomados de la portada) para que puedas probar `tienda.html` ya mismo. El scraper los reemplaza por el catálogo completo cuando lo corras.
- `tienda.html` — la tienda web. Lee `productos.json` (debe estar en la misma carpeta) y muestra el catálogo con buscador, filtro por categoría/disponibilidad y botón de WhatsApp por producto.

## Para probarlo ya
1. Abre una terminal en esta carpeta.
2. Levanta un servidor simple: `python3 -m http.server 8000`
3. Abre `http://localhost:8000/tienda.html` en el navegador. Verás los 8 productos de ejemplo.

## Para correr el scraper real
1. Instala dependencias: `pip install requests beautifulsoup4 lxml`
2. Corre: `python3 scraper.py`
3. Esto sobrescribe `productos.json` con el catálogo completo real.
4. Revisa el log en pantalla — si ves muy pocos productos o errores 403/429, es señal de que el sitio está bloqueando el scraping o cambió su estructura HTML; en ese caso lo ajustamos juntos.

## Para que corra solo, una vez al día
Instrucciones de cron dentro del propio `scraper.py` (al final del archivo). En resumen:
```
0 5 * * * cd /ruta/a/esta/carpeta && /usr/bin/python3 scraper.py >> scraper.log 2>&1
```

## Antes de usarlo en producción
1. **Reemplaza `WHATSAPP_NUMERO`** dentro de `tienda.html` por tu número real.
2. **Verifica los selectores del scraper** contra una página de producto real (por ejemplo `https://grupo-electricos.com/shop/5st3010/`) — los nombres de clase de WooCommerce (`.sku`, `.price`, `.stock`, etc.) suelen ser estándar, pero cada tema los puede personalizar un poco.
3. Sube ambos archivos (`tienda.html` y el `productos.json` que genera el scraper) a tu hosting, y corre el scraper en el mismo servidor (o en tu máquina, subiendo el JSON resultante por FTP/rsync/Drive cada día).
4. Como ya usaste Google Drive como base de datos sincronizada para las notas de entrega, el mismo patrón sirve aquí: el scraper podría escribir `productos.json` directo a una carpeta de Drive, y `tienda.html` leerlo de ahí en vez de un archivo local — dímelo si quieres que lo arme así.
