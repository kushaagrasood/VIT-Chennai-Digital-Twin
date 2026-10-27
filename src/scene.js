import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';

export class CampusScene {
  constructor(canvasContainer, options = {}) {
    this.container = canvasContainer;
    this.graph = options.graph || null;
    this.callbacks = {
      onProgress: options.onProgress || (() => {}),
      onLoaded: options.onLoaded || (() => {}),
      onError: options.onError || (() => {}),
      onBuildingClick: options.onBuildingClick || (() => {}),
      onBuildingHover: options.onBuildingHover || (() => {}),
      getBuildingDisplayName: options.getBuildingDisplayName || null
    };

    // State
    this.isDebug = typeof window !== 'undefined' && window.location
      ? new URLSearchParams(window.location.search).get('debug') === 'true'
      : false;
    this.buildingMeshes = new Map(); // normalizedKey -> Mesh/Object3D
    this.selectedBuildingMesh = null;
    this.originalMaterials = new Map();
    this.hoveredBuildingKey = null;
    this.heatmapEnabled = false;
    this.buildingCrowdDensities = new Map();
    this.heatmapMaterials = new Map();
    this.highlightMaterials = new Map();

    // Camera animation state
    this.isTransitioningCamera = false;
    this.cameraAnim = null;

    // Default frame state
    this.defaultCameraPos = new THREE.Vector3(0, 750, 1050);
    this.defaultTarget = new THREE.Vector3(0, 0, 0);

    this.init();
  }

  init() {
    const width = this.container.clientWidth || window.innerWidth;
    const height = this.container.clientHeight || window.innerHeight;

    // 1. Scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x0a0f1d);
    // Gentle linear fog starting well beyond campus framing distance
    this.scene.fog = new THREE.Fog(0x0a0f1d, 1800, 6500);

    // 2. Camera
    this.camera = new THREE.PerspectiveCamera(45, width / height, 1, 10000);
    this.camera.position.copy(this.defaultCameraPos);

    // 3. Renderer
    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      powerPreference: 'high-performance',
      alpha: false
    });
    this.renderer.setSize(width, height);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.15;
    this.container.appendChild(this.renderer.domElement);
    
    // Floating crowd-density popup (hidden until hovering a building)
    this.densityPopup = document.createElement('div');

    Object.assign(this.densityPopup.style, {
      position: 'fixed',
      display: 'none',
      zIndex: '10000',
      width: '220px',
      maxWidth: 'calc(100vw - 20px)',
      boxSizing: 'border-box',
      padding: '12px 14px',
      borderRadius: '12px',
      background: 'rgba(10, 15, 29, 0.96)',
      border: '1px solid rgba(148, 163, 184, 0.35)',
      boxShadow: '0 12px 32px rgba(0, 0, 0, 0.35)',
      color: '#f8fafc',
      fontFamily: 'Arial, sans-serif',
      fontSize: '12px',
      lineHeight: '1.5',
      pointerEvents: 'none',
      backdropFilter: 'blur(10px)'
    });

    document.body.appendChild(this.densityPopup);


    // 4. Controls
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.05;
    this.controls.screenSpacePanning = false;
    this.controls.minDistance = 15;
    this.controls.maxDistance = 4500;
    this.controls.maxPolarAngle = Math.PI / 2 - 0.02; // Keep camera above ground
    this.controls.target.copy(this.defaultTarget);

    // 5. Lighting
    this.setupLighting();

    // 6. Subtle Ground Grid
    this.setupGroundHelpers();

    // 7. Raycaster
    this.raycaster = new THREE.Raycaster();
    this.mouse = new THREE.Vector2(-999, -999);
    this.setupInteractions();

    // 8. Resize Listener
    this.onWindowResize = this.onWindowResize.bind(this);
    window.addEventListener('resize', this.onWindowResize);

    // 9. Render Loop
    this.animate = this.animate.bind(this);
    this.clock = new THREE.Clock();
    requestAnimationFrame(this.animate);
  }

  setupLighting() {
    // Ambient light
    const ambient = new THREE.AmbientLight(0xffffff, 0.9);
    this.scene.add(ambient);

    // Hemisphere light (sky vs ground tint)
    const hemiLight = new THREE.HemisphereLight(0xbad2ff, 0x1f293d, 0.85);
    hemiLight.position.set(0, 500, 0);
    this.scene.add(hemiLight);

    // Sun directional light
    const sunLight = new THREE.DirectionalLight(0xfff5ea, 1.6);
    sunLight.position.set(400, 800, 450);
    this.scene.add(sunLight);

    // Fill light
    const fillLight = new THREE.DirectionalLight(0x7399db, 0.6);
    fillLight.position.set(-400, 400, -350);
    this.scene.add(fillLight);
  }

  setupGroundHelpers() {
    // Grid helper covering campus area
    const grid = new THREE.GridHelper(3000, 60, 0x1e293b, 0x141e2e);
    grid.position.y = -1.5;
    this.scene.add(grid);
  }

  /**
   * Load the campus 3D GLB model with progress and error handling
   */
  loadCampusModel(glbUrl = '/vit_map.glb') {
    const loader = new GLTFLoader();

    loader.load(
      glbUrl,
      (gltf) => {
        this.campusRoot = gltf.scene;
        this.scene.add(this.campusRoot);

        // Analyze and map building meshes
        this.processModelMeshes(gltf.scene);

        // Frame campus in view
        this.frameCampusView();

        if (this.callbacks.onLoaded) {
          this.callbacks.onLoaded({
            scene: gltf.scene,
            buildingsFound: this.buildingMeshes.size
          });
        }
      },
      (xhr) => {
        if (xhr.lengthComputable && xhr.total > 0) {
          const percent = Math.round((xhr.loaded / xhr.total) * 100);
          this.callbacks.onProgress({
            loaded: xhr.loaded,
            total: xhr.total,
            percent
          });
        } else {
          // Estimated fallback for chunked transfer
          this.callbacks.onProgress({
            loaded: xhr.loaded,
            total: 20313904, // 20.3MB vit_map.glb
            percent: Math.min(99, Math.round((xhr.loaded / 20313904) * 100))
          });
        }
      },
      (error) => {
        console.error('Failed to load campus GLB model:', error);
        if (this.callbacks.onError) {
          this.callbacks.onError(error);
        }
      }
    );
  }

  /**
   * Traverse model and index building meshes
   */
  processModelMeshes(root) {
    this.buildingMeshes.clear();
    this.clickableObjects = [];

    root.traverse((child) => {
      // Find building key by checking child and its parents
      let normKey = null;
      let matchingNode = null;
      let curr = child;

      while (curr && curr !== root) {
        normKey = this.normalizeBuildingName(curr.name);
        if (normKey) {
          matchingNode = curr;
          break;
        }
        curr = curr.parent;
      }

      if (normKey && child.isMesh) {
        child.userData.buildingKey = normKey;
        child.userData.rawMeshName = matchingNode ? matchingNode.name : child.name;

        // Optimize materials
        if (child.material) {
          child.material.roughness = 0.7;
          child.material.metalness = 0.1;
        }

        // Cache original material
        this.originalMaterials.set(child.uuid, child.material);
        this.buildingMeshes.set(normKey, child);
        this.clickableObjects.push(child);
      }
    });

    console.log(`Indexed ${this.buildingMeshes.size} building meshes in 3D scene.`);
  }

  normalizeBuildingName(name) {
    if (!name || typeof name !== 'string') return null;
    const trimmed = name.trim();
    if (trimmed === 'Main_Gate') return 'Main_Gate';
    if (trimmed === 'Gate') return 'Gate';
    if (trimmed === 'Building') return 'Building';

    // Handles 'Building.024', 'Building.001', 'Building024', etc.
    const match = trimmed.match(/^Building\.?(\d+)$/i);
    if (match) {
      return `Building${match[1]}`;
    }
    return null;
  }

  /**
   * Frame campus bounding box smoothly on initial load
   */
  frameCampusView() {
    if (!this.campusRoot) return;

    // Frame campus using the bounding box of building structures
    const buildingBbox = new THREE.Box3();
    let count = 0;
    this.buildingMeshes.forEach(mesh => {
      buildingBbox.expandByObject(mesh);
      count++;
    });

    const center = new THREE.Vector3();
    const size = new THREE.Vector3();

    if (count > 0) {
      buildingBbox.getCenter(center);
      buildingBbox.getSize(size);
    } else {
      const fullBbox = new THREE.Box3().setFromObject(this.campusRoot);
      fullBbox.getCenter(center);
      fullBbox.getSize(size);
    }

    const maxDim = Math.max(size.x, size.z, 600);
    const cameraDistance = maxDim * 0.85;
    const cameraHeight = maxDim * 0.65;

    this.defaultTarget.set(center.x, center.y + 10, center.z);
    this.defaultCameraPos.set(center.x, center.y + cameraHeight, center.z + cameraDistance);

    this.camera.position.copy(this.defaultCameraPos);
    this.controls.target.copy(this.defaultTarget);
    this.controls.update();

    console.log('Campus framed:', { center, size, defaultCameraPos: this.defaultCameraPos });
  }

  /**
   * Smoothly interpolate camera position and look-at target
   */
  animateCameraTo(targetPos, targetLookAt, duration = 1000) {
    this.isTransitioningCamera = true;
    this.cameraAnim = {
      startTime: performance.now(),
      duration: Math.max(100, duration),
      startPos: this.camera.position.clone(),
      targetPos: targetPos.clone(),
      startTarget: this.controls.target.clone(),
      targetLookAt: targetLookAt.clone()
    };
  }

  /**
   * Reset camera smoothly back to default campus overview
   */
  resetCamera(duration = 1000) {
    this.animateCameraTo(this.defaultCameraPos, this.defaultTarget, duration);
  }

  /**
   * Top-down plan view
   */
  setTopDownView(duration = 1000) {
    const topPos = new THREE.Vector3(
      this.defaultTarget.x,
      this.defaultTarget.y + 1400,
      this.defaultTarget.z + 0.1 // slight epsilon to avoid gimbal lock
    );
    this.animateCameraTo(topPos, this.defaultTarget, duration);
  }

  /**
   * Focus camera on a specific building
   */
  focusBuilding(buildingKey, duration = 1200) {
    const mesh = this.buildingMeshes.get(buildingKey);
    if (!mesh) {
      console.warn(`Mesh for building ${buildingKey} not found in 3D scene.`);
      return;
    }

    const bbox = new THREE.Box3().setFromObject(mesh);
    const center = new THREE.Vector3();
    const size = new THREE.Vector3();
    bbox.getCenter(center);
    bbox.getSize(size);

    const radius = Math.max(size.x, size.z, size.y, 35);
    const targetPos = new THREE.Vector3(
      center.x + radius * 1.4,
      center.y + radius * 1.1 + 25,
      center.z + radius * 1.5
    );

    this.highlightBuildingMesh(buildingKey);
    this.animateCameraTo(targetPos, center, duration);
  }

  /**
   * Focus camera on arbitrary position
   */
  focusPosition(pos, distance = 120, duration = 1000) {
    const targetPos = new THREE.Vector3(pos.x + distance, pos.y + distance * 0.8, pos.z + distance);
    const lookAt = new THREE.Vector3(pos.x, pos.y, pos.z);
    this.animateCameraTo(targetPos, lookAt, duration);
  }

  /**
   * Visually highlight a building mesh with emissive glow
   */
  
  highlightBuildingMesh(buildingKey) {
    this.selectedBuildingMesh = buildingKey
      ? this.buildingMeshes.get(buildingKey) || null
      : null;

    this.refreshBuildingAppearance();
  }

  
  
  updateHoverHeatmap(buildingKey) {
    // Restore the previous building's original appearance.
    if (this.hoveredHeatmapKey) {
      const previousMesh =
        this.buildingMeshes.get(this.hoveredHeatmapKey);

      if (previousMesh) {
        const original =
          this.originalMaterials.get(previousMesh.uuid);

        if (
          this.hoveredHeatmapKey ===
          this.selectedBuildingMesh?.userData.buildingKey
        ) {
          previousMesh.material =
            this.getHighlightMaterial(previousMesh) || original;
        } else {
          previousMesh.material = original;
        }
      }
    }

    this.hoveredHeatmapKey = null;
    this.hideDensityPopup();

    if (!buildingKey) return;

    const mesh = this.buildingMeshes.get(buildingKey);
    const density = this.buildingCrowdDensities.get(buildingKey);

    if (!mesh || density === undefined) return;

    const material = this.getHeatmapMaterial(mesh);
    if (!material) return;

    const color = this.getDensityColor(density);

    const applyColor = (mat) => {
      if (mat.color) mat.color.setHex(color);
      if (mat.emissive) {
        mat.emissive.setHex(color);
        mat.emissiveIntensity = 0.3;
      }
    };

    if (Array.isArray(material)) {
      material.forEach(applyColor);
    } else {
      applyColor(material);
    }

    mesh.material = material;
    this.hoveredHeatmapKey = buildingKey;

    this.showDensityPopup(
      buildingKey,
      this.lastPointerX ?? 0,
      this.lastPointerY ?? 0
    );
  }

  
  /**
   * Set or update graph reference dynamically
   */
  setGraph(graph) {
    this.graph = graph;
  }

  setDebugMode(enabled) {
    this.isDebug = Boolean(enabled);
  }

  /**
   * Update crowd-density value for an individual building.
   */
  setBuildingDensity(buildingKey, density) {
    const clamped = Math.max(0, Math.min(1, Number(density) || 0));
    this.buildingCrowdDensities.set(buildingKey, clamped);

    if (this.heatmapEnabled) {
      this.refreshBuildingAppearance();
    } else if (this.hoveredHeatmapKey === buildingKey) {
      // Refresh hovered building tint
      const mesh = this.buildingMeshes.get(buildingKey);
      if (mesh) {
        const material = this.getHeatmapMaterial(mesh);
        if (material) {
          const color = this.getDensityColor(clamped);
          const applyColor = (mat) => {
            if (mat.color) mat.color.setHex(color);
            if (mat.emissive) {
              mat.emissive.setHex(color);
              mat.emissiveIntensity = 0.3;
            }
          };
          if (Array.isArray(material)) material.forEach(applyColor);
          else applyColor(material);
          mesh.material = material;
        }
      }
    }
  }

  /**
   * Update crowd-density values for buildings.
   * densityByBuilding can be a Map or a plain object.
   * Each density is between 0 and 1.
   */
  setBuildingCrowdDensities(densityByBuilding) {
    this.buildingCrowdDensities.clear();

    const entries = densityByBuilding instanceof Map
      ? densityByBuilding.entries()
      : Object.entries(densityByBuilding || {});

    for (const [key, value] of entries) {
      this.buildingCrowdDensities.set(
        key,
        Math.max(0, Math.min(1, Number(value) || 0))
      );
    }

    if (this.heatmapEnabled) {
      this.refreshBuildingAppearance();
    }
  }

  setHeatmapEnabled(enabled) {
    this.heatmapEnabled = Boolean(enabled);
    this.refreshBuildingAppearance();
  }

  /**
   * Density colors:
   * Blue = low, green = moderate,
   * yellow = high, red = very high.
   */
  getDensityColor(density) {
    if (density < 0.25) return 0x22aaff;
    if (density < 0.50) return 0x22cc88;
    if (density < 0.75) return 0xffcc33;
    return 0xff3344;
  }

  
  getDensityStatus(density) {
    if (density < 0.25) {
      return { label: 'LOW', color: '#22aaff' };
    }
    if (density < 0.50) {
      return { label: 'MODERATE', color: '#22cc88' };
    }
    if (density < 0.75) {
      return { label: 'HIGH', color: '#ffcc33' };
    }
    return { label: 'VERY HIGH', color: '#ff4455' };
  }

  showDensityPopup(buildingKey, x, y) {
    if (!this.densityPopup) return;

    const density = this.buildingCrowdDensities.get(buildingKey);

    if (density === undefined) {
      this.hideDensityPopup();
      return;
    }

    const status = this.getDensityStatus(density);
    const percentage = Math.round(density * 100);

    this.densityPopup.replaceChildren();

    const title = document.createElement('div');
    title.textContent = this.getBuildingDisplayName(buildingKey);
    title.style.cssText =
      'font-size:14px;font-weight:700;margin-bottom:8px';

    const statusLine = document.createElement('div');
    statusLine.textContent = `Status: ${status.label}`;
    statusLine.style.color = status.color;

    const percentageLine = document.createElement('div');
    percentageLine.textContent = `Simulated density: ${percentage}%`;

    const bar = document.createElement('div');
    bar.style.cssText =
      'height:6px;background:#263244;border-radius:5px;margin-top:8px;overflow:hidden';

    const fill = document.createElement('div');
    fill.style.cssText =
      `height:100%;width:${percentage}%;background:${status.color}`;

    bar.appendChild(fill);

    const note = document.createElement('div');
    note.textContent = this.isDebug
      ? 'Simulated demonstration • Not live IoT sensor data'
      : 'Simulated demonstration • Campus planning projection';
    note.style.cssText =
      'font-size:10px;color:#94a3b8;margin-top:8px';

    this.densityPopup.append(title, statusLine, percentageLine, bar, note);

    // Make visible to measure dimensions for viewport clamping
    this.densityPopup.style.display = 'block';

    // Screen-edge clamping & smart viewport flip logic for narrow viewports
    const popupWidth = this.densityPopup.offsetWidth || 220;
    const popupHeight = this.densityPopup.offsetHeight || 140;
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const padding = 10;

    // Flip horizontally if placing to the right of cursor overflows viewport
    let posX = x + 16;
    if (posX + popupWidth > viewportWidth - padding) {
      posX = x - popupWidth - 16;
    }
    // Strict horizontal clamping
    posX = Math.max(padding, Math.min(posX, Math.max(padding, viewportWidth - popupWidth - padding)));

    // Flip vertically if placing below cursor overflows viewport
    let posY = y + 16;
    if (posY + popupHeight > viewportHeight - padding) {
      posY = y - popupHeight - 16;
    }
    // Strict vertical clamping
    posY = Math.max(padding, Math.min(posY, Math.max(padding, viewportHeight - popupHeight - padding)));

    this.densityPopup.style.left = `${Math.round(posX)}px`;
    this.densityPopup.style.top = `${Math.round(posY)}px`;
  }

  hideDensityPopup() {
    if (this.densityPopup) {
      this.densityPopup.style.display = 'none';
    }
  }

  getBuildingDisplayName(buildingKey) {
    if (!buildingKey) return '';

    // 1. Dynamic lookup via attached WayfinderGraph instance
    if (this.graph && typeof this.graph.buildings?.get === 'function') {
      const building = this.graph.buildings.get(buildingKey);
      if (building && building.displayName) {
        return building.displayName;
      }
    }

    // 2. Dynamic lookup via callback if configured
    if (typeof this.callbacks.getBuildingDisplayName === 'function') {
      const name = this.callbacks.getBuildingDisplayName(buildingKey);
      if (name) return name;
    }

    // 3. Fallback dictionary (resilience guarantee if datasets fail)
    const fallbackBuildingNames = {
      'Building': 'D Block Hostel',
      'Building001': 'Academic Block 3',
      'Building002': 'A Block hostel',
      'Building003': 'Academic Block 4',
      'Building004': 'E Block Hostel',
      'Building005': 'F Block Hostel',
      'Building006': 'Academic Block 2',
      'Building007': 'Academic Block 1',
      'Building008': 'Swimming Pool',
      'Building009': 'Sigma Block',
      'Building010': 'GymKhaana',
      'Building011': 'Admin Block',
      'Building012': 'North Square',
      'Building013': 'Alpha Block',
      'Building014': 'Academic Block 5',
      'Building015': 'Tennis Court',
      'Building016': 'Football Ground',
      'Building017': 'Basketball Court',
      'Building018': 'Volleyball Court',
      'Building019': 'Ground',
      'Building020': 'Omega Block',
      'Building021': 'Cricket Ground',
      'Building022': 'Guest House',
      'Building023': "Student's Parking",
      'Building024': 'Mahatma Gandhi Auditorium',
      'Building025': 'VIT-SEDAXIS',
      'Building026': "Student's Parking 2",
      'Building027': 'Staff Parking 1',
      'Building028': 'Staff Parking 2',
      'Building029': 'Gazebo',
      'Building030': 'B Block Hostel',
      'Building031': 'C Block Hostel',
      'Building032': 'Site Office',
      'Building033': 'Transport Office',
      'Main_Gate': 'Main Gate',
      'Gate': '2nd Gate'
    };

    return fallbackBuildingNames[buildingKey] || buildingKey;
  }


  getHeatmapMaterial(mesh) {
    let material = this.heatmapMaterials.get(mesh.uuid);

    if (!material) {
      const original = this.originalMaterials.get(mesh.uuid);
      if (!original) return null;

      const cloneOne = (mat) => {
        const clone = mat.clone();

        if (clone.color) {
          clone.color.setHex(0xffffff);
        }

        if (clone.emissive) {
          clone.emissive.setHex(0x000000);
        }

        return clone;
      };

      material = Array.isArray(original)
        ? original.map(cloneOne)
        : cloneOne(original);

      this.heatmapMaterials.set(mesh.uuid, material);
    }

    return material;
  }

  getHighlightMaterial(mesh) {
    let material = this.highlightMaterials.get(mesh.uuid);

    if (!material) {
      const original = this.originalMaterials.get(mesh.uuid);
      if (!original) return null;

      const cloneOne = (mat) => {
        const clone = mat.clone();
        clone.emissive.setHex(0x00d4ff);
        clone.emissiveIntensity = 0.45;
        return clone;
      };

      material = Array.isArray(original)
        ? original.map(cloneOne)
        : cloneOne(original);

      this.highlightMaterials.set(mesh.uuid, material);
    }

    return material;
  }

  refreshBuildingAppearance() {
    for (const [key, mesh] of this.buildingMeshes) {
      const original = this.originalMaterials.get(mesh.uuid);
      if (!original) continue;

      if (this.heatmapEnabled) {
        const material = this.getHeatmapMaterial(mesh);
        if (!material) continue;

        const density = this.buildingCrowdDensities.get(key) ?? 0;

        const color = this.getDensityColor(density);

        const applyColor = (mat) => {
          if (mat.color) mat.color.setHex(color);
          if (mat.emissive) {
            mat.emissive.setHex(color);
            mat.emissiveIntensity = 0.22;
          }
        };

        if (Array.isArray(material)) material.forEach(applyColor);
        else applyColor(material);

        // Retain a visible selection accent.
        const selected = key ===
          (this.selectedBuildingMesh?.userData.buildingKey);

        if (selected) {
          const applyHighlight = (mat) => {
            if (mat.emissive) {
              mat.emissive.setHex(0x00d4ff);
              mat.emissiveIntensity = 0.65;
            }
          };

          if (Array.isArray(material)) material.forEach(applyHighlight);
          else applyHighlight(material);
        }

        mesh.material = material;
      } else if (key ===
          this.selectedBuildingMesh?.userData.buildingKey) {
        mesh.material = this.getHighlightMaterial(mesh) || original;
      } else {
        mesh.material = original;
      }
    }
  }


  setupInteractions() {
    const dom = this.renderer.domElement;
    this.pointerDownPos = { x: 0, y: 0 };

    dom.addEventListener('pointerdown', (e) => {
      this.pointerDownPos.x = e.clientX;
      this.pointerDownPos.y = e.clientY;
    });

    dom.addEventListener('pointermove', (e) => {
      this.lastPointerX = e.clientX;
      this.lastPointerY = e.clientY;
      const rect = dom.getBoundingClientRect();
      this.mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      this.mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      this.checkHover();
    });

  

    dom.addEventListener('click', (e) => {
      // Disambiguate camera drag/orbit from click (threshold 6px)
      const dist = Math.hypot(e.clientX - this.pointerDownPos.x, e.clientY - this.pointerDownPos.y);
      if (dist > 6) return;

      const rect = dom.getBoundingClientRect();
      this.mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      this.mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      this.checkClick(e);
    });
  }

  checkHover() {
    if (!this.clickableObjects || this.clickableObjects.length === 0) return;
    this.raycaster.setFromCamera(this.mouse, this.camera);
    const intersects = this.raycaster.intersectObjects(this.clickableObjects, false);

    if (intersects.length > 0) {
      const hit = intersects[0].object;
      const bKey = hit.userData.buildingKey;
      if (bKey && bKey !== this.hoveredBuildingKey) {
        this.hoveredBuildingKey = bKey;
        this.updateHoverHeatmap(bKey);
        this.container.style.cursor = 'pointer';
        if (this.callbacks.onBuildingHover) {
          this.callbacks.onBuildingHover(bKey, hit.userData.rawMeshName);
        }
      }
    } else {
      if (this.hoveredBuildingKey) {
        this.hoveredBuildingKey = null;
        this.updateHoverHeatmap(null);
        this.container.style.cursor = 'default';
        if (this.callbacks.onBuildingHover) {
          this.callbacks.onBuildingHover(null, null);
        }
      }
    }
  }

  checkClick(e) {
    if (!this.clickableObjects || this.clickableObjects.length === 0) return;
    this.raycaster.setFromCamera(this.mouse, this.camera);
    const intersects = this.raycaster.intersectObjects(this.clickableObjects, false);

    if (intersects.length > 0) {
      const hit = intersects[0].object;
      const bKey = hit.userData.buildingKey;
      if (bKey && this.callbacks.onBuildingClick) {
        this.callbacks.onBuildingClick(bKey, hit);
      }
    }
  }

  onWindowResize() {
    const width = this.container.clientWidth || window.innerWidth;
    const height = this.container.clientHeight || window.innerHeight;
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);
  }

  animate() {
    requestAnimationFrame(this.animate);

    // Update smooth camera transition
    if (this.isTransitioningCamera && this.cameraAnim) {
      const now = performance.now();
      const elapsed = now - this.cameraAnim.startTime;
      const progress = Math.min(1, elapsed / this.cameraAnim.duration);

      // Smooth easeInOutCubic
      const ease = progress < 0.5
        ? 4 * progress * progress * progress
        : 1 - Math.pow(-2 * progress + 2, 3) / 2;

      this.camera.position.lerpVectors(this.cameraAnim.startPos, this.cameraAnim.targetPos, ease);
      this.controls.target.lerpVectors(this.cameraAnim.startTarget, this.cameraAnim.targetLookAt, ease);

      if (progress >= 1) {
        this.isTransitioningCamera = false;
        this.cameraAnim = null;
      }
    }

    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }
}
