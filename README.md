# VIT Chennai Campus AI Digital Twin

> **Cloud Architecture & Design (CAD) — Semester 5 Project**  
> *Vellore Institute of Technology (VIT), Chennai*

[![AWS Architecture](https://img.shields.io/badge/AWS-Serverless-orange.svg)](https://aws.amazon.com/)
[![Runtime](https://img.shields.io/badge/Lambda-Node.js%2022.x%20(arm64)-blue.svg)](https://nodejs.org/)
[![WebGL](https://img.shields.io/badge/3D%20Engine-Three.js-green.svg)](https://threejs.org/)
[![Database](https://img.shields.io/badge/NoSQL-Amazon%20DynamoDB-blueviolet.svg)](https://aws.amazon.com/dynamodb/)
[![License](https://img.shields.io/badge/License-Academic%20Demo-lightgrey.svg)](#academic-integrity--simulation-disclosure)

An interactive, cloud-connected **3D Digital Twin of the VIT Chennai Campus**, integrating serverless edge-to-cloud IoT telemetry ingestion, dual-state NoSQL persistence, real-time spatial WebGL rendering, and algorithmic Dijkstra perimeter evacuation routing.

> [!NOTE]
> **Project & Cloud Status:**  
> All live AWS cloud infrastructure (CloudFront distribution, API Gateway, Lambda, DynamoDB, IoT Core, and S3) provisioned during testing and evaluation has been safely deallocated to prevent recurring cloud expenditure. The application runs out-of-the-box in **Local Simulation Mode** with realistic auto-tick crowd drift upon launching the frontend (`npm run dev`). The full AWS environment can be reprovisioned anytime using the automated deployment scripts in `scripts/`.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Deployed AWS Cloud Architecture](#deployed-aws-cloud-architecture)
  - [Architecture Flow Diagram](#architecture-flow-diagram)
  - [Telemetry Path A: Web Client & UI Simulation](#telemetry-path-a-web-client--ui-simulation)
  - [Telemetry Path B: Edge IoT Turnstile Telemetry](#telemetry-path-b-edge-iot-turnstile-telemetry)
  - [Observability Branch: CloudWatch Monitoring & Alarms](#observability-branch-cloudwatch-monitoring--alarms)
  - [Frontend Delivery: S3 + CloudFront with OAC](#frontend-delivery-s3--cloudfront-with-oac)
- [AWS Services Implementation Details](#aws-services-implementation-details)
- [Key Features](#key-features)
  - [1. Interactive 3D Spatial Campus Model](#1-interactive-3d-spatial-campus-model)
  - [2. Dual-Path Real-Time Telemetry Engine](#2-dual-path-real-time-telemetry-engine)
  - [3. Algorithmic Campus Evacuation Navigation](#3-algorithmic-campus-evacuation-navigation)
  - [4. Temporal Crowd Dynamics Simulation](#4-temporal-crowd-dynamics-simulation)
- [DynamoDB Single-Table Schema](#dynamodb-single-table-schema)
- [Academic Integrity & Simulation Disclosure](#academic-integrity--simulation-disclosure)
- [Project Structure](#project-structure)
- [Getting Started & Local Setup](#getting-started--local-setup)
- [Live Demonstration Procedures](#live-demonstration-procedures)
- [Future Roadmap](#future-roadmap)
- [Attribution & Acknowledgments](#attribution--acknowledgments)

---

## Project Overview

Modern campus operations require unified situational awareness across buildings, pedestrian thoroughfares, venue occupancies, and emergency egress corridors. Managing these domains with disconnected siloes impairs timely operational decisions during large events and emergencies.

This project implements a cloud-native **Digital Twin** centered on the **Mahatma Gandhi Auditorium (`Building024`)** and the VIT Chennai campus topography:

1. **Edge-to-Cloud Telemetry Pipeline:** Ingests simulated turnstile and pedestrian traffic data via both lightweight MQTT protocols and HTTPS REST endpoints.
2. **Server-Authoritative Evaluation:** Validates venue capacities, calculates utilization rates, determines occupancy status (`NORMAL`, `MODERATE`, `HIGH`, `OVERCAPACITY`), and logs structured alert signals using AWS Lambda.
3. **Atomic Dual-State Persistence:** Records instantaneous hot venue state alongside an immutable, TTL-expiring historical telemetry log using Amazon DynamoDB transactional writes.
4. **Interactive 3D WebGL Digital Twin:** Visualizes 36 campus buildings, 278 topological waypoints, and 606 road segments in real-time with responsive status tinting and dynamic camera framing.
5. **Algorithmic Perimeter Evacuation Analysis:** Computes multi-exit shortest paths to campus gates (`Main Gate - Entrance 1`, `Main Gate - Entrance 2`, `2nd Gate`) using Dijkstra's algorithm, estimating total egress duration including bottleneck door discharge delays.

---

## Deployed AWS Cloud Architecture

The project implements a completely serverless, pay-as-you-go architecture deployed in the **AWS Asia Pacific (Mumbai) `ap-south-1`** region.

### Architecture Flow Diagram

```text
       +-------------------------------------------------------------------------+
       |                         STATIC CDN DELIVERY                             |
       |                                                                         |
       |  +--------------------+     OAC     +------------------+    HTTPS       |
       |  |  Amazon S3 Bucket  | ----------> | Amazon CloudFront| -----------> [ User Browser ]
       |  | (Private, BPA: ON) |  (TLS 1.3)  |  (Edge Caching)  |              [ Three.js Twin]
       +--+--------------------+-------------+------------------+---------------------+--+
                                                                                      |
       +-------------------------------------------------------------+                |
       |             PATH A: WEB UI SIMULATION & POLLING             |                |
       |                                                             |                |
       |  [ User Browser ] -- POST /telemetry (Slider/Presets) ----> |                |
       |  [ User Browser ] <-- GET /telemetry/latest (5s Polling) -- |                |
       |                                                             v                |
       |                                                 +-----------------------+    |
       |                                                 | Amazon API Gateway v2 |    |
       |                                                 |  (HTTP API / CORS)    |    |
       +-------------------------------------------------+-----------+-----------+----+
                                                                     |
                                                              Proxy  |
                                                                     v
       +------------------------------------+            +-----------------------+
       |   PATH B: EDGE IoT TELEMETRY       |            |      AWS Lambda       |
       |                                    |            | (Node.js 22.x arm64)  |
       |  +------------------------------+  |            |                       |
       |  | PowerShell Sensor Simulator  |  |            |  - Schema Validation  |
       |  | (demo.ps1 / synthetic edge)  |  |            |  - Capacity Derivation|
       |  +--------------+---------------+  |            |  - Status Assignment  |
       |                 | MQTT / TLS 1.2   |            +-----------+-----------+
       |                 v                  |                        |
       |  +------------------------------+  |         TransactWrite  |  Stdout Logs
       |  |        AWS IoT Core          |  |         Items          |  (Structured JSON)
       |  | (Endpoint: ATS, Port 8883)   |  |                        |
       |  +--------------+---------------+  |                        v
       |                 | Topic Match      |            +-----------------------+
       |                 v                  |            |    Amazon DynamoDB    |
       |  +------------------------------+  |            | (vit-campus-telemetry)|
       |  |     IoT Rules Engine         | -+ Direct     |  - sk: 'LATEST' (Hot) |
       |  |  (SELECT * FROM 'vit/...')   |  | Invoke     |  - sk: 'TS#...' (TTL) |
       +--+------------------------------+--+            +-----------------------+
                                                                     |
                                                                     v
       +-------------------------------------------------------------------------+
       |                     NON-BLOCKING OBSERVABILITY BRANCH                   |
       |                                                                         |
       |  +--------------------+  Metric Filter   +------------------+  Alarms   |
       |  | CloudWatch Logs    | ---------------> | CloudWatch Metrics| -------> | CloudWatch |
       |  | (7-day retention)  |  (HighOccupancy) |  VITChennai Twin |           | Dashboard  |
       +--+--------------------+------------------+------------------+-----------+------------+
```

### Telemetry Path A: Web Client & UI Simulation
- The user moves the client occupancy slider or selects a quick scenario preset (`Empty`, `Cultural Event`, `Overcapacity`) in the web application.
- Updates are debounced by 400ms to conserve HTTP requests and prevent write contention.
- The browser dispatches an HTTPS `POST /telemetry` request through **Amazon API Gateway HTTP API v2**.
- API Gateway routes the payload via the `$default` stage to the **AWS Lambda** handler (`vit-telemetry-handler`).
- Lambda executes authoritative capacity validation, determines safety thresholds, and executes a dual-item atomic transaction against **Amazon DynamoDB**.

### Telemetry Path B: Edge IoT Turnstile Telemetry
- Automated edge simulation scripts (`scripts/demo.ps1`, `scripts/publish_sensor_sim.ps1`) generate synthetic sensor events representing physical gate turnstiles (`IOT_MQTT_TURNSTILE`).
- Telemetry publishes over MQTT (TLS 1.2) to the AWS IoT Core ATS broker endpoint on topic `vit/campus/Building024/telemetry`.
- The **AWS IoT Topic Rule** (`vit_campus_telemetry_rule`) triggers via SQL match (`SELECT * FROM 'vit/campus/Building024/telemetry'`) and invokes the Lambda handler asynchronously.
- Lambda validates the payload, updates DynamoDB atomically, and emits structured CloudWatch logs.
- The web browser periodically polls `GET /telemetry/latest?venueId=Building024` every 5 seconds to ingest newly published state into the 3D scene.

### Observability Branch: CloudWatch Monitoring & Alarms
- CloudWatch operates as an **asynchronous, non-blocking monitoring branch** outside the critical write path.
- The Lambda function logs structured JSON events to `stdout` captured by `/aws/lambda/vit-telemetry-handler` (7-day retention).
- A metric filter (`vit-high-occupancy-filter`) extracts alert events (`VENUE_THRESHOLD_ALARM`) into custom namespace `VITChennai/DigitalTwin`.
- 3 CloudWatch Metric Alarms monitor Lambda Errors, Lambda Throttles, and High Occupancy breaches, visible via an operations dashboard (`vit-campus-digital-twin-dashboard`).

### Frontend Delivery: S3 + CloudFront with OAC
- Static build assets (HTML, CSS, JS, datasets, and the 20.3 MB GLTF campus model `vit_map.glb`) reside in a private **Amazon S3** bucket with **S3 Block Public Access** fully enabled.
- **Amazon CloudFront** delivers the site globally over HTTPS (TLS 1.3), using **Origin Access Control (OAC)** to sign requests to the private bucket, preventing direct public S3 exposure.

---

## AWS Services Implementation Details

| Service | Architectural Role | Implementation Details |
|---|---|---|
| **AWS IoT Core** | Edge telemetry broker | Mutual TLS / TLS 1.2 on port 8883; accepts MQTT topics `vit/campus/{venueId}/telemetry`. |
| **AWS IoT Rules Engine** | Serverless message routing | Rule `vit_campus_telemetry_rule` matches MQTT messages via SQL and invokes Lambda with zero always-on compute servers. |
| **Amazon API Gateway** | HTTP client ingress | HTTP API v2 provides low-latency REST endpoints (`POST /telemetry`, `GET /telemetry/latest`), stage rate limiting (10 req/s, burst 20), and CORS enforcement. |
| **AWS Lambda** | Server-authoritative logic | Node.js 22.x on AWS Graviton2 (`arm64`); validates inputs, enforces venue capacity limits (2,400 for MG Auditorium), computes percentage utilization, determines alarm status, and coordinates atomic persistence. |
| **Amazon DynamoDB** | Hot & historical state persistence | Single-table schema (`vit-campus-telemetry`) using `TransactWriteItems` to atomically update hot state (`sk: 'LATEST'`) and append historical audit records (`sk: 'TS#...'`) with 7-day TTL expiration. |
| **Amazon CloudWatch** | Observability & alerting | Structured JSON log ingestion, log metric filter (`vit-high-occupancy-filter`), 3 metric alarms, and centralized operations dashboard (`vit-campus-digital-twin-dashboard`). |
| **Amazon S3** | Secure asset storage | Private bucket with Block Public Access enabled; hosts static Vite distribution bundles, JSON road networks, and 3D GLB models. |
| **Amazon CloudFront** | Edge caching & TLS termination | Global Content Delivery Network with Origin Access Control (OAC) and gzip/brotli compression, providing low-latency distribution for the 20.3 MB 3D asset. |
| **AWS IAM** | Least-privilege access control | Dedicated execution role (`vit-telemetry-lambda-role`) scoped strictly to table `vit-campus-telemetry` and log group `/aws/lambda/vit-telemetry-handler`. |

---

## Key Features

### 1. Interactive 3D Spatial Campus Model
- **Engine:** Three.js WebGL with `OrbitControls`, custom raycasting, and dynamic lighting.
- **Coverage:** 36 campus structures, 278 topological waypoints, and 606 road graph edges aligned to real-world coordinates.
- **Search & Selection:** Real-time building search dropdown with auto-focus camera animation and smooth panning.
- **Live Status Tinting:** Buildings change color based on real-time occupancy status:
  - 🟢 **NORMAL** (< 50% capacity): Subdued green glow.
  - 🟡 **MODERATE** (50% – 79% capacity): Amber cautionary tint.
  - 🔴 **HIGH** (80% – 100% capacity): Vibrant coral/red warning pulse.
  - 🟣 **OVERCAPACITY** (> 100% capacity): Critical flashing alert tint.

### 2. Dual-Path Real-Time Telemetry Engine
- **Debounced Web Telemetry:** Browser slider controls emit debounced telemetry without flooding API endpoints.
- **Dynamic Capacity Derivation:** Lambda calculates utilization percentage ($utilization = \frac{occupancy}{capacity} \times 100$) on the server to prevent client spoofing.
- **Scenario Presets:** Instant testing of typical campus scenarios:
  - *Normal Activity*: 650 / 2,400 (27.1%, `NORMAL`)
  - *Cultural Event / Seminar*: 2,150 / 2,400 (89.6%, `HIGH`)
  - *Overcrowded Emergency*: 2,550 / 2,400 (106.3%, `OVERCAPACITY`)

### 3. Algorithmic Campus Evacuation Navigation
- **Topological Road Graph:** Directed graph constructed from `waypoints.json`, `buildingEntrances.json`, and `oneWayRoads.json`.
- **Dijkstra Shortest Path:** Computes exact perimeter egress routes from any campus building to the 3 main perimeter gates:
  - `Main Gate - Entrance 1` (Waypoint 111)
  - `Main Gate - Entrance 2` (Waypoint 188)
  - `2nd Gate` (Waypoint 33)
- **Total Evacuation Time Estimation:** Combines walking transit time at average pedestrian speed ($1.2\text{ m/s}$) with doorway bottleneck discharge delay:
  $$\text{Total Egress Time} = \frac{\text{Distance}}{1.2\text{ m/s}} + \frac{\text{Occupancy}}{\text{Doors} \times \text{Discharge Rate}}$$

### 4. Temporal Crowd Dynamics Simulation
- Models campus-wide pedestrian flow throughout a 24-hour cycle:
  - Morning arrival peaks (08:00 – 09:00)
  - Inter-class transit surges (hourly transition intervals)
  - Food court & canteen lunch rush (12:30 – 14:00)
  - Evening library & hostel dispersion (17:00 – 20:00)

---

## DynamoDB Single-Table Schema

All operational state and historical audit records reside in a single DynamoDB table named `vit-campus-telemetry`:

- **Primary Partition Key (`PK`):** `venueId` (e.g. `Building024`)
- **Primary Sort Key (`SK`):** `sk`

```text
+----------------+--------------------------+-----------+------------+--------+-------------+------------+
| venueId (PK)   | sk (SK)                  | occupancy | flowRate   | status | isSimulated | ttl        |
+----------------+--------------------------+-----------+------------+--------+-------------+------------+
| Building024    | LATEST                   | 2150      | +25        | HIGH   | true        | -          |
| Building024    | TS#2026-10-30T08:45:00Z  | 2150      | +25        | HIGH   | true        | 1793868300 |
| Building024    | TS#2026-10-30T08:40:00Z  | 1920      | +40        | MODERATE| true       | 1793868000 |
+----------------+--------------------------+-----------+------------+--------+-------------+------------+
```

- **`sk = 'LATEST'`**: Stores the authoritative current venue state. Allows sub-10ms point reads by the frontend polling mechanism (`GetItem`).
- **`sk = 'TS#<ISO8601>'`**: Append-only historical log written in the same transaction. Includes a Unix timestamp `ttl` attribute for automated 7-day cleanup without scan or delete costs.

---

## Academic Integrity & Simulation Disclosure

> [!IMPORTANT]
> **Educational Simulation Notice:**  
> This project was developed as an academic demonstration for the Cloud Architecture & Design course.
> 1. All sensor readings, occupancy figures, flow rates, and safety alerts are synthetic, generated by automated simulation scripts stamped with `isSimulated: true`.
> 2. No physical cameras, optical turnstiles, or infrared break-beam hardware sensors are deployed on campus doors.
> 3. Evacuation routes and egress durations demonstrate algorithmic graph traversal (Dijkstra) and queue discharge modeling. They are educational simulations and are not certified life-safety or emergency response protocols.

---

## Project Structure

```text
vit-chennai-digital-twin/
├── backend/
│   └── lambda/
│       ├── index.js                  # Serverless handler (validation, business logic, DynamoDB writes)
│       └── package.json              # Lambda dependencies (@aws-sdk/client-dynamodb)
├── public/
│   ├── assets/
│   │   └── vit_map.glb               # 20.3 MB 3D campus model (36 buildings, roads, foliage)
│   ├── waypoints.json                # 278 campus road navigation nodes
│   ├── buildingEntrances.json        # Building identifiers & nearest entrance waypoints
│   ├── oneWayRoads.json              # Directed road segment sequences
│   ├── path.json                     # Bundled graph topology fallback
│   ├── config.json                   # Runtime API configuration (auto-wired or overridden)
│   └── config.example.json           # Template configuration file
├── src/
│   ├── main.js                       # Application entry point & service wiring
│   ├── scene.js                      # Three.js 3D WebGL viewport, lighting & materials
│   ├── twinSimulation.js             # Client simulation engine, telemetry polling & state manager
│   ├── graph.js                      # Dijkstra navigation graph & evacuation pathfinder
│   ├── temporalCrowd.js              # 24-hour campus crowd schedule simulation
│   ├── navigationView.js             # Route line rendering & 3D waypoint indicators
│   └── ui.js                         # HUD controls, preset triggers, modal & accessibility logic
├── scripts/
│   ├── demo.ps1                      # Automated end-to-end cloud diagnostic & demo runner
│   ├── deploy_backend.ps1            # AWS Lambda & API Gateway deployment script
│   ├── deploy_stage2.ps1             # AWS IoT Core & topic rule provisioning script
│   ├── deploy_s3_cloudfront.ps1      # S3 sync and CloudFront CDN cache invalidation
│   ├── deploy_all.ps1                # Comprehensive multi-stage cloud deployer
│   └── publish_sensor_sim.ps1        # Synthetic MQTT sensor telemetry publisher
├── index.html                        # Application shell & Deployed AWS Architecture modal
├── style.css                         # Dark theme, telemetry HUD, responsive layout & modal styling
├── vite.config.js                    # Vite bundler configuration
└── package.json                      # Frontend project dependencies (Three.js, Vite)
```

---

## Getting Started & Local Setup

### Prerequisites

- **Node.js**: `v18.0.0` or later (tested on Node.js 22.x)
- **npm**: `v9.0.0` or later
- **Modern Web Browser**: Chrome, Edge, Firefox, or Safari with WebGL enabled.
- **AWS CLI** *(Optional, for cloud deployment or live IoT simulation)*: Configured with appropriate IAM permissions.

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kushaagrasood/VIT-Chennai-Digital-Twin.git
   cd VIT-Chennai-Digital-Twin
   ```

2. **Install frontend dependencies:**
   ```bash
   npm install
   ```

3. **Configure API Gateway (Optional):**
   - By default, the application runs in **Local Simulation Mode** with realistic continuous auto-tick drift.
   - To connect to a deployed AWS backend, configure `public/config.json`:
     ```json
     {
       "apiUrl": "https://<your-api-id>.execute-api.ap-south-1.amazonaws.com"
     }
     ```
   - Alternatively, pass the endpoint at runtime via query parameter:
     ```text
     http://localhost:5173/?api=https://<your-api-id>.execute-api.ap-south-1.amazonaws.com
     ```

4. **Launch development server:**
   ```bash
   npm run dev
   ```
   Open the printed local URL (typically `http://localhost:5173`) in your browser.

5. **Build for production:**
   ```bash
   npm run build
   ```
   Generates optimized static assets in `dist/`.

---

## Live Demonstration Procedures

The automated demonstration script `scripts/demo.ps1` verifies the health of all AWS services and executes automated telemetry scenarios.

### Step 1: Run Cloud Diagnostics
Verify that all cloud resources are reachable and correctly configured:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\demo.ps1 -DiagnosticOnly
```

The script performs 8 diagnostic checks:
1. IAM deployment user identity & caller verification.
2. DynamoDB table status (`vit-campus-telemetry`).
3. Lambda execution role permissions (`vit-telemetry-lambda-role`).
4. Lambda function active state (`vit-telemetry-handler`).
5. API Gateway HTTP API v2 route integration.
6. CloudWatch dashboard accessibility (`vit-campus-digital-twin-dashboard`).
7. S3 private bucket status.
8. CloudFront distribution deployment state.

### Step 2: Demonstrate High Occupancy Threshold Alert
Publish a high-occupancy event to trigger the safety threshold and observe real-time cloud propagation:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\demo.ps1 -Scenario High
```

**Expected Results:**
- **Injected Payload:** Occupancy: 2,150 / 2,400 seats (+25 people/min flow).
- **Derived Utilization:** **89.6%** ($\ge 80\%$ safety threshold).
- **Status Assigned:** `HIGH` with `alarm: true`.
- **Lambda Log:** Structured JSON output: `VENUE_THRESHOLD_ALARM`.
- **DynamoDB:** Atomically records 2,150 into `LATEST` and writes historical timestamp record.
- **Web UI:** Auditorium status pill turns red/orange, 3D model glows amber, and egress calculations display ~5 min total exit time.

### Step 3: Demonstrate Normal Recovery
Publish a normal-occupancy event to clear the alert:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\demo.ps1 -Scenario Normal
```

**Expected Results:**
- **Injected Payload:** Occupancy: 650 / 2,400 seats (+5 people/min flow).
- **Derived Utilization:** **27.1%** (< 50% threshold).
- **Status Assigned:** `NORMAL` (`alarm: false`).
- **Web UI:** Auditorium returns to green, and alarm banner dismisses.

---

## Future Roadmap

The following architectural enhancements represent conceptual extensions for a physical production deployment:

1. **Hardware Edge Ingestion:** Physical ESP32 microcontrollers deployed at venue turnstiles with infrared break-beams, authenticating via AWS IoT Core X.509 device certificates.
2. **Real-Time Push Subscriptions:** AWS AppSync GraphQL or WebSocket API Gateway subscriptions replacing client HTTP polling for sub-second state broadcasts.
3. **Computer Vision Head-Counting:** Amazon Kinesis Video Streams integrating AWS Panorama or edge YOLOv8 models for automated density monitoring.
4. **Predictive AI Crowding:** Amazon SageMaker models forecasting corridor bottlenecks 30 minutes in advance by correlating university timetables with historical turnstile flows.

---

## Attribution & Acknowledgments

- **Campus Model & Spatial Graph:** Derived from the VIT Chennai Wayfinder map data and campus blueprints for educational use.
- **Frameworks & Libraries:**
  - [Three.js](https://threejs.org/) for 3D WebGL rendering.
  - [Vite](https://vitejs.dev/) for frontend bundling.
  - [AWS SDK for JavaScript v3](https://github.com/aws/aws-sdk-js-v3) for serverless cloud integration.
- **Course Faculty & Evaluators:** Developed under the guidance of the Department of Cloud Computing & Computer Science, VIT Chennai.
