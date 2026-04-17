import { useCallback, useEffect, useRef, useState } from 'react';
import * as cornerstone from '@cornerstonejs/core';
import * as cornerstoneTools from '@cornerstonejs/tools';
import {
  segmentLeftAtrium,
  materializeLabelmap,
  worldToIJK,
} from '../la/leftAtriumSegmentation';
import { trimThinBranches, cutAtPlane, countVoxels } from '../la/morphology';
import { marchingCubesBinary } from '../la/marchingCubes';
import { meshToBinarySTL, downloadBlob } from '../la/stlExport';

interface Props {
  renderingEngineId: string;
  volumeId: string;
}

const LA_SEGMENTATION_ID = 'leftAtriumSegmentation';
const MPR_VIEWPORT_IDS = ['axial', 'sagittal', 'coronal'];
const ALL_VIEWPORT_IDS = ['axial', 'sagittal', 'coronal', 'volume3d'];

const DEFAULT_MIN_HU = 200;
const DEFAULT_MAX_HU = 700;

interface LAState {
  data: Uint8Array;
  dims: { dx: number; dy: number; dz: number };
  voxelToWorld: (i: number, j: number, k: number) => [number, number, number];
  voxelVolumeMm3: number;
  labelmapVolumeId: string;
  seedIJK: [number, number, number];
}

export function LeftAtriumPanel({ renderingEngineId, volumeId }: Props) {
  const [minHU, setMinHU] = useState(DEFAULT_MIN_HU);
  const [maxHU, setMaxHU] = useState(DEFAULT_MAX_HU);
  const [seedWorld, setSeedWorld] = useState<number[] | null>(null);
  const [seedHU, setSeedHU] = useState<number | null>(null);
  const [seedMode, setSeedMode] = useState(false);
  const [trimRadius, setTrimRadius] = useState(3);
  const [mvMode, setMvMode] = useState(false);
  const [mvPoints, setMvPoints] = useState<Array<[number, number, number]>>([]);
  const [running, setRunning] = useState(false);
  const [statusMsg, setStatusMsg] = useState<string | null>(null);
  const [voxelCount, setVoxelCount] = useState<number | null>(null);
  const [volumeCm3, setVolumeCm3] = useState<number | null>(null);
  const [leaked, setLeaked] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const laStateRef = useRef<LAState | null>(null);

  const clearSegmentation = useCallback(() => {
    const { segmentation } = cornerstoneTools;
    for (const vpId of ALL_VIEWPORT_IDS) {
      try {
        segmentation.removeSegmentationRepresentations(vpId, {
          segmentationId: LA_SEGMENTATION_ID,
        });
      } catch { /* ignore */ }
    }
    try { segmentation.removeSegmentation(LA_SEGMENTATION_ID); } catch { /* ignore */ }
    if (laStateRef.current?.labelmapVolumeId) {
      try { cornerstone.cache.removeVolumeLoadObject(laStateRef.current.labelmapVolumeId); } catch { /* ignore */ }
    }
    laStateRef.current = null;
    setVoxelCount(null);
    setVolumeCm3(null);
    setLeaked(false);
    setStatusMsg(null);
    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    engine?.renderViewports(ALL_VIEWPORT_IDS);
  }, [renderingEngineId]);

  // Attach labelmap representation to all viewports
  const attachRepresentation = useCallback(async (labelmapVolumeId: string) => {
    const { segmentation, Enums: ToolsEnums } = cornerstoneTools;
    try { segmentation.removeSegmentation(LA_SEGMENTATION_ID); } catch { /* ignore */ }
    segmentation.addSegmentations([
      {
        segmentationId: LA_SEGMENTATION_ID,
        representation: {
          type: ToolsEnums.SegmentationRepresentations.Labelmap,
          data: { volumeId: labelmapVolumeId },
        },
      },
    ]);
    const laColor: [number, number, number, number] = [220, 60, 60, 160];
    for (const vpId of MPR_VIEWPORT_IDS) {
      await segmentation.addLabelmapRepresentationToViewport(vpId, [
        {
          segmentationId: LA_SEGMENTATION_ID,
          config: {
            colorLUTOrIndex: [[0, 0, 0, 0], laColor] as any,
          },
        },
      ]);
    }
    try {
      await segmentation.addLabelmapRepresentationToViewport('volume3d', [
        {
          segmentationId: LA_SEGMENTATION_ID,
          config: {
            colorLUTOrIndex: [[0, 0, 0, 0], [220, 60, 60, 255]] as any,
          },
        },
      ]);
    } catch { /* 3D repr may not be supported */ }
    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    engine?.renderViewports(ALL_VIEWPORT_IDS);
  }, [renderingEngineId]);

  // Replace in-memory labelmap with modified data + re-render
  const applyData = useCallback(async (newData: Uint8Array) => {
    const cur = laStateRef.current;
    if (!cur) return;
    // Remove prior labelmap volume from cache
    if (cur.labelmapVolumeId) {
      try { cornerstone.cache.removeVolumeLoadObject(cur.labelmapVolumeId); } catch { /* ignore */ }
    }
    const newId = materializeLabelmap(volumeId, newData);
    if (!newId) {
      setError('Failed to materialize labelmap volume.');
      return;
    }
    laStateRef.current = { ...cur, data: newData, labelmapVolumeId: newId };
    await attachRepresentation(newId);
    const nv = countVoxels(newData);
    setVoxelCount(nv);
    setVolumeCm3((nv * cur.voxelVolumeMm3) / 1000);
  }, [volumeId, attachRepresentation]);

  // Seed placement (click on MPR)
  useEffect(() => {
    if (!seedMode && !mvMode) return;
    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    if (!engine) return;

    const cleanups: Array<() => void> = [];
    for (const vpId of MPR_VIEWPORT_IDS) {
      const vp = engine.getViewport(vpId);
      if (!vp?.element) continue;
      const el = vp.element;

      const handler = (e: MouseEvent) => {
        if (e.button !== 0) return;
        e.preventDefault();
        e.stopPropagation();
        const rect = el.getBoundingClientRect();
        const cx = e.clientX - rect.left;
        const cy = e.clientY - rect.top;
        const world = (vp as any).canvasToWorld?.([cx, cy]);
        if (!world) return;

        if (seedMode) {
          const volume = cornerstone.cache.getVolume(volumeId);
          if (!volume?.imageData) return;
          const ijkFloat = volume.imageData.worldToIndex(world);
          const dims = volume.imageData.getDimensions();
          const i = Math.round(ijkFloat[0]);
          const j = Math.round(ijkFloat[1]);
          const k = Math.round(ijkFloat[2]);
          if (i < 0 || i >= dims[0] || j < 0 || j >= dims[1] || k < 0 || k >= dims[2]) return;
          const hu = volume.imageData.getPointData().getScalars()
            .getTuple(k * dims[0] * dims[1] + j * dims[0] + i)?.[0] ?? null;
          setSeedWorld(world);
          setSeedHU(hu);
          setSeedMode(false);
          setError(null);
        } else if (mvMode) {
          setMvPoints((prev) => {
            const next = [...prev, [world[0], world[1], world[2]] as [number, number, number]];
            if (next.length >= 3) setMvMode(false);
            return next;
          });
        }
      };

      el.addEventListener('mousedown', handler, true);
      cleanups.push(() => el.removeEventListener('mousedown', handler, true));
    }
    return () => cleanups.forEach((fn) => fn());
  }, [seedMode, mvMode, renderingEngineId, volumeId]);

  const runReconstruction = useCallback(async () => {
    setError(null);
    setStatusMsg(null);
    if (!seedWorld) {
      setError('Place seed inside left atrium first.');
      return;
    }
    const seedIJK = worldToIJK(volumeId, seedWorld);
    if (!seedIJK) {
      setError('Seed coord out of volume bounds.');
      return;
    }

    setRunning(true);
    try {
      clearSegmentation();
      await new Promise((r) => setTimeout(r, 20));

      const res = await segmentLeftAtrium(volumeId, { minHU, maxHU, seedIJK });
      if (!res) {
        setError('Segmentation failed: volume unavailable.');
        return;
      }

      laStateRef.current = {
        data: res.data,
        dims: res.dims,
        voxelToWorld: res.voxelToWorld,
        voxelVolumeMm3: res.voxelVolumeMm3,
        labelmapVolumeId: res.labelmapVolumeId,
        seedIJK,
      };

      await attachRepresentation(res.labelmapVolumeId);

      setVoxelCount(res.voxelCount);
      setVolumeCm3(res.volumeCm3);
      setLeaked(res.leaked);
    } catch (err: any) {
      setError(err?.message || 'Reconstruction failed.');
    } finally {
      setRunning(false);
    }
  }, [seedWorld, volumeId, minHU, maxHU, clearSegmentation, attachRepresentation]);

  const runTrimVeins = useCallback(async () => {
    const cur = laStateRef.current;
    if (!cur) return;
    setError(null);
    setStatusMsg(null);
    setRunning(true);
    try {
      await new Promise((r) => setTimeout(r, 20));
      const trimmed = trimThinBranches(cur.data, cur.dims, trimRadius);
      await applyData(trimmed);
      setStatusMsg(`Trimmed thin branches at radius ${trimRadius} voxels.`);
    } catch (err: any) {
      setError(err?.message || 'Trim failed.');
    } finally {
      setRunning(false);
    }
  }, [trimRadius, applyData]);

  const runMVCut = useCallback(async () => {
    const cur = laStateRef.current;
    if (!cur || mvPoints.length < 3) return;
    setError(null);
    setStatusMsg(null);
    setRunning(true);
    try {
      await new Promise((r) => setTimeout(r, 20));
      // Plane from 3 points
      const [p0, p1, p2] = mvPoints;
      const ax = p1[0] - p0[0], ay = p1[1] - p0[1], az = p1[2] - p0[2];
      const bx = p2[0] - p0[0], by = p2[1] - p0[1], bz = p2[2] - p0[2];
      let nx = ay * bz - az * by;
      let ny = az * bx - ax * bz;
      let nz = ax * by - ay * bx;
      const len = Math.sqrt(nx * nx + ny * ny + nz * nz) || 1;
      nx /= len; ny /= len; nz /= len;
      const origin: [number, number, number] = [
        (p0[0] + p1[0] + p2[0]) / 3,
        (p0[1] + p1[1] + p2[1]) / 3,
        (p0[2] + p1[2] + p2[2]) / 3,
      ];

      // Determine which side contains the seed — keep that side
      const [si, sj, sk] = cur.seedIJK;
      const [sw0, sw1, sw2] = cur.voxelToWorld(si, sj, sk);
      const seedDot = (sw0 - origin[0]) * nx + (sw1 - origin[1]) * ny + (sw2 - origin[2]) * nz;
      // cutAtPlane removes dot > 0 side → flip normal if seed is on that side
      let normal: [number, number, number] = [nx, ny, nz];
      if (seedDot > 0) normal = [-nx, -ny, -nz];

      const cut = cutAtPlane(cur.data, cur.dims, cur.voxelToWorld, origin, normal);
      await applyData(cut);
      setMvPoints([]);
      setStatusMsg('Mitral-valve plane cut applied.');
    } catch (err: any) {
      setError(err?.message || 'MV cut failed.');
    } finally {
      setRunning(false);
    }
  }, [mvPoints, applyData]);

  const runExportSTL = useCallback(async () => {
    const cur = laStateRef.current;
    if (!cur) return;
    setError(null);
    setStatusMsg(null);
    setRunning(true);
    try {
      setStatusMsg('Running marching cubes…');
      await new Promise((r) => setTimeout(r, 20));
      const mesh = marchingCubesBinary(cur.data, cur.dims, cur.voxelToWorld);
      if (mesh.triangleCount === 0) {
        setError('No surface generated. Is the mask empty?');
        return;
      }
      const blob = meshToBinarySTL(mesh, 'Left Atrium — antidicom');
      const ts = new Date().toISOString().replace(/[:.]/g, '-');
      downloadBlob(blob, `left-atrium-${ts}.stl`);
      setStatusMsg(`Exported ${mesh.triangleCount.toLocaleString()} triangles.`);
    } catch (err: any) {
      setError(err?.message || 'STL export failed.');
    } finally {
      setRunning(false);
    }
  }, []);

  const resetSeed = useCallback(() => {
    setSeedWorld(null);
    setSeedHU(null);
    setSeedMode(false);
    setError(null);
  }, []);

  const hasMask = laStateRef.current !== null && voxelCount !== null && voxelCount > 0;

  return (
    <div className="la-panel">
      <div className="la-section">
        <h4>Left Atrium 3D Reconstruction</h4>
        <p className="la-hint">
          Contrast-enhanced CT. Seeded flood-fill → trim PVs → MV plane cut → STL export.
        </p>
      </div>

      <div className="la-section">
        <h4>1. Place Seed</h4>
        <button
          className={`la-btn ${seedMode ? 'active' : ''}`}
          onClick={() => { setSeedMode((v) => !v); setMvMode(false); }}
          disabled={running}
        >
          {seedMode ? 'Click in LA on any MPR…' : seedWorld ? 'Re-place Seed' : 'Place Seed'}
        </button>
        {seedWorld && (
          <div className="la-seed-info">
            <div>World: [{seedWorld.map((v) => v.toFixed(1)).join(', ')}]</div>
            {seedHU !== null && <div>HU at seed: {Math.round(seedHU)}</div>}
            <button className="la-btn la-btn-secondary" onClick={resetSeed} disabled={running}>
              Clear Seed
            </button>
          </div>
        )}
      </div>

      <div className="la-section">
        <h4>2. HU Threshold (blood pool)</h4>
        <div className="la-range-inputs">
          <label>
            Min HU
            <input type="number" value={minHU}
              onChange={(e) => setMinHU(Number(e.target.value))} disabled={running} />
          </label>
          <label>
            Max HU
            <input type="number" value={maxHU}
              onChange={(e) => setMaxHU(Number(e.target.value))} disabled={running} />
          </label>
        </div>
        <div className="la-range-slider">
          <input type="range" min={-200} max={1500} value={minHU}
            onChange={(e) => setMinHU(Number(e.target.value))} disabled={running} />
          <input type="range" min={-200} max={1500} value={maxHU}
            onChange={(e) => setMaxHU(Number(e.target.value))} disabled={running} />
        </div>
        <div className="la-preset-row">
          <button className="la-btn la-btn-secondary"
            onClick={() => { setMinHU(DEFAULT_MIN_HU); setMaxHU(DEFAULT_MAX_HU); }}
            disabled={running}>Reset defaults</button>
          <button className="la-btn la-btn-secondary"
            onClick={() => { setMinHU(150); setMaxHU(500); }} disabled={running}>Loose</button>
          <button className="la-btn la-btn-secondary"
            onClick={() => { setMinHU(280); setMaxHU(600); }} disabled={running}>Tight</button>
        </div>
      </div>

      <div className="la-section">
        <h4>3. Reconstruct</h4>
        <button
          className="la-btn la-btn-primary"
          onClick={runReconstruction}
          disabled={running || !seedWorld}
        >
          {running ? 'Working…' : 'Run Flood-Fill'}
        </button>
        {hasMask && (
          <button className="la-btn la-btn-secondary" onClick={clearSegmentation} disabled={running}>
            Clear Mask
          </button>
        )}
      </div>

      {hasMask && (
        <>
          <div className="la-section">
            <h4>4. Trim Pulmonary Veins</h4>
            <p className="la-hint">
              Morphological opening by reconstruction — erode N, keep largest CC, dilate N.
              Surrogate for distance-transform narrowing detection.
            </p>
            <div className="la-range-inputs">
              <label>
                Radius (vox)
                <input type="number" min={1} max={10} value={trimRadius}
                  onChange={(e) => setTrimRadius(Math.max(1, Math.min(10, Number(e.target.value))))}
                  disabled={running} />
              </label>
            </div>
            <button className="la-btn" onClick={runTrimVeins} disabled={running}>
              Trim Veins
            </button>
          </div>

          <div className="la-section">
            <h4>5. Mitral-Valve Plane Cut</h4>
            <p className="la-hint">
              Click 3 points on the MV annulus (any MPR). Plane removes LV side; LA side preserved (seed-anchored).
            </p>
            <button
              className={`la-btn ${mvMode ? 'active' : ''}`}
              onClick={() => { setMvMode((v) => !v); setSeedMode(false); if (!mvMode) setMvPoints([]); }}
              disabled={running}
            >
              {mvMode
                ? `Click point ${mvPoints.length + 1}/3 on MV annulus…`
                : mvPoints.length >= 3
                  ? 'Re-pick MV Points'
                  : 'Define MV Plane (3 points)'}
            </button>
            {mvPoints.length > 0 && (
              <div className="la-seed-info">
                {mvPoints.map((p, idx) => (
                  <div key={idx}>P{idx + 1}: [{p.map((v) => v.toFixed(1)).join(', ')}]</div>
                ))}
                {mvPoints.length < 3 && <div className="la-hint">Need {3 - mvPoints.length} more.</div>}
              </div>
            )}
            <button
              className="la-btn la-btn-primary"
              onClick={runMVCut}
              disabled={running || mvPoints.length < 3}
            >
              Apply MV Cut
            </button>
          </div>

          <div className="la-section">
            <h4>6. Export</h4>
            <button className="la-btn la-btn-primary" onClick={runExportSTL} disabled={running}>
              Export STL (binary)
            </button>
          </div>
        </>
      )}

      {error && <div className="la-error">{error}</div>}
      {statusMsg && <div className="la-status">{statusMsg}</div>}

      {voxelCount !== null && (
        <div className="la-section la-results">
          <h4>Current Mask</h4>
          <div className="la-result-row">
            <span>Voxels</span>
            <span>{voxelCount.toLocaleString()}</span>
          </div>
          {volumeCm3 !== null && (
            <div className="la-result-row">
              <span>Volume</span>
              <span>{volumeCm3.toFixed(2)} cm³</span>
            </div>
          )}
          {leaked && (
            <div className="la-warn">
              Hit voxel cap — region may have leaked. Tighten upper HU, re-seed, or Trim Veins.
            </div>
          )}
        </div>
      )}
    </div>
  );
}
