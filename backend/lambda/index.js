/**
 * VIT Chennai Campus AI Digital Twin — Serverless Telemetry Ingestion Handler
 * Architecture:
 *   1. Amazon API Gateway (HTTP API v2) -> AWS Lambda -> Amazon DynamoDB
 *   2. AWS IoT Core Topic Rule (MQTT) -> AWS Lambda -> Amazon DynamoDB
 *
 * Course: Cloud Architecture Design (CAD)
 * Target Region: ap-south-1
 * Runtime: Node.js 22.x (AWS SDK v3 included in execution environment)
 *
 * Security & Data Invariants:
 * 1. Server-Authoritative Derivation: Client/Sensor cannot forge capacity, timestamps, status, or venue metadata.
 * 2. Concurrency-Safe Seeding: Conditional write prevents overwriting newer records during cold start.
 * 3. Atomic State Updates: Uses TransactWriteItems to atomically update hot state and history.
 * 4. Structured CloudWatch Logging: All admissions, overrides, and threshold alarms emit searchable JSON.
 * 5. Simulation Transparency: All records are strictly stamped with isSimulated: true.
 */

let DynamoDBClient;
let DynamoDBDocumentClient;
let GetCommand;
let PutCommand;
let TransactWriteCommand;

try {
  const ddb = require('@aws-sdk/client-dynamodb');
  const ddbDoc = require('@aws-sdk/lib-dynamodb');
  DynamoDBClient = ddb.DynamoDBClient;
  DynamoDBDocumentClient = ddbDoc.DynamoDBDocumentClient;
  GetCommand = ddbDoc.GetCommand;
  PutCommand = ddbDoc.PutCommand;
  TransactWriteCommand = ddbDoc.TransactWriteCommand;
} catch {
  // In local development or test runners without @aws-sdk installed,
  // provide lightweight command wrappers so handlers can be fully tested offline.
  class MockCommand {
    constructor(input) {
      this.input = input;
    }
  }
  GetCommand = class GetCommand extends MockCommand {};
  PutCommand = class PutCommand extends MockCommand {};
  TransactWriteCommand = class TransactWriteCommand extends MockCommand {};
}

const TABLE_NAME = process.env.TABLE_NAME || 'vit-campus-telemetry';

// Authoritative campus venue catalog and safety thresholds
const VENUE_CATALOG = {
  Building024: {
    venueId: 'Building024',
    name: 'Mahatma Gandhi Auditorium',
    capacity: 2400,
    moderateThreshold: 50, // %
    highThreshold: 80,     // %
    maxAllowedOccupancy: 3000, // Hard ceiling for simulation: 125% of rated capacity
    defaultSeedOccupancy: 1480
  }
};

const ALLOWED_ORIGINS = [
  'https://d457w1fwy7gg.cloudfront.net',
  'http://localhost:5173',
  'http://localhost:4173'
];

/**
 * Generate standard CORS and security response headers
 */
function getCorsHeaders(requestOrigin) {
  const allowOrigin = ALLOWED_ORIGINS.includes(requestOrigin)
    ? requestOrigin
    : 'https://d457w1fwy7gg.cloudfront.net';

  return {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Simulation-Token',
    'Access-Control-Max-Age': '86400',
    'X-Content-Type-Options': 'nosniff'
  };
}

/**
 * Server-side evaluation of occupancy status and threshold alert levels
 */
function evaluateStatus(utilization, venueConfig) {
  if (utilization > 100) {
    return {
      level: 'OVERCAPACITY',
      label: 'Over Capacity Alert',
      color: '#ef4444',
      thresholdAlert: true,
      description: 'Occupancy exceeds rated venue capacity. Ingress throttling recommended.'
    };
  }
  if (utilization >= venueConfig.highThreshold) {
    return {
      level: 'HIGH',
      label: 'High Occupancy',
      color: '#f97316',
      thresholdAlert: true,
      description: 'Venue near capacity. Auxiliary exits should be unlocked.'
    };
  }
  if (utilization >= venueConfig.moderateThreshold) {
    return {
      level: 'MODERATE',
      label: 'Moderate Occupancy',
      color: '#eab308',
      thresholdAlert: false,
      description: 'Nominal operational range. Hall and lobby traffic is steady.'
    };
  }
  return {
    level: 'LOW',
    label: 'Low / Normal Occupancy',
    color: '#10b981',
    thresholdAlert: false,
    description: 'Standard density. Egress paths fully unobstructed.'
  };
}

/**
 * Validate incoming client POST payload
 */
function validateTelemetryInput(body) {
  if (!body || typeof body !== 'object') {
    return { valid: false, error: 'Request body must be a valid JSON object.' };
  }

  const { venueId, occupancy, flowDelta, sensorSource } = body;

  if (!venueId || typeof venueId !== 'string') {
    return { valid: false, error: 'Field "venueId" is required and must be a string.' };
  }

  const venueConfig = VENUE_CATALOG[venueId];
  if (!venueConfig) {
    return {
      valid: false,
      error: `Unknown venueId "${venueId}". Allowed venues: ${Object.keys(VENUE_CATALOG).join(', ')}.`
    };
  }

  if (typeof occupancy !== 'number' || !Number.isInteger(occupancy)) {
    return { valid: false, error: 'Field "occupancy" must be an integer.' };
  }

  if (occupancy < 0 || occupancy > venueConfig.maxAllowedOccupancy) {
    return {
      valid: false,
      error: `Field "occupancy" must be between 0 and ${venueConfig.maxAllowedOccupancy}.`
    };
  }

  let cleanFlow = 0;
  if (flowDelta !== undefined) {
    if (typeof flowDelta !== 'number' || !Number.isInteger(flowDelta)) {
      return { valid: false, error: 'Field "flowDelta", if provided, must be an integer.' };
    }
    cleanFlow = Math.max(-100, Math.min(100, flowDelta));
  }

  let cleanSource = 'UI_SLIDER';
  if (sensorSource !== undefined) {
    if (typeof sensorSource !== 'string') {
      return { valid: false, error: 'Field "sensorSource", if provided, must be a string.' };
    }
    cleanSource = sensorSource.trim().slice(0, 32).replace(/[^A-Za-z0-9_-]/g, '') || 'UI_SLIDER';
  }

  return {
    valid: true,
    data: {
      venueId,
      occupancy,
      flowDelta: cleanFlow,
      sensorSource: cleanSource,
      venueConfig
    }
  };
}

/**
 * Build a default baseline simulated telemetry state for cold-start seeding
 */
function createSeedState(venueConfig) {
  const seedTimestamp = new Date().toISOString();
  const capacity = venueConfig.capacity;
  const occupancy = venueConfig.defaultSeedOccupancy;
  const utilization = Math.round((occupancy / capacity) * 1000) / 10;
  const statusInfo = evaluateStatus(utilization, venueConfig);

  return {
    venueId: venueConfig.venueId,
    sk: 'LATEST',
    venueName: venueConfig.name,
    capacity,
    occupancy,
    utilization,
    status: statusInfo.level,
    statusLabel: statusInfo.label,
    statusColor: statusInfo.color,
    flowRate: 0,
    sensorSource: 'COLD_START_SEED',
    thresholdAlert: statusInfo.thresholdAlert,
    isSimulated: true,
    updatedAt: seedTimestamp,
    disclaimer: 'Simulated CAD demonstration data. Physical IoT turnstile integration pending.'
  };
}

/**
 * Handle direct invocation from AWS IoT Topic Rules
 */
async function handleIotPayload(payload, context, ddbDoc) {
  const validation = validateTelemetryInput(payload);
  if (!validation.valid) {
    console.warn(JSON.stringify({
      level: 'WARN',
      event: 'IOT_PAYLOAD_VALIDATION_FAILED',
      error: validation.error,
      rawPayload: payload
    }));
    return { success: false, error: validation.error };
  }

  const { venueId, occupancy, flowDelta, sensorSource, venueConfig } = validation.data;
  const nowIso = new Date().toISOString();
  const capacity = venueConfig.capacity;
  const utilization = Math.round((occupancy / capacity) * 1000) / 10;
  const statusInfo = evaluateStatus(utilization, venueConfig);
  const ttlEpoch = Math.floor(Date.now() / 1000) + (7 * 86400);

  const hotStateItem = {
    venueId,
    sk: 'LATEST',
    venueName: venueConfig.name,
    capacity,
    occupancy,
    utilization,
    status: statusInfo.level,
    statusLabel: statusInfo.label,
    statusColor: statusInfo.color,
    flowRate: flowDelta,
    sensorSource: sensorSource || 'IOT_MQTT_TURNSTILE',
    thresholdAlert: statusInfo.thresholdAlert,
    isSimulated: true,
    updatedAt: nowIso,
    disclaimer: 'Simulated CAD demonstration data. Physical IoT turnstile integration pending.'
  };

  const historyItem = {
    venueId,
    sk: `TS#${nowIso}`,
    occupancy,
    utilization,
    status: statusInfo.level,
    flowDelta,
    sensorSource: sensorSource || 'IOT_MQTT_TURNSTILE',
    isSimulated: true,
    timestamp: nowIso,
    ttl_epoch: ttlEpoch
  };

  await ddbDoc.send(new TransactWriteCommand({
    TransactItems: [
      { Put: { TableName: TABLE_NAME, Item: hotStateItem } },
      { Put: { TableName: TABLE_NAME, Item: historyItem } }
    ]
  }));

  console.log(JSON.stringify({
    level: statusInfo.thresholdAlert ? 'WARN' : 'INFO',
    event: statusInfo.thresholdAlert ? 'VENUE_THRESHOLD_ALARM' : 'IOT_TELEMETRY_INGESTED',
    source: 'AWS_IOT_CORE',
    requestId: context.awsRequestId || 'iot-rule',
    venueId,
    occupancy,
    capacity,
    utilization,
    status: statusInfo.level,
    alertTriggered: statusInfo.thresholdAlert,
    sensorSource: sensorSource || 'IOT_MQTT_TURNSTILE',
    timestamp: nowIso
  }));

  return {
    success: true,
    source: 'AWS_IOT_CORE',
    message: 'IoT telemetry ingested and persisted atomically.',
    data: hotStateItem
  };
}

/**
 * Factory to create handler with optional injected DynamoDB client (enables local testing)
 */
function createHandler(customDdbDoc) {
  const ddbDoc = customDdbDoc || (DynamoDBDocumentClient && DynamoDBClient ? DynamoDBDocumentClient.from(
    new DynamoDBClient({ region: process.env.AWS_REGION || 'ap-south-1' })
  ) : null);

  return async function handler(event, context = {}) {
    // 0. Detect direct AWS IoT Topic Rule invocation
    const isHttp = Boolean(event.requestContext?.http?.method || event.httpMethod || event.rawPath);
    if (!isHttp && (event.venueId || event.occupancy !== undefined)) {
      return handleIotPayload(event, context, ddbDoc);
    }

    const method = (event.requestContext?.http?.method || event.httpMethod || 'GET').toUpperCase();
    const rawPath = event.rawPath || event.path || '';
    const headers = event.headers || {};
    const requestOrigin = headers.origin || headers.Origin || '';

    // 1. CORS Preflight
    if (method === 'OPTIONS') {
      return {
        statusCode: 204,
        headers: getCorsHeaders(requestOrigin),
        body: ''
      };
    }

    try {
      // 2. GET /telemetry/latest
      if (method === 'GET') {
        const query = event.queryStringParameters || {};
        const venueId = query.venueId || 'Building024';
        const venueConfig = VENUE_CATALOG[venueId];

        if (!venueConfig) {
          return {
            statusCode: 400,
            headers: getCorsHeaders(requestOrigin),
            body: JSON.stringify({
              success: false,
              error: `Invalid venueId "${venueId}". Allowed: ${Object.keys(VENUE_CATALOG).join(', ')}`
            })
          };
        }

        const getRes = await ddbDoc.send(new GetCommand({
          TableName: TABLE_NAME,
          Key: { venueId, sk: 'LATEST' }
        }));

        if (getRes && getRes.Item) {
          return {
            statusCode: 200,
            headers: getCorsHeaders(requestOrigin),
            body: JSON.stringify(getRes.Item)
          };
        }

        // Concurrency-safe initial seeding when no record exists yet
        const seedState = createSeedState(venueConfig);
        try {
          await ddbDoc.send(new PutCommand({
            TableName: TABLE_NAME,
            Item: seedState,
            ConditionExpression: 'attribute_not_exists(venueId) AND attribute_not_exists(sk)'
          }));

          console.log(JSON.stringify({
            level: 'INFO',
            event: 'COLD_START_SEED_CREATED',
            venueId,
            occupancy: seedState.occupancy,
            timestamp: seedState.updatedAt
          }));

          return {
            statusCode: 200,
            headers: getCorsHeaders(requestOrigin),
            body: JSON.stringify(seedState)
          };
        } catch (condErr) {
          if (condErr.name === 'ConditionalCheckFailedException') {
            // Concurrent request seeded or updated the record in the interim; fetch the live item
            const reRead = await ddbDoc.send(new GetCommand({
              TableName: TABLE_NAME,
              Key: { venueId, sk: 'LATEST' }
            }));
            return {
              statusCode: 200,
              headers: getCorsHeaders(requestOrigin),
              body: JSON.stringify(reRead.Item || seedState)
            };
          }
          throw condErr;
        }
      }

      // 3. POST /telemetry
      if (method === 'POST') {
        let bodyObj = null;
        try {
          bodyObj = typeof event.body === 'string' ? JSON.parse(event.body || '{}') : event.body;
        } catch {
          return {
            statusCode: 400,
            headers: getCorsHeaders(requestOrigin),
            body: JSON.stringify({ success: false, error: 'Malformed JSON payload.' })
          };
        }

        const validation = validateTelemetryInput(bodyObj);
        if (!validation.valid) {
          return {
            statusCode: 400,
            headers: getCorsHeaders(requestOrigin),
            body: JSON.stringify({ success: false, error: validation.error })
          };
        }

        const { venueId, occupancy, flowDelta, sensorSource, venueConfig } = validation.data;
        const nowIso = new Date().toISOString();
        const capacity = venueConfig.capacity;
        const utilization = Math.round((occupancy / capacity) * 1000) / 10;
        const statusInfo = evaluateStatus(utilization, venueConfig);

        // Seven-day TTL for audit history records (asynchronous background deletion)
        const ttlEpoch = Math.floor(Date.now() / 1000) + (7 * 86400);

        const hotStateItem = {
          venueId,
          sk: 'LATEST',
          venueName: venueConfig.name,
          capacity,
          occupancy,
          utilization,
          status: statusInfo.level,
          statusLabel: statusInfo.label,
          statusColor: statusInfo.color,
          flowRate: flowDelta,
          sensorSource,
          thresholdAlert: statusInfo.thresholdAlert,
          isSimulated: true, // Server-enforced flag
          updatedAt: nowIso,
          disclaimer: 'Simulated CAD demonstration data. Physical IoT turnstile integration pending.'
        };

        const historyItem = {
          venueId,
          sk: `TS#${nowIso}`,
          occupancy,
          utilization,
          status: statusInfo.level,
          flowDelta,
          sensorSource,
          isSimulated: true,
          timestamp: nowIso,
          ttl_epoch: ttlEpoch
        };

        // Atomic transaction: update hot state AND append time-series history
        await ddbDoc.send(new TransactWriteCommand({
          TransactItems: [
            {
              Put: {
                TableName: TABLE_NAME,
                Item: hotStateItem
              }
            },
            {
              Put: {
                TableName: TABLE_NAME,
                Item: historyItem
              }
            }
          ]
        }));

        // Structured CloudWatch observability log
        console.log(JSON.stringify({
          level: statusInfo.thresholdAlert ? 'WARN' : 'INFO',
          event: statusInfo.thresholdAlert ? 'VENUE_THRESHOLD_ALARM' : 'TELEMETRY_INGESTED',
          requestId: context.awsRequestId || 'local-test',
          venueId,
          occupancy,
          capacity,
          utilization,
          status: statusInfo.level,
          alertTriggered: statusInfo.thresholdAlert,
          sensorSource,
          timestamp: nowIso
        }));

        return {
          statusCode: 200,
          headers: getCorsHeaders(requestOrigin),
          body: JSON.stringify({
            success: true,
            message: 'Simulated telemetry accepted and atomically persisted.',
            data: hotStateItem
          })
        };
      }

      // 4. Fallback for unhandled routes
      return {
        statusCode: 404,
        headers: getCorsHeaders(requestOrigin),
        body: JSON.stringify({ success: false, error: `Route not found: ${method} ${rawPath}` })
      };
    } catch (err) {
      console.error('Unhandled Lambda exception:', err);
      return {
        statusCode: 500,
        headers: getCorsHeaders(requestOrigin),
        body: JSON.stringify({
          success: false,
          error: 'Internal server error while processing telemetry.'
        })
      };
    }
  };
}

const defaultHandler = (typeof DynamoDBClient !== 'undefined') ? createHandler() : null;

module.exports = {
  handler: defaultHandler,
  createHandler,
  evaluateStatus,
  validateTelemetryInput,
  createSeedState,
  handleIotPayload,
  GetCommand,
  PutCommand,
  TransactWriteCommand,
  VENUE_CATALOG,
  ALLOWED_ORIGINS
};
