# AI Digital Twin of VIT Chennai Campus

An interactive **Digital Twin of VIT Chennai campus** designed to explore smart-campus monitoring, spatial visualization, simulated IoT data, and evacuation-route analysis using cloud technologies.

The project aims to create a unified digital representation of campus infrastructure, enabling users to explore campus locations, visualize simulated occupancy, monitor building status, and demonstrate how real-time data and simulation can support campus operations.

> **Project status:** Under development. Features described as planned or simulated are not necessarily implemented or connected to live infrastructure.

## Overview

Campus infrastructure involves multiple interconnected systems, including buildings, pedestrian pathways, occupancy, utilities, and emergency response. Managing these systems independently makes it difficult to understand campus conditions holistically.

This project explores how a **cloud-connected Digital Twin** can represent campus infrastructure and combine spatial data with simulated sensor readings and analytical tools.

The initial demonstration focuses on VIT Chennai's campus model and Mahatma Gandhi Auditorium as an example of building-level occupancy monitoring and evacuation-route visualization.

## Key Features

### Interactive 3D Campus
- Browser-based visualization of the campus model.
- Camera controls for orbiting, panning, and zooming.
- Searchable campus locations and building selection.
- Optional navigation graph visualization.

### Simulated Smart-Campus Monitoring
- Simulated occupancy updates for selected buildings.
- Occupancy utilization and status indicators.
- Configurable thresholds for demonstration alerts.
- A foundation for future integration with real IoT sensors.

### Navigation and Evacuation Simulation
- Navigation graph constructed from waypoint and road data.
- Route calculation where graph connectivity supports it.
- Demonstration of alternative routes and potential congestion.
- A foundation for future crowd-flow simulation.

### Cloud Architecture
The project is designed to explore AWS-based ingestion, storage, processing, and dashboard delivery. Cloud integration will be documented as it is implemented and tested.

## Technology Stack

| Component | Technology |
|---|---|
| 3D visualization | Three.js, GLTFLoader |
| Frontend | React / Vite, subject to the existing implementation |
| Campus model | glTF Binary (`.glb`) |
| Spatial and navigation data | JSON |
| Backend/API | AWS API Gateway and AWS Lambda (planned) |
| Operational data | Amazon DynamoDB (planned) |
| Time-series data | Amazon Timestream (planned) |
| IoT ingestion | AWS IoT Core (planned) |
| Static asset storage | Amazon S3 (planned) |
| Monitoring and visualization | Amazon CloudWatch and optional dashboard services (planned) |

The final stack will reflect the services actually implemented in the repository.

## System Architecture

The intended high-level data flow is:

```text
Campus Model + Navigation Data
              |
              v
     Interactive Web Frontend
              |
       API Gateway (planned)
              |
         AWS Lambda
              |
       +------+------+
       |             |
       v             v
   DynamoDB      Timestream
  Latest State   Time Series
       |             |
       +------+------+
              |
              v
      Digital Twin Dashboard
```

Simulated readings will be used initially. AWS components are planned architecture until their integration is implemented and verified.

## Campus Data

The project uses campus assets and navigation data obtained from the VIT Chennai Wayfinder website, subject to applicable licensing and attribution requirements.

Expected local assets include:

```text
public/
  assets/
    vit_map.glb

data/
  path.json
  buildingEntrances.json
  waypoints.json
  oneWayRoads.json
```

The exact paths may differ depending on the repository implementation.

- **`vit_map.glb`** — 3D campus model.
- **`path.json`** — combined navigation data containing `buildingEntrances`, `oneWayRoads`, and `waypoints`.
- **`buildingEntrances.json`** — named locations and entrance waypoint references.
- **`waypoints.json`** — navigation nodes and associated data.
- **`oneWayRoads.json`** — directional road sequences.

The application must validate coordinate systems and graph connections before using them for visualization or route calculations. Building footprints, entrance relationships, and model alignment should not be assumed without verification.

## Demonstration Scenario: Mahatma Gandhi Auditorium

The initial scenario explores building-level occupancy monitoring.

The planned dashboard will display:
- Current simulated occupancy.
- Estimated capacity and utilization percentage.
- Occupancy status based on configurable thresholds.
- Changes in occupancy over time.
- A demonstration of route selection and evacuation flow.

Unless real sensor data and verified capacity information are integrated, all such values will be clearly labelled as **simulated**.

The evacuation feature is an educational demonstration and is not a validated life-safety or emergency-response system.

## Getting Started

### Prerequisites

- Node.js and npm, if the frontend uses the React/Vite stack.
- Git.
- A modern web browser.
- The campus model and required JSON data files.

### Installation

Clone the repository:

```bash
git clone <YOUR_REPOSITORY_URL>
cd <YOUR_REPOSITORY_DIRECTORY>
```

Install dependencies:

```bash
npm install
```

Start the development server:

```bash
npm run dev
```

Open the local URL printed by the development server.

> These commands assume a Node.js frontend with npm scripts. Adjust them to match the repository's actual configuration.

## Project Structure

The intended organization is:

```text
.
├── public/
│   └── assets/
│       └── vit_map.glb
├── data/
│   ├── path.json
│   ├── buildingEntrances.json
│   ├── waypoints.json
│   └── oneWayRoads.json
├── src/
│   ├── components/
│   ├── pages/
│   ├── services/
│   └── simulation/
├── SESSION_NOTES.md
├── README.md
└── package.json
```

The actual structure should follow the implemented codebase.


## Limitations

- Occupancy data is simulated unless explicitly connected to real sensors.
- Capacity values must be verified or clearly identified as estimates.
- Navigation quality depends on the completeness and correctness of the source graph.
- Evacuation routes are demonstrations, not certified emergency guidance.
- AWS services may remain planned until end-to-end integration is verified.

## Responsible Use and Attribution

Campus assets and navigation data originate from the VIT Chennai Wayfinder website. Their reuse, modification, redistribution, and public hosting must comply with applicable terms and licensing conditions. Appropriate attribution should be provided where required.

Do not commit AWS credentials, API keys, cookies, or other secrets to the repository.

## Academic Context

Developed as a Cloud Architecture Design project exploring digital twins, cloud infrastructure, spatial data, IoT simulation, and intelligent campus operations.
