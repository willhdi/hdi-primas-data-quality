# -*- coding: utf-8 -*-
"""
generar_sql — Regenera los bloques list-driven del SQL desde dq_primas_logica.py.

El archivo `sql/consultas/primas_monto_mensual.sql` contiene un bloque CASE largo y
propenso a error (categoria_ramo) que debe coincidir con el mapeo del módulo. Este
script lo reemplaza dentro de los marcadores `-- >>> AUTOGEN:<clave> ... <<<` /
`-- >>> END:<clave> <<<`, de modo que la fuente de verdad sea SIEMPRE
dq_primas_logica.py. El resto del SQL (estructura, CTEs, filtros) es escrito a mano
y no se toca. (El `nombre_natural` del cubo `sql/vistas/01_vw_kpi_cubo_mensual.sql`
se mantiene a mano: perdió sus marcadores AUTOGEN al pasar a vista pura.)

Uso:
    python generar_sql.py           # regenera los bloques in-place
    python generar_sql.py --check   # NO escribe; sale con código 1 si algo está desfasado
                                     # (útil para un pre-commit / CI)
"""
import re
import sys
from pathlib import Path

import dq_primas_logica as dq

RAIZ = Path(__file__).resolve().parent.parent
SQL_07 = RAIZ / 'sql' / 'consultas' / 'primas_monto_mensual.sql'

INDENT = '        '  # 8 espacios: nivel de los WHEN dentro del CASE


def _bloque_categoria_ramo():
    """Líneas WHEN ... THEN ... agrupadas por categoría + ELSE (sql/07)."""
    # Agrupar códigos por categoría preservando el orden de aparición.
    por_categoria = {}
    for codigo, categoria in dq.CATEGORIA_RAMO.items():
        por_categoria.setdefault(categoria, []).append(codigo)

    lineas = []
    for categoria, codigos in por_categoria.items():
        lineas.append(f'{INDENT}-- {categoria}')
        # 3 WHEN por línea para mantenerlo legible.
        for i in range(0, len(codigos), 3):
            trozo = codigos[i:i + 3]
            lineas.append(INDENT + ' '.join(f"WHEN '{c}' THEN '{categoria}'" for c in trozo))
    lineas.append(f"{INDENT}ELSE 'Sin clasificar'")
    return '\n'.join(lineas)


BLOQUES = {
    (SQL_07, 'categoria_ramo'): _bloque_categoria_ramo,
}


def _reemplazar(texto, clave, contenido):
    """Sustituye lo que haya entre los marcadores AUTOGEN/END de `clave`."""
    patron = re.compile(
        r'(?P<ini>-- >>> AUTOGEN:' + re.escape(clave) + r'\b.*?<<<\n)'
        r'.*?'
        r'(?P<fin>[^\n]*-- >>> END:' + re.escape(clave) + r' <<<)',
        re.DOTALL,
    )
    m = patron.search(texto)
    if not m:
        raise SystemExit(f'ERROR: no se encontraron los marcadores AUTOGEN/END:{clave} en el archivo.')
    reemplazo = m.group('ini') + contenido + '\n' + INDENT + m.group('fin').strip()
    return texto[:m.start()] + reemplazo + texto[m.end():]


def main():
    check = '--check' in sys.argv
    desfasados = []
    for (ruta, clave), constructor in BLOQUES.items():
        original = ruta.read_text(encoding='utf-8')
        nuevo = _reemplazar(original, clave, constructor())
        if nuevo != original:
            desfasados.append(f'{ruta.name} [{clave}]')
            if not check:
                ruta.write_text(nuevo, encoding='utf-8')

    if check:
        if desfasados:
            print('DESFASADO (corre `python generar_sql.py`): ' + ', '.join(desfasados))
            sys.exit(1)
        print('OK: los bloques SQL están sincronizados con dq_primas_logica.py.')
    else:
        if desfasados:
            print('Regenerados: ' + ', '.join(desfasados))
        else:
            print('Sin cambios: los bloques ya estaban sincronizados.')


if __name__ == '__main__':
    main()
