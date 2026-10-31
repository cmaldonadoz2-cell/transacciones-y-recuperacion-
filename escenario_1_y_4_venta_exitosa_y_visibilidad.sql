-- ============================================================================
-- ARCHIVO: 01_venta_exitosa.sql
-- PROPÓSITO: Demostrar una operación de venta atómica exitosa con cálculo
--            dinámico del total y comprobar la visibilidad entre dos sesiones
--            independientes (A y B) bajo aislamiento Read Committed.
-- ============================================================================

-- ============================================================================
-- [CONEXIÓN A] 1. Verificación de entorno, sesión y datos existentes
-- Resultado esperado: PID único de la Conexión A, aislamiento 'read committed',
-- 1 fila para customer_id = 1 y 3 filas para track_id IN (1, 2, 3).
-- ============================================================================
\echo '--- [CONEXION A] Estado de sesion y aislamiento ---'
\echo :AUTOCOMMIT
SELECT 
    pg_backend_pid() AS pid_conexion_a,
    current_setting('transaction_isolation') AS nivel_aislamiento,
    current_timestamp AS fecha_hora_inicio;

-- Verificar que el cliente y las canciones existen en el catálogo original
SELECT customer_id, first_name, last_name, address, city, state, country, postal_code
FROM customer
WHERE customer_id = 1;

SELECT track_id, name, unit_price
FROM track
WHERE track_id IN (1, 2, 3)
ORDER BY track_id;

-- ============================================================================
-- [CONEXIÓN A] 2. Inicio de transacción explícita e inserción de cabecera
-- Resultado esperado: BEGIN y retorno del nuevo invoice_id almacenado en
-- la variable de sesión :v_invoice_id (por ejemplo, 413 en copia limpia).
-- ============================================================================
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Insertar cabecera tomando los datos de facturación reales del cliente 1.
-- Se inicializa total en 0.00 temporalmente para calcularlo luego a partir de los detalles.
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
WHERE customer_id = 1
RETURNING invoice_id \gset v_

\echo '--- [CONEXION A] Factura creada en transaccion abierta con ID: ' :v_invoice_id

-- ============================================================================
-- [CONEXIÓN A] 3. Inserción de al menos tres detalles válidos
-- Resultado esperado: INSERT 0 3. Se emplea el unit_price oficial de la tabla
-- track y cantidades positivas (1, 2 y 1).
-- ============================================================================
INSERT INTO invoice_line (invoice_id, track_id, unit_price, quantity)
SELECT 
    :v_invoice_id,
    t.track_id,
    t.unit_price,
    v.cantidad
FROM track t
JOIN (
    VALUES 
        (1, 1),
        (2, 2),
        (3, 1)
) AS v(track_id, cantidad) ON t.track_id = v.track_id;

-- ============================================================================
-- [CONEXIÓN A] 4. Cálculo dinámico del total de la factura
-- Resultado esperado: UPDATE 1. El campo total toma la suma exacta de
-- (unit_price * quantity) redondeada a numeric(10,2).
-- ============================================================================
UPDATE invoice i
SET total = (
    SELECT COALESCE(SUM(il.unit_price * il.quantity), 0.00)::numeric(10,2)
    FROM invoice_line il
    WHERE il.invoice_id = i.invoice_id
)
WHERE i.invoice_id = :v_invoice_id;

-- ============================================================================
-- [CONEXIÓN A] 5. Comprobación interna antes de confirmar (COMMIT)
-- Resultado esperado: 1 fila con cantidad_detalles = 3, total_cabecera = 3.96,
-- suma_detalles = 3.96 y coincidencia_exacta = true.
-- ============================================================================
SELECT 
    i.invoice_id,
    COUNT(il.invoice_line_id) AS cantidad_detalles,
    i.total AS total_cabecera,
    SUM(il.unit_price * il.quantity)::numeric(10,2) AS suma_detalles,
    (i.total = SUM(il.unit_price * il.quantity)::numeric(10,2)) AS coincidencia_exacta
FROM invoice i
JOIN invoice_line il ON i.invoice_id = il.invoice_id
WHERE i.invoice_id = :v_invoice_id
GROUP BY i.invoice_id, i.total;

-- ============================================================================
-- [PAUSA PARA PRUEBA DE VISIBILIDAD - EJECUTAR EN CONEXIÓN B ANTES DEL COMMIT]
-- Copie y ejecute el siguiente bloque en la terminal de la Conexión B
-- reemplazando 413 por el :v_invoice_id obtenido si fuera distinto.
-- Resultado esperado en Conexión B ANTES del COMMIT:
--   1. pid_conexion_b distinto de pid_conexion_a.
--   2. 0 filas en invoice y 0 filas en invoice_line (no existen lecturas sucias).
-- ============================================================================
/*
-- >>> EJECUTAR EN CONEXIÓN B (ANTES DE COMMIT EN A) <<<
\set v_invoice_id 413
SELECT pg_backend_pid() AS pid_conexion_b, current_setting('transaction_isolation') AS aislamiento;

SELECT invoice_id, customer_id, invoice_date, total
FROM invoice
WHERE invoice_id = :v_invoice_id;

SELECT invoice_line_id, invoice_id, track_id, unit_price, quantity
FROM invoice_line
WHERE invoice_id = :v_invoice_id;
*/

-- ============================================================================
-- [CONEXIÓN A] 6. Confirmación definitiva de la transacción
-- Resultado esperado: COMMIT. Los cambios se hacen permanentes y visibles.
-- ============================================================================
COMMIT;

-- ============================================================================
-- [CONEXIÓN B] 7. Comprobación de visibilidad posterior al COMMIT
-- Ejecute este bloque en la Conexión B una vez confirmado el COMMIT en A.
-- Resultado esperado en Conexión B DESPUÉS del COMMIT:
--   1. 1 fila de cabecera con total = 3.96.
--   2. 3 filas de detalle en invoice_line que suman 3.96.
-- ============================================================================
/*
-- >>> EJECUTAR EN CONEXIÓN B (DESPUÉS DE COMMIT EN A) <<<
SELECT 
    pg_backend_pid() AS pid_conexion_b,
    i.invoice_id,
    i.customer_id,
    i.invoice_date,
    i.total AS total_confirmado
FROM invoice i
WHERE i.invoice_id = :v_invoice_id;

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
WHERE il.invoice_id = :v_invoice_id
ORDER BY il.invoice_line_id;
*/