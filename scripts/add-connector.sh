#!/bin/bash

# Script to add Airbyte connectors to Jitsu v2.11.0
# Usage: ./scripts/add-connector.sh <connector-id> <docker-image> <display-name>
# Example: ./scripts/add-connector.sh airbyte-stripe airbyte/source-stripe "Stripe"

set -e

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <connector-id> <docker-image> <display-name>"
    echo ""
    echo "Example: $0 airbyte-stripe airbyte/source-stripe \"Stripe\""
    echo ""
    echo "Available connectors: https://github.com/airbytehq/airbyte/tree/master/airbyte-integrations/connectors"
    exit 1
fi

CONNECTOR_ID="$1"
DOCKER_IMAGE="$2"
DISPLAY_NAME="$3"

echo "🔌 Adding Airbyte connector to Jitsu..."
echo "   ID: $CONNECTOR_ID"
echo "   Image: $DOCKER_IMAGE"
echo "   Name: $DISPLAY_NAME"
echo ""

# Insert connector into database
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  "export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  \"INSERT INTO newjitsu.\\\"ConnectorPackage\\\" (id, \\\"packageId\\\", \\\"packageType\\\", meta) \
   VALUES ('$CONNECTOR_ID', \
           '$DOCKER_IMAGE', \
           'airbyte', \
           '{\\\"name\\\": \\\"$DISPLAY_NAME\\\", \\\"license\\\": \\\"MIT\\\", \\\"connectorSubtype\\\": \\\"api\\\"}'::jsonb) \
   ON CONFLICT (id) DO NOTHING;\""

echo ""
echo "✅ Connector added successfully!"
echo ""
echo "🔍 Verifying..."
echo ""

# Wait a moment for the change to propagate
sleep 1

# Verify via API
CONNECTOR_COUNT=$(curl -s http://localhost:4000/api/sources 2>/dev/null | jq '.sources | length' 2>/dev/null || echo "API not accessible")

if [ "$CONNECTOR_COUNT" != "API not accessible" ]; then
    echo "   Total connectors available: $CONNECTOR_COUNT"
    echo ""
    echo "📍 Access connector in UI:"
    echo "   http://localhost:4000/jitsu/services?id=new&packageType=airbyte&packageId=$(echo $DOCKER_IMAGE | sed 's/\//%2F/g')"
else
    echo "   ⚠️  Could not verify via API (port-forward to 4000 may not be running)"
    echo "   Please check http://localhost:4000 manually"
fi

echo ""
echo "✨ Done!"
