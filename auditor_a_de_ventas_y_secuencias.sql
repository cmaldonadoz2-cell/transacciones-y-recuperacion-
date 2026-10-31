-- ============================================================================
-- ARCHIVO: 04_validaciones.sql
-- PROPÓSITO: Comprobar la integridad global de las ventas nuevas de práctica
--            (invoice_id mayor a 412), verificar que no existan cabeceras
--            huérfanas ni descuadres de total, y evidenciar el hueco dejado
--            en la secuencia por el ROLLBACK del Escenario 2.
-- ============================================================================

-- ============================================================================
-- 1. Auditoría de ventas nuevas generadas en la práctica (invoice_id > 412)
-- Resultado esperado: 2 filas (la factura del Escenario 1 y la del Escenario 3),
-- ambas con al menos 3 detalles y diferencia_total = 0.00.
-- Se observa además el salto numérico en invoice_id (ej. de 413 a 415) dejado
-- por el ROLLBACK de la factura 414 en el Escenario 2.
-- ============================================================================
SELECT 
    i.invoice_id,
    i.customer_id,
    i.invoice_date,
    COUNT(il.invoice_line_id) AS total_lineas,
    i.total AS total_factura,
    COALESCE(SUM(il.unit_price * il.quantity), 0.00)::numeric(10,2) AS suma_lineas,
    (i.total - COALESCE(SUM(il.unit_price * il.quantity), 0.00)::numeric(10,2)) AS diferencia_total
FROM invoice i
LEFT JOIN invoice_line il ON i.invoice_id = il.invoice_id
WHERE i.invoice_id > 412
GROUP BY i.invoice_id, i.customer_id, i.invoice_date, i.total
ORDER BY i.invoice_id;

-- ============================================================================
-- 2. Verificación de inexistencia de facturas huérfanas (sin detalles)
-- Resultado esperado: 0 filas. Ninguna factura quedó con cabecera incompleta.
-- ============================================================================
SELECT i.invoice_id, i.customer_id, i.total
FROM invoice i
LEFT JOIN invoice_line il ON i.invoice_id = il.invoice_id
WHERE il.invoice_line_id IS NULL;

-- ============================================================================
-- 3. Inspección del estado actual de las secuencias SERIAL
-- Resultado esperado: El last_value de las secuencias refleja los incrementos
-- consumidos tanto por las transacciones confirmadas como por las revertidas.
-- ============================================================================
SELECT 
    pg_get_serial_sequence('invoice', 'invoice_id') AS secuencia_factura,
    last_value AS ultimo_valor_factura,
    is_called
FROM invoice_invoice_id_seq;

SELECT 
    pg_get_serial_sequence('invoice_line', 'invoice_line_id') AS secuencia_detalle,
    last_value AS ultimo_valor_detalle,
    is_called
FROM invoice_line_invoice_line_id_seq;