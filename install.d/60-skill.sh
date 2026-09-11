#!/usr/bin/env bash
# ============================================================================
# Instala la skill global validar-links-referido-mercadolibre en ~/.claude.
# ============================================================================
[ -n "${_COMMON_LOADED:-}" ] || source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/00-common.sh"

log "Creando skill global validar-links-referido-mercadolibre…"
SKILL_DIR="$HOME/.claude/skills/validar-links-referido-mercadolibre"
mkdir -p "$SKILL_DIR"
cat > "$SKILL_DIR/SKILL.md" <<'SKILL_EOF'
---
name: validar-links-referido-mercadolibre
description: "Auditar links de referido meli.la en producción (vivos, rotos, precio, identidad) y aplicar los precios y links corregidos a la base de Avena con update_supplement_prices."
---

# Validar links de referido de MercadoLibre

Dos fases, y conviene separarlas incluso en sesiones distintas:

1. **Auditar** — ¿el link sigue vivo?, ¿sigue llevando al producto correcto?, ¿el precio
   guardado sigue siendo el de ML? Entrega CSVs + un payload JSON.
2. **Aplicar** — escribir precios y links corregidos a la base con el MCP de Avena Interno.

La fase 1 es lenta y frágil (depende del navegador y de la sesión de ML); la 2 es rápida
y determinista. Si la 1 ya corrió, empezar directo en la 2 con el payload.

Entrada típica: `get_avena_supplements` del MCP de Avena Interno, que ya devuelve solo
los suplementos con `productURL` en `meli.la` (`id`, `name`, `brand`, `price`,
`adjustmentMarginPercentage`, `productURL`).

---

# Fase 1 — Auditar

## Cómo se ve un link vivo

Un `meli.la` de este programa **no abre la página del producto**: resuelve al perfil
social del afiliado, `mercadolibre.com.mx/social/<tag>`, con el producto enlazado
destacado hasta arriba y el resto de las recomendaciones abajo.

| Resultado | Significa |
|---|---|
| `/social/<tag>` **con** `.rl-card-featured` | link vivo; la tarjeta destacada es el producto |
| `/social/<tag>/lists` **sin** `.rl-card-featured` | **link roto**: el producto ya no está en la lista de recomendaciones |

Ese segundo caso es el hallazgo que justifica la auditoría: el link responde 200 y no
parece fallado, pero el cliente aterriza en una lista genérica en lugar del producto que
pidió. No se detecta con un check de status HTTP.

## Cómo correrlo: iframes en paralelo, no navegación por link

El perfil social está en el **mismo origen** que una pestaña de `mercadolibre.com.mx`.
Desde una pestaña ya cargada ahí se pueden abrir los `meli.la` en iframes y leer su
`contentDocument`. 314 links en ~8 llamadas, en vez de una navegación por link.

`fetch()` contra `meli.la` **no sirve**: falla por CORS.

Mientras el iframe sigue en `meli.la` (otro origen) `contentDocument` truena o da `null`;
en cuanto redirige a `mercadolibre.com.mx` se vuelve legible. Eso es justamente la espera
activa — no usar `setTimeout` fijo.

```js
const abrir = url => new Promise(resolve => {
  const f = document.createElement('iframe');
  f.style.cssText = 'width:1200px;height:900px;position:fixed;left:-9999px';
  const t0 = Date.now();
  const poll = setInterval(() => {
    let d = null;
    try { d = f.contentDocument } catch (e) {}          // aún en meli.la
    const card = d && d.querySelector('.rl-card-featured');
    const lists = d && d.location.pathname.endsWith('/lists');
    if (card || lists || Date.now() - t0 > 15000) {
      clearInterval(poll);
      resolve(extraer(d, url));
      f.remove();
    }
  }, 300);
  f.src = url;
  document.body.appendChild(f);
});

JSON.stringify(await Promise.all(lote.map(abrir)));   // lote de 10-12
```

**Concurrencia: 10-12 para perfiles sociales, 3 para páginas de producto.** Con 10+ en
páginas de producto ML lanza un desafío de seguridad ("Por seguridad, completa este
paso") que tiene que pasar una persona.

## Extractor de la tarjeta destacada

```js
function extraer(d, url) {
  const f = d && d.querySelector('.rl-card-featured');
  if (!f) return { url, ok: false, path: d && d.location.pathname,
    motivo: d && d.location.pathname.endsWith('/lists')
      ? 'roto: el producto ya no esta en la lista de recomendaciones'
      : 'sin tarjeta destacada / timeout' };
  const q = s => f.querySelector(s);
  const fr = q('.andes-money-amount__fraction'), ce = q('.andes-money-amount__cents');
  const a = q('a[href*="MLM"]');
  return { url, ok: true,
    titulo: q('.poly-component__title')?.textContent.trim(),
    precio: fr && +(fr.textContent.replace(/,/g, '') + (ce ? '.' + ce.textContent.trim() : '')),
    vendedor: q('.poly-component__seller')?.textContent.trim().replace(/^Por /, ''),
    mlid: a && (a.href.match(/MLM-?\d+/) || [null])[0] };
}
```

**La tarjeta destacada trae el `MLM` id.** Guardarlo siempre: la base solo almacena el
`meli.la`, un link corto que no revela a qué apunta, así que esta auditoría es la única
forma de reconstruir el mapeo producto → listing.

## Los rotos: ir a la página de producto a ver por qué

Casi siempre el link roto es **síntoma**, no problema: el producto salió de venta en ML,
su página de catálogo existe y responde pero dice *"Este producto no está disponible por
el momento"*, y al salir de venta sale de la lista de recomendaciones del afiliado.
**Regenerar el link no sirve — no hay a qué apuntar.** Lo que corresponde es marcarlo sin
stock en Avena o remapearlo a otro listing con vendedor activo.

En la última corrida: de 26 rotos, 23 fuera de venta y solo 3 recuperables.

### Trampa del precio en páginas de producto (importante)

En el layout angosto ML renderiza el **carrusel de relacionados arriba** del buy box, y
`.ui-pdp-price` / `.ui-pdp-price__second-line` no existen. Un selector genérico como
`.poly-price__current` toma el precio de la **primera tarjeta del carrusel**, no del
producto: daba $239 idéntico para tres productos que no tienen nada que ver, con
`vendedor: null`. Ese patrón — mismo precio en productos distintos — es la pista.

```js
const RECOS = '.poly-card__content, .recos-polycard, .andes-carousel-free__slide, .ui-recommendations, [class*=recos]';
const montos = [...d.querySelectorAll('.andes-money-amount__fraction')]
  .filter(el => !el.closest(RECOS));
```

Si no queda ningún monto propio y el texto dice "no está disponible", el producto está
fuera de venta — no es que falle el scraping. El precio del buy box carga en lazy: esperar
por el elemento **o** por el aviso de no disponible.

## Qué comparar

1. **Vivo o roto** — la señal de arriba.
2. **Precio** — `precio` de ML contra `price` del registro. Marcar diferencias mayores a
   ~1%; las de centavos son ruido de redondeo (449 vs 449.09 no es un cambio real).
3. **Sin precio base** — separar los que tienen `price` vacío/`null`. No cambiaron: nunca
   se guardaron. En la última corrida eran 100 de 327, el hallazgo más grande.
4. **Identidad** — título del listing contra `name` + `brand`. Esto atrapa el mapeo mal
   hecho: link vivo, precio plausible, otro producto. Revisar a ojo los que no compartan
   palabras clave. **Estos no se cargan automáticamente.**
5. **Vendedor** — guardarlo. Si cambió quien gana el buy box suele explicar un salto de
   precio, y también si un link empieza o deja de generar comisión.

No asumir que precio igual = todo bien: un producto puede seguir vivo y al mismo precio
pero haber cambiado de presentación.

## Integridad de datos (revisar siempre, aunque no se haya pedido)

Con el `mlid` reconstruido salen problemas que no son del link sino de la base, y suelen
ser más caros que los precios desactualizados:

- **Links compartidos por más de un producto** — mismo `meli.la` para sabores o tamaños
  distintos. Fueron 13 en la última corrida.
- **`id` duplicados en la base** — dos productos con el mismo `id`; uno de los dos es
  inalcanzable.
- **Sabor/presentación que no coincide** — p. ej. `ElectroBlend Orange` apuntando al
  listing de ElectroBlend Limonada.

## Trampas de sesión

- **`/gz/account-verification`**: ML pide verificación y *toda* URL redirige ahí. Lo tiene
  que pasar el usuario. Si aparece a media corrida, guardar el avance y pedírselo.
- **reCAPTCHA**: igual.
- Si varios links seguidos dan el mismo resultado sospechoso, verificar que la sesión no
  esté bloqueada **antes** de marcar 50 productos como rotos.
- Todo esto depende de estar logueado en la cuenta de afiliado dueña de los links.

## Entrega de la fase 1

CSV con `id` como primera columna:

```
id, marca, nombre, productURL, estatus, precio_guardado, precio_ML, diff_pct,
vendedor_ML, mlid_detectado, titulo_en_ML, nota
```

`estatus`: `ok` / `precio_cambio` / `sin_precio_base` / `revisar_identidad` /
`roto_recuperable` / `roto_fuera_de_venta`

Más un **payload JSON listo para la fase 2**, agrupado en lotes y con los campos de
contexto prefijados con `_` para que no se confundan con los que se escriben:

```json
{"lotes": {"A_precio_cambio": {"n": 68, "items": [
  {"id": "...", "price": 580.67, "_precio_anterior": 290, "_diff_pct": 100.23,
   "_nombre": "Ka 30", "_mlid": "MLM26028849"}]}}}
```

Guardar a disco conforme salgan los resultados: si la sesión se corta a medio camino no
se pierde la corrida, y el payload es lo que permite retomar en otra sesión.

Al reportar, abrir con lo accionable, no con el conteo: cuántos rotos, cuántos con precio
desactualizado y de cuánto es la diferencia agregada. Los que están bien no necesitan
explicación.

---

# Fase 2 — Aplicar a la base

`update_supplement_prices` del MCP de **Avena Interno**:
`updates: [{id, price?, productURL?}]`, mínimo uno de `price` o `productURL`.

## Validar antes de escribir

Nunca escribir el payload a ciegas: es producción y las sobreescrituras no tienen undo.
Traer `get_avena_supplements` y verificar contra él.

```python
import json
by = {s['id']: s for s in supps}
for it in items:
    s = by.get(it['id'])
    assert s, f"id inexistente: {it['id']}"                       # ids que ya no existen
    prev = it.get('_precio_anterior')
    if str(prev or '') != str(s.get('price') or ''):              # la base cambió desde la auditoría
        print('desajuste', it['id'], prev, s.get('price'))
    if s.get('price') == it.get('price'):
        print('no-op', it['id'])                                  # nada que escribir
```

Y revisar que no haya `id` repetidos dentro del payload.

Un desajuste string/número (`"799"` vs `799`) es ruido; un desajuste real de valor
significa que alguien más tocó ese producto — preguntar antes de pisarlo.

## Escribir

Lotes de ~45. El tool **devuelve el objeto completo de cada suplemento actualizado**, así
que la respuesta es enorme y casi siempre acaba volcada a archivo por exceder el límite
de tokens. Eso está bien: no leerla. La verificación real viene después.

Mismo problema con `get_avena_supplements` (~9,700 líneas): parsearlo con python desde el
archivo, nunca meterlo al contexto.

## Qué NO tocar

Solo `price` y `productURL`. **No** tocar `adjustmentMarginPercentage`.

`adjustedPrice` **lo recalcula el backend** al escribir — confirmado (Ka 30: `price`
580.67 → `adjustedPrice` 639 con margen 10%). No mandarlo.

Ojo: los productos que nunca tuvieron precio tampoco tienen `adjustmentMarginPercentage`,
así que después de cargarles `price` siguen sin `adjustedPrice`. Si la app los muestra con
precio ajustado, falta definirles margen — vale la pena señalarlo.

Los `revisar_identidad` no se cargan: primero se confirma a qué producto apuntan.

## Verificar

Volver a traer `get_avena_supplements` y diferenciar programáticamente contra el payload.
Reportar `N/N`, no "listo".

**Gotcha:** `get_avena_supplements` filtra por `productURL` que contenga `meli.la`. Un
producto al que se le cargó un link directo de catálogo (porque el Programa de Afiliados
rechazó generarle referido) **desaparece de esa lista** — el total baja de 327 a 326. No
es un borrado, y hay que decirlo así en el reporte para que no cunda el pánico. Ese link
además no genera comisión: vale reintentar el referido más adelante.

---

## Cada cuándo

Tiene sentido correrla periódicamente: los precios de ML se mueven solos, el vendedor del
buy box cambia, y un producto puede salirse de la lista de recomendaciones sin aviso.
Ofrecer dejarla como tarea programada si el usuario la va a repetir.

Dejar el registro de la corrida en el doc del proyecto: qué se cargó, cuándo, qué quedó
pendiente. La corrida siguiente empieza leyendo eso.
SKILL_EOF
