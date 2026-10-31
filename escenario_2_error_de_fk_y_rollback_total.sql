-- ============================================================================
-- ARCHIVO: 02_rollback_total.sql
-- PROPÓSITO: Demostrar que ante una violación real de FOREIGN KEY en un detalle,
--            la transacción entra en estado abortado y el ROLLBACK revierte
--            tanto los detalles previos como la cabecera de la factura.
-- ============================================================================

-- Desactivar parada automática en psql para permitir que el script continúe
-- hasta el bloque de recuperación (ROLLBACK) tras capturar el error esperado.
\set ON_ERROR_STOP off

-- ============================================================================
-- 1. Verificación previa de datos y de la referencia inexistente
-- Resultado esperado:
--   - 1 fila para customer_id = 2 y 1 fila para track_id = 4 (válidos).
--   - 0 filas para track_id = 999999 (confirmando que la canción NO existe).
-- ============================================================================
SELECT pg_backend_pid() AS pid_sesion, current_setting('transaction_isolation') AS aislamiento;

SELECT customer_id, first_name, last_name FROM customer WHERE customer_id = 2;
SELECT track_id, name, unit_price FROM track WHERE track_id = 4;

-- Comprobación previa obligatoria: demostrar que track_id = 999999 no existe
SELECT track_id, name
FROM track
WHERE track_id = 999999;

-- ============================================================================
-- 2. Inicio de transacción, creación de cabecera y primer detalle válido
-- Resultado esperado: BEGIN, creación de factura (:v_err_invoice_id) e
-- inserción exitosa de 1 detalle válido (INSERT 0 1).
-- ============================================================================
BEGIN;

INSERT INTO invoice (
    customer_id,
    invoice_date,
    billing_address,
    billing_city,
    billing_state,
    billing_country,
    billing_postal_code,
    total
)
SELECT 
    customer_id,
    CURRENT_TIMESTAMP,
    address,
    city,
    state,
    country,
    postal_code,
    0.00::numeric(10,2)
FROM customer
WHERE customer_id = 2
RETURNING invoice_id \gset v_err_

\echo '--- Factura temporal en transaccion (pendiente): ' :v_err_invoice_id

-- Insertar un detalle válido (track_id = 4, cantidad = 2)
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :v_err_invoice_id, track_id, unit_price, 2
FROM track
WHERE track_id = 4;

-- ============================================================================
-- 3. Provocación de violación real de FOREIGN KEY
-- Resultado esperado:
--   ERROR: insert or update on table "invoice_line" violates foreign key
--   constraint "invoice_line_track_id_fkey"
--   DETAIL: Key (track_id)=(999999) is not present in table "track".
-- ============================================================================
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
VALUES (:v_err_invoice_id, 999999, 0.99, 1);

-- ============================================================================
-- 4. Evidencia del estado abortado de la transacción en PostgreSQL
-- Propósito: Intentar consultar la factura antes de hacer ROLLBACK demuestra
-- que PostgreSQL rechaza cualquier instrucción dentro de una transacción fallida.
-- Resultado esperado:
--   ERROR: current transaction is aborted, commands ignored until end of
--   transaction block
-- ============================================================================
SELECT invoice_id, total FROM invoice WHERE invoice_id = :v_err_invoice_id;

-- ============================================================================
-- 5. Bloque de recuperación: Reversión explícita (ROLLBACK)
-- Nota: Si su cliente detuvo la ejecución en el paso 3, ejecute a partir de aquí.
-- Resultado esperado: ROLLBACK.
-- ============================================================================
ROLLBACK;

-- ============================================================================
-- 6. Comprobación posterior al ROLLBACK por clave específica
-- Resultado esperado: 0 filas en invoice y 0 filas en invoice_line para
-- el identificador :v_err_invoice_id. No quedó cabecera incompleta ni detalles.
-- ============================================================================
\echo '--- Verificando ausencia de datos para invoice_id revertido: ' :v_err_invoice_id

SELECT invoice_id, customer_id, invoice_date, total
FROM invoice
WHERE invoice_id = :v_err_invoice_id;

SELECT invoice_line_id, invoice_id, track_id, unit_price, quantity
FROM invoice_line
WHERE invoice_id = :v_err_invoice_id;