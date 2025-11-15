# Adding Custom Airbyte Connectors to Jitsu

This guide explains how to add custom Airbyte connectors to your Jitsu deployment beyond the default 4 connectors (Firebase, Attio, Linear, MongoDB).

## Overview

Jitsu v2.11.0 ships with a limited set of pre-configured connectors. To use additional Airbyte connectors (like Google Analytics, Stripe, PostgreSQL, etc.), you need to add them to your deployment configuration.

## Available Airbyte Connectors

Browse the full Airbyte connector catalog:
- **GitHub Repository**: https://github.com/airbytehq/airbyte/tree/master/airbyte-integrations/connectors
- **Airbyte Connector Registry**: https://hub.docker.com/u/airbyte

## Method 1: Add Connector via Helm Values (Recommended)

### Step 1: Find the Connector

1. Visit the [Airbyte connectors directory](https://github.com/airbytehq/airbyte/tree/master/airbyte-integrations/connectors)
2. Locate your desired connector (e.g., `source-google-analytics-data-api`)
3. Note the Docker image name (usually `airbyte/source-{name}`)

### Step 2: Add to values.yaml

Add the connector configuration to your `values.yaml` file:

```yaml
console:
  config:
    # ... existing config ...

    # Add custom connectors
    customSources:
      - id: "airbyte-google-analytics-source"
        packageId: "airbyte/source-google-analytics-data-api"
        packageType: "airbyte"
        meta:
          name: "Google Analytics (GA4)"
          license: "MIT"
          connectorSubtype: "api"
        logoSvg: |
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <!-- Add your logo SVG here -->
          </svg>
        versions:
          - "latest"
        sortIndex: 100

      - id: "airbyte-stripe-source"
        packageId: "airbyte/source-stripe"
        packageType: "airbyte"
        meta:
          name: "Stripe"
          license: "MIT"
          connectorSubtype: "api"
        logoSvg: |
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
            <!-- Stripe logo SVG -->
          </svg>
        versions:
          - "latest"
        sortIndex: 95
```

### Step 3: Update Deployment

```bash
helm upgrade jitsu . -f values.yaml -n jitsu --timeout 10m
```

## Method 2: Add Connector via Database

Connectors are stored in the PostgreSQL database. You can add them directly:

### Step 1: Connect to PostgreSQL

```bash
kubectl exec -it -n jitsu jitsu-postgresql-0 -- bash
```

### Step 2: Access the Database

```bash
PGPASSWORD=$(cat /opt/bitnami/postgresql/conf/.s.PGSQL.5432) psql -U postgres -d jitsu
```

### Step 3: Insert Connector

```sql
-- Switch to the correct schema
SET search_path TO newjitsu;

-- Insert Google Analytics connector
INSERT INTO "Source" (
  id,
  "packageId",
  "packageType",
  meta,
  "createdAt",
  "updatedAt",
  "sortIndex"
) VALUES (
  'airbyte-google-analytics-source',
  'airbyte/source-google-analytics-data-api',
  'airbyte',
  '{"name": "Google Analytics (GA4)", "license": "MIT", "connectorSubtype": "api"}'::jsonb,
  NOW(),
  NOW(),
  100
);

-- Verify insertion
SELECT id, "packageId", meta->>'name' FROM "Source" ORDER BY "sortIndex" DESC;
```

## Method 3: Add Connector via API

Use the Jitsu API to add connectors programmatically:

```bash
# Get your authentication token from the Jitsu console

curl -X POST http://localhost:4000/api/sources \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -d '{
    "id": "airbyte-google-analytics-source",
    "packageId": "airbyte/source-google-analytics-data-api",
    "packageType": "airbyte",
    "meta": {
      "name": "Google Analytics (GA4)",
      "license": "MIT",
      "connectorSubtype": "api"
    },
    "logoSvg": "<svg>...</svg>",
    "sortIndex": 100
  }'
```

## Common Airbyte Connectors

Here are some popular Airbyte connectors and their package IDs:

| Connector | Package ID | Description |
|-----------|------------|-------------|
| Google Analytics (GA4) | `airbyte/source-google-analytics-data-api` | Google Analytics 4 data |
| Stripe | `airbyte/source-stripe` | Payment and billing data |
| PostgreSQL | `airbyte/source-postgres` | PostgreSQL database |
| MySQL | `airbyte/source-mysql` | MySQL database |
| Google Ads | `airbyte/source-google-ads` | Google Ads campaign data |
| Facebook Marketing | `airbyte/source-facebook-marketing` | Facebook Ads data |
| GitHub | `airbyte/source-github` | GitHub repositories and events |
| Shopify | `airbyte/source-shopify` | E-commerce data |
| Salesforce | `airbyte/source-salesforce` | CRM data |
| HubSpot | `airbyte/source-hubspot` | Marketing and CRM data |
| Slack | `airbyte/source-slack` | Workspace messages and data |
| Google Sheets | `airbyte/source-google-sheets` | Spreadsheet data |
| Airtable | `airbyte/source-airtable` | Database data |
| Mailchimp | `airbyte/source-mailchimp` | Email marketing data |
| Intercom | `airbyte/source-intercom` | Customer messaging data |

## Example: Adding Google Analytics Connector

### Complete values.yaml Configuration

```yaml
console:
  config:
    seedUserEmail: "admin@jitsu.local"
    seedUserPassword: "admin123"
    disableSignup: false
    nextauthUrl: "http://localhost:4000"
    jitsuPublicUrl: "http://localhost:4000"

    # Add Google Analytics connector
    customSources:
      - id: "airbyte-google-analytics-data-api"
        packageId: "airbyte/source-google-analytics-data-api"
        packageType: "airbyte"
        meta:
          name: "Google Analytics (GA4)"
          license: "MIT"
          connectorSubtype: "api"
          documentationUrl: "https://docs.airbyte.com/integrations/sources/google-analytics-data-api"
        logoSvg: |
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="100%" height="100%">
            <path fill="#F9AB00" d="M22.84 2.998v17.999a3 3 0 01-3 3H4.16a3 3 0 01-3-3V2.998a3 3 0 013-3h15.68a3 3 0 013 3z"/>
            <path fill="#E37400" d="M12 8.5a3.5 3.5 0 100 7 3.5 3.5 0 000-7z"/>
            <circle fill="#E37400" cx="18" cy="6.5" r="2"/>
            <circle fill="#FFF" cx="6" cy="17.5" r="2"/>
          </svg>
        versions:
          - "latest"
          - "2.0.0"
        sortIndex: 160
```

### Apply the Configuration

```bash
# Update your Helm release
helm upgrade jitsu . -f examples/local-kind/values.yaml -n jitsu --timeout 10m

# Wait for console pod to restart
kubectl rollout status deployment/jitsu-console -n jitsu

# Restart port-forward if needed
kubectl port-forward -n jitsu svc/jitsu-console 4000:3000 &
```

### Verify the Connector

1. Open http://localhost:4000
2. Navigate to Sources/Connectors
3. You should now see "Google Analytics (GA4)" in the list

## Docker Image Requirements

### Finding the Correct Image

Airbyte connectors are published to Docker Hub:

```bash
# Search for a connector
docker search airbyte/source-google-analytics

# Pull the image to verify it exists
docker pull airbyte/source-google-analytics-data-api:latest
```

### Image Naming Convention

Airbyte uses this naming pattern:
- **Source**: `airbyte/source-{connector-name}`
- **Destination**: `airbyte/destination-{connector-name}`

Examples:
- `airbyte/source-google-analytics-data-api`
- `airbyte/source-postgres`
- `airbyte/destination-snowflake`

## Connector Configuration

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (e.g., `airbyte-google-analytics-source`) |
| `packageId` | string | Docker image name (e.g., `airbyte/source-google-analytics-data-api`) |
| `packageType` | string | Always `"airbyte"` for Airbyte connectors |
| `meta.name` | string | Display name in UI |
| `sortIndex` | number | Ordering (higher = appears first) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `meta.license` | string | License type (e.g., `"MIT"`, `"Apache-2.0"`) |
| `meta.connectorSubtype` | string | Type: `"api"`, `"database"`, `"file"` |
| `meta.documentationUrl` | string | Link to connector documentation |
| `logoSvg` | string | SVG logo for UI display |
| `versions` | array | Available versions (e.g., `["latest", "1.0.0"]`) |

## Troubleshooting

### Connector Not Appearing in UI

1. **Check database insertion**:
   ```sql
   SELECT id, "packageId", meta->>'name'
   FROM newjitsu."Source"
   WHERE "packageId" LIKE 'airbyte/%';
   ```

2. **Verify API response**:
   ```bash
   curl -s http://localhost:4000/api/sources | jq '.sources[] | select(.packageId | contains("google-analytics"))'
   ```

3. **Clear browser cache**: The UI might cache the connector list

### Connector Configuration Fails

1. **Check Docker image exists**:
   ```bash
   docker pull airbyte/source-google-analytics-data-api:latest
   ```

2. **Check Syncctl logs**:
   ```bash
   kubectl logs -n jitsu -l app.kubernetes.io/component=syncctl --tail=100
   ```

3. **Verify network access**: Ensure your cluster can pull Docker images from Docker Hub

### Image Pull Errors

If you see `ImagePullBackOff`:

```bash
# Check pod events
kubectl describe pod -n jitsu {syncctl-pod-name}

# Verify image exists
docker pull airbyte/source-google-analytics-data-api:latest

# Check if specific version is needed
kubectl logs -n jitsu -l app.kubernetes.io/component=syncctl
```

## Advanced Configuration

### Adding Multiple Connectors at Once

Create a `custom-connectors.yaml` file:

```yaml
customSources:
  - id: "airbyte-google-analytics"
    packageId: "airbyte/source-google-analytics-data-api"
    packageType: "airbyte"
    meta:
      name: "Google Analytics (GA4)"
    sortIndex: 160

  - id: "airbyte-stripe"
    packageId: "airbyte/source-stripe"
    packageType: "airbyte"
    meta:
      name: "Stripe"
    sortIndex: 200

  - id: "airbyte-postgres"
    packageId: "airbyte/source-postgres"
    packageType: "airbyte"
    meta:
      name: "PostgreSQL"
    sortIndex: 150
```

Then merge with your main values:

```bash
helm upgrade jitsu . \
  -f examples/local-kind/values.yaml \
  -f custom-connectors.yaml \
  -n jitsu
```

### Using Specific Versions

Instead of `latest`, pin to specific versions:

```yaml
- id: "airbyte-google-analytics"
  packageId: "airbyte/source-google-analytics-data-api"
  versions:
    - "2.0.0"  # Specific stable version
    - "1.5.0"  # Alternative version
```

## References

- [Airbyte Connector Catalog](https://docs.airbyte.com/integrations/)
- [Airbyte GitHub Repository](https://github.com/airbytehq/airbyte)
- [Airbyte Docker Hub](https://hub.docker.com/u/airbyte)
- [Jitsu Documentation](https://jitsu.com/docs)

## Next Steps

After adding connectors:
1. Configure the connector in Jitsu UI
2. Set up data sources with credentials
3. Create sync jobs to destinations
4. Monitor sync status in the Jitsu dashboard
