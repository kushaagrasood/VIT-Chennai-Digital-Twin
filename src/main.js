import { CampusScene } from './scene.js';
import { WayfinderGraph } from './graph.js';
import { NavigationView } from './navigationView.js';
import { TwinSimulationEngine } from './twinSimulation.js';
import { UIController } from './ui.js';

async function bootstrap() {
  const canvasContainer = document.getElementById('canvas-container');
  const isDebug = new URLSearchParams(window.location.search).get('debug') === 'true';

  // 1. Initialize Wayfinder Graph
  const graph = new WayfinderGraph();
  let scene = null;

  // 2. Fetch and parse Wayfinder datasets with resilient fallback
  let dataLoaded = false;
  try {
    const [waypointsRes, entrancesRes, oneWayRes] = await Promise.all([
      fetch('/waypoints.json'),
      fetch('/buildingEntrances.json'),
      fetch('/oneWayRoads.json')
    ]);

    if (waypointsRes.ok && entrancesRes.ok && oneWayRes.ok) {
      const rawWaypoints = await waypointsRes.json();
      const rawEntrances = await entrancesRes.json();
      const rawOneWayRoads = await oneWayRes.json();

      
      graph.loadWaypoints(rawWaypoints);
      graph.buildGraph(rawOneWayRoads);
      graph.loadBuildingEntrances(rawEntrances);
      if (scene) scene.setGraph(graph);

      
      // Diagnostic tests enabled only in debug mode (?debug=true)
      if (isDebug) {
        console.log('[DEBUG] Testing alternative route algorithm...');
        if (typeof graph.findAlternativePaths === 'function') {
          const routes = graph.findAlternativePaths('199', '33', 3);
          console.table(
            routes.map((route, index) => ({
              route: index + 1,
              distance: `${route.distanceMeters} m`,
              waypointCount: route.path.length,
              path: route.path.join(' -> ')
            }))
          );
        }

        const gates = [
          { name: 'Main Gate - Entrance 1', id: '111' },
          { name: 'Main Gate - Entrance 2', id: '188' },
          { name: '2nd Gate', id: '33' }
        ];

        console.table(
          gates.map(gate => ({
            gate: gate.name,
            waypointId: gate.id,
            exists: graph.waypoints.has(gate.id),
            neighborCount: (graph.adjacency.get(gate.id) || new Set()).size
          }))
        );

        if (typeof graph.getCampusEvacuationRoutes === 'function') {
          const campusRoutes = graph.getCampusEvacuationRoutes(['111', '188', '33']);
          const reachableCount = campusRoutes.filter(b => b.nearestExit).length;
          console.log(`[DEBUG] Campus evacuation reachability: ${reachableCount} / ${campusRoutes.length} buildings.`);
        }
      }

      dataLoaded = true;
      console.log('Wayfinder datasets loaded via primary JSON endpoints.');

    }
  } catch (err) {
    console.warn('Direct dataset fetch failed, attempting path.json fallback:', err);
  }

  // Fallback to consolidated path.json if direct fetch encountered an issue
  if (!dataLoaded) {
    try {
      const pathRes = await fetch('/path.json');
      if (pathRes.ok) {
        const pathData = await pathRes.json();
        graph.loadWaypoints(pathData.waypoints);
        graph.buildGraph(pathData.oneWayRoads);
        graph.loadBuildingEntrances(pathData.buildingEntrances);
        if (scene) scene.setGraph(graph);
        dataLoaded = true;
        console.log('Wayfinder data successfully loaded from fallback /path.json');
      }
    } catch (fallbackErr) {
      console.error('All Wayfinder dataset loading attempts failed:', fallbackErr);
    }
  }

  // 3. Initialize Twin Simulation Engine for Mahatma Gandhi Auditorium (Building024)
  const twinEngine = new TwinSimulationEngine({
    capacity: 2400,
    moderateThreshold: 50,
    highThreshold: 80,
    initialOccupancy: 1480,
    isLive: true
  });

  // 4. Initialize Three.js 3D Campus Scene
  let ui = null;
  let navView = null;

  scene = new CampusScene(canvasContainer, {
    graph,
    getBuildingDisplayName: (key) => graph.buildings.get(key)?.displayName,
    onProgress: (p) => {
      if (ui) {
        ui.updateLoading(
          Math.min(95, Math.round(p.percent * 0.95)),
          `Loading 3D Campus Geometry (${(p.loaded / (1024 * 1024)).toFixed(1)} MB / 20.3 MB)...`
        );
      }
    },
    onLoaded: ({ buildingsFound }) => {
      console.log(`GLB Loaded: Found ${buildingsFound} building meshes.`);

      // Create Navigation View overlay once scene is ready
      navView = new NavigationView(scene.scene, graph);

      // Register navView update loop into scene animation
      const originalAnimate = scene.animate;
      scene.animate = () => {
        if (navView) {
          navView.update(scene.clock.getElapsedTime());
        }
        originalAnimate();
      };

      // Connect UI controller
      ui = new UIController({
        scene,
        graph,
        navView,
        twinEngine
      });

      // Expose to window for testing/verification
      window.__campusScene = scene;
      window.__wayfinderGraph = graph;
      window.__twinEngine = twinEngine;
      window.__ui = ui;
      window.__navView = navView;

      
      // Initialize baseline simulated crowd density across campus buildings
      const buildingDensities = new Map();
      const buildingKeys = [...scene.buildingMeshes.keys()];

      buildingKeys.forEach((key, index) => {
        // Stable, varied demonstration values between 10% and 95%
        const density = 0.10 + (((index * 37 + 17) % 86) / 100);
        buildingDensities.set(key, density);
      });

      // Synchronize auditorium density with the live telemetry state
      const twinState = twinEngine.getState();
      const auditoriumDensity = Math.max(
        0,
        Math.min(1, twinState.occupancy / twinState.capacity)
      );

      if (buildingDensities.has('Building024')) {
        buildingDensities.set('Building024', auditoriumDensity);
      }

      scene.setBuildingCrowdDensities(buildingDensities);
      scene.setHeatmapEnabled(false);

      if (isDebug) {
        console.log(`[DEBUG] Hover density initialized for ${buildingDensities.size} buildings.`);
      }


      // Finish loading bar and select Auditorium WITHOUT moving the camera,
      // preserving the initial full-campus framed overview
      ui.updateLoading(100, 'Campus 3D Twin Ready!');
      setTimeout(() => {
        ui.selectBuilding('Building024', false);
      }, 500);
    },
    onError: (err) => {
      console.error('Error loading campus GLB:', err);
      const loadingText = document.getElementById('loading-text');
      const loadingOverlay = document.getElementById('loading-overlay');
      if (loadingText) {
        loadingText.innerHTML = `
          <div style="color: #ef4444; margin-bottom: 12px;">
            <strong>Unable to load 3D campus model (/vit_map.glb)</strong><br>
            <small style="color: #cbd5e1;">${err.message || 'Asset fetch or WebGL decoding failed'}</small>
          </div>
          <div style="display: flex; gap: 10px; justify-content: center; margin-top: 14px;">
            <button id="btn-retry-glb" style="background: #0284c7; color: white; border: none; padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 0.8rem;">Retry Loading</button>
            <button id="btn-data-mode" style="background: rgba(255,255,255,0.15); color: white; border: 1px solid rgba(255,255,255,0.2); padding: 6px 14px; border-radius: 6px; cursor: pointer; font-size: 0.8rem;">Data-Only Mode</button>
          </div>
        `;

        document.getElementById('btn-retry-glb')?.addEventListener('click', () => {
          location.reload();
        });

        document.getElementById('btn-data-mode')?.addEventListener('click', () => {
          if (!ui) {
            navView = new NavigationView(scene.scene, graph);
            ui = new UIController({ scene, graph, navView, twinEngine });
            window.__campusScene = scene;
            window.__wayfinderGraph = graph;
            window.__twinEngine = twinEngine;
            window.__ui = ui;
            ui.selectBuilding('Building024', false);
          }
          if (loadingOverlay) {
            loadingOverlay.classList.add('fade-out');
            setTimeout(() => loadingOverlay.remove(), 400);
          }
        });
      }
    }
  });

  // Start model loading
  scene.loadCampusModel('/vit_map.glb');
}

// Launch application
window.addEventListener('DOMContentLoaded', bootstrap);
