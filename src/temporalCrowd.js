/**
 * Temporal Crowd Density Simulation for VIT Chennai Campus
 * Models dynamic, schedule-driven crowd migrations across daily academic,
 * dining, residential, athletic, and transit time blocks.
 */

export class TemporalCrowdSimulation {
  constructor() {
    // Categorization of all 36 campus buildings for temporal scheduling
    this.buildingCategories = {
      // Academic Blocks & Institutes
      Building007: 'academic',   // Academic Block 1 (AB1)
      Building006: 'academic',   // Academic Block 2 (AB2)
      Building001: 'academic',   // Academic Block 3 (AB3)
      Building003: 'academic',   // Academic Block 4 (AB4)
      Building014: 'academic',   // Academic Block 5 (AB5)
      Building009: 'academic',   // Sigma Block
      Building013: 'academic',   // Alpha Block
      Building020: 'academic',   // Omega Block
      Building011: 'academic',   // Admin Block
      Building025: 'academic',   // VIT-SEDAXIS

      // Residential Hostels
      Building: 'hostel',        // D Block Hostel
      Building002: 'hostel',     // A Block hostel
      Building004: 'hostel',     // E Block Hostel
      Building005: 'hostel',     // F Block Hostel
      Building030: 'hostel',     // B Block Hostel
      Building031: 'hostel',     // C Block Hostel

      // Student Commons, Dining & Hangouts
      Building012: 'commons',    // North Square (Food Court & Student Center)
      Building029: 'commons',    // Gazebo

      // Sports, Athletics & Recreation
      Building008: 'sports',     // Swimming Pool
      Building010: 'sports',     // GymKhaana
      Building015: 'sports',     // Tennis Court
      Building016: 'sports',     // Football Ground
      Building017: 'sports',     // Basketball Court
      Building018: 'sports',     // Volleyball Court
      Building019: 'sports',     // Ground
      Building021: 'sports',     // Cricket Ground

      // Assembly & Venues
      Building024: 'auditorium', // Mahatma Gandhi Auditorium

      // Campus Gates & Transit
      Main_Gate: 'gates',        // Main Gate (Entrance 1 & 2)
      Gate: 'gates',             // 2nd Gate

      // Vehicle Parkings
      Building023: 'parking',    // Student's Parking
      Building026: 'parking',    // Student's Parking 2
      Building027: 'parking',    // Staff Parking 1
      Building028: 'parking',    // Staff Parking 2

      // Campus Administration & Facilities
      Building022: 'facilities', // Guest House
      Building032: 'facilities', // Site Office
      Building033: 'facilities'  // Transport Office
    };

    // Piecewise temporal curves across the 24-hour cycle [0 - 24]
    this.curves = {
      academic: [
        { t: 0, v: 0.05 }, { t: 6.5, v: 0.05 }, { t: 8, v: 0.55 }, { t: 9.5, v: 0.90 },
        { t: 12.5, v: 0.72 }, { t: 13.5, v: 0.85 }, { t: 16.5, v: 0.80 }, { t: 17.5, v: 0.42 },
        { t: 18.5, v: 0.22 }, { t: 21, v: 0.15 }, { t: 22.5, v: 0.08 }, { t: 24, v: 0.05 }
      ],
      hostel: [
        { t: 0, v: 0.96 }, { t: 6.5, v: 0.96 }, { t: 8, v: 0.62 }, { t: 9.5, v: 0.35 },
        { t: 12.5, v: 0.25 }, { t: 13.5, v: 0.18 }, { t: 16.5, v: 0.22 }, { t: 17.5, v: 0.50 },
        { t: 18.5, v: 0.60 }, { t: 21, v: 0.75 }, { t: 22.5, v: 0.92 }, { t: 24, v: 0.96 }
      ],
      commons: [
        { t: 0, v: 0.05 }, { t: 7, v: 0.05 }, { t: 8.5, v: 0.38 }, { t: 10, v: 0.45 },
        { t: 12, v: 0.82 }, { t: 13.5, v: 0.94 }, { t: 15, v: 0.62 }, { t: 17, v: 0.80 },
        { t: 18.5, v: 0.88 }, { t: 20.5, v: 0.65 }, { t: 22, v: 0.25 }, { t: 24, v: 0.05 }
      ],
      sports: [
        { t: 0, v: 0.04 }, { t: 5.5, v: 0.04 }, { t: 6.5, v: 0.42 }, { t: 8, v: 0.18 },
        { t: 12, v: 0.12 }, { t: 14, v: 0.12 }, { t: 16, v: 0.55 }, { t: 17.5, v: 0.88 },
        { t: 18.5, v: 0.92 }, { t: 20, v: 0.45 }, { t: 21.5, v: 0.15 }, { t: 24, v: 0.04 }
      ],
      auditorium: [
        { t: 0, v: 0.05 }, { t: 8, v: 0.15 }, { t: 10, v: 0.60 }, { t: 13.5, v: 0.50 },
        { t: 16, v: 0.70 }, { t: 18, v: 0.85 }, { t: 21, v: 0.40 }, { t: 24, v: 0.05 }
      ],
      gates: [
        { t: 0, v: 0.08 }, { t: 6.5, v: 0.15 }, { t: 8.5, v: 0.88 }, { t: 10, v: 0.42 },
        { t: 13, v: 0.35 }, { t: 16.5, v: 0.58 }, { t: 18, v: 0.86 }, { t: 19.5, v: 0.60 },
        { t: 21, v: 0.30 }, { t: 24, v: 0.08 }
      ],
      parking: [
        { t: 0, v: 0.08 }, { t: 7.5, v: 0.45 }, { t: 9, v: 0.88 }, { t: 13.5, v: 0.80 },
        { t: 16.5, v: 0.65 }, { t: 18, v: 0.38 }, { t: 20, v: 0.20 }, { t: 24, v: 0.08 }
      ],
      facilities: [
        { t: 0, v: 0.10 }, { t: 8, v: 0.35 }, { t: 11, v: 0.65 }, { t: 14, v: 0.60 },
        { t: 17, v: 0.45 }, { t: 20, v: 0.25 }, { t: 24, v: 0.10 }
      ]
    };
  }

  /**
   * Deterministic pseudo-random variation based on building key string
   */
  hashBuilding(key) {
    let h = 0;
    for (let i = 0; i < key.length; i++) {
      h = (h * 31 + key.charCodeAt(i)) & 0xffffffff;
    }
    return Math.abs(h);
  }

  /**
   * Cosine-smoothed interpolation between piecewise keyframe points
   */
  interpolate(points, t) {
    if (!points || points.length === 0) return 0.2;
    if (t <= points[0].t) return points[0].v;
    if (t >= points[points.length - 1].t) return points[points.length - 1].v;

    for (let i = 0; i < points.length - 1; i++) {
      const p1 = points[i];
      const p2 = points[i + 1];
      if (t >= p1.t && t <= p2.t) {
        const frac = (t - p1.t) / (p2.t - p1.t);
        // Smooth cosine S-curve
        const smooth = (1 - Math.cos(frac * Math.PI)) / 2;
        return p1.v + (p2.v - p1.v) * smooth;
      }
    }
    return 0.3;
  }

  /**
   * Calculate crowd density for all 36 campus buildings at a given decimal hour [0 - 24]
   * @param {number} hour Decimal hour of the day (e.g. 13.5 = 1:30 PM)
   * @returns {Map<string, number>} Map of buildingKey -> density [0.0 - 1.0]
   */
  calculateDensitiesForHour(hour) {
    const clampedHour = Math.max(0, Math.min(24, Number(hour) || 12));
    const densityMap = new Map();

    Object.entries(this.buildingCategories).forEach(([key, category]) => {
      const curve = this.curves[category] || this.curves.academic;
      const baseValue = this.interpolate(curve, clampedHour);

      // Add small individual building variance (±6%) for natural visual diversity
      const variance = ((this.hashBuilding(key) % 13) - 6) / 100;
      const finalDensity = Math.max(0.04, Math.min(0.98, baseValue + variance));

      densityMap.set(key, Math.round(finalDensity * 100) / 100);
    });

    return densityMap;
  }

  /**
   * Get macro summary of category percentages for UI badges
   */
  getCategorySummary(hour) {
    const clampedHour = Math.max(0, Math.min(24, Number(hour) || 12));
    return {
      academic: Math.round(this.interpolate(this.curves.academic, clampedHour) * 100),
      hostel: Math.round(this.interpolate(this.curves.hostel, clampedHour) * 100),
      commons: Math.round(this.interpolate(this.curves.commons, clampedHour) * 100),
      sports: Math.round(this.interpolate(this.curves.sports, clampedHour) * 100)
    };
  }

  /**
   * Format decimal hour into a friendly display string (e.g. 13.5 -> "01:30 PM")
   */
  formatHour(hour) {
    const h = Math.floor(hour);
    const m = Math.round((hour - h) * 60);
    const period = h >= 12 ? 'PM' : 'AM';
    const displayH = h % 12 === 0 ? 12 : h % 12;
    const strH = String(displayH).padStart(2, '0');
    const strM = String(m).padStart(2, '0');
    return `${strH}:${strM} ${period}`;
  }

  /**
   * Get contextual description of the current temporal state
   */
  getScheduleDescription(hour) {
    if (hour >= 8 && hour < 12) {
      return 'Morning Classes: High occupancy across Academic Blocks & Labs; Hostels transitioning to low.';
    }
    if (hour >= 12 && hour < 15.5) {
      return 'Afternoon Lunch & Break: High concentration at North Square & Gazebo; Hostels low.';
    }
    if (hour >= 15.5 && hour < 19.5) {
      return 'Evening Recreation: Peak density across sports grounds & courts; Academic blocks dispersing.';
    }
    if (hour >= 19.5 && hour < 23) {
      return 'Night Return: Hostels rising to high; Academic and recreation areas closed/minimal.';
    }
    return 'Overnight Curfew: Campus operations quiet; Peak residential concentration in hostels.';
  }
}

