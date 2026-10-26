import * as THREE from 'three';

/**
 * 3D Navigation Overlay Visualizer
 * Renders Wayfinder waypoints, road adjacency edges, entrance pins,
 * and animated evacuation egress paths directly aligned onto the campus model.
 */

export class NavigationView {
  constructor(scene, wayfinderGraph) {
    this.scene = scene;
    this.graph = wayfinderGraph;

    // Root visual groups
    this.overlayGroup = new THREE.Group();
    this.overlayGroup.name = 'NavigationOverlay';
    this.scene.add(this.overlayGroup);

    // Dense graph network (waypoint spheres, road edges, entrance markers)
    // Hidden by default for a clean campus view
    this.graphGroup = new THREE.Group();
    this.graphGroup.name = 'DenseGraphNetwork';
    this.overlayGroup.add(this.graphGroup);

    this.waypointSpheres = null;
    this.roadEdges = null;
    this.entranceMarkersGroup = new THREE.Group();
    this.graphGroup.add(this.entranceMarkersGroup);

    // Selected entrance beacon (visible when a building is selected)
    this.selectedMarkerGroup = new THREE.Group();
    this.overlayGroup.add(this.selectedMarkerGroup);

    // Active route visual (drawn when route/evacuation is requested)
    this.evacuationGroup = new THREE.Group();
    this.overlayGroup.add(this.evacuationGroup);

    this.isGraphVisible = false;
    this.graphGroup.visible = false;
    this.isVisible = false;
    this.elevationOffset = 1.2; // Elevation above ground so markers sit cleanly on roads

    this.buildGraphVisuals();
    this.buildEntranceMarkers();
    this.createSelectedMarker();
  }

  /**
   * Build road edges and waypoint instanced mesh
   */
  buildGraphVisuals() {
    const waypoints = Array.from(this.graph.waypoints.values());
    if (waypoints.length === 0) return;

    // 1. Waypoint Instanced Mesh
    const sphereGeo = new THREE.SphereGeometry(1.6, 12, 12);
    const sphereMat = new THREE.MeshBasicMaterial({
      color: 0x00d4ff,
      wireframe: false
    });

    this.waypointSpheres = new THREE.InstancedMesh(sphereGeo, sphereMat, waypoints.length);
    const dummy = new THREE.Object3D();

    waypoints.forEach((wp, i) => {
      dummy.position.set(wp.x, wp.y + this.elevationOffset, wp.z);
      dummy.scale.set(1, 1, 1);
      dummy.updateMatrix();
      this.waypointSpheres.setMatrixAt(i, dummy.matrix);
    });
    this.waypointSpheres.instanceMatrix.needsUpdate = true;
    this.graphGroup.add(this.waypointSpheres);

    // 2. Road Edges (LineSegments)
    const edgePositions = [];
    const addedEdges = new Set();

    for (const [idA, neighbors] of this.graph.adjacency.entries()) {
      const wpA = this.graph.waypoints.get(idA);
      if (!wpA) continue;

      for (const idB of neighbors) {
        const wpB = this.graph.waypoints.get(idB);
        if (!wpB) continue;

        // Dedup undirected pair
        const pairKey = idA < idB ? `${idA}_${idB}` : `${idB}_${idA}`;
        if (!addedEdges.has(pairKey)) {
          addedEdges.add(pairKey);
          edgePositions.push(
            wpA.x, wpA.y + this.elevationOffset, wpA.z,
            wpB.x, wpB.y + this.elevationOffset, wpB.z
          );
        }
      }
    }

    const lineGeo = new THREE.BufferGeometry();
    lineGeo.setAttribute('position', new THREE.Float32BufferAttribute(edgePositions, 3));
    const lineMat = new THREE.LineBasicMaterial({
      color: 0x38bdf8,
      transparent: true,
      opacity: 0.7,
      linewidth: 1
    });

    this.roadEdges = new THREE.LineSegments(lineGeo, lineMat);
    this.graphGroup.add(this.roadEdges);
  }

  /**
   * Build markers for all building entrances
   */
  buildEntranceMarkers() {
    this.entranceMarkersGroup.clear();

    const diamondGeo = new THREE.OctahedronGeometry(2.4, 0);
    const entranceMat = new THREE.MeshStandardMaterial({
      color: 0xf59e0b,
      emissive: 0xd97706,
      emissiveIntensity: 0.6,
      roughness: 0.3
    });

    const entrances = new Set();
    for (const b of this.graph.buildings.values()) {
      for (const eid of b.entranceIds) {
        entrances.add(eid);
      }
    }

    entrances.forEach(eid => {
      const wp = this.graph.waypoints.get(eid);
      if (wp) {
        const marker = new THREE.Mesh(diamondGeo, entranceMat);
        marker.position.set(wp.x, wp.y + this.elevationOffset + 3, wp.z);
        marker.userData = { entranceId: eid };
        this.entranceMarkersGroup.add(marker);
      }
    });
  }

  /**
   * Create animated beacon for currently selected entrance
   */
  createSelectedMarker() {
    this.selectedMarkerGroup.clear();

    // Glowing vertical cylinder / beam
    const beamGeo = new THREE.CylinderGeometry(0.5, 0.5, 18, 16);
    const beamMat = new THREE.MeshBasicMaterial({
      color: 0x38bdf8,
      transparent: true,
      opacity: 0.85
    });
    const beam = new THREE.Mesh(beamGeo, beamMat);
    beam.position.y = 9;
    this.selectedMarkerGroup.add(beam);

    // Pulsing ground ring
    const ringGeo = new THREE.RingGeometry(3, 4.5, 32);
    ringGeo.rotateX(-Math.PI / 2);
    const ringMat = new THREE.MeshBasicMaterial({
      color: 0x00d4ff,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.8
    });
    this.selectedRing = new THREE.Mesh(ringGeo, ringMat);
    this.selectedRing.position.y = 0.5;
    this.selectedMarkerGroup.add(this.selectedRing);

    // Start invisible until selected
    this.selectedMarkerGroup.visible = false;
  }

  /**
   * Highlight a specific entrance waypoint
   */
  highlightEntrance(waypointId) {
    const wp = this.graph.waypoints.get(String(waypointId));
    if (!wp) {
      this.selectedMarkerGroup.visible = false;
      return null;
    }

    this.selectedMarkerGroup.position.set(wp.x, wp.y + this.elevationOffset, wp.z);
    this.selectedMarkerGroup.visible = true;
    return wp;
  }

  /**
   * Display evacuation route on 3D scene
   */
  displayEvacuationRoute(routeWaypoints, options = {}) {
    this.evacuationGroup.clear();
    if (!routeWaypoints || routeWaypoints.length < 2) return;

    const isEvacuation = options.isEvacuation ?? false;
    const points = routeWaypoints.map(wp =>
      new THREE.Vector3(wp.x, wp.y + this.elevationOffset + 0.6, wp.z)
    );

    // 1. Route curve / path line (Cyan for walking transit, Red/Amber for emergency evacuation)
    const curve = new THREE.CatmullRomCurve3(points, false, 'centripetal', 0.1);
    const tubeGeo = new THREE.TubeGeometry(curve, points.length * 8, 1.2, 8, false);
    const tubeMat = new THREE.MeshStandardMaterial({
      color: isEvacuation ? 0xef4444 : 0x00d4ff,
      emissive: isEvacuation ? 0xd97706 : 0x0284c7,
      emissiveIntensity: 0.85,
      roughness: 0.2
    });

    const routeMesh = new THREE.Mesh(tubeGeo, tubeMat);
    this.evacuationGroup.add(routeMesh);

    // 2. Waypoint node markers along route
    const nodeGeo = new THREE.SphereGeometry(2.0, 12, 12);
    const nodeMat = new THREE.MeshBasicMaterial({
      color: isEvacuation ? 0xffedd5 : 0xbae6fd
    });
    points.forEach(p => {
      const nodeMesh = new THREE.Mesh(nodeGeo, nodeMat);
      nodeMesh.position.copy(p);
      this.evacuationGroup.add(nodeMesh);
    });

    // 3. Exit Gateway / Arrival beacon at the terminus
    const exitPos = points[points.length - 1];
    const exitRingGeo = new THREE.RingGeometry(5, 8, 32);
    exitRingGeo.rotateX(-Math.PI / 2);
    const exitRingMat = new THREE.MeshBasicMaterial({
      color: isEvacuation ? 0x10b981 : 0x38bdf8,
      side: THREE.DoubleSide
    });
    const exitRing = new THREE.Mesh(exitRingGeo, exitRingMat);
    exitRing.position.set(exitPos.x, exitPos.y + 0.5, exitPos.z);
    this.evacuationGroup.add(exitRing);

    this.evacuationGroup.visible = true;
  }

  
  /**
   * Calculate and display a route from a building entrance to a gate.
   */
  showBuildingEvacuationRoute(buildingKey, gateIds = ['111', '188', '33']) {
    const routes = this.graph.findBuildingEvacuationRoutes(
      buildingKey,
      gateIds
    );

    if (!routes || routes.length === 0) {
      this.clearEvacuationRoute();
      console.warn(`No evacuation route found for ${buildingKey}`);
      return null;
    }

    // Select the shortest route among the available entrances and gates.
    const route = routes[0];

    this.displayEvacuationRoute(route.waypoints);

    console.log('Displayed evacuation route:', {
      building: buildingKey,
      entrance: route.entranceId,
      gate: route.exitId,
      distance: route.distanceMeters,
      waypointCount: route.path.length
    });

    return route;
  }


  clearEvacuationRoute() {
    this.evacuationGroup.clear();
    this.evacuationGroup.visible = false;
  }

  /**
   * Toggle visibility of dense navigation network (spheres and road lines)
   */
  setGraphVisible(visible) {
    this.isGraphVisible = Boolean(visible);
    this.graphGroup.visible = this.isGraphVisible;
  }

  toggleGraph() {
    this.setGraphVisible(!this.isGraphVisible);
    return this.isGraphVisible;
  }

  // Compatibility aliases
  setVisible(visible) {
    this.setGraphVisible(visible);
  }

  toggle() {
    return this.toggleGraph();
  }

  /**
   * Called in animation loop to pulse rings / markers
   */
  update(time) {
    if (this.selectedRing && this.selectedMarkerGroup && this.selectedMarkerGroup.visible) {
      const scale = 1 + 0.25 * Math.sin(time * 3);
      this.selectedRing.scale.set(scale, scale, scale);
    }
    if (this.entranceMarkersGroup && this.isGraphVisible) {
      this.entranceMarkersGroup.children.forEach((child, i) => {
        child.rotation.y = time * 0.8 + i * 0.1;
      });
    }
  }
}
