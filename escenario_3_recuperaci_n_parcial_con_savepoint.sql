-- ============================================================================
-- ARCHIVO: 03_savepoint.sql
-- PROPÓSITO: Demostrar la recuperación parcial dentro de una transacción usando
--            SAVEPOINT y ROLLBACK TO SAVEPOINT, conservando la cabecera y los
--            dos detalles previos al error, corrigiendo el tercer detalle y
--            confirmando la venta completa con COMMIT.
-- ============================================================================

\set ON_ERROR_STOP off

-- ============================================================================
-- 1. Verificación previa de referencias válidas e inválidas
-- Resultado esperado:
--   - 1 fila para customer_id = 3.
--   - 3 filas para track_id IN (5, 6, 7) (canciones válidas).
--   - 0 filas para track_id = 888888 (canción inexistente para la prueba).
-- ============================================================================
SELECT pg_backend_pid() AS pid_sesion, current_setting('transaction_isolation') AS aislamiento;

SELECT customer_id, first_name, last_name FROM customer WHERE customer_id = 3;

SELECT track_id, name, unit_price
FROM track
WHERE track_id IN (5, 6, 7)
ORDER BY track_id;

SELECT track_id, name
FROM track
WHERE track_id = 888888;

-- ============================================================================
-- 2. Inicio de la tercera venta, cabecera y dos detalles válidos iniciales
-- Resultado esperado: BEGIN, nuevo :v_sp_invoice_id e INSERT 0 2 en invoice_line.
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
WHERE customer_id = 3
RETURNING invoice_id \gset v_sp_

\echo '--- Factura iniciada en Escenario 3 con ID: ' :v_sp_invoice_id

-- Agregar dos detalles válidos previos al punto de guardado (tracks 5 y 6)
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT 
    :v_sp_invoice_id,
    t.track_id,
    t.unit_price,
    v.cantidad
FROM track t
JOIN (
    VALUES 
        (5, 1),
        (6, 3)
) AS v(track_id, cantidad) ON t.track_id = v.track_id;

-- ============================================================================
-- 3. Creación del SAVEPOINT antes de la operación de riesgo
-- Resultado esperado: SAVEPOINT
-- ============================================================================
SAVEPOINT sp_antes_tercer_detalle;

-- ============================================================================
-- 4. Operación fallida: intento de insertar detalle con track_id inexistente
-- Resultado esperado:
--   ERROR: insert or update on table "invoice_line" violates foreign key
--   constraint "invoice_line_track_id_fkey"
--   DETAIL: Key (track_id)=(888888) is not present in table "track".
-- ============================================================================
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
VALUES (:v_sp_invoice_id, 888888, 0.99, 1);

-- ============================================================================
-- 5. Bloque de recuperación parcial: ROLLBACK TO SAVEPOINT y corrección
-- Nota: Si su cliente detiene el script al primer error, ejecute desde aquí.
-- Explicación técnica sobre RELEASE SAVEPOINT:
--   RELEASE SAVEPOINT elimina el punto de control y fusiona la subtransacción
--   con la transacción principal, pero NO confirma los cambios en disco ni los
--   hace visibles a otras sesiones; se requiere el COMMIT final.
-- Resultado esperado:
--   - ROLLBACK (hacia el savepoint, reactivando la transacción sin perder
--     la cabecera ni los tracks 5 y 6).
--   - INSERT 0 1 (inserción del detalle corregido con track_id = 7).
--   - RELEASE, UPDATE 1 y COMMIT.
-- ============================================================================
ROLLBACK TO SAVEPOINT sp_antes_tercer_detalle;

-- Insertar el tercer detalle corregido usando una canción existente (track_id = 7)
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT :v_sp_invoice_id, track_id, unit_price, 2
FROM track
WHERE track_id = 7;

-- Liberar el savepoint (elimina el marcador interno sin hacer COMMIT de la transacción)
RELEASE SAVEPOINT sp_antes_tercer_detalle;

-- Recalcular el total de la factura con los tres detalles válidos
UPDATE invoice i
SET total = (
    SELECT COALESCE(SUM(il.unit_price * il.quantity), 0.00)::numeric(10,2)
    FROM invoice_line il
    WHERE il.invoice_id = i.invoice_id
)
WHERE i.invoice_id = :v_sp_invoice_id;

COMMIT;

-- ============================================================================
-- 6. Demostración de resultados posteriores al COMMIT
-- Resultado esperado:
--   - Cabecera confirmada con total = 5.94 (1*0.99 + 3*0.99 + 2*0.99).
--   - Exactamente 3 detalles válidos registrados (track_id 5, 6 y 7).
--   - 0 registros con track_id = 888888.
-- ============================================================================
SELECT 
    i.invoice_id,
    i.customer_id,
    i.total AS total_cabecera,
    COUNT(il.invoice_line_id) AS cantidad_detalles,
    SUM(il.unit_price * il.quantity)::numeric(10,2) AS suma_detalles,
    (i.total = SUM(il.unit_price * il.quantity)::numeric(10,2)) AS coincidencia_exacta
FROM invoice i
JOIN invoice_line il ON i.invoice_id = il.invoice_id
WHERE i.invoice_id = :v_sp_invoice_id
GROUP BY i.invoice_id, i.customer_id, i.total;

SELECT 
    il.invoice_line_id,
    il.invoice_id,
    il.track_id,
    t.name AS cancion,
    il.unit_price,
    il.quantity,
    (il.unit_price * il.quantity)::numeric(10,2) AS subtotal
FROM invoice_line il
JOIN track t ON il.track_id = t.track_id
WHERE il.invoice_id = :v_sp_invoice_id
ORDER BY il.invoice_line_id;