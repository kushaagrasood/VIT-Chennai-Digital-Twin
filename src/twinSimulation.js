/**
 * Mahatma Gandhi Auditorium Digital Twin Telemetry & Simulation Engine
 * Simulates real-time occupancy, dynamic fluctuation, threshold evaluation,
 * and emergency egress calculation for Building024 (Entrance WP 199).
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
      disclaimer: 'Simulated demo telemetry. Real VIT Chennai deployment requires live IoT door sensors / turnstile feeds.'
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
   * Start live simulation loop
   */
  /**
   * Start live simulation loop
   */
  startLiveSimulation() {
    if (this.timer) clearInterval(this.timer);
    this.isLive = true;
    this.timer = setInterval(() => {
      this.tick();
    }, 2500);
  }

  /**
   * Reset the auto-tick timer interval so user adjustments (slider/presets)
   * enjoy a fresh 2.5s window before subsequent natural drift begins.
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
   * Advance simulation time step with realistic pedestrian drift
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
    if (this.isLive) {
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
      if (this.isLive) {
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
    if (this.isLive) {
      this.restartTimer();
    }
    this.notify();
  }

  /**
   * Compute theoretical evacuation time for the current occupancy
   * Note: Explicit disclaimer provided with calculation!
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
