# Infraestructura CampusLab

CampusLab permite gestionar recursos académicos y reservas mediante
microservicios Spring Boot, Angular, Microsoft Entra ID y RabbitMQ.

## Acceso público

https://wktaaga6j4.execute-api.us-east-1.amazonaws.com

El sistema necesita que las dos instancias EC2 y sus contenedores estén activos.

## Repositorios

- [Frontend](https://github.com/CampusLabDiego/frontend-campuslab)
- [BFF](https://github.com/CampusLabDiego/ms-campuslab-bff)
- [Reservas](https://github.com/CampusLabDiego/ms-campuslab-bookings)
- [Catálogo](https://github.com/CampusLabDiego/ms-campuslab-catalog)
- [Notificaciones y auditoría](https://github.com/CampusLabDiego/ms-campuslab-notifier)
- [Administrador RabbitMQ](https://github.com/CampusLabDiego/ms-campuslab-rabbit-admin)
- [Infraestructura](https://github.com/CampusLabDiego/infra-campuslab)

Los repositorios privados requieren acceso autorizado.

## Distribución del despliegue

### EC2 de aplicaciones

IP privada: 172.31.45.240.

Ejecuta:

| Servicio | Puerto del contenedor | Responsabilidad |
|---|---:|---|
| frontend | 80 | Aplicación Angular servida por Nginx |
| bff | 8080 | Validación JWT, autorización y enrutamiento |
| catalog | 8081 | Recursos y movimientos de stock |
| bookings | 8082 | Reservas y publicación de eventos |
| notifier | 8083 | Correos, PDF y auditoría |
| rabbit-admin | 8084 | Administración de topología RabbitMQ |
| mysql | 3306 | Persistencia |

El frontend se publica en el puerto 4200 del host.
Los microservicios 8081 a 8084 se comunican mediante la red interna de Docker.

### EC2 de RabbitMQ

IP privada: 172.31.45.233.

Ejecuta dos nodos unidos en un clúster:

- rabbit1: puerto AMQP del host 5672.
- rabbit2: puerto AMQP del host 5673.
- Management UI: 127.0.0.1:15672 y 127.0.0.1:15673.

Ambos nodos están en una misma EC2. Esta configuración no proporciona
tolerancia a la caída completa de esa instancia.

Las colas utilizadas son classic; formar un clúster no implica
que sus mensajes estén replicados entre ambos nodos.

## HTTPS y API Gateway

La aplicación pública utiliza AWS API Gateway como entrada HTTPS.

- GET / y GET /{proxy+}: integración al frontend en el puerto 4200.
- Rutas funcionales /api/...: integración al BFF en el puerto 8080.
- Las rutas de API protegidas utilizan autorizador JWT y scope access_as_user.
- Las rutas OPTIONS se configuran sin autorización.
- Las integraciones conservan la ruta mediante overwrite:path = $request.path.

Los archivos públicos de Angular no requieren token.
Las operaciones de negocio requieren autenticación y autorización.

Microsoft Entra ID tiene registradas las redirecciones SPA:

- http://localhost:4200
- https://wktaaga6j4.execute-api.us-east-1.amazonaws.com

## Autenticación y roles

Angular utiliza MSAL para iniciar y cerrar sesión y obtener el Access Token.

API Gateway, BFF y microservicios protegidos validan el token.
El BFF aplica autorización por rol.

| Rol | Acceso principal |
|---|---|
| Cliente | Catálogo, reservas propias y sus notificaciones/documentos |
| Operador | Gestión de reservas y consulta de notificaciones/documentos |
| Admin | Catálogo, reservas, auditoría y administración RabbitMQ |
| Auditor | Consulta del historial de auditoría |

El rol Cliente puede confirmar la llegada de su reserva cuando
se cumplen las condiciones de estado y horario.

## Mensajería

### Exchanges

| Exchange | Tipo |
|---|---|
| cmd.direct | direct |
| cmd.topic | topic |
| cmd.dead.dlx | direct |

### Colas funcionales

| Cola | Finalidad | DLQ |
|---|---|---|
| q.cmd.stock | Movimientos de stock | q.cmd.stock.dlq |
| q.result.stock | Resultados de stock | q.result.stock.dlq |
| q.cmd.email | Correos | q.cmd.email.dlq |
| q.cmd.prep | Tickets de preparación | q.cmd.prep.dlq |
| q.cmd.voucher | Comprobantes PDF | q.cmd.voucher.dlq |
| q.evt.audit | Historial de eventos | q.evt.audit.dlq |

Correos y comprobantes se publican en cmd.topic.
Preparación y comandos de stock utilizan cmd.direct.
Auditoría se publica en cmd.topic con routing key booking.audit.

### Confirmaciones y errores

- Los productores utilizan confirmaciones del broker.
- La outbox guarda publicaciones pendientes junto con el cambio de negocio.
- Los consumidores utilizan ACK manual después de completar su procesamiento.
- Los errores recuperables del consumidor tienen reintentos acotados.
- Los errores permanentes o agotados se rechazan sin requeue y van a la DLQ.
- Los listeners de DLQ registran sus metadatos en logs y confirman su consumo.
- Los identificadores permiten reconocer entregas duplicadas.

Una confirmación del broker no significa que el consumidor haya terminado.

El envío SMTP tiene una limitación: si el servidor acepta un correo y el
proceso falla antes de confirmar su persistencia, podría enviarse otra vez.

### Retención

Las colas funcionales tienen:

- TTL de mensajes: 24 horas.
- Máximo: 10000 mensajes.
- Máximo de bytes: 10 MiB.
- Overflow: reject-publish.

Las DLQ tienen:

- TTL: 7 días.
- Límites de mensajes y bytes.
- Overflow: drop-head.

Los mensajes de las DLQ pueden desaparecer rápidamente porque sus
listeners los consumen y registran en logs.

## Configuración local

Las credenciales se guardan en archivos .env excluidos de Git.

El Compose de aplicaciones necesita:

- MYSQL_ROOT_PASSWORD
- MYSQL_DATABASE
- MYSQL_USER
- MYSQL_PASSWORD
- RABBITMQ_USER
- RABBITMQ_PASSWORD
- MAIL_HOST
- MAIL_PORT
- MAIL_USERNAME
- MAIL_PASSWORD
- MAIL_FROM

Configuración adicional:

- RABBITMQ_ADDRESSES
- MAIL_TEST_RECIPIENT
- MAIL_SMTP_AUTH
- MAIL_STARTTLS
- MAIL_STARTTLS_REQUIRED

MAIL_TEST_RECIPIENT permite redirigir los correos durante pruebas.
Si está vacío, se utiliza el destinatario del evento.

La contraseña SMTP de Gmail debe ser una contraseña de aplicación.

El Compose de RabbitMQ utiliza su propio archivo rabbitmq/.env
y las variables indicadas en rabbitmq/.env.example.

## Estructura en la EC2 de aplicaciones

```text
~/campuslab/
  infra-campuslab/
  frontend-campuslab/
  ms-campuslab-bff/
  ms-campuslab-bookings/
  ms-campuslab-catalog/
  ms-campuslab-notifier/
  ms-campuslab-rabbit-admin/
```

## Arranque

Primero inicia RabbitMQ en su EC2:

```bash
cd ~/infra-campuslab/rabbitmq
docker compose up -d
docker compose exec rabbit1 rabbitmqctl cluster_status
```

En la EC2 de aplicaciones:

```bash
cd ~/campuslab/infra-campuslab
docker compose config --quiet
```

Para construir las imágenes, ejecuta cada comando después de que
el anterior termine correctamente:

```bash
docker compose build catalog
docker compose build bookings
docker compose build notifier
docker compose build rabbit-admin
docker compose build bff
docker compose build frontend
```

Después:

```bash
docker compose up -d
docker compose ps
```

La EC2 tiene recursos limitados: evita builds simultáneos.

Los contenedores con estado Up pueden seguir inicializándose.
Comprueba los mensajes Started en los servicios Spring Boot.

## Persistencia

- mysql_data conserva las bases de datos.
- notifier_documents conserva los PDF.
- Los nodos RabbitMQ tienen volúmenes persistentes.

No ejecutes docker compose down -v si necesitas conservar los datos.

Las bases de datos de catálogo, reservas y notifier deben existir y
tener los permisos necesarios. El script de inicialización de MySQL
se ejecuta al inicializar un directorio de datos vacío.

## Reinicio de AWS Academy

1. Iniciar la sesión del laboratorio.
2. Encender ambas EC2.
3. Comprobar contenedores y clúster.
4. Revisar la IP pública de la EC2 de aplicaciones.
5. Si cambió, actualizar las dos integraciones de API Gateway:
   - BFF: http://NUEVA_IP:8080
   - Frontend: http://NUEVA_IP:4200

La dirección de API Gateway permanece mientras se conserve la API.

La configuración actual de RabbitMQ usa la IP privada de su EC2.
Si esa dirección cambia por reemplazo de la instancia, también debe
actualizarse RABBITMQ_ADDRESSES.

## Comandos de diagnóstico

```bash
docker compose ps
docker compose logs --tail=100 bff bookings catalog notifier rabbit-admin
docker stats --no-stream
free -h
df -h /
```

Publicación y consumo de tareas:

```bash
docker compose logs --since=10m bookings notifier |
  grep -E 'Tarea publicada|Tarea confirmada|Reintentando tarea|DLQ'
```

Auditoría:

```bash
docker compose logs --since=10m bookings notifier |
  grep -E 'Auditoría publicada|Auditoría confirmada|Auditoría en DLQ'
```

## Evidencias funcionales realizadas

- Login y acceso según rol.
- Cliente rechazado con HTTP 403 en la API administrativa.
- Creación y eliminación de colas, exchanges y bindings.
- Nombre de cola inválido: HTTP 400 con detalle.
- Publicación y consumo mediante exchanges direct y topic.
- Procesamiento de correos, tickets y comprobantes.
- Movimiento de stock mediante mensajería.
- Rechazo controlado hacia las tres DLQ de tareas.
- Fallo SMTP controlado: reintentos y envío a DLQ al tercer intento.
- Expiración de mensajes en una cola de demostración.
- Rechazo de publicaciones al alcanzar el límite de una cola.
- Auditoría de solicitudes y confirmaciones de cambios de estado.
- Acceso público HTTPS y operaciones integradas.

## Alcance y pendientes

La auditoría implementada utiliza RabbitMQ y MySQL.
Registra eventos generados desde su activación, sin reconstrucción histórica.

El módulo de reportería de indicadores del caso todavía está pendiente.
La interfaz RabbitMQ Management muestra métricas del broker, que son
distintas de los indicadores de negocio de reportería.