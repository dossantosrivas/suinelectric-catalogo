"""Pone las fotos oficiales de Schneider en productos_manuales.json.

Uso: python3 scripts/aplicar-fotos-schneider.py <carpeta con resultado-*.json y fotos/>
  - Copia las fotos usadas a imagenes/schneider/oficial/
  - imagen = foto principal; imagenes = principal + vistas (+ foto real si existe
    en imagenes/schneider/reales/<REF o familia>.jpg y está en REALES)
  - Si un modelo no tiene página en se.com, usa las fotos del modelo más parecido
    de su misma familia (la misma foto que tenía antes).
  - FORZAR permite corregir a mano la foto principal de un modelo o familia.
"""
import json, os, re, shutil, sys, glob

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 'https://raw.githubusercontent.com/dossantosrivas/suinelectric-catalogo/main/'
DEST = 'imagenes/schneider/oficial'
src = sys.argv[1]

res = {}
for f in glob.glob(os.path.join(src, '**', 'resultado-*.json'), recursive=True):
    res.update(json.load(open(f)))
fotos_src = {os.path.basename(p): p for p in glob.glob(os.path.join(src, '**', 'fotos', '*.jpg'), recursive=True)}
archivo = lambda r: re.sub(r'[^A-Za-z0-9._+-]', '_', r) + '.jpg'

# Correcciones a mano: modelo (o prefijo) -> lista de refs
FORZAR = json.load(open(os.path.join(RAIZ, 'scripts', 'fotos-schneider-forzar.json'))) \
    if os.path.exists(os.path.join(RAIZ, 'scripts', 'fotos-schneider-forzar.json')) else {}
# Fotos reales: familia (nombre de la foto vieja) -> archivo en imagenes/schneider/reales/
REALES = json.load(open(os.path.join(RAIZ, 'scripts', 'fotos-schneider-reales.json'))) \
    if os.path.exists(os.path.join(RAIZ, 'scripts', 'fotos-schneider-reales.json')) else {}

ruta = os.path.join(RAIZ, 'productos_manuales.json')
data = json.load(open(ruta))
prods = [p for p in data['productos'] if (p.get('marca') or '').upper() == 'SCHNEIDER']

def familia(p):
    if p.get('_familia_foto'):
        return p['_familia_foto']
    img = p.get('imagen') or ''
    if '/imagenes/schneider/' in img and '/oficial/' not in img:
        return os.path.basename(img).rsplit('.', 1)[0]
    return ' > '.join(p.get('subcategorias') or [])

def refs_de(m):
    for clave, refs in FORZAR.items():
        if m == clave or (clave.endswith('*') and m.startswith(clave[:-1])):
            return refs
    r = res.get(m)
    return r['refs'] if r and r.get('refs') else []

fams = {}
for p in prods:
    p['_familia_foto'] = familia(p)
    fams.setdefault(p['_familia_foto'], []).append(p)

usadas, sin, prestadas = set(), [], []
for fam, lista in fams.items():
    for i, p in enumerate(lista):
        refs = refs_de(p['modelo'])
        if not refs:  # el vecino más cercano de la familia que sí tenga fotos
            for d in range(1, len(lista)):
                for j in (i - d, i + d):
                    if 0 <= j < len(lista) and refs_de(lista[j]['modelo']):
                        refs = refs_de(lista[j]['modelo']); break
                if refs: break
            if refs: prestadas.append(p['modelo'])
        refs = [r for r in refs if archivo(r) in fotos_src or os.path.exists(os.path.join(RAIZ, DEST, archivo(r)))]
        if not refs:
            sin.append(p['modelo']); continue
        urls = [BASE + DEST + '/' + archivo(r) for r in refs]
        real = REALES.get(fam)
        if real and os.path.exists(os.path.join(RAIZ, real)):
            urls.insert(1, BASE + real)
        p['imagen'] = urls[0]
        p['imagenes'] = urls
        usadas.update(archivo(r) for r in refs)

os.makedirs(os.path.join(RAIZ, DEST), exist_ok=True)
for a in usadas:
    if a in fotos_src:
        shutil.copyfile(fotos_src[a], os.path.join(RAIZ, DEST, a))
for p in prods:
    p.pop('_familia_foto', None)

open(ruta, 'w').write(json.dumps(data, ensure_ascii=False, indent=2))
print(f'{len(prods)} productos · {len(usadas)} fotos · prestadas de su familia: {len(prestadas)} · sin foto: {len(sin)}')
if sin: print('Sin foto:', ' '.join(sin))
