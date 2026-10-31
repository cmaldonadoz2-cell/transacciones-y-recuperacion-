# transacciones-y-recuperacion en Postgres 

el proyecto tiene como base fundamental para comprobar el funcionamiento de las transacciones en postgres utilizando la base de datos de chinook. 

Primero se debe iniciar el servidor PostgreSQL y verificar que esté funcionando.
Después, se crea una base de datos llamada chinook, si todavía no existe.
La creación puede realizarse desde una herramienta gráfica o desde psql:
CREATE DATABASE CHINOOK 

Versión y variante utilizada
motor de base de datos: PostgreSQL 18.
variante: Chinook_PostgreSql_SerialPKs.sql.
base de datos de trabajo en : chinook.
Cliente de ejecución: psql o una herramienta gráfica compatible con PostgreSQL.

01_venta_exitosa.sql: registra una venta y comprueba su confirmación.
02_rollback_total.sql: provoca un error controlado y revierte la transacción completa.
03_savepoint.sql: utiliza un punto de control para descartar una operación incorrecta y conservar las operaciones válidas.
04_validaciones.sql: verifica los resultados y comprueba que las consultas se ejecute 

son 2 conexiones A Y B las cuales ejecuta las operaciones y la otra las consultase determina  de datos 
durante las transaccion que todavia no a sido confirmada a la conexion B no debe ser observar los cambios pendiente a la conexion A 

el mmodo de autocommit se determina si las instrucciones se confirma cuando se ejecuta de manera individual en psql donde se consulta el estado 
que seria \echo :AUTOCOMMIT y haci paso a paso pya que las pruebas de transaccion debe seguir las instrucciones de cada archivo 

haci se pueda repetir las pruebas al iniciar el servicio y despues la verificacion  de las bases ,comprobar las tablas y poder abrir las conexiones A yB  PARA ejecutar los archivos SQL y revisar los resultados 

