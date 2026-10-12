# Pasa admin-beta.html a admin.html quitando solo lo propio de la beta ([BETA], enlaces -beta y la etiqueta BETA).
# Uso: python3 scripts/admin-beta-a-oficial.py admin-beta.html admin.html
import re, sys
def a_oficial(s):
    s = s.replace('<title>[BETA] Panel web | Suinelectric</title>', '<title>Panel web | Suinelectric</title>', 1)
    s = s.replace("const BASE = '/admin-beta';", "const BASE = '/admin';", 1)
    s = s.replace('/tienda-beta.html', '/tienda.html').replace('/tienda-beta', '/tienda').replace('/ventas-beta', '/ventas')
    # etiqueta BETA (y el cierre de la página que la acompaña): el cierre va siempre al final
    s = re.sub(r'</script>\n<div id="beta-aviso"[^\n]*</div>\n</body>\n</html>\n', '\n', s, count=1)
    s = re.sub(r'<div id="beta-aviso"[^\n]*</div>\n', '', s, count=1)
    s = s.rstrip('\n')
    if not s.endswith('</html>'): s += '\n</script>\n</body>\n</html>'
    return s + '\n'
if __name__ == '__main__':
    out = a_oficial(open(sys.argv[1], encoding='utf8').read())
    for resto in ['admin-beta', 'ventas-beta', 'tienda-beta', '<title>[BETA]', 'beta-aviso']:
        if resto in out: print('QUEDA:', resto, out.count(resto))
    open(sys.argv[2], 'w', encoding='utf8').write(out)
