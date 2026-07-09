"""
FeriaApp API v2.1 — Router: Catálogo (complemento)
Endpoints adicionales para selects dinámicos del frontend
"""
from typing import Optional, List
from fastapi import APIRouter, Depends
from lib.core.database import get_db

router = APIRouter(prefix="/catalogo", tags=["Catálogo"])


@router.get("/subcategorias")
async def listar_subcategorias(
    categoria_id: Optional[int] = None,
    conn=Depends(get_db)
):
    """Listar subcategorías de ropa (opcionalmente filtradas por categoría)"""
    query = """
        SELECT id, categoria_ropa_id, nombre, descripcion
        FROM subcategorias_ropa
        WHERE activo = TRUE
    """
    params = []
    if categoria_id:
        query += " AND categoria_ropa_id = $" + str(len(params) + 1)
        params.append(categoria_id)
    query += " ORDER BY nombre"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/niveles-calidad")
async def listar_niveles_calidad(conn=Depends(get_db)):
    """Listar niveles de calidad predefinidos"""
    rows = await conn.fetch("""
        SELECT id, codigo, nombre, descripcion, multiplicador_precio
        FROM niveles_calidad
        WHERE activo = TRUE
        ORDER BY multiplicador_precio DESC
    """)
    return [dict(r) for r in rows]


@router.get("/temporadas")
async def listar_temporadas(conn=Depends(get_db)):
    """Listar temporadas para clasificación de productos"""
    rows = await conn.fetch("""
        SELECT id, nombre, fecha_inicio, fecha_fin, activo
        FROM temporadas
        WHERE activo = TRUE
        ORDER BY fecha_inicio DESC
    """)
    return [dict(r) for r in rows]


@router.get("/flujo-prenda")
async def listar_flujo_prenda(conn=Depends(get_db)):
    """Listar estados de flujo de prenda"""
    return [
        {"id": "primera_seleccion", "nombre": "Primera Selección", "descripcion": "Prenda en excelente estado, lista para venta directa"},
        {"id": "segunda_seleccion", "nombre": "Segunda Selección", "descripcion": "Prenda con pequeños detalles, precio rebajado"},
        {"id": "donacion", "nombre": "Donación", "descripcion": "Prenda para donar a comunidad"},
        {"id": "reciclaje", "nombre": "Reciclaje", "descripcion": "Material para upcycling o reciclaje textil"}
    ]
