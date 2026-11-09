-- ============================================================================
-- LABIOFARM · Sistema de Gestión de Producción y Control de Calidad
-- Script 02 de 05 · Creación del esquema, tipos, tablas, índices y comentarios
-- ----------------------------------------------------------------------------
-- Prerrequisitos:
--   * Haber ejecutado antes el script 01_crear_base_datos.sql.
--   * Ejecutar este script CONECTADO a la base de datos "labiofarm".
--
-- Qué hace (en orden):
--   1. Elimina el esquema "biofarm" si existe (idempotencia destructiva,
--      ver advertencia) y lo vuelve a crear.
--   2. Crea los tipos enumerados del negocio (dominios cerrados).
--   3. Crea las 12 tablas EN ORDEN DE DEPENDENCIA (primero tablas sin
--      claves foráneas; las que referencian a otras van después).
--   4. Crea los índices adicionales (PostgreSQL NO indexa claves foráneas
--      de forma automática).
--   5. Documenta tablas y columnas clave con COMMENT ON.
--
-- ADVERTENCIA DE IDEMPOTENCIA:
--   La primera línea elimina el esquema completo (tablas, vistas, funciones,
--   tipos y TODOS SUS DATOS) para poder re-ejecutar el script desde cero sin
--   errores. Es la estrategia estándar para scripts de arranque (bootstrap)
--   en entornos de desarrollo. NO uses este script tal cual en producción
--   con datos reales; en ese caso, comenta el DROP SCHEMA y usa migraciones
--   incrementales.
--
-- Convenciones de nomenclatura:
--   * Todo en snake_case, sin acentos ni "ñ" (portabilidad de identificadores:
--     "numero" y no "número").
--   * Restricciones nombradas para mensajes de error legibles:
--       pk_<tabla>            clave primaria
--       uq_<tabla>_<regla>    unicidad
--       fk_<tabla>_<ref>      clave foránea
--       chk_<tabla>_<regla>   validación de dominio
--   * Índices: idx_<tabla>_<columnas>.
--   * Las claves primarias son BIGINT GENERATED ALWAYS AS IDENTITY
--     (sucesor moderno de SERIAL: no permite insertar ids a mano por error).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) REINICIO DEL ESQUEMA
-- ---------------------------------------------------------------------------
DROP SCHEMA IF EXISTS biofarm CASCADE;

CREATE SCHEMA biofarm;

-- Comodidad para la sesión: permite referirse a los objetos sin el prefijo
-- "biofarm.". Los scripts siguen usando nombres totalmente calificados como
-- buena práctica, pero esto evita sorpresas en sesiones interactivas.
SET search_path TO biofarm, public;

COMMENT ON SCHEMA biofarm IS
    'Esquema del sistema de producción y control de calidad del laboratorio biofarmacéutico LabioFarm.';

COMMENT ON DATABASE labiofarm IS
    'LabioFarm: gestión de formulaciones, producción por lotes, control de calidad, inventario y ventas.';

-- ---------------------------------------------------------------------------
-- 2) TIPOS ENUMERADOS (dominios cerrados del negocio)
-- ---------------------------------------------------------------------------
-- Se usan ENUM en lugar de CHECK (col IN (...)) para los catálogos estables,
-- porque ofrecen mejor rendimiento de comparación, mensajes de error claros
-- y orden natural de valores. Agregar un valor nuevo en el futuro es simple:
--   ALTER TYPE biofarm.estado_pedido ADD VALUE 'devuelto';

-- Segmento al que pertenece el cliente.
CREATE TYPE biofarm.tipo_cliente AS ENUM
    ('hospital', 'farmacia', 'distribuidor', 'clinica');

-- Puesto del personal del laboratorio.
CREATE TYPE biofarm.puesto_empleado AS ENUM
    ('analista_calidad', 'operador_produccion', 'supervisor_produccion', 'gerente_general');

-- Unidades de medida aceptadas para materias primas e ingredientes.
CREATE TYPE biofarm.unidad_medida AS ENUM
    ('mg', 'g', 'kg', 'ml', 'l', 'unidad');

-- Forma farmacéutica de presentación del producto terminado.
CREATE TYPE biofarm.forma_farmaceutica AS ENUM
    ('comprimido', 'capsula', 'jarabe', 'solucion_inyectable', 'crema', 'gel');

-- Ciclo de vida de un pedido de venta.
CREATE TYPE biofarm.estado_pedido AS ENUM
    ('pendiente', 'confirmado', 'en_preparacion', 'enviado', 'entregado', 'cancelado');

-- Ciclo de vida de una orden de producción.
CREATE TYPE biofarm.estado_orden_produccion AS ENUM
    ('planificada', 'en_proceso', 'completada', 'cancelada');

-- Ciclo de vida de un lote farmacéutico.
CREATE TYPE biofarm.estado_lote AS ENUM
    ('cuarentena', 'liberado', 'rechazado', 'vencido');

-- Tipo de análisis de control de calidad.
CREATE TYPE biofarm.tipo_control AS ENUM
    ('fisico', 'quimico', 'microbiologico');

-- Resultado de un análisis de control de calidad.
CREATE TYPE biofarm.resultado_control AS ENUM
    ('en_proceso', 'conforme', 'no_conforme');

-- ---------------------------------------------------------------------------
-- 3) TABLAS (en orden de dependencia: primero las que no referencian a nada)
-- ---------------------------------------------------------------------------

-- ============================================================================
-- 3.1  PROVEEDORES
-- Empresas que suministran las materias primas del laboratorio.
-- ============================================================================
CREATE TABLE biofarm.proveedores (
    id_proveedor  BIGINT GENERATED ALWAYS AS IDENTITY,
    razon_social  VARCHAR(150)  NOT NULL,                 -- Nombre legal de la empresa
    nif           VARCHAR(20)   NOT NULL,                 -- Número de identificación fiscal
    pais          VARCHAR(50)   NOT NULL,
    email         VARCHAR(120),                           -- Correo de contacto (opcional)
    telefono      VARCHAR(25),
    activo        BOOLEAN       NOT NULL DEFAULT TRUE,    -- FALSE = proveedor dado de baja
    creado_en     TIMESTAMPTZ   NOT NULL DEFAULT now(),   -- Auditoría: momento de alta
    CONSTRAINT pk_proveedores PRIMARY KEY (id_proveedor),
    CONSTRAINT uq_proveedores_nif UNIQUE (nif),
    CONSTRAINT chk_proveedores_razon_social
        CHECK (LENGTH(TRIM(razon_social)) > 0),           -- Evita cadenas vacías o de espacios
    CONSTRAINT chk_proveedores_email
        CHECK (email IS NULL OR POSITION('@' IN email) > 1)  -- Validación básica de correo
);

COMMENT ON TABLE biofarm.proveedores IS
    'Empresas proveedoras de materias primas. Un proveedor activo puede suministrar N materias primas.';

-- ============================================================================
-- 3.2  EMPLEADOS
-- Personal del laboratorio: analistas de calidad, operadores y supervisores
-- de producción, y gerencia. Participan como responsables de órdenes de
-- producción y como analistas de controles de calidad.
-- ============================================================================
CREATE TABLE biofarm.empleados (
    id_empleado        BIGINT GENERATED ALWAYS AS IDENTITY,
    nombre             VARCHAR(80)             NOT NULL,
    apellido_paterno   VARCHAR(80)             NOT NULL,
    apellido_materno   VARCHAR(80),                            -- NULL permitido: no todos los países lo usan
    puesto             biofarm.puesto_empleado NOT NULL,
    email_corporativo  VARCHAR(120)            NOT NULL,
    telefono           VARCHAR(25),
    fecha_contratacion DATE                    NOT NULL DEFAULT CURRENT_DATE,
    activo             BOOLEAN                 NOT NULL DEFAULT TRUE,
    creado_en          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    CONSTRAINT pk_empleados PRIMARY KEY (id_empleado),
    CONSTRAINT uq_empleados_email UNIQUE (email_corporativo),
    CONSTRAINT chk_empleados_nombre
        CHECK (LENGTH(TRIM(nombre)) > 0 AND LENGTH(TRIM(apellido_paterno)) > 0),
    CONSTRAINT chk_empleados_email
        CHECK (POSITION('@' IN email_corporativo) > 1),
    CONSTRAINT chk_empleados_fecha_contratacion
        CHECK (fecha_contratacion <= CURRENT_DATE)          -- No se puede contratar a futuro
);

COMMENT ON TABLE biofarm.empleados IS
    'Personal del laboratorio. Los empleados figuran como responsables de órdenes de producción y como analistas de controles de calidad.';

COMMENT ON COLUMN biofarm.empleados.puesto IS
    'Puesto: analista_calidad (QA/QC), operador_produccion, supervisor_produccion o gerente_general.';

-- ============================================================================
-- 3.3  CLIENTES
-- Hospitales, farmacias, distribuidores y clínicas que compran los productos.
-- ============================================================================
CREATE TABLE biofarm.clientes (
    id_cliente   BIGINT GENERATED ALWAYS AS IDENTITY,
    razon_social VARCHAR(150)        NOT NULL,
    tipo_cliente biofarm.tipo_cliente NOT NULL,            -- Segmento comercial
    nif          VARCHAR(20)         NOT NULL,
    email        VARCHAR(120),
    telefono     VARCHAR(25),
    direccion    VARCHAR(200),
    ciudad       VARCHAR(80),
    pais         VARCHAR(50)         NOT NULL,
    activo       BOOLEAN             NOT NULL DEFAULT TRUE,
    creado_en    TIMESTAMPTZ         NOT NULL DEFAULT now(),
    CONSTRAINT pk_clientes PRIMARY KEY (id_cliente),
    CONSTRAINT uq_clientes_nif UNIQUE (nif),
    CONSTRAINT chk_clientes_razon_social
        CHECK (LENGTH(TRIM(razon_social)) > 0),
    CONSTRAINT chk_clientes_email
        CHECK (email IS NULL OR POSITION('@' IN email) > 1)
);

COMMENT ON TABLE biofarm.clientes IS
    'Compradores de los productos terminados: hospitales, farmacias, distribuidores y clínicas. Un cliente activo puede tener N pedidos.';

-- ============================================================================
-- 3.4  MATERIAS_PRIMAS
-- Insumos comprados a proveedores y consumidos por las formulaciones.
-- El inventario de materias primas se controla aquí con stock actual y mínimo
-- (en este modelo las materias primas NO se rastrean por lote; ver
-- "posibles extensiones" en el README).
-- ============================================================================
CREATE TABLE biofarm.materias_primas (
    id_materia_prima BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo           VARCHAR(30)           NOT NULL,        -- Código interno, ej. MP-001
    nombre           VARCHAR(120)          NOT NULL,
    descripcion      TEXT,
    unidad_medida    biofarm.unidad_medida NOT NULL,
    stock_actual     NUMERIC(12,3)         NOT NULL DEFAULT 0,
    stock_minimo     NUMERIC(12,3)         NOT NULL DEFAULT 0,  -- Umbral de reabastecimiento
    costo_unitario   NUMERIC(12,4)         NOT NULL,        -- Costo por unidad de medida
    id_proveedor     BIGINT                NOT NULL,
    creado_en        TIMESTAMPTZ           NOT NULL DEFAULT now(),
    CONSTRAINT pk_materias_primas PRIMARY KEY (id_materia_prima),
    CONSTRAINT uq_materias_primas_codigo UNIQUE (codigo),
    CONSTRAINT fk_materias_primas_proveedor
        FOREIGN KEY (id_proveedor)
        REFERENCES biofarm.proveedores (id_proveedor)
        ON DELETE RESTRICT ON UPDATE CASCADE,              -- No se borra un proveedor con insumos asociados
    CONSTRAINT chk_materias_primas_nombre
        CHECK (LENGTH(TRIM(nombre)) > 0),
    CONSTRAINT chk_materias_primas_stock_actual
        CHECK (stock_actual >= 0),
    CONSTRAINT chk_materias_primas_stock_minimo
        CHECK (stock_minimo >= 0),
    CONSTRAINT chk_materias_primas_costo
        CHECK (costo_unitario >= 0)
);

COMMENT ON TABLE biofarm.materias_primas IS
    'Insumos comprados a proveedores. El control de existencias usa stock_actual frente a stock_minimo para disparar reabastecimientos (ver vista_materias_primas_stock_bajo).';

COMMENT ON COLUMN biofarm.materias_primas.stock_minimo IS
    'Nivel de existencias por debajo del cual se debe emitir una orden de compra al proveedor.';

-- ============================================================================
-- 3.5  PRODUCTOS
-- Medicamentos terminados que fabrica y vende el laboratorio.
-- DECISIÓN DE DISEÑO: el stock de producto terminado NO se guarda aquí;
-- se calcula a partir de los lotes liberados (ver vista_stock_productos).
-- Así se evita la anomalía de actualización de mantener un contador redundante.
-- ============================================================================
CREATE TABLE biofarm.productos (
    id_producto          BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo               VARCHAR(30)                NOT NULL,   -- Código interno, ej. PROD-001
    nombre_comercial     VARCHAR(120)               NOT NULL,
    principio_activo     VARCHAR(150)               NOT NULL,
    forma_farmaceutica   biofarm.forma_farmaceutica NOT NULL,
    concentracion        VARCHAR(50)                NOT NULL,   -- Texto libre: "500 mg", "120 mg/5 mL"
    requiere_receta      BOOLEAN                    NOT NULL DEFAULT FALSE,
    requiere_cadena_frio BOOLEAN                    NOT NULL DEFAULT FALSE,
    precio_unitario      NUMERIC(12,2)              NOT NULL,
    activo               BOOLEAN                    NOT NULL DEFAULT TRUE,
    creado_en            TIMESTAMPTZ                NOT NULL DEFAULT now(),
    CONSTRAINT pk_productos PRIMARY KEY (id_producto),
    CONSTRAINT uq_productos_codigo UNIQUE (codigo),
    CONSTRAINT chk_productos_nombre
        CHECK (LENGTH(TRIM(nombre_comercial)) > 0),
    CONSTRAINT chk_productos_concentracion
        CHECK (LENGTH(TRIM(concentracion)) > 0),
    CONSTRAINT chk_productos_precio
        CHECK (precio_unitario >= 0)
);

COMMENT ON TABLE biofarm.productos IS
    'Catálogo de medicamentos terminados. El stock disponible no se almacena: se deriva de los lotes liberados no vencidos menos lo comprometido en pedidos (vista_stock_productos).';

COMMENT ON COLUMN biofarm.productos.concentracion IS
    'Concentración como texto porque sus unidades son heterogéneas (mg por comprimido, mg/5 mL en jarabes).';

COMMENT ON COLUMN biofarm.productos.requiere_cadena_frio IS
    'TRUE si el producto debe conservarse entre 2 y 8 °C durante almacenamiento y transporte.';

-- ============================================================================
-- 3.6  FORMULACIONES
-- Recetas (maestro de fórmula) de cada producto. Un producto tiene una o
-- varias VERSIONES de receta; solo una debe estar vigente. Las órdenes de
-- producción se atan a una versión concreta para garantizar trazabilidad
-- regulatoria (GMP): siempre se puede saber con qué fórmula se hizo un lote.
-- ============================================================================
CREATE TABLE biofarm.formulaciones (
    id_formulacion   BIGINT GENERATED ALWAYS AS IDENTITY,
    id_producto      BIGINT       NOT NULL,
    version_receta   INTEGER      NOT NULL,
    descripcion      VARCHAR(300),
    fecha_aprobacion DATE         NOT NULL,
    vigente          BOOLEAN      NOT NULL DEFAULT TRUE,
    creado_en        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT pk_formulaciones PRIMARY KEY (id_formulacion),
    CONSTRAINT uq_formulaciones_producto_version
        UNIQUE (id_producto, version_receta),              -- Cada producto tiene una sola receta v1, v2...
    -- Clave única "puente": habilita la FK compuesta de ordenes_produccion
    -- que garantiza que la receta usada pertenezca al producto fabricado.
    CONSTRAINT uq_formulaciones_producto_formulacion
        UNIQUE (id_formulacion, id_producto),
    CONSTRAINT fk_formulaciones_producto
        FOREIGN KEY (id_producto)
        REFERENCES biofarm.productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_formulaciones_version
        CHECK (version_receta >= 1),
    CONSTRAINT chk_formulaciones_fecha_aprobacion
        CHECK (fecha_aprobacion <= CURRENT_DATE)
);

COMMENT ON TABLE biofarm.formulaciones IS
    'Versiones de la receta (maestro de fórmula) de cada producto. Solo una versión por producto debe estar vigente; las órdenes de producción referencian la versión exacta usada (trazabilidad GMP).';

COMMENT ON COLUMN biofarm.formulaciones.vigente IS
    'TRUE para la versión aprobada actualmente en uso. Al aprobar una versión nueva se desactiva la anterior.';

-- ============================================================================
-- 3.7  FORMULACION_INGREDIENTES
-- Tabla de unión (N:M) que resuelve la relación entre formulaciones y
-- materias primas: qué insumos lleva cada receta y en qué cantidad.
-- Clave primaria compuesta: un ingrediente aparece una sola vez por receta.
-- ============================================================================
CREATE TABLE biofarm.formulacion_ingredientes (
    id_formulacion   BIGINT                 NOT NULL,
    id_materia_prima BIGINT                 NOT NULL,
    cantidad         NUMERIC(12,3)          NOT NULL,
    unidad_medida    biofarm.unidad_medida  NOT NULL,
    CONSTRAINT pk_formulacion_ingredientes
        PRIMARY KEY (id_formulacion, id_materia_prima),
    CONSTRAINT fk_formulacion_ingredientes_formulacion
        FOREIGN KEY (id_formulacion)
        REFERENCES biofarm.formulaciones (id_formulacion)
        ON DELETE CASCADE ON UPDATE CASCADE,               -- Los ingredientes mueren con su receta
    CONSTRAINT fk_formulacion_ingredientes_materia_prima
        FOREIGN KEY (id_materia_prima)
        REFERENCES biofarm.materias_primas (id_materia_prima)
        ON DELETE RESTRICT ON UPDATE CASCADE,              -- No se borra un insumo usado en recetas
    CONSTRAINT chk_formulacion_ingredientes_cantidad
        CHECK (cantidad > 0)
);

COMMENT ON TABLE biofarm.formulacion_ingredientes IS
    'Detalle de ingredientes de cada formulación (relación N:M entre recetas y materias primas).';

COMMENT ON COLUMN biofarm.formulacion_ingredientes.cantidad IS
    'Cantidad de materia prima requerida para producir un lote estándar de 1 000 unidades de producto terminado.';

-- ============================================================================
-- 3.8  ORDENES_PRODUCCION
-- Órdenes para fabricar un producto usando una versión de receta concreta,
-- bajo la responsabilidad de un empleado. Generan lotes al completarse.
-- ============================================================================
CREATE TABLE biofarm.ordenes_produccion (
    id_orden_produccion     BIGINT GENERATED ALWAYS AS IDENTITY,
    codigo                  VARCHAR(30)                      NOT NULL,  -- Ej. OP-2026-001
    id_producto             BIGINT                           NOT NULL,
    id_formulacion          BIGINT                           NOT NULL,
    id_empleado_responsable BIGINT                           NOT NULL,
    fecha_inicio            DATE                             NOT NULL DEFAULT CURRENT_DATE,
    fecha_fin               DATE,                                        -- NULL mientras está en curso
    cantidad_planeada       NUMERIC(12,3)                    NOT NULL,
    cantidad_producida      NUMERIC(12,3)                    NOT NULL DEFAULT 0,
    estado                  biofarm.estado_orden_produccion  NOT NULL DEFAULT 'planificada',
    creado_en               TIMESTAMPTZ                      NOT NULL DEFAULT now(),
    CONSTRAINT pk_ordenes_produccion PRIMARY KEY (id_orden_produccion),
    CONSTRAINT uq_ordenes_produccion_codigo UNIQUE (codigo),
    CONSTRAINT fk_ordenes_produccion_producto
        FOREIGN KEY (id_producto)
        REFERENCES biofarm.productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- INTEGRIDAD CRUZADA (técnica avanzada): la FK compuesta exige que el par
    -- (id_formulacion, id_producto) exista en formulaciones, es decir, que la
    -- receta utilizada pertenezca EXACTAMENTE al producto que se fabrica.
    -- Sin esto, nada impediría producir un producto con la receta de otro.
    CONSTRAINT fk_ordenes_produccion_formulacion
        FOREIGN KEY (id_formulacion, id_producto)
        REFERENCES biofarm.formulaciones (id_formulacion, id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_ordenes_produccion_empleado
        FOREIGN KEY (id_empleado_responsable)
        REFERENCES biofarm.empleados (id_empleado)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- Clave única "puente" que habilita la FK compuesta de lotes.
    CONSTRAINT uq_ordenes_produccion_coherencia
        UNIQUE (id_orden_produccion, id_producto),
    CONSTRAINT chk_ordenes_produccion_cantidad_planeada
        CHECK (cantidad_planeada > 0),
    CONSTRAINT chk_ordenes_produccion_cantidad_producida
        CHECK (cantidad_producida >= 0),
    CONSTRAINT chk_ordenes_produccion_fechas
        CHECK (fecha_fin IS NULL OR fecha_fin >= fecha_inicio)
);

COMMENT ON TABLE biofarm.ordenes_produccion IS
    'Órdenes de fabricación: qué producto, con qué versión de receta, cuánto y bajo la responsabilidad de qué empleado. Cada orden puede generar uno o varios lotes.';

COMMENT ON COLUMN biofarm.ordenes_produccion.fecha_fin IS
    'Fecha de cierre de la orden; NULL mientras esté planificada o en proceso.';

-- ============================================================================
-- 3.9  LOTES
-- Unidades de fabricación con identidad regulatoria propia (número de lote).
-- Cada lote sale de una orden de producción y pasa por control de calidad:
-- cuarentena -> liberado / rechazado; y "vencido" al pasar su caducidad.
-- La trazabilidad farmacéutica completa es: cliente -> detalle de pedido ->
-- lote -> orden de producción -> formulación -> materias primas/proveedores.
-- ============================================================================
CREATE TABLE biofarm.lotes (
    id_lote             BIGINT GENERATED ALWAYS AS IDENTITY,
    numero_lote         VARCHAR(30)             NOT NULL,     -- Ej. L-2026-001 (impreso en el empaque)
    id_producto         BIGINT                  NOT NULL,
    id_orden_produccion BIGINT                  NOT NULL,
    fecha_fabricacion   DATE                    NOT NULL,
    fecha_caducidad     DATE                    NOT NULL,
    cantidad_producida  NUMERIC(12,3)           NOT NULL,
    estado              biofarm.estado_lote     NOT NULL DEFAULT 'cuarentena',
    creado_en           TIMESTAMPTZ             NOT NULL DEFAULT now(),
    CONSTRAINT pk_lotes PRIMARY KEY (id_lote),
    CONSTRAINT uq_lotes_numero UNIQUE (numero_lote),
    CONSTRAINT fk_lotes_producto
        FOREIGN KEY (id_producto)
        REFERENCES biofarm.productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- INTEGRIDAD CRUZADA: garantiza que el lote pertenezca al mismo producto
    -- que la orden de producción de la que proviene.
    CONSTRAINT fk_lotes_coherencia
        FOREIGN KEY (id_orden_produccion, id_producto)
        REFERENCES biofarm.ordenes_produccion (id_orden_produccion, id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- Clave única "puente" que habilita la FK compuesta de detalle_pedido.
    CONSTRAINT uq_lotes_coherencia
        UNIQUE (id_lote, id_producto),
    CONSTRAINT chk_lotes_cantidad
        CHECK (cantidad_producida > 0),
    CONSTRAINT chk_lotes_fechas
        CHECK (fecha_caducidad > fecha_fabricacion)
);

COMMENT ON TABLE biofarm.lotes IS
    'Lotes fabricados: la unidad de trazabilidad del sistema. Un lote nace de una orden de producción, pasa por controles de calidad y de él se surten los pedidos de venta.';

COMMENT ON COLUMN biofarm.lotes.estado IS
    'Ciclo de vida: cuarentena (recién fabricado, en análisis) -> liberado (aprobado, vendible) o rechazado; vencido cuando supera su fecha de caducidad.';

-- ============================================================================
-- 3.10  CONTROLES_CALIDAD
-- Análisis de laboratorio practicados a los lotes por analistas.
-- Un lote suele requerir varios controles (físico, químico, microbiológico)
-- y se libera solo cuando todos concluyen como conformes.
-- ============================================================================
CREATE TABLE biofarm.controles_calidad (
    id_control           BIGINT GENERATED ALWAYS AS IDENTITY,
    id_lote              BIGINT                     NOT NULL,
    id_empleado_analista BIGINT                     NOT NULL,
    tipo_control         biofarm.tipo_control       NOT NULL,
    fecha_analisis       DATE                       NOT NULL DEFAULT CURRENT_DATE,
    resultado            biofarm.resultado_control  NOT NULL DEFAULT 'en_proceso',
    observaciones        TEXT,
    creado_en            TIMESTAMPTZ                NOT NULL DEFAULT now(),
    CONSTRAINT pk_controles_calidad PRIMARY KEY (id_control),
    CONSTRAINT fk_controles_calidad_lote
        FOREIGN KEY (id_lote)
        REFERENCES biofarm.lotes (id_lote)
        ON DELETE RESTRICT ON UPDATE CASCADE,           -- El historial de calidad es indeleble (GMP)
    CONSTRAINT fk_controles_calidad_analista
        FOREIGN KEY (id_empleado_analista)
        REFERENCES biofarm.empleados (id_empleado)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_controles_calidad_fecha
        CHECK (fecha_analisis <= CURRENT_DATE)
);

COMMENT ON TABLE biofarm.controles_calidad IS
    'Análisis de calidad por lote (físico, químico o microbiológico) realizados por analistas. El resultado en_proceso cambia a conforme o no_conforme al concluir el estudio.';

-- ============================================================================
-- 3.11  PEDIDOS
-- Órdenes de venta realizadas por los clientes.
-- ============================================================================
CREATE TABLE biofarm.pedidos (
    id_pedido              BIGINT GENERATED ALWAYS AS IDENTITY,
    numero_pedido          VARCHAR(30)             NOT NULL,   -- Ej. PED-2026-101
    id_cliente             BIGINT                  NOT NULL,
    fecha_pedido           DATE                    NOT NULL DEFAULT CURRENT_DATE,
    fecha_entrega_estimada DATE,                                -- NULL = sin fecha comprometida aún
    estado                 biofarm.estado_pedido   NOT NULL DEFAULT 'pendiente',
    creado_en              TIMESTAMPTZ             NOT NULL DEFAULT now(),
    CONSTRAINT pk_pedidos PRIMARY KEY (id_pedido),
    CONSTRAINT uq_pedidos_numero UNIQUE (numero_pedido),
    CONSTRAINT fk_pedidos_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES biofarm.clientes (id_cliente)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_pedidos_fechas
        CHECK (fecha_entrega_estimada IS NULL OR fecha_entrega_estimada >= fecha_pedido)
);

COMMENT ON TABLE biofarm.pedidos IS
    'Órdenes de venta de los clientes. El monto total NO se almacena: se calcula desde el detalle (vista_resumen_pedidos / funcion_calcular_total_pedido).';

-- ============================================================================
-- 3.12  DETALLE_PEDIDO
-- Líneas de cada pedido: producto, cantidad, precio pactado y (opcionalmente)
-- el lote desde el cual se surte la línea — el eslabón final de la
-- trazabilidad hacia atrás (del cliente a la materia prima).
-- ============================================================================
CREATE TABLE biofarm.detalle_pedido (
    id_detalle      BIGINT GENERATED ALWAYS AS IDENTITY,
    id_pedido       BIGINT        NOT NULL,
    id_producto     BIGINT        NOT NULL,
    id_lote         BIGINT,                            -- NULL hasta asignar lote al surtir
    cantidad        NUMERIC(12,3) NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,            -- Precio pactado en el momento de la venta
    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_detalle),
    CONSTRAINT fk_detalle_pedido_pedido
        FOREIGN KEY (id_pedido)
        REFERENCES biofarm.pedidos (id_pedido)
        ON DELETE CASCADE ON UPDATE CASCADE,           -- Las líneas pertenecen a su pedido
    CONSTRAINT fk_detalle_pedido_producto
        FOREIGN KEY (id_producto)
        REFERENCES biofarm.productos (id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    -- INTEGRIDAD CRUZADA: si la línea tiene lote asignado, el par
    -- (id_lote, id_producto) debe existir en lotes, es decir, el lote debe
    -- ser DEL MISMO producto que la línea vende. Al ser id_lote nullable,
    -- PostgreSQL (MATCH SIMPLE) no evalúa la FK mientras id_lote sea NULL.
    CONSTRAINT fk_detalle_pedido_coherencia
        FOREIGN KEY (id_lote, id_producto)
        REFERENCES biofarm.lotes (id_lote, id_producto)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_detalle_pedido_cantidad
        CHECK (cantidad > 0),
    CONSTRAINT chk_detalle_pedido_precio
        CHECK (precio_unitario >= 0)
);

COMMENT ON TABLE biofarm.detalle_pedido IS
    'Líneas de pedido: producto, cantidad y precio pactado. id_lote se asigna al surtir la línea y es la clave de la trazabilidad hacia atrás.';

COMMENT ON COLUMN biofarm.detalle_pedido.id_lote IS
    'Lote desde el que se surte la línea. NULL mientras el pedido no se prepara en almacén.';

COMMENT ON COLUMN biofarm.detalle_pedido.precio_unitario IS
    'Precio histórico pactado en la venta; no cambia si luego cambia el precio de catálogo del producto.';

-- ---------------------------------------------------------------------------
-- 4) ÍNDICES
-- PostgreSQL crea automáticamente índices para claves primarias y
-- restricciones UNIQUE, pero NO para claves foráneas. Los siguientes índices
-- aceleran los JOIN y filtros más frecuentes del sistema.
-- ---------------------------------------------------------------------------
CREATE INDEX idx_materias_primas_proveedor
    ON biofarm.materias_primas (id_proveedor);

CREATE INDEX idx_formulaciones_producto
    ON biofarm.formulaciones (id_producto);

-- Búsqueda inversa: "¿en qué recetas se usa esta materia prima?"
-- (la clave primaria compuesta solo indexa la búsqueda en el otro sentido).
CREATE INDEX idx_formulacion_ingredientes_materia
    ON biofarm.formulacion_ingredientes (id_materia_prima);

CREATE INDEX idx_ordenes_produccion_producto
    ON biofarm.ordenes_produccion (id_producto);

CREATE INDEX idx_ordenes_produccion_empleado
    ON biofarm.ordenes_produccion (id_empleado_responsable);

-- Panel de órdenes por estado y fecha.
CREATE INDEX idx_ordenes_produccion_estado_fecha
    ON biofarm.ordenes_produccion (estado, fecha_inicio);

CREATE INDEX idx_lotes_producto
    ON biofarm.lotes (id_producto);

-- ÍNDICE PARCIAL: solo indexa los lotes liberados (los vendibles), que son
-- los que consultan el cálculo de stock y el alerta de caducidad. Menos filas
-- indexadas = índice más pequeño y más rápido.
CREATE INDEX idx_lotes_producto_caducidad_liberados
    ON biofarm.lotes (id_producto, fecha_caducidad)
    WHERE estado = 'liberado';

CREATE INDEX idx_controles_calidad_lote
    ON biofarm.controles_calidad (id_lote);

-- Carga de trabajo y productividad de analistas.
CREATE INDEX idx_controles_calidad_analista_fecha
    ON biofarm.controles_calidad (id_empleado_analista, fecha_analisis);

CREATE INDEX idx_pedidos_cliente
    ON biofarm.pedidos (id_cliente);

-- Seguimiento comercial: pedidos abiertos por fecha.
CREATE INDEX idx_pedidos_estado_fecha
    ON biofarm.pedidos (estado, fecha_pedido);

CREATE INDEX idx_detalle_pedido_pedido
    ON biofarm.detalle_pedido (id_pedido);

CREATE INDEX idx_detalle_pedido_producto
    ON biofarm.detalle_pedido (id_producto);

-- Índice parcial para trazabilidad: "¿a qué clientes se envió este lote?"
CREATE INDEX idx_detalle_pedido_lote
    ON biofarm.detalle_pedido (id_lote)
    WHERE id_lote IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 5) FIN DEL SCRIPT
-- Verificación rápida: debe devolver 12 tablas.
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'biofarm' AND table_type = 'BASE TABLE';
-- ============================================================================
