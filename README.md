# Infraestructura CampusLab

Infraestructura de despliegue para CampusLab. El sistema integra Angular, microservicios Spring Boot, MySQL, RabbitMQ, Kafka, Microsoft Entra ID, Docker Compose y AWS API Gateway.

## Repositorios

- [Frontend](https://github.com/CampusLabDiego/frontend-campuslab)
- [BFF](https://github.com/CampusLabDiego/ms-campuslab-bff)
- [Reservas](https://github.com/CampusLabDiego/ms-campuslab-bookings)
- [Catálogo](https://github.com/CampusLabDiego/ms-campuslab-catalog)
- [Notificaciones y auditoría](https://github.com/CampusLabDiego/ms-campuslab-notifier)
- [Administración RabbitMQ y Kafka](https://github.com/CampusLabDiego/ms-campuslab-rabbit-admin)
- [Infraestructura](https://github.com/CampusLabDiego/infra-campuslab)

Los repositorios privados requieren acceso autorizado.

## Componentes desplegados

### EC2 de aplicaciones

| Servicio | Puerto del contenedor | Responsabilidad |
|---|---:|---|
| frontend | 80 | Aplicación Angular servida por Nginx |
| bff | 8080 | Validación JWT, autorización y enrutamiento |
| catalog | 8081 | Recursos y movimientos de stock |
| bookings | 8082 | Reservas y publicación de eventos |
| notifier | 8083 | Correos, PDF y auditoría |
| rabbit-admin | 8084 | Administración de RabbitMQ y Kafka |
| mysql | 3306 | Persistencia de los microservicios |

El frontend se publica en el puerto `4200` del host. Los microservicios se comunican mediante la red interna de Docker.

### EC2 de RabbitMQ

RabbitMQ se ejecuta en una instancia separada con dos nodos de broker y la interfaz de administración.

Los puertos de Management se enlazan a loopback en la instancia. Para acceder desde un computador se utiliza un túnel SSH. Ambos nodos están en la misma EC2; esto no proporciona tolerancia ante la caída completa de esa instancia. Las colas funcionales son classic y no se replican automáticamente por formar parte de un clúster.

### EC2 de Kafka

Kafka se despliega por separado usando `kafka/compose.yml`:

- Tres brokers Kafka.
- Tres nodos ZooKeeper.
- Volúmenes persistentes para brokers y ZooKeeper.
- Kafka UI conectada al clúster.
- Creación automática de los tópicos de aplicación mediante el servicio `kafka-init`.

Kafka UI se enlaza a una dirección local de la EC2. Comprueba el puerto real con `docker compose ps` y usa un túnel SSH para abrirla desde el computador.

## API Gateway y HTTPS

AWS API Gateway es la entrada HTTPS a la aplicación:

- Las solicitudes del frontend se integran con el contenedor frontend.
- Las rutas `/api/...` se integran con el BFF.
- Las rutas protegidas utilizan autorización JWT y el scope configurado para la API.
- Las solicitudes `OPTIONS` se permiten para CORS.

El origen de producción debe estar registrado como redirección SPA en Microsoft Entra ID.

## Autenticación y roles

Angular usa MSAL para iniciar sesión y obtener el Access Token. API Gateway, BFF y microservicios validan el token y los permisos correspondientes.

| Rol | Acceso principal |
|---|---|
| Cliente | Catálogo, reservas propias y documentos autorizados |
| Operador | Gestión de reservas y consulta de documentos autorizados |
| Admin | Catálogo, reservas, auditoría y administración RabbitMQ/Kafka |
| Auditor | Consulta del historial de auditoría |

La autorización del frontend no reemplaza la validación realizada en el backend.

## Mensajería RabbitMQ

Exchanges principales:

| Exchange | Tipo |
|---|---|
| `cmd.direct` | direct |
| `cmd.topic` | topic |
| `cmd.dead.dlx` | direct |

Colas funcionales:

| Cola | Finalidad | DLQ |
|---|---|---|
| `q.cmd.stock` | Movimientos de stock | `q.cmd.stock.dlq` |
| `q.result.stock` | Resultados de stock | `q.result.stock.dlq` |
| `q.cmd.email` | Correos | `q.cmd.email.dlq` |
| `q.cmd.prep` | Tickets de preparación | `q.cmd.prep.dlq` |
| `q.cmd.voucher` | Comprobantes PDF | `q.cmd.voucher.dlq` |
| `q.evt.audit` | Eventos de auditoría | `q.evt.audit.dlq` |

Los productores utilizan confirmaciones del broker y los consumidores procesan con ACK manual. Los fallos se reintentan de forma acotada y los mensajes no procesables se envían a una DLQ.

## Mensajería Kafka

Los tópicos de aplicación se crean con tres particiones y factor de replicación tres:

| Tópico | Uso | Retención |
|---|---|---|
| `bookings.events` | Eventos de reservas | 7 días |
| `audit.timeline` | Eventos para auditoría | 30 días, compactación y eliminación |
| `bookings.events.DLT` | Eventos de reservas fallidos | 14 días |
| `audit.timeline.DLT` | Eventos de auditoría fallidos | 14 días |

Bookings publica eventos de auditoría en `bookings.events` y `audit.timeline`. Notifier consume ambos tópicos con el grupo `campuslab-notifier`, persiste los eventos en MySQL y utiliza los tópicos `.DLT` cuando el procesamiento falla.

La API del microservicio `rabbit-admin` permite listar tópicos, consultar sus particiones, listar grupos de consumidores y crear tópicos. Estas rutas requieren el rol Admin.

El tópico `demo.carga` se crea manualmente para pruebas de carga. No forma parte de la inicialización normal ni es consumido por Notifier.

## Configuración de Kafka

Copia el ejemplo y edita sus valores:

```bash
cd kafka
cp .env.example .env
```

Configura `KAFKA_BIND_ADDRESS` y los valores `KAFKA1_ADVERTISED_HOST`, `KAFKA2_ADVERTISED_HOST` y `KAFKA3_ADVERTISED_HOST` con la dirección que corresponda a la EC2 Kafka.

Inicia el clúster:

```bash
docker compose up -d
docker compose ps
```

Lista los tópicos:

```bash
docker compose exec kafka1 kafka-topics \
  --bootstrap-server kafka1:29092 --list
```

La configuración de aplicaciones, en el `.env` de la raíz de infraestructura, debe incluir:

```text
KAFKA_BOOTSTRAP_SERVERS=IP_PRIVADA_KAFKA:9092,IP_PRIVADA_KAFKA:9093,IP_PRIVADA_KAFKA:9094
```

Las direcciones deben ser alcanzables desde la EC2 de aplicaciones. No uses una IP pública dinámica como dirección anunciada del clúster.

## Configuración de la aplicación

El Compose de aplicaciones utiliza variables de entorno para bases de datos, RabbitMQ y correo. Entre ellas:

```text
MYSQL_ROOT_PASSWORD
MYSQL_DATABASE
MYSQL_USER
MYSQL_PASSWORD
RABBITMQ_ADDRESSES
RABBITMQ_USER
RABBITMQ_PASSWORD
MAIL_HOST
MAIL_PORT
MAIL_USERNAME
MAIL_PASSWORD
MAIL_FROM
KAFKA_BOOTSTRAP_SERVERS
```

`MAIL_TEST_RECIPIENT` permite redirigir los correos durante pruebas. El archivo `.env` contiene valores del entorno y no debe subirse al repositorio.

## Estructura esperada en la EC2 de aplicaciones

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

## Arranque de la aplicación

Primero comprueba la configuración:

```bash
cd ~/campuslab/infra-campuslab
docker compose config --quiet
```

Construye las imágenes de forma secuencial para reducir el uso de memoria:

```bash
docker compose build catalog
docker compose build bookings
docker compose build notifier
docker compose build rabbit-admin
docker compose build bff
docker compose build frontend
```

Luego inicia los servicios:

```bash
docker compose up -d
docker compose ps
```

Un contenedor en estado `Up` puede seguir inicializándose. Revisa los logs y confirma el mensaje de inicio de cada servicio Spring Boot.

## Persistencia

Los volúmenes Docker conservan las bases de datos, los documentos generados y los datos de Kafka y RabbitMQ.

No ejecutes `docker compose down -v` si necesitas conservar esos datos.

## Diagnóstico

```bash
docker compose ps
docker compose logs --tail=100 bff bookings catalog notifier rabbit-admin
docker stats --no-stream
free -h
df -h /
```

Para revisar tópicos y grupos Kafka, utiliza Kafka UI o los comandos Kafka desde la EC2 correspondiente.

## Reinicio del entorno AWS

1. Inicia el laboratorio de AWS y enciende las instancias.
2. Comprueba los contenedores de cada EC2.
3. Comprueba la salud de los clústeres RabbitMQ y Kafka.
4. Revisa si cambió la IP pública de la EC2 de aplicaciones.
5. Si cambió, actualiza las integraciones de API Gateway del BFF y frontend.
6. Si cambió una IP privada por reemplazo de una instancia, actualiza las direcciones de RabbitMQ o Kafka en la configuración de la aplicación.

## Evidencias funcionales

- Inicio de sesión y acceso según rol.
- Rechazo de acceso administrativo para usuarios sin rol autorizado.
- Administración de colas, exchanges y bindings RabbitMQ.
- Consulta y creación de tópicos Kafka mediante la API administrativa.
- Consulta del grupo de consumidores `campuslab-notifier`.
- Publicación y consumo de eventos de reservas y auditoría.
- Envío controlado de eventos fallidos a sus tópicos DLT.
- Procesamiento de stock y tareas asíncronas.
- Consulta de eventos en la vista de auditoría.
- Acceso HTTPS a la aplicación mediante API Gateway.

## Alcance pendiente

La reportería de indicadores de negocio es distinta de las métricas técnicas que muestran Kafka UI y RabbitMQ Management. Si la rúbrica exige indicadores de negocio, deben presentarse en un módulo de reportería o documentarse como pendiente.
