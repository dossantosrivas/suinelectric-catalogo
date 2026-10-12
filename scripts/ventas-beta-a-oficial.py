# Pasa ventas-beta.html a ventas.html quitando solo lo propio de la beta (noindex, [BETA], enlaces -beta y la etiqueta BETA).
# Uso: python3 scripts/ventas-beta-a-oficial.py ventas-beta.html ventas.html
import re,sys
def a_oficial(s):
    s=s.replace('<meta name="robots" content="noindex, nofollow">\n','',1)
    s=s.replace('<title>[BETA] Gestión | Suinelectric</title>','<title>Gestión | Suinelectric</title>',1)
    s=s.replace('/^\\/ventas-beta(?:\\.html)?','/^\\/ventas(?:\\.html)?').replace("'/ventas-beta/'","'/ventas/'")
    s=s.replace('href="/tienda-beta"','href="/tienda"').replace('href="/admin-beta"','href="/admin"').replace('/admin-beta/','/admin/')
    i=s.find('<div id="beta-aviso"')
    if i>=0:
        j=s.index('</div>',i)+len('</div>')
        if s[j:j+1]=='\n': j+=1
        s=s[:i]+s[j:]
    return s
src,dst=sys.argv[1],sys.argv[2]
out=a_oficial(open(src,encoding='utf8').read())
for resto in ['ventas-beta','admin-beta','tienda-beta','[BETA]','beta-aviso','noindex']:
    if resto in out: print('QUEDA:',resto, out.count(resto))
open(dst,'w',encoding='utf8').write(out)
