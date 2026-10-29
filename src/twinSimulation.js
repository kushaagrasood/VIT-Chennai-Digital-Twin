/**
 * Mahatma Gandhi Auditorium Digital Twin Telemetry & Simulation Engine
 * Simulates real-time occupancy, dynamic fluctuation, threshold evaluation,
 * and emergency egress calculation for Building024 (Entrance WP 199).
 *
 * Stage 1 Cloud Architecture:
 * - When configured with an API Gateway endpoint, polls AWS DynamoDB for hot state.
 * - When user modifies slider or scenario presets, dispatches a debounced POST to /telemetry.
 * - Gracefully falls back to deterministic local random-walk simulation when API is unreachable.
 * - Local auto-tick and cloud polling are mutually exclusive to prevent state race conditions.
 */

export class TwinSimulationEngine {
  constructor(options = {}) {
    this.buildingKey = 'Building024';
    this.buildingName = 'Mahatma Gandhi Auditorium';
    this.entranceWaypointId = '199';

    // Capacity is an estimated demo value (flagged clearly)
    this.capacity = options.capacity || 2400;

    // Configurable thresholds (percentages)
    this.thresholds = {
      moderate: options.moderateThreshold || 50, // 50%
      high: options.highThreshold || 80          // 80%
    };

    // Current state
    this.currentOccupancy = options.initialOccupancy || 1480;
    this.isLive = options.isLive ?? true;
    this.flowRate = 0; // people per minute (positive = entering, negative = exiting)
    this.lastUpdated = new Date();
    this.activePreset = null;

    // Cloud connection configuration
    this.apiEndpoint = options.apiEndpoint ? options.apiEndpoint.replace(/\/+$/, '') : null;
    this.connectionMode = this.apiEndpoint ? 'connecting' : 'local'; // 'local' | 'connecting' | 'cloud'
    this.cloudPollTimer = null;
    this.postDebounceTimer = null;
    this.consecutiveFailures = 0;

    // Event listeners for UI updates
    this.subscribers = new Set();
    this.timer = null;

    if (this.isLive) {
      this.startLiveSimulation();
    }
  }

  /**
   * Subscribe to state updates
   */
  subscribe(callback) {
    this.subscribers.add(callback);
    // Immediately emit current state
    callback(this.getState());
    return () => this.subscribers.delete(callback);
  }

  notify() {
    const state = this.getState();
    for (const cb of this.subscribers) {
      try {
        cb(state);
      } catch (err) {
        console.error('Subscription callback error:', err);
      }
    }
  }

  /**
   * Return comprehensive telemetry snapshot
   */
  getState() {
    const occupancy = Math.max(0, Math.round(this.currentOccupancy));
    const utilization = Math.round((occupancy / this.capacity) * 1000) / 10;
    const status = this.evaluateStatus(utilization);

    let cloudStatusLabel = 'LOCAL SIMULATION (OFFLINE DEMO)';
    if (this.connectionMode === 'cloud') {
      cloudStatusLabel = 'AWS SERVERLESS BUS (ONLINE)';
    } else if (this.connectionMode === 'connecting') {
      cloudStatusLabel = 'CONNECTING TO AWS BUS...';
    }

    return {
      buildingKey: this.buildingKey,
      buildingName: this.buildingName,
      entranceWaypointId: this.entranceWaypointId,
      capacity: this.capacity,
      occupancy,
      utilization, // percentage (e.g., 62.5%)
      status: status.level, // 'LOW' | 'MODERATE' | 'HIGH' | 'OVERCAPACITY'
      statusLabel: status.label,
      statusColor: status.color,
      statusDescription: status.description,
      flowRate: this.flowRate,
      thresholds: { ...this.thresholds },
      isLive: this.isLive,
      lastUpdated: this.lastUpdated,
      activePreset: this.activePreset,
      isSimulated: true, // Explicit flag required by specifications
      disclaimer: 'Simulated demo telemetry. Real VIT Chennai deployment requires live IoT door sensors / turnstile feeds.',
      connectionMode: this.connectionMode,
      apiEndpoint: this.apiEndpoint,
      cloudStatusLabel
    };
  }

  /**
   * Classify utilization against configurable thresholds
   */
  evaluateStatus(utilization) {
    if (utilization > 100) {
      return {
        level: 'OVERCAPACITY',
        label: 'Over Capacity Alert',
        color: '#ef4444',
        description: 'Occupancy exceeds rated venue capacity. Ingress throttling recommended.'
      };
    }
    if (utilization >= this.thresholds.high) {
      return {
        level: 'HIGH',
        label: 'High Occupancy',
        color: '#f97316',
        description: 'Venue near capacity. Auxiliary exits should be unlocked.'
      };
    }
    if (utilization >= this.thresholds.moderate) {
      return {
        level: 'MODERATE',
        label: 'Moderate Occupancy',
        color: '#eab308',
        description: 'Nominal operational range. Hall and lobby traffic is steady.'
      };
    }
    return {
      level: 'LOW',
      label: 'Low / Normal Occupancy',
      color: '#10b981',
      description: 'Standard density. Egress paths fully unobstructed.'
    };
  }

  /**
   * Start live simulation or polling loop
   */
  startLiveSimulation() {
    this.isLive = true;
    if (this.apiEndpoint) {
      this.startCloudPolling();
    } else {
      this.startLocalTimer();
    }
  }

  startLocalTimer() {
    if (this.timer) clearInterval(this.timer);
    this.timer = setInterval(() => {
      this.tick();
    }, 2500);
  }

  startCloudPolling() {
    if (this.cloudPollTimer) clearInterval(this.cloudPollTimer);
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.fetchCloudLatest();
    this.cloudPollTimer = setInterval(() => {
      this.fetchCloudLatest();
    }, 5000);
  }

  /**
   * Poll latest telemetry from AWS API Gateway
   */
  async fetchCloudLatest() {
    if (!this.apiEndpoint) return;
    try {
      const res = await fetch(`${this.apiEndpoint}/telemetry/latest?venueId=${this.buildingKey}`, {
        signal: AbortSignal.timeout(3500)
      });
      if (res.ok) {
        const data = await res.json();
        if (typeof data.occupancy === 'number') {
          this.currentOccupancy = data.occupancy;
          this.flowRate = typeof data.flowRate === 'number' ? data.flowRate : 0;
          this.lastUpdated = data.updatedAt ? new Date(data.updatedAt) : new Date();
          this.connectionMode = 'cloud';
          this.consecutiveFailures = 0;
          this.notify();
          return;
        }
      }
      throw new Error(`HTTP ${res.status}`);
    } catch (err) {
      this.consecutiveFailures++;
      if (this.consecutiveFailures >= 3 && this.connectionMode !== 'local') {
        console.warn('API Gateway telemetry polling failed 3 times; falling back to local simulation:', err.message);
        this.connectionMode = 'local';
        if (this.isLive && !this.timer) {
          this.startLocalTimer();
        }
        this.notify();
      }
    }
  }

  /**
   * Push state to AWS API Gateway with debouncing to prevent flood
   */
  pushCloudState(occupancy) {
    if (!this.apiEndpoint || this.connectionMode !== 'cloud') return;
    if (this.postDebounceTimer) clearTimeout(this.postDebounceTimer);

    this.postDebounceTimer = setTimeout(async () => {
      try {
        const res = await fetch(`${this.apiEndpoint}/telemetry`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            venueId: this.buildingKey,
            occupancy: Math.round(occupancy),
            flowDelta: this.flowRate,
            sensorSource: 'UI_SLIDER'
          }),
          signal: AbortSignal.timeout(4000)
        });
        if (res.ok) {
          const resData = await res.json();
          if (resData.data?.updatedAt) {
            this.lastUpdated = new Date(resData.data.updatedAt);
          }
          this.notify();
        }
      } catch (err) {
        console.warn('Cloud telemetry push error:', err);
      }
    }, 400);
  }

  /**
   * Reset local timer on user interaction
   */
  restartTimer() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = setInterval(() => {
        this.tick();
      }, 2500);
    }
  }

  stopLiveSimulation() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    if (this.cloudPollTimer) {
      clearInterval(this.cloudPollTimer);
      this.cloudPollTimer = null;
    }
    this.isLive = false;
    this.flowRate = 0;
    this.notify();
  }

  toggleLiveSimulation() {
    if (this.isLive) {
      this.stopLiveSimulation();
    } else {
      this.startLiveSimulation();
    }
  }

  /**
   * Advance simulation time step with realistic pedestrian drift (Local Mode Only)
   */
  tick() {
    // Generate realistic fluctuating pedestrian flow (-18 to +22 people)
    const delta = Math.floor((Math.random() - 0.48) * 36);
    this.flowRate = Math.round((delta / 2.5) * 60); // approx people/min

    // Soft bounds around capacity
    let nextOccupancy = this.currentOccupancy + delta;
    if (nextOccupancy < 20) {
      nextOccupancy = 20 + Math.floor(Math.random() * 25);
    }
    if (nextOccupancy > this.capacity * 1.08) {
      nextOccupancy = Math.floor(this.capacity * 1.05) + Math.floor((Math.random() - 0.5) * 30);
    }

    this.currentOccupancy = nextOccupancy;
    this.lastUpdated = new Date();
    this.notify();
  }

  /**
   * Manual override of occupancy value
   */
  setOccupancy(value) {
    this.currentOccupancy = Math.max(0, Number(value) || 0);
    this.activePreset = null;
    this.flowRate = 0;
    this.lastUpdated = new Date();
    if (this.connectionMode === 'cloud') {
      this.pushCloudState(this.currentOccupancy);
    } else if (this.isLive) {
      this.restartTimer();
    }
    this.notify();
  }

  /**
   * Set venue capacity (configurable)
   */
  setCapacity(value) {
    const val = Number(value);
    if (val > 0) {
      this.capacity = val;
      if (this.connectionMode === 'local' && this.isLive) {
        this.restartTimer();
      }
      this.notify();
    }
  }

  /**
   * Update configurable thresholds
   */
  setThresholds(moderate, high) {
    const mod = Number(moderate);
    const hi = Number(high);
    if (mod > 0 && hi > mod) {
      this.thresholds.moderate = mod;
      this.thresholds.high = hi;
      this.notify();
    }
  }

  /**
   * Scenario Presets
   */
  applyPreset(scenarioKey) {
    this.activePreset = scenarioKey;
    switch (scenarioKey) {
      case 'empty':
        this.currentOccupancy = 65;
        break;
      case 'lecture':
        this.currentOccupancy = Math.round(this.capacity * 0.42);
        break;
      case 'cultural':
        this.currentOccupancy = Math.round(this.capacity * 0.76);
        break;
      case 'convocation':
        this.currentOccupancy = Math.round(this.capacity * 0.94);
        break;
      case 'overcrowded':
        this.currentOccupancy = Math.round(this.capacity * 1.06);
        break;
      default:
        this.activePreset = null;
        break;
    }
    this.lastUpdated = new Date();
    if (this.connectionMode === 'cloud') {
      this.pushCloudState(this.currentOccupancy);
    } else if (this.isLive) {
      this.restartTimer();
    }
    this.notify();
  }

  /**
   * Compute theoretical evacuation time for the current occupancy
   */
  calculateEvacuationMetrics(routeDistanceMeters) {
    const walkingSpeedMps = 1.2; // nominal walking speed 1.2 m/s
    const walkTimeSeconds = Math.round(routeDistanceMeters / walkingSpeedMps);

    // Theoretical flow bottleneck egress rate: 70 persons/min per double door exit lane
    // Assuming 6 egress door lanes for Mahatma Gandhi Auditorium
    const doorLanes = 6;
    const dischargeRatePersonsPerSec = (70 * doorLanes) / 60; // 7 persons/sec
    const egressQueueTimeSeconds = Math.round(this.currentOccupancy / dischargeRatePersonsPerSec);
    const totalEvacSeconds = egressQueueTimeSeconds + walkTimeSeconds;

    return {
      walkingSpeedMps,
      walkTimeSeconds,
      egressQueueTimeSeconds,
      totalEvacSeconds,
      formattedTime: `${Math.floor(totalEvacSeconds / 60)}m ${totalEvacSeconds % 60}s`,
      doorLanesAssumed: doorLanes,
      theoreticalDischargeRate: `${Math.round(dischargeRatePersonsPerSec * 60)} persons/min`,
      disclaimer: 'ALGORITHMIC DEMONSTRATION ONLY. This calculation is a simplified simulation using estimated egress parameters and is not a certified life-safety evacuation audit.'
    };
  }
}
