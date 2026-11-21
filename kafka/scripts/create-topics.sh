#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-kafka1:29092,kafka2:29092,kafka3:29092}"

crear_topic() {
  local nombre="$1"
  local retencion="$2"
  local politica="$3"

  kafka-topics \
    --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --create \
    --if-not-exists \
    --topic "$nombre" \
    --partitions 3 \
    --replication-factor 3 \
    --config "cleanup.policy=$politica" \
    --config "retention.ms=$retencion"
}

crear_topic "bookings.events" 604800000 "delete"
crear_topic "audit.timeline" 2592000000 "compact,delete"
crear_topic "bookings.events.DLT" 1209600000 "delete"
crear_topic "audit.timeline.DLT" 1209600000 "delete"

echo "Tópicos de CampusLab creados o ya existentes."