-- ============================================================================
-- LABIOFARM · Sistema de Gestión de Producción y Control de Calidad
-- Script 03 de 05 · Consultas persistentes: vistas, funciones y vista
--                    materializada
-- ----------------------------------------------------------------------------
-- Prerrequisitos: scripts 01 y 02 ejecutados. Conectado a "labiofarm".
--
-- Qué hace: implementa las consultas de negocio como OBJETOS PERSISTENTES de
-- la base de datos, para invocarlas después sin reescribir SQL:
--   * VISTAS: consultas almacenadas que se ejecutan en tiempo real.
--   * FUNCIONES: consultas parametrizables y reutilizables.
--   * VISTA MATERIALIZADA: resultados precalculados para tableros;
--     se actualiza explícitamente con REFRESH MATERIALIZED VIEW.
--
-- Con las tablas vacías todos los objetos se crean correctamente y devuelven
-- cero filas. Para ver resultados, carga el script 04_datos_prueba.sql.
--
-- Idempotencia: se usa CREATE OR REPLACE para vistas y funciones, y
-- DROP ... IF EXISTS antes de la vista materializada (que no soporta
-- OR REPLACE en versiones anteriores a PostgreSQL 9.3... y en todas las
-- modernas es la forma estándar de redefinirla).
-- ============================================================================

SET search_path TO biofarm, public;

-- ============================================================================
-- CONSULTA 1 · vista_materias_primas_stock_bajo          [dificultad: básica]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Qué materias primas necesitan reabastecimiento urgente y a qué
--   proveedor hay que contactar?
-- Técnicas: SELECT con filtro, JOIN interno.
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_materias_primas_stock_bajo AS
SELECT
    mp.codigo,
    mp.nombre,
    mp.unidad_medida,
    mp.stock_actual,
    mp.stock_minimo,
    (mp.stock_minimo - mp.stock_actual) AS faltante,      -- Cuánto falta para llegar al mínimo
    pr.razon_social AS proveedor,
    pr.email         AS email_proveedor,
    pr.telefono      AS telefono_proveedor
FROM biofarm.materias_primas AS mp
INNER JOIN biofarm.proveedores AS pr
        ON pr.id_proveedor = mp.id_proveedor
WHERE mp.stock_actual <= mp.stock_minimo;

COMMENT ON VIEW biofarm.vista_materias_primas_stock_bajo IS
    '¿Qué materias primas necesitan reabastecimiento urgente? Devuelve los insumos en o por debajo del stock mínimo junto con los datos de contacto de su proveedor.';

COMMENT ON COLUMN biofarm.vista_materias_primas_stock_bajo.faltante IS
    'Diferencia (stock_minimo - stock_actual): cuánto hay que comprar para volver al umbral de seguridad.';

-- ============================================================================
-- CONSULTA 2 · vista_lotes_por_vencer                    [dificultad: básica]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Qué lotes liberados caducan en los próximos 90 días y deben venderse o
--   destruirse pronto?
-- Técnicas: filtros, aritmética de fechas (fecha - fecha = días).
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_lotes_por_vencer AS
SELECT
    l.numero_lote,
    p.codigo          AS codigo_producto,
    p.nombre_comercial,
    l.cantidad_producida,
    l.fecha_caducidad,
    (l.fecha_caducidad - CURRENT_DATE) AS dias_restantes
FROM biofarm.lotes AS l
INNER JOIN biofarm.productos AS p
        ON p.id_producto = l.id_producto
WHERE l.estado = 'liberado'
  AND l.fecha_caducidad > CURRENT_DATE
  AND l.fecha_caducidad <= CURRENT_DATE + 90;

COMMENT ON VIEW biofarm.vista_lotes_por_vencer IS
    '¿Qué lotes liberados caducan en los próximos 90 días? Prioridad de liquidación o destrucción controlada.';

COMMENT ON COLUMN biofarm.vista_lotes_por_vencer.dias_restantes IS
    'Días que faltan para la caducidad (resta de dos fechas en PostgreSQL).';

-- ============================================================================
-- CONSULTA 3 · vista_stock_productos                  [dificultad: intermedia]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuántas unidades disponibles (liberadas, no vencidas y no comprometidas)
--   hay de cada producto?
-- Técnicas: CTEs, LEFT JOIN, agregación con GROUP BY, COALESCE.
-- Lógica:
--   disponibles = SUM(lotes liberados y no vencidos)
--               - SUM(líneas de pedidos no cancelados que consumirán esos
--                 lotes: líneas aún sin lote asignado o con lote válido).
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_stock_productos AS
WITH stock_liberado AS (
    -- Producción apta para venta: lotes liberados que no han caducado.
    SELECT
        l.id_producto,
        SUM(l.cantidad_producida) AS unidades_liberadas
    FROM biofarm.lotes AS l
    WHERE l.estado = 'liberado'
      AND l.fecha_caducidad > CURRENT_DATE
    GROUP BY l.id_producto
),
stock_comprometido AS (
    -- Unidades ya prometidas a clientes en pedidos vivos (no cancelados).
    -- Cuenta las líneas sin lote asignado (lo consumirán después) y las
    -- asignadas a lotes todavía válidos.
    SELECT
        dp.id_producto,
        SUM(dp.cantidad) AS unidades_comprometidas
    FROM biofarm.detalle_pedido AS dp
    INNER JOIN biofarm.pedidos AS pe
            ON pe.id_pedido = dp.id_pedido
    LEFT JOIN biofarm.lotes AS l
           ON l.id_lote = dp.id_lote
    WHERE pe.estado <> 'cancelado'
      AND (dp.id_lote IS NULL
           OR (l.estado = 'liberado' AND l.fecha_caducidad > CURRENT_DATE))
    GROUP BY dp.id_producto
)
SELECT
    p.id_producto,
    p.codigo,
    p.nombre_comercial,
    p.forma_farmaceutica,
    p.requiere_receta,
    p.requiere_cadena_frio,
    p.precio_unitario,
    COALESCE(sl.unidades_liberadas, 0)     AS unidades_liberadas,
    COALESCE(sc.unidades_comprometidas, 0) AS unidades_comprometidas,
    COALESCE(sl.unidades_liberadas, 0)
      - COALESCE(sc.unidades_comprometidas, 0) AS unidades_disponibles
FROM biofarm.productos AS p
LEFT JOIN stock_liberado   AS sl ON sl.id_producto = p.id_producto
LEFT JOIN stock_comprometido AS sc ON sc.id_producto = p.id_producto
WHERE p.activo;

COMMENT ON VIEW biofarm.vista_stock_productos IS
    '¿Cuántas unidades disponibles hay de cada producto? Calcula lotes liberados no vencidos menos unidades comprometidas en pedidos vivos. Un valor negativo indica demanda sin cobertura de stock.';

COMMENT ON COLUMN biofarm.vista_stock_productos.unidades_disponibles IS
    'unidades_liberadas - unidades_comprometidas. Negativo = hay pedidos por más unidades de las aptas para venta.';

-- ============================================================================
-- CONSULTA 4 · vista_resumen_pedidos                  [dificultad: intermedia]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuál es el estado, el número de líneas, las unidades y el monto total
--   de cada pedido, y de qué cliente es?
-- Técnicas: JOIN + LEFT JOIN, agregación, GROUP BY explícito.
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_resumen_pedidos AS
SELECT
    pe.id_pedido,
    pe.numero_pedido,
    c.razon_social  AS cliente,
    c.tipo_cliente,
    pe.fecha_pedido,
    pe.fecha_entrega_estimada,
    pe.estado,
    COUNT(dp.id_detalle)                                    AS lineas,
    COALESCE(SUM(dp.cantidad), 0)                           AS unidades_totales,
    -- ROUND(..., 2): los montos de dinero se presentan redondeados a centavos.
    ROUND(COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0), 2) AS monto_total
FROM biofarm.pedidos AS pe
INNER JOIN biofarm.clientes AS c
        ON c.id_cliente = pe.id_cliente
LEFT JOIN biofarm.detalle_pedido AS dp
       ON dp.id_pedido = pe.id_pedido
GROUP BY pe.id_pedido,
         pe.numero_pedido,
         c.razon_social,
         c.tipo_cliente,
         pe.fecha_pedido,
         pe.fecha_entrega_estimada,
         pe.estado;

COMMENT ON VIEW biofarm.vista_resumen_pedidos IS
    '¿Cuál es el estado y monto de cada pedido y de qué cliente es? Panel comercial de seguimiento de pedidos.';

-- ============================================================================
-- CONSULTA 5 · vista_historial_lotes                   [dificultad: avanzada]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio (trazabilidad, requisito GMP):
--   ¿Quién fabricó cada lote, con qué versión de receta, bajo qué orden de
--   producción y con qué resultados de control de calidad?
-- Técnicas: JOIN de 6 tablas, LEFT JOIN para no perder lotes sin controles,
--           agregación condicional con FILTER, GROUP BY.
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_historial_lotes AS
SELECT
    l.numero_lote,
    p.codigo              AS codigo_producto,
    p.nombre_comercial,
    p.forma_farmaceutica,
    op.codigo             AS codigo_orden_produccion,
    f.version_receta,
    (e.nombre || ' ' || e.apellido_paterno
       || COALESCE(' ' || e.apellido_materno, '')) AS responsable_produccion,
    l.fecha_fabricacion,
    l.fecha_caducidad,
    (l.fecha_caducidad - l.fecha_fabricacion) AS vida_util_dias,
    l.cantidad_producida,
    l.estado              AS estado_lote,
    COUNT(cc.id_control)                                          AS controles_realizados,
    COUNT(cc.id_control) FILTER (WHERE cc.resultado = 'conforme')     AS controles_conformes,
    COUNT(cc.id_control) FILTER (WHERE cc.resultado = 'no_conforme')  AS controles_no_conformes
FROM biofarm.lotes AS l
INNER JOIN biofarm.productos           AS p  ON p.id_producto = l.id_producto
INNER JOIN biofarm.ordenes_produccion  AS op ON op.id_orden_produccion = l.id_orden_produccion
INNER JOIN biofarm.formulaciones       AS f  ON f.id_formulacion = op.id_formulacion
INNER JOIN biofarm.empleados           AS e  ON e.id_empleado = op.id_empleado_responsable
LEFT JOIN biofarm.controles_calidad    AS cc ON cc.id_lote = l.id_lote
GROUP BY l.id_lote,
         p.codigo,
         p.nombre_comercial,
         p.forma_farmaceutica,
         op.codigo,
         f.version_receta,
         e.nombre,
         e.apellido_paterno,
         e.apellido_materno,
         l.fecha_fabricacion,
         l.fecha_caducidad,
         l.cantidad_producida,
         l.estado;

COMMENT ON VIEW biofarm.vista_historial_lotes IS
    'Trazabilidad completa de cada lote: producto, orden de producción, versión de receta, responsable de fabricación y resumen de sus controles de calidad (requisito GMP).';

COMMENT ON COLUMN biofarm.vista_historial_lotes.controles_conformes IS
    'Número de controles con resultado conforme (agregación condicional con la cláusula FILTER).';

-- ============================================================================
-- CONSULTA 6 · vista_productos_sin_ventas              [dificultad: avanzada]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Qué productos activos nunca han tenido ventas (para revisar catálogo,
--   precios o estrategia comercial)?
-- Técnicas: subconsulta correlacionada con NOT EXISTS (semántica anti-join).
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_productos_sin_ventas AS
SELECT
    p.id_producto,
    p.codigo,
    p.nombre_comercial,
    p.forma_farmaceutica,
    p.concentracion,
    p.precio_unitario,
    p.creado_en
FROM biofarm.productos AS p
WHERE p.activo
  AND NOT EXISTS (
        SELECT 1
        FROM biofarm.detalle_pedido AS dp
        INNER JOIN biofarm.pedidos AS pe
                ON pe.id_pedido = dp.id_pedido
        WHERE dp.id_producto = p.id_producto
          AND pe.estado <> 'cancelado'
      );

COMMENT ON VIEW biofarm.vista_productos_sin_ventas IS
    '¿Qué productos activos nunca han tenido ventas? Entrada para decisiones de catálogo, precios y marketing.';

-- ============================================================================
-- CONSULTA 7 · vista_ranking_productos_vendidos        [dificultad: avanzada]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuáles son los productos más vendidos, en qué posición van y qué
--   porcentaje del volumen y del ingreso total representan?
-- Técnicas: CTE + JOIN condicional, agregación con FILTER, FUNCIONES DE
--           VENTANA (RANK y SUM OVER para el total global).
-- ============================================================================
CREATE OR REPLACE VIEW biofarm.vista_ranking_productos_vendidos AS
WITH ventas_por_producto AS (
    SELECT
        p.id_producto,
        p.codigo,
        p.nombre_comercial,
        -- El LEFT JOIN a pedidos con condición de no-cancelado deja en NULL
        -- las líneas de pedidos cancelados; FILTER las excluye de las sumas
        -- pero mantiene el producto en el listado (con 0).
        COALESCE(SUM(dp.cantidad) FILTER (WHERE pe.id_pedido IS NOT NULL), 0)
            AS unidades_vendidas,
        ROUND(COALESCE(SUM(dp.cantidad * dp.precio_unitario)
                     FILTER (WHERE pe.id_pedido IS NOT NULL), 0), 2)
            AS monto_vendido    FROM biofarm.productos AS p
    LEFT JOIN biofarm.detalle_pedido AS dp
           ON dp.id_producto = p.id_producto
    LEFT JOIN biofarm.pedidos AS pe
           ON pe.id_pedido = dp.id_pedido
          AND pe.estado <> 'cancelado'
    GROUP BY p.id_producto, p.codigo, p.nombre_comercial
)
SELECT
    codigo,
    nombre_comercial,
    unidades_vendidas,
    monto_vendido,
    -- RANK(): los empates comparten posición (a diferencia de ROW_NUMBER).
    RANK() OVER (ORDER BY unidades_vendidas DESC, monto_vendido DESC)
        AS posicion_ranking,
    -- SUM(...) OVER () agrega sobre TODAS las filas del resultado:
    -- permite calcular el porcentaje que representa cada producto.
    ROUND(100.0 * unidades_vendidas
          / NULLIF(SUM(unidades_vendidas) OVER (), 0), 2) AS porcentaje_unidades,
    ROUND(100.0 * monto_vendido
          / NULLIF(SUM(monto_vendido) OVER (), 0), 2)      AS porcentaje_monto
FROM ventas_por_producto;

COMMENT ON VIEW biofarm.vista_ranking_productos_vendidos IS
    '¿Cuáles son los productos más vendidos y qué porcentaje del volumen e ingreso total representan? Usa funciones de ventana (RANK y agregadas OVER).';

COMMENT ON COLUMN biofarm.vista_ranking_productos_vendidos.porcentaje_unidades IS
    'Porcentaje del total de unidades vendidas (NULL si aún no hay ventas, por el NULLIF de protección).';

-- ============================================================================
-- CONSULTA 8 · vista_materializada_kpi_mensuales       [dificultad: avanzada]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuáles son los indicadores mensuales del laboratorio: lotes y unidades
--   producidas, controles conformes/no conformes, tasa de conformidad,
--   pedidos registrados/entregados y monto vendido?
-- Técnicas: CTEs de agregación mensual (date_trunc), FULL JOIN para combinar
--           meses con actividad distinta, FILTER condicional.
--
-- ¿Por qué MATERIALIZADA? Es un tablero pesado sobre históricos que no
-- necesita datos en tiempo real: se precalcula y se refresca en horarios
-- establecidos (o tras cada cierre). Refresco:
--   REFRESH MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY ...  -- sin bloquear lecturas
--     (requiere el índice UNIQUE que se crea abajo).
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS biofarm.vista_materializada_kpi_mensuales;

CREATE MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales AS
WITH produccion AS (
    SELECT
        date_trunc('month', l.fecha_fabricacion)::date AS mes,
        COUNT(*)                AS lotes_producidos,
        SUM(l.cantidad_producida) AS unidades_producidas
    FROM biofarm.lotes AS l
    GROUP BY 1
),
calidad AS (
    SELECT
        date_trunc('month', cc.fecha_analisis)::date AS mes,
        COUNT(*) FILTER (WHERE cc.resultado = 'conforme')    AS controles_conformes,
        COUNT(*) FILTER (WHERE cc.resultado = 'no_conforme') AS controles_no_conformes
    FROM biofarm.controles_calidad AS cc
    GROUP BY 1
),
ventas AS (
    SELECT
        date_trunc('month', pe.fecha_pedido)::date AS mes,
        -- DISTINCT porque el LEFT JOIN al detalle multiplica cada pedido
        -- por sus líneas: queremos contar PEDIDOS, no líneas.
        COUNT(DISTINCT pe.id_pedido)                             AS pedidos_registrados,
        COUNT(DISTINCT pe.id_pedido) FILTER (WHERE pe.estado = 'entregado')
                                                                 AS pedidos_entregados,
        ROUND(COALESCE(SUM(dp.cantidad * dp.precio_unitario)
                     FILTER (WHERE pe.estado <> 'cancelado'), 0), 2) AS monto_vendido
    FROM biofarm.pedidos AS pe
    LEFT JOIN biofarm.detalle_pedido AS dp
           ON dp.id_pedido = pe.id_pedido
    GROUP BY 1
)
SELECT
    COALESCE(pr.mes, ca.mes, ve.mes)                    AS mes,
    COALESCE(pr.lotes_producidos, 0)                    AS lotes_producidos,
    COALESCE(pr.unidades_producidas, 0)                 AS unidades_producidas,
    COALESCE(ca.controles_conformes, 0)                 AS controles_conformes,
    COALESCE(ca.controles_no_conformes, 0)              AS controles_no_conformes,
    ROUND(100.0 * COALESCE(ca.controles_conformes, 0)
          / NULLIF(COALESCE(ca.controles_conformes, 0)
                   + COALESCE(ca.controles_no_conformes, 0), 0), 2)
                                                        AS tasa_conformidad_pct,
    COALESCE(ve.pedidos_registrados, 0)                 AS pedidos_registrados,
    COALESCE(ve.pedidos_entregados, 0)                  AS pedidos_entregados,
    COALESCE(ve.monto_vendido, 0)                       AS monto_vendido
FROM produccion AS pr
FULL JOIN calidad  AS ca ON ca.mes = pr.mes
FULL JOIN ventas   AS ve ON ve.mes = COALESCE(pr.mes, ca.mes)
ORDER BY mes;

-- Índice único sobre la columna de agregación: necesario para poder usar
-- REFRESH MATERIALIZED VIEW CONCURRENTLY (refresco sin bloquear lectores).
CREATE UNIQUE INDEX uq_idx_kpi_mensuales_mes
    ON biofarm.vista_materializada_kpi_mensuales (mes);

COMMENT ON MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales IS
    'Tablero de indicadores mensuales (producción, calidad y ventas). Se actualiza con REFRESH MATERIALIZED VIEW, no en tiempo real.';

COMMENT ON COLUMN biofarm.vista_materializada_kpi_mensuales.tasa_conformidad_pct IS
    'Porcentaje de controles conformes sobre el total de controles concluidos (excluye los en_proceso). NULL si el mes no tuvo controles concluidos.';

-- ============================================================================
-- CONSULTA 9 · funcion_stock_disponible(p_id_producto) [dificultad: básica+]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuántas unidades disponibles hay de UN producto concreto?
-- Uso:
--   SELECT biofarm.funcion_stock_disponible(1);
-- Implementada en plpgsql sobre la vista 3: reutilización en capas.
-- ============================================================================
CREATE OR REPLACE FUNCTION biofarm.funcion_stock_disponible(
    p_id_producto BIGINT
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE                                              -- No modifica datos; resultado estable dentro de la transacción
AS $$
DECLARE
    v_stock NUMERIC;
BEGIN
    SELECT vp.unidades_disponibles
      INTO v_stock
      FROM biofarm.vista_stock_productos AS vp
     WHERE vp.id_producto = p_id_producto;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No existe el producto con id %', p_id_producto;
    END IF;

    RETURN v_stock;
END;
$$;

COMMENT ON FUNCTION biofarm.funcion_stock_disponible(BIGINT) IS
    '¿Cuántas unidades disponibles hay de un producto concreto? Reutiliza vista_stock_productos; lanza excepción si el producto no existe.';

-- ============================================================================
-- CONSULTA 10 · funcion_lotes_por_vencer(p_dias)       [dificultad: básica+]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Qué lotes liberados caducan dentro de N días? (versión parametrizable
--   de la consulta 2: el equipo de calidad elige el horizonte).
-- Uso:
--   SELECT * FROM biofarm.funcion_lotes_por_vencer(30);
--   SELECT * FROM biofarm.funcion_lotes_por_vencer();  -- usa el valor por defecto: 90
-- ============================================================================
CREATE OR REPLACE FUNCTION biofarm.funcion_lotes_por_vencer(
    p_dias INTEGER DEFAULT 90
)
RETURNS TABLE (
    numero_lote        VARCHAR(30),
    codigo_producto    VARCHAR(30),
    nombre_comercial   VARCHAR(120),
    cantidad_producida NUMERIC(12,3),
    fecha_caducidad    DATE,
    dias_restantes     INTEGER
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        l.numero_lote,
        p.codigo,
        p.nombre_comercial,
        l.cantidad_producida,
        l.fecha_caducidad,
        (l.fecha_caducidad - CURRENT_DATE) AS dias_restantes
    FROM biofarm.lotes AS l
    INNER JOIN biofarm.productos AS p
            ON p.id_producto = l.id_producto
    WHERE l.estado = 'liberado'
      AND l.fecha_caducidad > CURRENT_DATE
      AND l.fecha_caducidad <= CURRENT_DATE + p_dias
    ORDER BY l.fecha_caducidad;
$$;

COMMENT ON FUNCTION biofarm.funcion_lotes_por_vencer(INTEGER) IS
    '¿Qué lotes liberados caducan dentro de N días (por defecto 90)? Versión parametrizada de la alerta de caducidad.';

-- ============================================================================
-- CONSULTA 11 · funcion_calcular_total_pedido(p_id_pedido) [dificultad: media]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Cuál es el monto total facturable de un pedido concreto?
-- Uso:
--   SELECT biofarm.funcion_calcular_total_pedido(
--       (SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'));
-- Nota: devuelve 0 si el pedido no existe o no tiene líneas.
-- ============================================================================
CREATE OR REPLACE FUNCTION biofarm.funcion_calcular_total_pedido(
    p_id_pedido BIGINT
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT ROUND(COALESCE(SUM(dp.cantidad * dp.precio_unitario), 0), 2)
    FROM biofarm.detalle_pedido AS dp
    WHERE dp.id_pedido = p_id_pedido;
$$;

COMMENT ON FUNCTION biofarm.funcion_calcular_total_pedido(BIGINT) IS
    '¿Cuál es el monto total de un pedido? Suma cantidad x precio de sus líneas; 0 si no existe o está vacío.';

-- ============================================================================
-- CONSULTA 12 · funcion_productos_fabricables()        [dificultad: avanzada]
-- ----------------------------------------------------------------------------
-- Pregunta de negocio:
--   ¿Qué productos pueden fabricarse HOY con el stock actual de materias
--   primas, según su receta vigente?
-- Lógica: un producto es fabricable si NINGÚN ingrediente de su formulación
--         vigente está por debajo de la cantidad requerida por lote estándar.
-- Técnicas: DISTINCT ON (receta más reciente por producto), CTE con anti-join.
-- Uso:
--   SELECT * FROM biofarm.funcion_productos_fabricables();
-- ============================================================================
CREATE OR REPLACE FUNCTION biofarm.funcion_productos_fabricables()
RETURNS TABLE (
    id_producto      BIGINT,
    codigo           VARCHAR(30),
    nombre_comercial VARCHAR(120),
    version_receta   INTEGER
)
LANGUAGE sql
STABLE
AS $$
    WITH recetas_vigentes AS (
        -- DISTINCT ON se queda con UNA fila por producto: la versión de
        -- receta vigente más alta.
        SELECT DISTINCT ON (f.id_producto)
            f.id_producto,
            f.id_formulacion,
            f.version_receta
        FROM biofarm.formulaciones AS f
        WHERE f.vigente
        ORDER BY f.id_producto, f.version_receta DESC
    ),
    ingredientes_insuficientes AS (
        -- Ingredientes cuyo stock actual no alcanza para un lote estándar.
        SELECT
            rv.id_producto,
            COUNT(*) AS ingredientes_faltantes
        FROM recetas_vigentes AS rv
        INNER JOIN biofarm.formulacion_ingredientes AS fi
                ON fi.id_formulacion = rv.id_formulacion
        INNER JOIN biofarm.materias_primas AS mp
                ON mp.id_materia_prima = fi.id_materia_prima
        WHERE mp.stock_actual < fi.cantidad
        GROUP BY rv.id_producto
    )
    SELECT
        rv.id_producto,
        p.codigo,
        p.nombre_comercial,
        rv.version_receta
    FROM recetas_vigentes AS rv
    INNER JOIN biofarm.productos AS p
            ON p.id_producto = rv.id_producto
    LEFT JOIN ingredientes_insuficientes AS ii
           ON ii.id_producto = rv.id_producto
    -- Anti-join: solo productos SIN ingredientes insuficientes.
    WHERE ii.id_producto IS NULL
      AND p.activo
    ORDER BY p.codigo;
$$;

COMMENT ON FUNCTION biofarm.funcion_productos_fabricables() IS
    '¿Qué productos pueden fabricarse hoy con el stock actual de materias primas según su receta vigente? Un lote estándar equivale a 1 000 unidades.';

-- ============================================================================
-- Construcción inicial de la vista materializada (con tablas vacías queda
-- sin filas; tras cargar datos, recuerda refrescarla).
-- ============================================================================
REFRESH MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales;
