-- ============================================================================
-- LABIOFARM · Sistema de Gestión de Producción y Control de Calidad
-- Script 01 de 05 · Creación de la base de datos
-- ----------------------------------------------------------------------------
-- Qué hace:
--   Crea la base de datos "labiofarm" con codificación UTF-8 (necesaria para
--   almacenar textos con acentos y ñ sin sorpresas).
--
-- Cómo ejecutarlo (pgAdmin):
--   1. Conéctate a tu servidor.
--   2. Selecciona la base de datos "postgres" (un clic sobre ella en el árbol
--      izquierdo) y abre Query Tool (menú Tools > Query Tool).
--   3. Abre este archivo con el icono de carpeta y ejecútalo (F5).
--   IMPORTANTE: CREATE DATABASE no puede ejecutarse dentro de una transacción.
--   En pgAdmin verifica que "Auto-commit" esté ACTIVADO en la barra del
--   Query Tool (en versiones recientes viene activado por defecto).
--   Alternativa: crear la base desde la interfaz (clic derecho en
--   Databases > Create > Database > nombre: labiofarm).
--
-- Notas:
--   * Este script NO es idempotente: PostgreSQL no soporta
--     "CREATE DATABASE IF NOT EXISTS". Si la base ya existe verás un error
--     esperado; en ese caso simplemente continúa con el script 02.
--   * Si tu servidor regional está configurado con una codificación distinta
--     y el comando falla, sustitúyelo por:  CREATE DATABASE labiofarm;
-- ============================================================================

CREATE DATABASE labiofarm
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    TEMPLATE = template0;
