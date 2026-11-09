-- ============================================================================
-- LABIOFARM · Sistema de Gestión de Producción y Control de Calidad
-- Script 05 de 05 · Verificación de estructura y consultas
-- ----------------------------------------------------------------------------
-- Prerrequisitos: scripts 02 y 03 ejecutados (y opcionalmente el 04).
-- Conectado a "labiofarm".
--
-- Qué hace: comprueba desde el catálogo del sistema que todos los objetos
-- quedaron creados correctamente: tablas, vistas, vista materializada,
-- funciones, tipos enumerados, restricciones, índices y comentarios.
-- Al final incluye pruebas de humo ("smoke tests") de las consultas.
--
-- Resultados esperados (con o sin datos de prueba):
--   * 12 tablas base          * 7 vistas           * 1 vista materializada
--   * 4 funciones             * 9 tipos ENUM       * comentarios no nulos
-- ============================================================================

SET search_path TO biofarm, public;

-- ============================================================================
-- A. ESTRUCTURA
-- ============================================================================

-- A.1  Tablas base del esquema (se esperan 12, todas con comentario).
SELECT
    c.relname                                   AS tabla,
    (SELECT COUNT(*)
       FROM information_schema.columns AS col
      WHERE col.table_schema = 'biofarm'
        AND col.table_name   = c.relname)       AS columnas,
    obj_description(c.oid, 'pg_class')          AS comentario
FROM pg_class AS c
INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'biofarm'
  AND c.relkind = 'r'                           -- 'r' = tabla base
ORDER BY c.relname;

-- A.2  Conteo de filas por tabla (DO con SQL dinámico).
--      Sin datos de prueba: todas en 0. Con el script 04: 3, 5, 4, 9, 6, 8,
--      18, 8, 7, 13, 4 y 8 según el orden alfabético de las tablas.
DO $$
DECLARE
    r        RECORD;
    v_conteo BIGINT;
BEGIN
    RAISE NOTICE '===== Filas por tabla =====';
    FOR r IN
        SELECT table_name
          FROM information_schema.tables
         WHERE table_schema = 'biofarm'
           AND table_type   = 'BASE TABLE'
         ORDER BY table_name
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM biofarm.%I', r.table_name)
           INTO v_conteo;
        RAISE NOTICE '% => % fila(s)', r.table_name, v_conteo;
    END LOOP;
END $$;

-- A.3  Vistas (se esperan 7, cada una con su pregunta de negocio).
SELECT
    c.relname                          AS vista,
    obj_description(c.oid, 'pg_class') AS pregunta_de_negocio
FROM pg_class AS c
INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'biofarm'
  AND c.relkind = 'v'                  -- 'v' = vista
ORDER BY c.relname;

-- A.4  Vista materializada (se espera 1).
SELECT
    schemaname,
    matviewname     AS vista_materializada,
    ispopulated     AS contiene_datos,
    definition      AS definicion
FROM pg_matviews
WHERE schemaname = 'biofarm';

-- A.5  Funciones (se esperan 4).
SELECT
    routine_name AS funcion,
    data_type    AS tipo_retorno,
    routine_type AS tipo_objeto
FROM information_schema.routines
WHERE routine_schema = 'biofarm'
  AND routine_type   = 'FUNCTION'
ORDER BY routine_name;

-- A.6  Tipos enumerados y sus valores (se esperan 9).
SELECT
    t.typname AS tipo_enum,
    string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder) AS valores
FROM pg_type AS t
INNER JOIN pg_namespace AS n ON n.oid = t.typnamespace
INNER JOIN pg_enum      AS e ON e.enumtypid = t.oid
WHERE n.nspname = 'biofarm'
  AND t.typtype = 'e'                    -- 'e' = enumerado
GROUP BY t.typname
ORDER BY t.typname;

-- A.7  Claves foráneas declaradas (se esperan 16: incluyendo las 3
--      compuestas de integridad cruzada).
SELECT
    con.conname  AS restriccion_fk,
    con.conrelid::regclass AS tabla,
    con.confrelid::regclass AS referencia_a
FROM pg_constraint AS con
WHERE con.connamespace = 'biofarm'::regnamespace
  AND con.contype = 'f'
ORDER BY con.conrelid::regclass::text, con.conname;

-- A.8  Índices del esquema (los de las PK/UNIQUE son automáticos; los
--      idx_* y uq_idx_* son los creados explícitamente).
SELECT
    tablename  AS tabla,
    indexname  AS indice,
    indexdef   AS definicion
FROM pg_indexes
WHERE schemaname = 'biofarm'
ORDER BY tablename, indexname;

-- ============================================================================
-- B. PRUEBAS DE HUMO DE LAS CONSULTAS
-- (Con tablas vacías devuelven 0 filas pero NO deben dar error; con el
--  script 04 cargado devuelven los resultados descritos en el README.)
-- ============================================================================

-- B.1  Vistas básicas.
SELECT * FROM biofarm.vista_materias_primas_stock_bajo;   -- Insumos a reabastecer
SELECT * FROM biofarm.vista_lotes_por_vencer;             -- Lotes que caducan pronto

-- B.2  Vistas de inventario y ventas.
SELECT * FROM biofarm.vista_stock_productos;              -- Stock por producto
SELECT * FROM biofarm.vista_resumen_pedidos;              -- Panel de pedidos
SELECT * FROM biofarm.vista_productos_sin_ventas;         -- Catálogo sin movimiento
SELECT * FROM biofarm.vista_ranking_productos_vendidos;   -- Ranking con ventana

-- B.3  Trazabilidad completa por lote.
SELECT * FROM biofarm.vista_historial_lotes;

-- B.4  Vista materializada (tablero mensual) y su refresco.
SELECT * FROM biofarm.vista_materializada_kpi_mensuales ORDER BY mes;
-- Refresco normal (bloquea lecturas un instante):
REFRESH MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales;
-- Refresco concurrente (no bloquea lectores; requiere el índice único):
REFRESH MATERIALIZED VIEW CONCURRENTLY biofarm.vista_materializada_kpi_mensuales;

-- B.5  Funciones parametrizadas.
-- Stock disponible de un producto (por código). El CASE evita invocar la
-- función si no hay datos cargados: la función lanza excepción para ids
-- inexistentes (comportamiento deseado), y con la base vacía devolvería NULL.
SELECT CASE
           WHEN EXISTS (SELECT 1 FROM biofarm.productos WHERE codigo = 'PROD-001')
           THEN biofarm.funcion_stock_disponible(
                    (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'))
       END AS stock_disponible_prod001;

-- Lotes que vencen en los próximos 30 días (y con el valor por defecto, 90):
SELECT * FROM biofarm.funcion_lotes_por_vencer(30);
SELECT * FROM biofarm.funcion_lotes_por_vencer();

-- Monto total de un pedido concreto:
SELECT biofarm.funcion_calcular_total_pedido(
           (SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'))
       AS total_ped_2026_101;

-- Productos fabricables con el stock actual de materias primas:
SELECT * FROM biofarm.funcion_productos_fabricables();

-- ============================================================================
-- C. VERIFICACIÓN MANUAL DE RESTRICCIONES (opcional, para curiosear)
-- Cada INSERT siguiente DEBE fallar con el error indicado en el comentario.
-- Ejecútalos de uno por uno si quieres comprobar la integridad del modelo;
-- el fallo ES el resultado correcto. (Sección informativa, comentada.)
-- ============================================================================
-- 1. Receta de otro producto en una orden (FK compuesta):
-- INSERT INTO biofarm.ordenes_produccion
--     (codigo, id_producto, id_formulacion, id_empleado_responsable, cantidad_planeada)
-- VALUES ('OP-TEST-001',
--     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
--     (SELECT f.id_formulacion FROM biofarm.formulaciones f
--       JOIN biofarm.productos p ON p.id_producto = f.id_producto
--      WHERE p.codigo = 'PROD-002' AND f.version_receta = 1),
--     (SELECT id_empleado FROM biofarm.empleados LIMIT 1),
--     1000);
-- => ERROR: insert or update on table "ordenes_produccion" violates foreign
--    key constraint "fk_ordenes_produccion_formulacion"
--
-- 2. Línea de pedido surtida con un lote de otro producto (FK compuesta):
-- INSERT INTO biofarm.detalle_pedido (id_pedido, id_producto, id_lote, cantidad, precio_unitario)
-- VALUES ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'),
--         (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002'),
--         (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
--         10, 3.00);
-- => ERROR: viola la FK "fk_detalle_pedido_coherencia"
--
-- 3. Lote con caducidad anterior a su fabricación (CHECK):
-- INSERT INTO biofarm.lotes (numero_lote, id_producto, id_orden_produccion,
--     fecha_fabricacion, fecha_caducidad, cantidad_producida)
-- VALUES ('L-TEST-001',
--     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
--     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-001'),
--     '2026-11-01', '2026-10-01', 100);
-- => ERROR: new row violates check constraint "chk_lotes_fechas"
--
-- 4. Cantidad negativa en una línea de pedido (CHECK):
-- INSERT INTO biofarm.detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario)
-- VALUES ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'),
--         (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
--         -5, 2.50);
-- => ERROR: viola "chk_detalle_pedido_cantidad"
