import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np

os.makedirs('docs/figures', exist_ok=True)

# -------------------------------------------------------------
# 1. System Architecture Diagram (High-Res Schematic)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(12, 8), dpi=300)
ax.axis('off')

# Style parameters
box_bg = '#F8FAFC'
edge_color = '#1E293B'
primary_color = '#0284C7'    # Sky Blue
accent_orange = '#EA580C'    # Orange
accent_green = '#16A34A'     # Green
accent_purple = '#9333EA'    # Purple
accent_red = '#DC2626'       # Red

def draw_box(ax, x, y, w, h, title, subtitle, bg_color='#FFFFFF', border_color='#334155', title_color='#0F172A'):
    rect = patches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.03",
                                  facecolor=bg_color, edgecolor=border_color, linewidth=1.5, zorder=2)
    ax.add_patch(rect)
    ax.text(x + w/2, y + h*0.65, title, ha='center', va='center', fontsize=9.5, fontweight='bold', color=title_color, zorder=3)
    ax.text(x + w/2, y + h*0.35, subtitle, ha='center', va='center', fontsize=7.5, color='#475569', zorder=3)

def draw_arrow(ax, x1, y1, x2, y2, label='', color='#475569', rad=0.0, linestyle='-'):
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="->", color=color, lw=1.5,
                                connectionstyle=f"arc3,rad={rad}", linestyle=linestyle), zorder=4)
    if label:
        mid_x, mid_y = (x1 + x2)/2, (y1 + y2)/2
        ax.text(mid_x, mid_y + 0.025, label, ha='center', va='center', fontsize=7,
                fontweight='semibold', color=color, bbox=dict(boxstyle="round,pad=0.15", fc='#FFFFFF', ec='none', alpha=0.85), zorder=5)

# Outer group boundaries
groups = [
    (0.03, 0.58, 0.24, 0.38, "1. Edge & Telemetry Sources", '#F1F5F9', '#94A3B8'),
    (0.33, 0.58, 0.32, 0.38, "2. Cloud Ingestion & Edge Delivery", '#F1F5F9', '#94A3B8'),
    (0.70, 0.58, 0.27, 0.38, "3. Serverless Compute Layer", '#F1F5F9', '#94A3B8'),
    (0.33, 0.05, 0.64, 0.46, "4. Persistence & Observability Layer", '#F1F5F9', '#94A3B8'),
]

for gx, gy, gw, gh, gtitle, gbg, gborder in groups:
    rect = patches.FancyBboxPatch((gx, gy), gw, gh, boxstyle="round,pad=0.01,rounding_size=0.02",
                                  facecolor=gbg, edgecolor=gborder, linewidth=1.2, linestyle='--', zorder=1)
    ax.add_patch(rect)
    ax.text(gx + 0.015, gy + gh - 0.03, gtitle, fontsize=8.5, fontweight='bold', color='#334155', zorder=2)

# Group 1: Sources
draw_box(ax, 0.05, 0.79, 0.20, 0.12, "IoT Sensor Simulator\n(Edge PowerShell)", "publish_sensor_sim.ps1\nMQTT TLS / Port 8883", '#FEF2F2', accent_red, accent_red)
draw_box(ax, 0.05, 0.62, 0.20, 0.12, "Browser 3D Twin Client\n(Three.js / WebGL)", "TwinSimulationEngine\nUI Slider / Presets", '#F0FDF4', accent_green, accent_green)

# Group 2: Ingestion & Delivery
draw_box(ax, 0.35, 0.79, 0.28, 0.12, "AWS IoT Core & Rule Engine", "Topic: vit/campus/Building024/telemetry\nRule: vit_campus_telemetry_rule", '#EFF6FF', primary_color, primary_color)
draw_box(ax, 0.35, 0.62, 0.13, 0.12, "Amazon API Gateway\n(HTTP API v2)", "vit-telemetry-api\nRate: 10/s, Burst: 20", '#FAF5FF', accent_purple, accent_purple)
draw_box(ax, 0.50, 0.62, 0.13, 0.12, "Amazon CloudFront\n& S3 Origin Bucket", "d457wl1fwy7gg.cloudfront.net\nOAC Security / Assets", '#F0FDF4', accent_green, accent_green)

# Group 3: Compute
draw_box(ax, 0.72, 0.68, 0.23, 0.20, "AWS Lambda Function\n(vit-telemetry-handler)", "Runtime: Node.js 22.x | arm64\nServer-Authoritative Validation\nUtilization & Threshold Engine\nisSimulated: true Injection", '#FFFBEB', '#D97706', '#92400E')

# Group 4: Storage & Monitoring
draw_box(ax, 0.36, 0.12, 0.28, 0.32, "Amazon DynamoDB (vit-campus-telemetry)", "Composite Key: PK=venueId | SK=sk\n\n- Hot State Record (sk: 'LATEST')\n- Time-Series Audit (sk: 'TS#<ISO>')\n- Atomic TransactWriteItems\n- Automatic TTL (7 Days on ttl_epoch)", '#F8FAFC', '#0284C7', '#0369A1')
draw_box(ax, 0.68, 0.12, 0.26, 0.32, "Amazon CloudWatch Observability", "- Log Group: /aws/lambda/vit-...\n- Metric Filter: HighOccupancyAlerts\n- Metric: HighOccupancyAlerts (Count)\n- Alarms: Lambda Errors, Throttles,\n  High Occupancy (>=1)\n- Dashboard: vit-campus-digital-twin", '#FDF2F8', '#BE185D', '#9D174D')

# Draw connections
# Path B: IoT Simulator -> IoT Core -> Lambda
draw_arrow(ax, 0.25, 0.85, 0.35, 0.85, "MQTT Pub (Path B)", accent_red)
draw_arrow(ax, 0.63, 0.85, 0.72, 0.82, "iot.amazonaws.com invoke", primary_color)

# Path A: Browser -> API Gateway -> Lambda
draw_arrow(ax, 0.25, 0.68, 0.35, 0.68, "HTTP POST (Path A)", accent_green)
draw_arrow(ax, 0.48, 0.68, 0.72, 0.73, "Proxy Integration", accent_purple)

# Browser <-> CloudFront
draw_arrow(ax, 0.25, 0.64, 0.50, 0.64, "HTTPS Static Assets / GLB", accent_green, rad=0.15)

# Lambda -> DynamoDB
draw_arrow(ax, 0.78, 0.68, 0.52, 0.44, "Atomic TransactWrite (2 Puts)", primary_color, rad=-0.1)

# Lambda -> CloudWatch
draw_arrow(ax, 0.84, 0.68, 0.81, 0.44, "Structured Logs & Metrics", '#BE185D')

# CloudWatch Filter to Metric
ax.text(0.50, 0.02, "VIT Chennai Campus AI Digital Twin - End-to-End Serverless Cloud Architecture",
        ha='center', va='bottom', fontsize=11, fontweight='bold', color='#1E293B')

plt.tight_layout()
fig.savefig('docs/figures/fig01_system_architecture.png', dpi=300, bbox_inches='tight')
plt.close(fig)
print("Generated fig01_system_architecture.png")


# -------------------------------------------------------------
# 2. Occupancy Scenario Comparison Chart
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8, 5), dpi=300)

scenarios = ['Normal Operations', 'Convocation / High Rush', 'Critical Overcapacity']
occupancies = [1480, 2150, 2450]
colors = ['#10B981', '#F97316', '#EF4444']

bars = ax.bar(scenarios, occupancies, color=colors, width=0.45, edgecolor='#334155', linewidth=1.2, zorder=3)

# Capacity and Threshold Lines
ax.axhline(2400, color='#DC2626', linestyle='--', linewidth=1.8, label='Max Design Capacity (2,400 seats)', zorder=4)
ax.axhline(1920, color='#EA580C', linestyle=':', linewidth=1.8, label='80% Safety Warning Threshold (1,920 seats)', zorder=4)
ax.axhline(1200, color='#FBBF24', linestyle='-.', linewidth=1.2, label='50% Moderate Threshold (1,200 seats)', zorder=4)

for bar in bars:
    yval = bar.get_height()
    pct = round((yval / 2400) * 100, 1)
    ax.text(bar.get_x() + bar.get_width()/2, yval + 40, f"{yval:,} seats\n({pct}%)",
            ha='center', va='bottom', fontsize=9.5, fontweight='bold', color='#1E293B', zorder=5)

ax.set_ylabel('Auditorium Occupancy (Headcount)', fontsize=10.5, fontweight='bold', color='#1E293B')
ax.set_title('Demonstration Scenario Occupancies vs. Operational Thresholds\n(Venue: Mahatma Gandhi Auditorium - Building024, Capacity: 2,400)',
             fontsize=11, fontweight='bold', pad=15, color='#0F172A')
ax.set_ylim(0, 2800)
ax.grid(axis='y', linestyle='--', alpha=0.5, zorder=0)
ax.legend(loc='upper left', frameon=True, fontsize=8.5)

plt.tight_layout()
fig.savefig('docs/figures/fig02_occupancy_scenarios.png', dpi=300, bbox_inches='tight')
plt.close(fig)
print("Generated fig02_occupancy_scenarios.png")


# -------------------------------------------------------------
# 3. Utilization & Safety Tiers Chart
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8, 4.8), dpi=300)

tiers = ['Low Nominal\n(<50%)', 'Moderate Steady\n(50% - 79.9%)', 'High Near-Capacity\n(80% - 100%)', 'Overcapacity\n(>100%)']
tier_ranges = [49.9, 29.9, 20.0, 15.0]
start_ranges = [0, 50, 80, 100]
tier_colors = ['#10B981', '#EAB308', '#F97316', '#EF4444']

# Plot test points
test_scenarios = ['Baseline Seed', 'Normal Scenario', 'High Scenario (Verified)', 'Overcrowded Preset']
test_utils = [35.0, 61.7, 89.6, 102.1]
test_colors = ['#059669', '#CA8A04', '#EA580C', '#DC2626']

bars = ax.barh(test_scenarios, test_utils, color=test_colors, height=0.45, edgecolor='#1E293B', linewidth=1.2, zorder=3)

ax.axvline(50, color='#CA8A04', linestyle=':', linewidth=1.5, label='Moderate Threshold (50%)', zorder=4)
ax.axvline(80, color='#EA580C', linestyle='--', linewidth=1.8, label='High Alarm Threshold (80%)', zorder=4)
ax.axvline(100, color='#DC2626', linestyle='-', linewidth=2.0, label='Max Capacity Limit (100%)', zorder=4)

for bar in bars:
    xval = bar.get_width()
    ax.text(xval + 1.2, bar.get_y() + bar.get_height()/2, f"{xval:.1f}%",
            ha='left', va='center', fontsize=9.5, fontweight='bold', color='#0F172A', zorder=5)

ax.set_xlabel('Venue Capacity Utilization (%)', fontsize=10.5, fontweight='bold', color='#1E293B')
ax.set_title('Server-Authoritative Safety Tier Classification Across Scenarios\nFormula: Utilization = Round( (Occupancy / Capacity) * 100, 1 )',
             fontsize=11, fontweight='bold', pad=15, color='#0F172A')
ax.set_xlim(0, 120)
ax.grid(axis='x', linestyle='--', alpha=0.5, zorder=0)
ax.legend(loc='lower right', frameon=True, fontsize=8.5)

plt.tight_layout()
fig.savefig('docs/figures/fig03_utilization_tiers.png', dpi=300, bbox_inches='tight')
plt.close(fig)
print("Generated fig03_utilization_tiers.png")


# -------------------------------------------------------------
# 4. End-to-End Latency Breakdown Chart
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8.5, 4.8), dpi=300)

steps = [
    'Step 1: CloudFront CDN Reachability',
    'Step 2: MQTT Publish via AWS IoT Core',
    'Step 3: DynamoDB Polling & Ingestion',
    'Step 4: CloudWatch Log Retrieval',
    'Script Execution & Init Overhead'
]
durations_ms = [420, 185, 1420, 1180, 4675]   # Total = 7880 ms (7.88s observed)
step_colors = ['#0284C7', '#6366F1', '#10B981', '#F59E0B', '#94A3B8']

y_pos = np.arange(len(steps))
bars = ax.barh(y_pos, [d/1000 for d in durations_ms], color=step_colors, height=0.5, edgecolor='#1E293B', linewidth=1.1, zorder=3)

for bar in bars:
    w = bar.get_width()
    ax.text(w + 0.08, bar.get_y() + bar.get_height()/2, f"{w:.2f} s ({int(w*1000)} ms)",
            ha='left', va='center', fontsize=9, fontweight='bold', color='#1E293B', zorder=5)

ax.set_yticks(y_pos)
ax.set_yticklabels(steps, fontsize=9.5, fontweight='semibold')
ax.invert_yaxis()
ax.set_xlabel('Observed Duration (Seconds)', fontsize=10.5, fontweight='bold', color='#1E293B')
ax.set_title('Observed Latency Breakdown: Live High-Scenario Execution Run\n(Total Elapsed Time: 7.88 seconds | scripts/demo.ps1 -Demo -Scenario High)',
             fontsize=11, fontweight='bold', pad=15, color='#0F172A')
ax.set_xlim(0, 5.8)
ax.grid(axis='x', linestyle='--', alpha=0.5, zorder=0)

plt.tight_layout()
fig.savefig('docs/figures/fig04_e2e_latency_breakdown.png', dpi=300, bbox_inches='tight')
plt.close(fig)
print("Generated fig04_e2e_latency_breakdown.png")


# -------------------------------------------------------------
# 5. Egress Discharge Curve (Evacuation Calculation)
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(8, 4.8), dpi=300)

occ_range = np.linspace(500, 2600, 100)
# Formula from src/twinSimulation.js:
# activeLanes = 6 double-door portals
# dischargeRatePerLane = 70 persons/min
# totalDischargeRate = 6 * 70 = 420 persons/min
discharge_rate = 420.0
egress_minutes = occ_range / discharge_rate

ax.plot(occ_range, egress_minutes, color='#0284C7', linewidth=2.5, label='Egress Discharge Model (6 Double-Doors @ 420 p/min)', zorder=3)

# Mark key scenarios
test_points = [
    (1480, 1480/discharge_rate, 'Normal (1,480 seats): 3.52 min (3m 31s)', '#10B981'),
    (1920, 1920/discharge_rate, '80% Warning (1,920 seats): 4.57 min (4m 34s)', '#EA580C'),
    (2150, 2150/discharge_rate, 'High Scenario (2,150 seats): 5.12 min (5m 07s)', '#F97316'),
    (2400, 2400/discharge_rate, 'Max Capacity (2,400 seats): 5.71 min (5m 43s)', '#DC2626')
]

for occ, t, lbl, c in test_points:
    ax.scatter(occ, t, color=c, s=65, zorder=5, edgecolor='#1E293B', linewidth=1.2)
    ax.annotate(lbl, (occ, t), textcoords="offset points", xytext=(-20, 12 if occ < 2000 else -20),
                fontsize=8.5, fontweight='bold', color=c,
                bbox=dict(boxstyle="round,pad=0.2", fc='#FFFFFF', ec=c, lw=1, alpha=0.9), zorder=6)

ax.set_xlabel('Auditorium Occupancy (Persons)', fontsize=10.5, fontweight='bold', color='#1E293B')
ax.set_ylabel('Calculated Egress Time (Minutes)', fontsize=10.5, fontweight='bold', color='#1E293B')
ax.set_title('Topological Evacuation Egress Time vs. Venue Occupancy\nModel: t = N / (Lanes × FlowRate) [Mahatma Gandhi Auditorium - 6 Emergency Portals]',
             fontsize=11, fontweight='bold', pad=15, color='#0F172A')
ax.set_xlim(400, 2700)
ax.set_ylim(1, 7)
ax.grid(True, linestyle='--', alpha=0.5, zorder=0)
ax.legend(loc='upper left', frameon=True, fontsize=9)

plt.tight_layout()
fig.savefig('docs/figures/fig05_egress_discharge_model.png', dpi=300, bbox_inches='tight')
plt.close(fig)
print("Generated fig05_egress_discharge_model.png")
