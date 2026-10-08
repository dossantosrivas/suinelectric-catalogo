-- =====================================================================
--  16 · CATÁLOGO ÚNICO (propuesta)
--  Un solo catálogo para la tienda, el Panel web y Gestión.
--  Va en su propio esquema "catalogo" para convivir con las tablas
--  actuales mientras se migra (Supabase → Settings → API → Exposed
--  schemas: agregar "catalogo").
--  Modelo: tablas relacionales para lo fijo (marcas, categorías, precios,
--  existencias) + JSONB "specs" para las especificaciones técnicas, que
--  cambian según la categoría. La lista de atributos válidos por categoría
--  vive en tablas, así el JSONB no se vuelve un cajón de sastre.
-- =====================================================================
create schema if not exists catalogo;
create extension if not exists pg_trgm with schema extensions;

-- ---------- Marcas ----------
create table catalogo.marcas (
  id        smallint generated always as identity primary key,
  nombre    text not null unique,                 -- 'SIEMENS', 'INVT'
  slug      text not null unique,                 -- 'siemens'
  logo_url  text,
  orden     smallint not null default 0
);

-- ---------- Árbol de categorías: 1 familia · 2 categoría · 3 subcategoría ----------
create table catalogo.categorias (
  id        integer generated always as identity primary key,
  padre_id  integer references catalogo.categorias(id) on delete restrict,
  nivel     smallint not null default 1 check (nivel between 1 and 3),
  nombre    text not null,
  slug      text not null,
  ruta      text not null default '' ,            -- 'control-de-motores/contactores'
  orden     smallint not null default 0,
  en_menu   boolean not null default true,
  unique (padre_id, slug)
);
create unique index categorias_ruta_uq on catalogo.categorias (ruta);

-- nivel y ruta se calculan solos a partir del padre
create or replace function catalogo.categoria_ruta() returns trigger
language plpgsql set search_path = '' as $$
declare p catalogo.categorias;
begin
  if new.padre_id is null then
    new.nivel := 1; new.ruta := new.slug;
  else
    select * into p from catalogo.categorias where id = new.padre_id;
    new.nivel := p.nivel + 1; new.ruta := p.ruta || '/' || new.slug;
  end if;
  return new;
end $$;
create trigger categorias_ruta before insert or update of padre_id, slug on catalogo.categorias
  for each row execute function catalogo.categoria_ruta();

-- Rescata MAPA_CATEGORIAS de tienda.html: categoría del proveedor → categoría propia
create table catalogo.mapa_categorias (
  proveedor_id    smallint not null,
  ruta_proveedor  text not null,                  -- 'Guardamotores > Termomagneticos Sirius'
  categoria_id    integer not null references catalogo.categorias(id),
  primary key (proveedor_id, ruta_proveedor)
);

-- ---------- Atributos técnicos ----------
create table catalogo.atributos (
  id       smallint generated always as identity primary key,
  clave    text not null unique check (clave ~ '^[a-z0-9_]+$'),   -- 'potencia_kw'
  nombre   text not null,                         -- 'Potencia'
  tipo     text not null check (tipo in ('numero', 'lista', 'si_no', 'texto', 'rango')),
  unidad   text,                                  -- 'kW', 'A', 'V'
  valores  text[]                                 -- opciones válidas cuando tipo = 'lista'
);

-- Qué atributos usa cada categoría, en qué orden y para qué
create table catalogo.atributos_categoria (
  categoria_id     integer  not null references catalogo.categorias(id) on delete cascade,
  atributo_id      smallint not null references catalogo.atributos(id)  on delete cascade,
  orden            smallint not null default 0,
  es_filtro        boolean  not null default true,   -- sale como filtro en la tienda
  obligatorio      boolean  not null default false,  -- cuenta para "completo %"
  define_variante  boolean  not null default false,  -- eje de la matriz de variantes
  escalones        numeric[],                        -- {0.75,1.5,2.2,4,5.5,7.5} para filtros numéricos
  primary key (categoria_id, atributo_id)
);

-- ---------- Series (la ficha) y SKU (lo que se compra) ----------
create table catalogo.series (
  id            bigint generated always as identity primary key,
  marca_id      smallint not null references catalogo.marcas(id),
  categoria_id  integer  not null references catalogo.categorias(id),
  codigo        text not null,                    -- 'HGC1811NSA', '3RV2011'
  nombre        text not null,
  descripcion   text,
  imagenes      text[] not null default '{}',
  patron_codigo text,                             -- 'HGC1811NSA-{bobina_v}'
  estado        text not null default 'borrador' check (estado in ('borrador', 'publicado', 'oculto')),
  creado        timestamptz not null default now(),
  actualizado   timestamptz not null default now(),
  unique (marca_id, codigo)
);
create index series_categoria_idx on catalogo.series (categoria_id) where estado = 'publicado';

create table catalogo.skus (
  id            bigint generated always as identity primary key,
  serie_id      bigint not null references catalogo.series(id) on delete cascade,
  codigo        text not null unique,             -- 'HGC1811NSA-220', '3RV2011-1JA10'
  specs         jsonb not null default '{}'       -- TODAS sus especificaciones: {"corriente_ac3_a":18,"bobina_v":"220 VAC","polos":3}
                check (jsonb_typeof(specs) = 'object'),
  precio_lista  numeric(12,2),                    -- precio público propio en USD (null = usar el del proveedor)
  stock_minimo  integer not null default 0,
  activo        boolean not null default true,
  actualizado   timestamptz not null default now()
);
create index skus_serie_idx  on catalogo.skus (serie_id);
create index skus_specs_gin  on catalogo.skus using gin (specs jsonb_path_ops);
create index skus_codigo_trgm on catalogo.skus using gin (codigo extensions.gin_trgm_ops);

-- ---------- Proveedores y lo que ofrece cada uno ----------
create table catalogo.proveedores (
  id      smallint generated always as identity primary key,
  nombre  text not null unique,                   -- 'Grupo Eléctricos', 'SAER', 'EMI'
  origen  text not null default 'lista' check (origen in ('scraping', 'lista', 'manual')),
  dias_vigencia smallint not null default 30      -- a los cuántos días un precio se considera viejo
);

create table catalogo.ofertas_proveedor (
  sku_id            bigint   not null references catalogo.skus(id) on delete cascade,
  proveedor_id      smallint not null references catalogo.proveedores(id),
  codigo_proveedor  text,
  costo             numeric(12,2),                -- lo que te cuesta a ti
  precio_publico    numeric(12,2),                -- precio de lista del proveedor
  existencia        integer,
  url               text,
  visto             timestamptz not null default now(),   -- última vez que el scraping o la lista lo trajo
  primary key (sku_id, proveedor_id)
);
create index ofertas_visto_idx on catalogo.ofertas_proveedor (proveedor_id, visto);

-- ---------- Inventario propio (tu almacén y el de tu papá) ----------
create table catalogo.almacenes (
  id      smallint generated always as identity primary key,
  nombre  text not null unique                    -- 'Manuel', 'Papá'
);

create table catalogo.existencias (
  sku_id          bigint   not null references catalogo.skus(id) on delete cascade,
  almacen_id      smallint not null references catalogo.almacenes(id),
  cantidad        integer  not null default 0 check (cantidad >= 0),
  costo_promedio  numeric(12,2),
  actualizado     timestamptz not null default now(),
  primary key (sku_id, almacen_id)
);

create table catalogo.lotes_carga (
  id            bigint generated always as identity primary key,
  proveedor_id  smallint references catalogo.proveedores(id),
  archivo       text,
  resumen       jsonb,                            -- {"nuevos":38,"cambian_precio":212,"errores":6}
  deshecho      boolean not null default false,
  creado        timestamptz not null default now(),
  creado_por    uuid default auth.uid()
);

-- Nunca se edita una existencia a mano: se registra un movimiento y el trigger la actualiza.
create table catalogo.movimientos (
  id            bigint generated always as identity primary key,
  sku_id        bigint   not null references catalogo.skus(id) on delete cascade,
  almacen_id    smallint not null references catalogo.almacenes(id),
  cantidad      integer  not null check (cantidad <> 0),   -- + entra, − sale
  costo_unit    numeric(12,2),
  motivo        text not null check (motivo in ('compra', 'venta', 'ajuste', 'traslado', 'carga')),
  documento_id  text,                                       -- id del documento de Gestión
  lote_id       bigint references catalogo.lotes_carga(id),
  creado        timestamptz not null default now(),
  creado_por    uuid default auth.uid()
);
create index movimientos_sku_idx on catalogo.movimientos (sku_id, creado desc);

create or replace function catalogo.aplicar_movimiento() returns trigger
language plpgsql set search_path = '' as $$
begin
  update catalogo.existencias e
     set cantidad = e.cantidad + new.cantidad,   -- si queda negativa, la regla cantidad >= 0 frena la venta
         -- costo promedio ponderado solo cuando entra mercancía con costo
         costo_promedio = case when new.cantidad > 0 and new.costo_unit is not null
                               then round((coalesce(e.costo_promedio, 0) * e.cantidad + new.costo_unit * new.cantidad)
                                          / (e.cantidad + new.cantidad), 2)
                               else e.costo_promedio end,
         actualizado = now()
   where e.sku_id = new.sku_id and e.almacen_id = new.almacen_id;
  if not found then
    if new.cantidad < 0 then
      raise exception 'No hay existencia de este producto en ese almacén';
    end if;
    insert into catalogo.existencias (sku_id, almacen_id, cantidad, costo_promedio)
    values (new.sku_id, new.almacen_id, new.cantidad, new.costo_unit);
  end if;
  return new;
end $$;
create trigger movimientos_aplicar after insert on catalogo.movimientos
  for each row execute function catalogo.aplicar_movimiento();

-- ---------- Sinónimos del rubro para la búsqueda ----------
create table catalogo.sinonimos (
  termino   text primary key,                     -- 'breaker'
  equivale  text[] not null                       -- {'interruptor termomagnetico','disyuntor'}
);

-- ---------- "actualizado" automático ----------
create or replace function catalogo.tocar() returns trigger
language plpgsql set search_path = '' as $$
begin new.actualizado := now(); return new; end $$;
create trigger series_tocar before update on catalogo.series for each row execute function catalogo.tocar();
create trigger skus_tocar   before update on catalogo.skus   for each row execute function catalogo.tocar();

-- ---------- Vista que alimenta la tienda (y el catalogo-tienda.json) ----------
-- La lee el script que genera catalogo-tienda.json con la clave secreta (y los
-- administradores); los visitantes no la consultan directo.
-- Disponibilidad: 'propio' (tu inventario) > 'distribuidor' > 'a_pedido'
create or replace view catalogo.v_tienda with (security_invoker = on) as
select k.id            as sku_id,
       k.codigo,
       s.id            as serie_id,
       s.codigo        as serie,
       s.nombre,
       m.nombre        as marca,
       c.ruta          as categoria,
       k.specs,
       coalesce(k.precio_lista, o.precio_publico) as precio,
       case when coalesce(ex.propio, 0) > 0 then 'propio'
            when coalesce(o.existencia, 0) > 0 then 'distribuidor'
            else 'a_pedido' end                   as disponibilidad,
       s.imagenes[1]   as imagen
from catalogo.skus k
join catalogo.series s      on s.id = k.serie_id and s.estado = 'publicado'
join catalogo.marcas m      on m.id = s.marca_id
join catalogo.categorias c  on c.id = s.categoria_id
left join lateral (select sum(cantidad) propio from catalogo.existencias e where e.sku_id = k.id) ex on true
left join lateral (select precio_publico, existencia from catalogo.ofertas_proveedor op
                    where op.sku_id = k.id order by op.existencia desc nulls last, op.visto desc limit 1) o on true
where k.activo;

-- ---------- Seguridad ----------
-- Público: catálogo publicado. Solo administradores: costos, existencias reales, movimientos, lotes.
alter table catalogo.marcas              enable row level security;
alter table catalogo.categorias          enable row level security;
alter table catalogo.mapa_categorias     enable row level security;
alter table catalogo.atributos           enable row level security;
alter table catalogo.atributos_categoria enable row level security;
alter table catalogo.series              enable row level security;
alter table catalogo.skus                enable row level security;
alter table catalogo.proveedores         enable row level security;
alter table catalogo.ofertas_proveedor   enable row level security;
alter table catalogo.almacenes           enable row level security;
alter table catalogo.existencias         enable row level security;
alter table catalogo.lotes_carga         enable row level security;
alter table catalogo.movimientos         enable row level security;
alter table catalogo.sinonimos           enable row level security;

create policy leer on catalogo.marcas              for select using (true);
create policy leer on catalogo.categorias          for select using (true);
create policy leer on catalogo.atributos           for select using (true);
create policy leer on catalogo.atributos_categoria for select using (true);
create policy leer on catalogo.sinonimos           for select using (true);
create policy leer on catalogo.series for select using (estado = 'publicado' or public.es_admin());
create policy leer on catalogo.skus   for select using (
  public.es_admin() or (activo and exists (select 1 from catalogo.series s where s.id = serie_id and s.estado = 'publicado')));
-- Costos y existencias reales: solo administradores. La tienda los recibe ya resumidos
-- (precio y disponibilidad) en catalogo-tienda.json, que arma un script con la clave secreta.
create policy admin on catalogo.ofertas_proveedor for select using (public.es_admin());
create policy admin on catalogo.existencias       for select using (public.es_admin());

do $$ declare t text; begin
  foreach t in array array['marcas','categorias','mapa_categorias','atributos','atributos_categoria','series','skus',
                           'proveedores','ofertas_proveedor','almacenes','existencias','lotes_carga','movimientos','sinonimos'] loop
    execute format('create policy escribir on catalogo.%I for all to authenticated using (public.es_admin()) with check (public.es_admin())', t);
  end loop;
end $$;

grant usage on schema catalogo to anon, authenticated, service_role;
grant all on all tables in schema catalogo to service_role;
grant select on all tables in schema catalogo to anon, authenticated;
grant insert, update, delete on all tables in schema catalogo to authenticated;
revoke select on catalogo.ofertas_proveedor, catalogo.existencias, catalogo.movimientos, catalogo.lotes_carga,
               catalogo.proveedores, catalogo.almacenes, catalogo.mapa_categorias from anon;
