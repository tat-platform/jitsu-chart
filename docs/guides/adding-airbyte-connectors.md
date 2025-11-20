# Adding Airbyte Connectors to Jitsu

This guide shows you how to add custom Airbyte connectors (Google Analytics, Stripe, PostgreSQL, etc.) to your Jitsu v2.11.0 deployment.

## Overview

Jitsu v2.11.0 ships with 4 default connectors but supports adding any Airbyte connector via the database.

**Default Connectors:**
- Firebase
- Attio
- Linear
- MongoDB

**How It Works:**
Jitsu loads connectors from two sources:
1. **Application code** - 4 hardcoded connectors
2. **PostgreSQL database** - `ConnectorPackage` table (custom connectors)

## Quick Start

### Add Google Analytics (GA4)

```bash
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "INSERT INTO newjitsu.\"ConnectorPackage\" (id, \"packageId\", \"packageType\", meta) \
   VALUES ('\''airbyte-google-analytics-data-api'\'', \
           '\''airbyte/source-google-analytics-data-api'\'', \
           '\''airbyte'\'', \
           '\''{\"name\": \"Google Analytics (GA4)\", \"license\": \"MIT\", \"connectorSubtype\": \"api\"}'\''::jsonb);"'
```

### Verify

```bash
# List all connector names
curl -s http://localhost:4000/api/sources | jq -r '.sources[] | .meta.name' | sort

# Expected output (shows 5 connectors):
# Attio
# Firebase
# Google Analytics (GA4)
# Linear
# MongoDb (alternative version)

# Or view detailed information
curl -s http://localhost:4000/api/sources | jq '.sources[] | {name: .meta.name, id: .id}'
```

**Access in UI:**
- All connectors: http://localhost:4000/jitsu/services
- Direct link: http://localhost:4000/jitsu/services?id=new&packageType=airbyte&packageId=airbyte%2Fsource-google-analytics-data-api

> **Note**: Refresh the page if you don't see new connectors immediately.

---

## Using the Helper Script

We provide a script to simplify adding connectors:

```bash
# Add Stripe
./scripts/add-connector.sh airbyte-stripe airbyte/source-stripe "Stripe"

# Add PostgreSQL
./scripts/add-connector.sh airbyte-postgres airbyte/source-postgres "PostgreSQL"

# Add Shopify
./scripts/add-connector.sh airbyte-shopify airbyte/source-shopify "Shopify"
```

**Script Usage:**
```bash
./scripts/add-connector.sh <connector-id> <docker-image> <display-name>
```

---

## Popular Connectors

Here are some commonly used Airbyte connectors you can add:

### Analytics & Tracking

| Name | Command |
|------|---------|
| **Google Analytics (GA4)** | `./scripts/add-connector.sh airbyte-ga4 airbyte/source-google-analytics-data-api "Google Analytics (GA4)"` |
| **Google Ads** | `./scripts/add-connector.sh airbyte-google-ads airbyte/source-google-ads "Google Ads"` |
| **Facebook Marketing** | `./scripts/add-connector.sh airbyte-facebook airbyte/source-facebook-marketing "Facebook Marketing"` |
| **Mixpanel** | `./scripts/add-connector.sh airbyte-mixpanel airbyte/source-mixpanel "Mixpanel"` |

### E-Commerce

| Name | Command |
|------|---------|
| **Stripe** | `./scripts/add-connector.sh airbyte-stripe airbyte/source-stripe "Stripe"` |
| **Shopify** | `./scripts/add-connector.sh airbyte-shopify airbyte/source-shopify "Shopify"` |
| **WooCommerce** | `./scripts/add-connector.sh airbyte-woocommerce airbyte/source-woocommerce "WooCommerce"` |

### CRM & Sales

| Name | Command |
|------|---------|
| **Salesforce** | `./scripts/add-connector.sh airbyte-salesforce airbyte/source-salesforce "Salesforce"` |
| **HubSpot** | `./scripts/add-connector.sh airbyte-hubspot airbyte/source-hubspot "HubSpot"` |
| **Pipedrive** | `./scripts/add-connector.sh airbyte-pipedrive airbyte/source-pipedrive "Pipedrive"` |
| **Zendesk** | `./scripts/add-connector.sh airbyte-zendesk airbyte/source-zendesk "Zendesk"` |

### Databases

| Name | Command |
|------|---------|
| **PostgreSQL** | `./scripts/add-connector.sh airbyte-postgres airbyte/source-postgres "PostgreSQL"` |
| **MySQL** | `./scripts/add-connector.sh airbyte-mysql airbyte/source-mysql "MySQL"` |
| **Microsoft SQL Server** | `./scripts/add-connector.sh airbyte-mssql airbyte/source-mssql "SQL Server"` |
| **Oracle DB** | `./scripts/add-connector.sh airbyte-oracle airbyte/source-oracle "Oracle"` |
| **Snowflake** | `./scripts/add-connector.sh airbyte-snowflake airbyte/source-snowflake "Snowflake"` |

### Development & Project Management

| Name | Command |
|------|---------|
| **GitHub** | `./scripts/add-connector.sh airbyte-github airbyte/source-github "GitHub"` |
| **GitLab** | `./scripts/add-connector.sh airbyte-gitlab airbyte/source-gitlab "GitLab"` |
| **Jira** | `./scripts/add-connector.sh airbyte-jira airbyte/source-jira "Jira"` |

### Communication

| Name | Command |
|------|---------|
| **Slack** | `./scripts/add-connector.sh airbyte-slack airbyte/source-slack "Slack"` |
| **Intercom** | `./scripts/add-connector.sh airbyte-intercom airbyte/source-intercom "Intercom"` |
| **Mailchimp** | `./scripts/add-connector.sh airbyte-mailchimp airbyte/source-mailchimp "Mailchimp"` |

### Other Data Sources

| Name | Command |
|------|---------|
| **Google Sheets** | `./scripts/add-connector.sh airbyte-google-sheets airbyte/source-google-sheets "Google Sheets"` |
| **Airtable** | `./scripts/add-connector.sh airbyte-airtable airbyte/source-airtable "Airtable"` |
| **Amazon S3** | `./scripts/add-connector.sh airbyte-s3 airbyte/source-s3 "Amazon S3"` |

---

## Manual Method: Direct Database Insertion

If you prefer to add connectors manually or the script doesn't work for your environment:

### Step 1: Find the Connector

Browse available connectors:
- **Airbyte Connector Catalog**: https://docs.airbyte.com/integrations/sources/
- **GitHub Repository**: https://github.com/airbytehq/airbyte/tree/master/airbyte-integrations/connectors

### Step 2: Insert into Database

```bash
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "INSERT INTO newjitsu.\"ConnectorPackage\" \
   (id, \"packageId\", \"packageType\", meta) \
   VALUES ('\''<connector-id>'\'', \
           '\''<docker-image>'\'', \
           '\''airbyte'\'', \
           '\''{\"name\": \"<Display Name>\", \"license\": \"MIT\", \"connectorSubtype\": \"api\"}'\''::jsonb) \
   ON CONFLICT (id) DO NOTHING;"'
```

**Replace:**
- `<connector-id>` - Unique ID (e.g., `airbyte-stripe`)
- `<docker-image>` - Docker image name (e.g., `airbyte/source-stripe`)
- `<Display Name>` - Name shown in UI (e.g., `Stripe`)

### Step 3: Verify

```bash
# List all connectors
curl -s http://localhost:4000/api/sources | jq '.sources[] | {name: .meta.name, package: .packageId}'

# Or check database directly
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "SELECT id, \"packageId\", meta->>'\''name'\'' as name FROM newjitsu.\"ConnectorPackage\";"'
```

---

## Database Schema

The `ConnectorPackage` table structure:

```sql
Table "newjitsu.ConnectorPackage"
   Column    |         Type          | Nullable |      Default
-------------+-----------------------+----------+-------------------
 id          | text                  | not null |
 packageId   | text                  | not null | (Docker image)
 packageType | text                  | not null | 'airbyte'::text
 meta        | jsonb                 |          | (connector metadata)
 logoSvg     | bytea                 |          | (optional logo)
 createdAt   | timestamp(3)          | not null | CURRENT_TIMESTAMP
 updatedAt   | timestamp(3)          | not null | CURRENT_TIMESTAMP

Primary Key: id
```

**Required Fields:**
- `id` - Unique identifier
- `packageId` - Docker image (e.g., `airbyte/source-stripe`)
- `packageType` - Always `'airbyte'` for Airbyte connectors
- `meta` - JSON object with at minimum: `{"name": "Display Name"}`

**Optional meta Fields:**
- `license` - License type (e.g., `"MIT"`)
- `connectorSubtype` - Type: `"api"`, `"database"`, or `"file"`
- `documentationUrl` - Link to connector docs

---

## Adding Multiple Connectors at Once

Create a SQL file with multiple INSERTs:

```sql
-- connectors.sql
INSERT INTO newjitsu."ConnectorPackage" (id, "packageId", "packageType", meta) VALUES
  ('airbyte-stripe', 'airbyte/source-stripe', 'airbyte',
   '{"name": "Stripe", "license": "MIT", "connectorSubtype": "api"}'::jsonb),

  ('airbyte-postgres', 'airbyte/source-postgres', 'airbyte',
   '{"name": "PostgreSQL", "license": "MIT", "connectorSubtype": "database"}'::jsonb),

  ('airbyte-shopify', 'airbyte/source-shopify', 'airbyte',
   '{"name": "Shopify", "license": "MIT", "connectorSubtype": "api"}'::jsonb)

ON CONFLICT (id) DO NOTHING;
```

Execute:

```bash
kubectl exec -i -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu' < connectors.sql
```

---

## Testing & Verification

After adding connectors, verify they're working correctly:

### 1. Check Connector Count

```bash
# Count total connectors (should increase after adding)
curl -s http://localhost:4000/api/sources | jq '.sources | length'

# Example output: 7 (4 default + 3 added)
```

### 2. List All Connectors

```bash
# List with names and IDs
curl -s http://localhost:4000/api/sources | jq -r '.sources[] | "\(.id) - \(.meta.name)"' | sort

# Example output:
# airbyte-hubspot - HubSpot
# airbyte-postgres - PostgreSQL
# airbyte-stripe - Stripe
# external-linear-source - Linear
# jitsu-attio-source - Attio
# jitsu-firebase-source - Firebase
# jitsu-mongodb-source - MongoDb (alternative version)
```

### 3. Verify Database Entries

```bash
# Query the database directly
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "SELECT id, \"packageId\", meta->>'\''name'\'' as name
   FROM newjitsu.\"ConnectorPackage\"
   ORDER BY id;"'

# Example output:
#        id        |        packageId        |    name
# ------------------+-------------------------+------------
#  airbyte-hubspot  | airbyte/source-hubspot  | HubSpot
#  airbyte-postgres | airbyte/source-postgres | PostgreSQL
#  airbyte-stripe   | airbyte/source-stripe   | Stripe
```

### 4. Test in UI

1. Open http://localhost:4000/jitsu/services
2. Click "Add Service"
3. You should see your newly added connectors in the list
4. Click on a connector to verify its configuration page loads

### 5. Test Direct URL

Access connector directly (replace `airbyte/source-stripe` with your connector):

```bash
# URL encode the packageId (/ becomes %2F)
PACKAGE_ID="airbyte%2Fsource-stripe"
echo "http://localhost:4000/jitsu/services?id=new&packageType=airbyte&packageId=$PACKAGE_ID"

# Or use the helper from add-connector.sh output
```

**Success Indicators:**
- ✅ Connector appears in API response
- ✅ Connector shows in database query
- ✅ Connector visible in UI service list
- ✅ Direct URL loads connector configuration page

---

## Troubleshooting

### Connector Not Appearing in UI

1. **Check database insertion**:
```bash
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "SELECT * FROM newjitsu.\"ConnectorPackage\";"'
```

2. **Verify API response**:
```bash
curl -s http://localhost:4000/api/sources | jq '.sources | length'
# Should be more than 4
```

3. **Clear browser cache and refresh** the Jitsu UI

### Connector Configuration Fails

1. **Verify Docker image exists**:
```bash
docker pull airbyte/source-google-analytics-data-api:latest
```

2. **Check Syncctl logs**:
```bash
kubectl logs -n jitsu -l app.kubernetes.io/component=syncctl --tail=50
```

3. **Ensure network access** to Docker Hub from your cluster

### Duplicate ID Error

If you get a duplicate key error:

```bash
# Update existing connector instead
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "UPDATE newjitsu.\"ConnectorPackage\" \
   SET \"packageId\" = '\''airbyte/source-stripe'\'', \
       meta = '\''{\"name\": \"Stripe\"}'\''::jsonb \
   WHERE id = '\''airbyte-stripe'\'';"'
```

### Remove a Connector

```bash
kubectl exec -n jitsu jitsu-postgresql-0 -- bash -c \
  'export PGPASSWORD=jitsu123 && psql -U jitsu -d jitsu -c \
  "DELETE FROM newjitsu.\"ConnectorPackage\" WHERE id = '\''airbyte-stripe'\'';"'
```

---

## Docker Image Naming

Airbyte connectors follow this naming pattern:

- **Sources**: `airbyte/source-{name}`
- **Destinations**: `airbyte/destination-{name}`

Examples:
- `airbyte/source-google-analytics-data-api`
- `airbyte/source-postgres`
- `airbyte/source-stripe`
- `airbyte/destination-snowflake`

**Find connectors**:
- Docker Hub: https://hub.docker.com/u/airbyte
- GitHub: https://github.com/airbytehq/airbyte/tree/master/airbyte-integrations/connectors

---

## Technical Details

### How Jitsu Loads Connectors

The `/api/sources` endpoint combines connectors from:

1. **Hardcoded sources** ([source code](https://github.com/jitsucom/jitsu/blob/bc98f9c575eddb77e65716e7823cb65520b6246c/webapps/console/pages/api/sources/index.ts#L101))
2. **Database query**:
```typescript
const sources = await db.prisma().connectorPackage.findMany()
```

This means connectors added to the database appear immediately without restarting Jitsu!

### Connector Execution

When you create a sync:
1. Jitsu Console sends the `packageId` to Syncctl
2. Syncctl pulls the Docker image: `docker pull airbyte/source-{name}`
3. Syncctl runs the container with your configuration
4. Data flows from source → Syncctl → Destination (ClickHouse, etc.)

---

## Resources

- **Airbyte Connector Catalog**: https://docs.airbyte.com/integrations/
- **Airbyte GitHub**: https://github.com/airbytehq/airbyte
- **Airbyte Docker Hub**: https://hub.docker.com/u/airbyte
- **Jitsu Documentation**: https://jitsu.com/docs
- **Jitsu Source Code**: https://github.com/jitsucom/jitsu

---

## Next Steps

After adding connectors:

1. **Refresh the Jitsu UI** - Go to http://localhost:4000/jitsu/services
2. **Create a new source** - Click on your newly added connector
3. **Configure credentials** - Follow the Airbyte connector documentation
4. **Set up sync** - Choose destination and sync schedule
5. **Monitor status** - Check sync logs in Jitsu dashboard

For connector-specific configuration, refer to the [Airbyte documentation](https://docs.airbyte.com/integrations/) for each connector.
