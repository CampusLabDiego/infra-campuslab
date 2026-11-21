#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_SERVERS="${BOOTSTRAP_SERVERS:-kafka1:29092,kafka2:29092,kafka3:29092}"

echo "=== Brokers disponibles ==="
kafka-broker-api-versions --bootstrap-server "$BOOTSTRAP_SERVERS"

echo
echo "=== Tópicos y particiones ==="
for TOPIC in \
  "bookings.events" \
  "audit.timeline" \
  "bookings.events.DLT" \
  "audit.timeline.DLT"
do
  echo
  echo "--- $TOPIC ---"
  kafka-topics \
    --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --describe \
    --topic "$TOPIC"
done

echo
echo "=== Consumer groups ==="
GROUPS=$(kafka-consumer-groups \
  --bootstrap-server "$BOOTSTRAP_SERVERS" \
  --list)

if [[ -z "$GROUPS" ]]; then
  echo "Todavía no hay consumer groups activos."
else
  kafka-consumer-groups \
    --bootstrap-server "$BOOTSTRAP_SERVERS" \
    --all-groups \
    --describe
fi