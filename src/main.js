import { CampusScene } from './scene.js';
import { WayfinderGraph } from './graph.js';
import { NavigationView } from './navigationView.js';
import { TwinSimulationEngine } from './twinSimulation.js';
import { UIController } from './ui.js';

async function bootstrap() {
  const canvasContainer = document.getElementById('canvas-container');
  const isDebug = new URLSearchParams(window.location.search).get('debug') === 'true';

  // Helper to reliably update the loading screen DOM from anywhere in the lifecycle
  function updateLoadingScreen({ percent, statusText, indeterminate = false, subText = null }) {
    const loadingBar = document.getElementById('loading-bar');
    const loadingPercent = document.getElementById('loading-percent');
    const loadingText = document.getElementById('loading-text');
    const loadingSub = document.getElementById('loading-sub');
    const loadingOverlay = document.getElementById('loading-overlay');

    if (loadingBar) {
      if (indeterminate) {
        loadingBar.classList.add('indeterminate');
        loadingBar.style.width = '100%';
      } else {
        loadingBar.classList.remove('indeterminate');
        const safe = Math.max(0, Math.min(100, Number(percent) || 0));
        loadingBar.style.width = `${safe}%`;
      }
    }

    if (loadingPercent) {
      if (indeterminate) {
        loadingPercent.textContent = '...';
      } else if (percent !== null && percent !== undefined) {
        loadingPercent.textContent = `${Math.round(percent)}%`;
      }
    }

    if (loadingText && statusText) {
      loadingText.textContent = statusText;
    }

    if (loadingSub && subText) {
      loadingSub.textContent = subText;
    }

    if (!indeterminate && percent !== null && percent >= 100) {
      setTimeout(() => {
        if (loadingOverlay) {
          loadingOverlay.classList.add('fade-out');
          setTimeout(() => loadingOverlay.remove(), 600);
        }
      }, 400);
    }
  }

  // 1. Initialize Wayfinder Graph
  const graph = new WayfinderGraph();
  let scene = null;

  updateLoadingScreen({
    percent: 5,
    statusText: 'Loading campus topology datasets...'
  });

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

  updateLoadingScreen({
    percent: 15,
    statusText: 'Connecting to 3D campus model repository...'
  });

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
      if (p.lengthComputable && p.total && p.total > 0) {
        // Deterministic byte progress (e.g. Content-Length present)
        const downloadFraction = Math.min(1, p.loaded / p.total);
        // Map 0-100% of download to 15% - 88% overall progress (reserving 88-100% for parsing and setup)
        const displayPercent = Math.min(88, Math.round(15 + downloadFraction * 73));
        const loadedMb = (p.loaded / (1024 * 1024)).toFixed(1);
        const totalMb = (p.total / (1024 * 1024)).toFixed(1);
        const downloadPct = Math.round(downloadFraction * 100);

        updateLoadingScreen({
          percent: displayPercent,
          statusText: `Downloading 3D Campus Geometry (${loadedMb} MB / ${totalMb} MB • ${downloadPct}%)...`,
          indeterminate: false,
          subText: `${loadedMb} / ${totalMb} MB (${downloadPct}%) • 1:1 Metric Coordinate Frame`
        });
      } else {
        // Indeterminate progress (e.g. chunked transfer or unknown total length)
        const loadedMb = (p.loaded / (1024 * 1024)).toFixed(1);
        updateLoadingScreen({
          percent: null,
          statusText: `Downloading 3D Campus Geometry (${loadedMb} MB downloaded)...`,
          indeterminate: true,
          subText: `${loadedMb} MB received • S3 Static Website Storage`
        });
      }

      if (ui) {
        ui.updateLoading(
          p.lengthComputable ? Math.round(15 + (p.loaded / p.total) * 73) : null,
          p.lengthComputable
            ? `Downloading 3D Campus Geometry (${(p.loaded / 1048576).toFixed(1)} MB / ${(p.total / 1048576).toFixed(1)} MB)...`
            : `Downloading 3D Campus Geometry (${(p.loaded / 1048576).toFixed(1)} MB downloaded)...`,
          !p.lengthComputable
        );
      }
    },
    onParsing: () => {
      updateLoadingScreen({
        percent: 92,
        statusText: 'Parsing & Indexing 3D Campus Meshes...',
        indeterminate: false,
        subText: 'Processing geometry buffers & material nodes'
      });
      if (ui) {
        ui.updateLoading(92, 'Parsing & Indexing 3D Campus Meshes...');
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

      
      // Initialize baseline simulated crowd density across campus buildings via temporal model
      ui.applyTemporalHour(ui.currentTemporalHour, true);
      scene.setHeatmapEnabled(false);

      if (isDebug) {
        console.log(`[DEBUG] Temporal crowd density initialized for ${scene.buildingMeshes.size} buildings.`);
      }


      // Finish loading bar and select Auditorium WITHOUT moving the camera,
      // preserving the initial full-campus framed overview
      updateLoadingScreen({
        percent: 100,
        statusText: 'Campus 3D Twin Ready!',
        indeterminate: false,
        subText: `${buildingsFound} building structures initialized`
      });
      ui.updateLoading(100, 'Campus 3D Twin Ready!');

      setTimeout(() => {
        ui.selectBuilding('Building024', false);
      }, 500);
    },
    onError: (err) => {
      console.error('Error loading campus GLB:', err);
      const loadingBar = document.getElementById('loading-bar');
      if (loadingBar) {
        loadingBar.classList.remove('indeterminate');
        loadingBar.style.width = '100%';
        loadingBar.style.background = '#ef4444';
      }
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
