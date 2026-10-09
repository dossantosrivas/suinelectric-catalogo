# Pasa la tienda-beta a la tienda oficial.
# Copia tienda-beta.html en tienda.html quitando solo lo que es propio de la beta:
#   · noindex, "[BETA]" en el título y la etiqueta BETA
#   · el rastreo de visitas (la beta no lo usa; la oficial sí)
#   · enlaces a /tienda-beta, /admin-beta y /ventas-beta
#   · la carga de catalogo-beta.json (la oficial usa su catálogo de siempre y
#     calcula las especificaciones en el navegador con /especificaciones.js)
# Uso: python3 scripts/beta-a-oficial.py
import os

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
s = open(os.path.join(RAIZ, 'tienda-beta.html'), encoding='utf-8').read()

def rep(viejo, nuevo, veces=1):
    global s
    n = s.count(viejo)
    if n != veces:
        raise SystemExit('No encontré (%d de %d veces):\n%s' % (n, veces, viejo[:200]))
    s = s.replace(viejo, nuevo)

rep('<meta name="robots" content="noindex, nofollow">\n', '')
rep('<title>[BETA] Suinelectric', '<title>Suinelectric')
rep("""<!-- beta: sin rastreo.js para no mezclar las pruebas con las visitas reales -->
<script>window.suinRastreo = { visitante: '', evento: function(){}, iniciar: function(){}, tarjetas: function(){}, noContarMas: function(){}, vaciar: function(){} };</script>""",
    '<script src="/rastreo.js?v=3"></script>')
rep("return location.origin + '/tienda-beta';", "return location.origin + '/tienda';")
rep('href="/admin-beta"', 'href="/admin"')
rep('href="/ventas-beta"', 'href="/ventas"')

# Sin catalogo-beta.json: la oficial siempre usa su carga normal
i = s.index("    // Catálogo único (beta): si existe catalogo-beta.json, ya trae todo unido desde la base nueva.")
j = s.index("    const [{ data, manuales: manualesJson }, panel] = await Promise.all([traerCatalogo(silencioso), traerDelPanel()]);", i)
s = s[:i] + s[j:]

# Etiqueta BETA
i = s.index('<div id="beta-aviso"')
j = s.index('</div>', i) + len('</div>')
s = s[:i] + s[j:].lstrip('\n')

for resto in ['tienda-beta', 'admin-beta', 'ventas-beta', 'catalogo-beta.json', '[BETA]', 'beta-aviso']:
    usos = [l.strip()[:120] for l in s.split('\n') if resto in l and not l.strip().startswith(('//', '/*', '*'))]
    usos = [u for u in usos if 'traerCatalogoBeta' not in u and "fetch('catalogo-beta.json'" not in u]
    if usos:
        print('Aviso: queda "%s" en:' % resto, *usos, sep='\n  ')

open(os.path.join(RAIZ, 'tienda.html'), 'w', encoding='utf-8').write(s)
print('tienda.html generada desde tienda-beta.html')
