-- ============================================================================
-- LABIOFARM · Sistema de Gestión de Producción y Control de Calidad
-- Script 04 de 05 · Datos de prueba (OPCIONAL)
-- ----------------------------------------------------------------------------
-- Prerrequisitos: scripts 02 y 03 ejecutados. Conectado a "labiofarm".
--
-- Qué hace: carga un conjunto pequeño pero REALISTA de datos para poder
-- probar las vistas y funciones. Los datos son ficticios.
--
-- Idempotencia: comienza con TRUNCATE ... RESTART IDENTITY de todas las
-- tablas, por lo que puede re-ejecutarse cuantas veces sea necesario y los
-- identificadores vuelven a empezar en 1.
--
-- Buenas prácticas usadas aquí:
--   * INSERT con lista explícita de columnas (nunca posicionales).
--   * Las referencias a otras tablas se resuelven con subconsultas sobre
--     claves naturales (codigo, nif, email...), de modo que el script no
--     depende de valores de IDENTITY y se autovalida.
--   * Transacción única: o se carga todo, o no se carga nada.
--
-- NOTA: las fechas están pensadas para "hoy = noviembre de 2026". Si lo
-- ejecutas en otra fecha, los resultados de las alertas de caducidad
-- cambiarán (los lotes vencidos o ya fuera del horizonte de 90 días).
-- ============================================================================

BEGIN;

-- Limpieza completa (el orden no importa: TRUNCATE multi-tabla respeta las FK).
TRUNCATE TABLE biofarm.detalle_pedido,
               biofarm.pedidos,
               biofarm.controles_calidad,
               biofarm.lotes,
               biofarm.ordenes_produccion,
               biofarm.formulacion_ingredientes,
               biofarm.formulaciones,
               biofarm.productos,
               biofarm.materias_primas,
               biofarm.clientes,
               biofarm.empleados,
               biofarm.proveedores
RESTART IDENTITY;

-- ---------------------------------------------------------------------------
-- PROVEEDORES (3)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.proveedores (razon_social, nif, pais, email, telefono, activo) VALUES
    ('Química FarmaLab, S.A.',      'B12345678', 'España',   'compras@farmalab.es',      '+34 913 456 789', TRUE),
    ('Insumos BioBiotics Ltda.',    'N90123456', 'Colombia', 'ventas@biobiotics.co',     '+57 601 555 0199', TRUE),
    ('Excipientes Ibéricos, S.L.',  'B87654321', 'España',   'pedidos@excipientes.es',   '+34 934 111 222', TRUE);

-- ---------------------------------------------------------------------------
-- EMPLEADOS (5)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.empleados
    (nombre, apellido_paterno, apellido_materno, puesto, email_corporativo, telefono, fecha_contratacion, activo)
VALUES
    ('María', 'López',    'Gutiérrez', 'analista_calidad',     'maria.lopez@labiofarm.com',    '+52 55 1000 2001', '2019-03-01', TRUE),
    ('Carlos', 'Méndez',  NULL,        'analista_calidad',     'carlos.mendez@labiofarm.com',  '+52 55 1000 2002', '2021-07-15', TRUE),
    ('Jorge', 'Ramírez',  'Salas',     'operador_produccion',  'jorge.ramirez@labiofarm.com',  '+52 55 1000 2003', '2018-11-05', TRUE),
    ('Ana',   'Torres',   NULL,        'supervisor_produccion','ana.torres@labiofarm.com',     '+52 55 1000 2004', '2023-02-20', TRUE),
    ('Lucía', 'Fernández','Ruiz',      'gerente_general',      'lucia.fernandez@labiofarm.com','+52 55 1000 2005', '2015-06-01', TRUE);

-- ---------------------------------------------------------------------------
-- CLIENTES (4)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.clientes
    (razon_social, tipo_cliente, nif, email, telefono, direccion, ciudad, pais, activo)
VALUES
    ('Hospital San Rafael',        'hospital',     'HSR-88001', 'compras@hsanrafael.org',  '+52 55 1234 5600', 'Av. Insurgentes 1450',    'Ciudad de México', 'México', TRUE),
    ('Farmacia Central del Valle', 'farmacia',     'FCV-77102', 'contacto@farmaciacentral.mx', '+52 33 3678 9010', 'Av. Vallarta 322',    'Guadalajara',      'México', TRUE),
    ('Distribuidora MediPlus',     'distribuidor', 'DMP-66003', 'pedidos@mediplus.com',    '+52 81 8123 4567', 'Carretera Norte km 12',   'Monterrey',        'México', TRUE),
    ('Clínica Santa Elena',        'clinica',      'CSE-55004', 'insumos@csantaelena.mx',  '+52 22 2456 7890', 'Blvd. Atlixco 88',        'Puebla',           'México', TRUE);

-- ---------------------------------------------------------------------------
-- MATERIAS PRIMAS (9)
-- Tres de ellas (MP-002, MP-007, MP-008) quedan por debajo del stock mínimo
-- a propósito para que la vista de stock bajo devuelva resultados.
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.materias_primas
    (codigo, nombre, descripcion, unidad_medida, stock_actual, stock_minimo, costo_unitario, id_proveedor)
VALUES
    ('MP-001', 'Paracetamol DC 90',                'Principio activo, granulación directa', 'kg', 120.000, 40.000,  18.5000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B12345678')),
    ('MP-002', 'Ibuprofeno 50',                    'Principio activo',                       'kg',   0.200, 20.000,  22.3000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B12345678')),
    ('MP-003', 'Ácido ascórbico (Vitamina C)',     'Principio activo',                       'kg',  95.000, 30.000,  15.2000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'N90123456')),
    ('MP-004', 'Almidón de maíz',                  'Diluyente / desintegrante',              'kg', 300.000, 100.000,  2.1000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B87654321')),
    ('MP-005', 'Estearato de magnesio',            'Lubricante',                             'kg',  45.000, 10.000,   6.8000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B87654321')),
    ('MP-006', 'Sorbitol solución 70%',            'Vehículo para jarabes',                  'kg', 210.000, 80.000,   3.4000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'N90123456')),
    ('MP-007', 'Tartrazina (colorante amarillo)',  'Colorante permitido',                    'kg',   4.000,  5.000,   9.9000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'N90123456')),
    ('MP-008', 'Clorhidrato de metoclopramina',    'Principio activo inyectable',            'kg',   0.005, 15.000, 310.0000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B12345678')),
    ('MP-009', 'Ácido acetilsalicílico',           'Principio activo (aspirina)',            'kg',  60.000, 20.000,  12.0000,
        (SELECT id_proveedor FROM biofarm.proveedores WHERE nif = 'B12345678'));

-- ---------------------------------------------------------------------------
-- PRODUCTOS (6)
-- PROD-006 no tiene lotes ni ventas: debe aparecer en
-- vista_productos_sin_ventas y en funcion_productos_fabricables.
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.productos
    (codigo, nombre_comercial, principio_activo, forma_farmaceutica, concentracion,
     requiere_receta, requiere_cadena_frio, precio_unitario, activo)
VALUES
    ('PROD-001', 'Termoflex 500',          'Paracetamol',                   'comprimido',          '500 mg',      FALSE, FALSE, 2.50, TRUE),
    ('PROD-002', 'Ibuprax 400',            'Ibuprofeno',                    'comprimido',          '400 mg',      FALSE, FALSE, 3.00, TRUE),
    ('PROD-003', 'Vitac 100',              'Ácido ascórbico',               'jarabe',              '100 mg/5 mL', FALSE, FALSE, 4.20, TRUE),
    ('PROD-004', 'Termoflex Pediátrico',   'Paracetamol',                   'jarabe',              '120 mg/5 mL', FALSE, FALSE, 5.50, TRUE),
    ('PROD-005', 'Metoflex Inyectable',    'Clorhidrato de metoclopramina', 'solucion_inyectable', '10 mg/2 mL',  TRUE,  TRUE,  8.00, TRUE),
    ('PROD-006', 'Aspirinex 100',          'Ácido acetilsalicílico',        'comprimido',          '100 mg',      FALSE, FALSE, 1.80, TRUE);

-- ---------------------------------------------------------------------------
-- FORMULACIONES (8): PROD-001 tiene dos versiones (la v1 histórica no vigente).
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.formulaciones
    (id_producto, version_receta, descripcion, fecha_aprobacion, vigente)
VALUES
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'), 1,
     'Formulación inicial de comprimidos', '2024-02-10', FALSE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'), 2,
     'Optimización del proceso de granulación', '2025-06-01', TRUE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002'), 1,
     'Formulación base de ibuprofeno', '2024-08-15', TRUE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'), 1,
     'Jarabe de vitamina C', '2025-01-20', TRUE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004'), 1,
     'Jarabe pediátrico de paracetamol', '2025-03-05', TRUE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005'), 1,
     'Solución inyectable de metoclopramina', '2025-09-12', TRUE),
    ((SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-006'), 1,
     'Comprimidos de aspirina de baja dosis', '2026-01-15', TRUE);

-- ---------------------------------------------------------------------------
-- FORMULACION_INGREDIENTES (18)
-- Cantidad = requerida por lote estándar de 1 000 unidades.
-- Con estos números, PROD-002 y PROD-005 NO son fabricables hoy
-- (MP-002 y MP-008 por debajo de lo requerido).
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.formulacion_ingredientes
    (id_formulacion, id_materia_prima, cantidad, unidad_medida)
VALUES
    -- PROD-001 v2 (vigente): fabricable.
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-001'), 0.550, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-004'), 0.150, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-005'), 0.015, 'kg'),
    -- PROD-001 v1 (histórica).
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-001'), 0.580, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-004'), 0.180, 'kg'),
    -- PROD-002 v1: NO fabricable (MP-002 requiere 0.420 kg y solo hay 0.200).
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-002'), 0.420, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-004'), 0.180, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-005'), 0.012, 'kg'),
    -- PROD-003 v1: fabricable.
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-003'), 0.120, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-006'), 6.500, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-007'), 0.020, 'kg'),
    -- PROD-004 v1: fabricable.
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-001'), 2.400, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-006'), 55.000, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-007'), 0.030, 'kg'),
    -- PROD-005 v1: NO fabricable (MP-008 requiere 0.010 kg y solo hay 0.005).
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-008'), 0.010, 'kg'),
    -- PROD-006 v1: fabricable (pero sin ventas todavía).
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-006')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-009'), 0.110, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-006')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-004'), 0.150, 'kg'),
    ((SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-006')
          AND f.version_receta = 1),
     (SELECT id_materia_prima FROM biofarm.materias_primas WHERE codigo = 'MP-005'), 0.010, 'kg');

-- ---------------------------------------------------------------------------
-- ORDENES_DE_PRODUCCION (8)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.ordenes_produccion
    (codigo, id_producto, id_formulacion, id_empleado_responsable,
     fecha_inicio, fecha_fin, cantidad_planeada, cantidad_producida, estado)
VALUES
    ('OP-2026-001',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'ana.torres@labiofarm.com'),
     '2026-08-10', '2026-08-16', 50000, 50000, 'completada'),
    ('OP-2026-002',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'ana.torres@labiofarm.com'),
     '2026-08-31', '2026-09-03', 30000, 30000, 'completada'),
    ('OP-2026-003',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002')
          AND f.version_receta = 1),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'jorge.ramirez@labiofarm.com'),
     '2026-10-18', '2026-10-22', 20000, 20000, 'completada'),
    ('OP-2026-004',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003')
          AND f.version_receta = 1),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'ana.torres@labiofarm.com'),
     '2026-10-01', '2026-10-07', 8000, 8000, 'completada'),
    ('OP-2026-005',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004')
          AND f.version_receta = 1),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'jorge.ramirez@labiofarm.com'),
     '2026-09-08', '2026-09-12', 5000, 5000, 'completada'),
    ('OP-2026-006',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005')
          AND f.version_receta = 1),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'ana.torres@labiofarm.com'),
     '2026-10-25', '2026-10-29', 12000, 12000, 'completada'),
    ('OP-2026-007',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003')
          AND f.version_receta = 1),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'jorge.ramirez@labiofarm.com'),
     '2025-08-28', '2025-09-02', 6000, 6000, 'completada'),
    ('OP-2026-008',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT f.id_formulacion FROM biofarm.formulaciones f
        WHERE f.id_producto = (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001')
          AND f.version_receta = 2),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'jorge.ramirez@labiofarm.com'),
     '2026-11-05', NULL, 40000, 0, 'en_proceso');

-- ---------------------------------------------------------------------------
-- LOTES (7)
-- L-2026-004 caduca el 2026-12-15 (aparece en la alerta de vencimiento a 90
-- días); L-2026-007 ya está vencido; L-2026-005 fue rechazado por calidad.
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.lotes
    (numero_lote, id_producto, id_orden_produccion, fecha_fabricacion,
     fecha_caducidad, cantidad_producida, estado)
VALUES
    ('L-2026-001',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-001'),
     '2026-08-15', '2028-08-15', 50000, 'liberado'),
    ('L-2026-002',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-002'),
     '2026-09-02', '2028-09-02', 30000, 'liberado'),
    ('L-2026-003',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-003'),
     '2026-10-20', '2028-10-20', 20000, 'cuarentena'),
    ('L-2026-004',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-004'),
     '2026-10-05', '2026-12-15', 8000, 'liberado'),
    ('L-2026-005',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-005'),
     '2026-09-10', '2027-03-10', 5000, 'rechazado'),
    ('L-2026-006',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-006'),
     '2026-10-28', '2027-04-28', 12000, 'liberado'),
    ('L-2026-007',
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT id_orden_produccion FROM biofarm.ordenes_produccion WHERE codigo = 'OP-2026-007'),
     '2025-09-01', '2026-08-01', 6000, 'vencido');

-- ---------------------------------------------------------------------------
-- CONTROLES_CALIDAD (13)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.controles_calidad
    (id_lote, id_empleado_analista, tipo_control, fecha_analisis, resultado, observaciones)
VALUES
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'fisico', '2026-08-17', 'conforme', 'Dureza y friabilidad dentro de especificación.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'quimico', '2026-08-18', 'conforme', 'Contenido de principio activo 99.2%.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'microbiologico', '2026-08-20', 'conforme', NULL),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-002'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'quimico', '2026-09-04', 'conforme', 'Disolución completa en 12 minutos.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-002'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'microbiologico', '2026-09-06', 'conforme', NULL),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-003'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'fisico', '2026-10-23', 'en_proceso', 'Peso promedio en verificación.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-003'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'quimico', '2026-10-24', 'en_proceso', NULL),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-004'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'quimico', '2026-10-09', 'conforme', 'pH 5.1, dentro de especificación.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-004'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'microbiologico', '2026-10-11', 'conforme', NULL),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-005'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'microbiologico', '2026-09-14', 'no_conforme',
     'Recuento de mohos y levaduras por encima del límite de especificación. Lote rechazado.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-006'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'fisico', '2026-10-30', 'conforme', 'Volumen de llenado correcto en las 3 líneas muestreadas.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-006'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'maria.lopez@labiofarm.com'),
     'quimico', '2026-10-31', 'conforme', 'Pureza 99.8%.'),
    ((SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-007'),
     (SELECT id_empleado FROM biofarm.empleados WHERE email_corporativo = 'carlos.mendez@labiofarm.com'),
     'quimico', '2025-09-03', 'conforme', NULL);

-- ---------------------------------------------------------------------------
-- PEDIDOS (4)
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.pedidos
    (numero_pedido, id_cliente, fecha_pedido, fecha_entrega_estimada, estado)
VALUES
    ('PED-2026-101',
     (SELECT id_cliente FROM biofarm.clientes WHERE nif = 'FCV-77102'),
     '2026-10-25', '2026-10-28', 'entregado'),
    ('PED-2026-102',
     (SELECT id_cliente FROM biofarm.clientes WHERE nif = 'HSR-88001'),
     '2026-11-02', '2026-11-12', 'confirmado'),
    ('PED-2026-103',
     (SELECT id_cliente FROM biofarm.clientes WHERE nif = 'DMP-66003'),
     '2026-11-05', '2026-11-20', 'en_preparacion'),
    ('PED-2026-104',
     (SELECT id_cliente FROM biofarm.clientes WHERE nif = 'CSE-55004'),
     '2026-11-08', NULL, 'cancelado');

-- ---------------------------------------------------------------------------
-- DETALLE_PEDIDO (8 líneas)
-- Las líneas sin lote asignado (NULL) representan pedidos aún no surtidos.
-- PED-2026-104 está cancelado: sus líneas NO deben contar como stock
-- comprometido ni como ventas.
-- ---------------------------------------------------------------------------
INSERT INTO biofarm.detalle_pedido
    (id_pedido, id_producto, id_lote, cantidad, precio_unitario)
VALUES
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
     2000, 2.50),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-101'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-004'),
     300, 4.20),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-102'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-001'),
     5000, 2.50),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-102'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-002'),
     NULL,                                   -- Aún sin lote asignado (lote en cuarentena)
     1000, 3.00),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-102'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-005'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-006'),
     500, 8.00),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-103'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-001'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-002'),
     10000, 2.40),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-103'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-004'),
     NULL,                                   -- Producto sin stock liberado
     400, 5.50),
    ((SELECT id_pedido FROM biofarm.pedidos WHERE numero_pedido = 'PED-2026-104'),
     (SELECT id_producto FROM biofarm.productos WHERE codigo = 'PROD-003'),
     (SELECT id_lote FROM biofarm.lotes WHERE numero_lote = 'L-2026-004'),
     100, 4.50);

COMMIT;

-- ---------------------------------------------------------------------------
-- La vista materializada NO se actualiza sola: refrescar tras cargar datos.
-- ---------------------------------------------------------------------------
REFRESH MATERIALIZED VIEW biofarm.vista_materializada_kpi_mensuales;

-- ---------------------------------------------------------------------------
-- Resumen rápido de lo cargado (verificación visual inmediata).
-- ---------------------------------------------------------------------------
SELECT 'proveedores'              AS tabla, COUNT(*) AS filas FROM biofarm.proveedores
UNION ALL SELECT 'empleados',                 COUNT(*) FROM biofarm.empleados
UNION ALL SELECT 'clientes',                  COUNT(*) FROM biofarm.clientes
UNION ALL SELECT 'materias_primas',           COUNT(*) FROM biofarm.materias_primas
UNION ALL SELECT 'productos',                 COUNT(*) FROM biofarm.productos
UNION ALL SELECT 'formulaciones',             COUNT(*) FROM biofarm.formulaciones
UNION ALL SELECT 'formulacion_ingredientes',  COUNT(*) FROM biofarm.formulacion_ingredientes
UNION ALL SELECT 'ordenes_produccion',        COUNT(*) FROM biofarm.ordenes_produccion
UNION ALL SELECT 'lotes',                     COUNT(*) FROM biofarm.lotes
UNION ALL SELECT 'controles_calidad',         COUNT(*) FROM biofarm.controles_calidad
UNION ALL SELECT 'pedidos',                   COUNT(*) FROM biofarm.pedidos
UNION ALL SELECT 'detalle_pedido',            COUNT(*) FROM biofarm.detalle_pedido
ORDER BY tabla;
