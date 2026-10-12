-- Creación de bases de datos
CREATE DATABASE IF NOT EXISTS campuslab_catalog;

CREATE DATABASE IF NOT EXISTS campuslab_bookings;


-- Permisos para el usuario de la aplicación
GRANT ALL PRIVILEGES ON campuslab_catalog.* 
TO 'campuslab'@'%';

GRANT ALL PRIVILEGES ON campuslab_bookings.* 
TO 'campuslab'@'%';


-- Aplicar cambios de permisos
FLUSH PRIVILEGES;