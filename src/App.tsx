import { useState, useCallback, useRef, useEffect } from 'react';
import * as cornerstone from '@cornerstonejs/core';
(window as any).__cornerstone = cornerstone;
import { initCornerstone } from './core/initCornerstone';
import { loadDicomFiles, createVolume, DicomSeriesInfo } from './core/dicomLoader';
import { setupToolGroups, destroyToolGroups, resetCrosshairsToCenter, enterDoubleObliqueMode, exitDoubleObliqueMode } from './core/toolManager';
import type { ViewportMode } from './components/ViewportGrid';
import { Toolbar } from './components/Toolbar';
import { DicomDropzone } from './components/DicomDropzone';
import { ViewportGrid } from './components/ViewportGrid';
import { WindowLevelPresets } from './components/WindowLevelPresets';
import { MetadataPanel } from './components/MetadataPanel';
import { SegmentationPanel } from './components/SegmentationPanel';
import { VolumeStats } from './components/VolumeStats';
import { RenderModeSelector } from './components/RenderModeSelector';
import { SeriesPanel } from './components/SeriesPanel';
import { TAVIPanel, TAVIPanelHandle } from './components/TAVIPanel';
import { ViewAnglePresets } from './components/ViewAnglePresets';
import { HUProbeOverlay } from './components/HUProbeOverlay';
import { DicomInfoOverlay } from './components/DicomInfoOverlay';
import { HandMRPanel, HandMRPanelHandle } from './components/HandMRPanel';

const RENDERING_ENGINE_ID = 'myRenderingEngine';
const VOLUME_ID = 'cornerstoneStreamingImageVolume:myVolume';
const VIEWPORT_IDS = ['axial', 'sagittal', 'coronal', 'volume3d'];
const MPR_VIEWPORT_IDS = ['axial', 'sagittal', 'coronal'];

type RightPanel = null | '3d' | 'tavi' | 'hand-mr';

interface VolumeResult {
  name: string;
  volumeCm3: number;
}

export default function App() {
  const [isInitialized, setIsInitialized] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [seriesList, setSeriesList] = useState<DicomSeriesInfo[]>([]);
  const [activeSeries, setActiveSeries] = useState<DicomSeriesInfo | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loadingProgress, setLoadingProgress] = useState('');
  const [showMetadata, setShowMetadata] = useState(false);
  const [showSegmentation, setShowSegmentation] = useState(false);
  const [rightPanel, setRightPanel] = useState<RightPanel>(null);
  const [reportExpanded, setReportExpanded] = useState(false);
  const [volumeResults, setVolumeResults] = useState<VolumeResult[]>([]);
  const [viewportMode, setViewportMode] = useState<ViewportMode>('standard');
  const renderingEngineRef = useRef<cornerstone.RenderingEngine | null>(null);
  const taviPanelRef = useRef<TAVIPanelHandle>(null);
  const handMRPanelRef = useRef<HandMRPanelHandle>(null);
  const toolGroupsInitialized = useRef(false);
  const vol3dPanelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    initCornerstone()
      .then(() => {
        const engine = new cornerstone.RenderingEngine(RENDERING_ENGINE_ID);
        renderingEngineRef.current = engine;
        setIsInitialized(true);
      })
      .catch((err) => {
        setError(`Failed to initialize: ${err.message}`);
      });

    return () => {
      destroyToolGroups();
      renderingEngineRef.current?.destroy();
    };
  }, []);

  // When the 3D side panel is open, resize Cornerstone canvases.
  // We no longer move DOM elements — the 3D viewport stays in its grid position
  // and CSS handles visual placement.
  useEffect(() => {
    setTimeout(() => {
      renderingEngineRef.current?.resize(true, false);

      // When entering tavi-oblique mode, disable MIP on the oblique viewports
      // (Reference=axial, Working=coronal) so they show clean thin-slice cross-sections
      if (viewportMode === 'tavi-oblique') {
        const engine = renderingEngineRef.current;
        if (engine) {
          for (const vpId of ['axial', 'coronal']) {
            const vp = engine.getViewport(vpId);
            if (vp && 'setBlendMode' in vp) {
              (vp as any).setBlendMode(cornerstone.Enums.BlendModes.COMPOSITE);
              vp.render();
            }
          }
        }
      }
    }, 100);
  }, [rightPanel, viewportMode]);

  // Auto W/L: when scrolling, sample voxels around focal point to compute W/L
  useEffect(() => {
    if (!activeSeries) return;
    const engine = renderingEngineRef.current;
    if (!engine) return;

    let lastFocalStr = '';

    const autoWL = (vpId: string) => {
      try {
        const volume = cornerstone.cache.getVolume(VOLUME_ID) as any;
        if (!volume?.imageData || !volume?.voxelManager) return;

        const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
        if (!vp) return;
        const cam = vp.getCamera();
        if (!cam.focalPoint) return;

        // Check if focal point actually changed
        const focalStr = cam.focalPoint.map((v: number) => v.toFixed(1)).join(',');
        if (focalStr === lastFocalStr) return;
        lastFocalStr = focalStr;

        const dims = volume.imageData.getDimensions();
        const ijk = volume.imageData.worldToIndex(cam.focalPoint);
        const ci = Math.round(ijk[0]);
        const cj = Math.round(ijk[1]);
        const ck = Math.round(ijk[2]);

        // Determine scroll axis from view plane normal
        const vpn = cam.viewPlaneNormal || [0, 0, 1];
        const absVpn = [Math.abs(vpn[0]), Math.abs(vpn[1]), Math.abs(vpn[2])];
        const scrollAxis = absVpn.indexOf(Math.max(...absVpn));

        // Sample a grid of voxels on the current slice plane
        const vm = volume.voxelManager;
        const samples: number[] = [];
        const step = 2; // sample every 2nd voxel for speed

        if (scrollAxis === 2) {
          // Axial: sample XY plane at z=ck
          const k = Math.max(0, Math.min(dims[2] - 1, ck));
          for (let j = 0; j < dims[1]; j += step) {
            for (let i = 0; i < dims[0]; i += step) {
              samples.push(vm.getAtIJK(i, j, k));
            }
          }
        } else if (scrollAxis === 1) {
          // Coronal: sample XZ plane at y=cj
          const j = Math.max(0, Math.min(dims[1] - 1, cj));
          for (let k = 0; k < dims[2]; k += step) {
            for (let i = 0; i < dims[0]; i += step) {
              samples.push(vm.getAtIJK(i, j, k));
            }
          }
        } else {
          // Sagittal: sample YZ plane at x=ci
          const i = Math.max(0, Math.min(dims[0] - 1, ci));
          for (let k = 0; k < dims[2]; k += step) {
            for (let j = 0; j < dims[1]; j += step) {
              samples.push(vm.getAtIJK(i, j, k));
            }
          }
        }

        if (samples.length < 10) return;

        // Percentile W/L (5th-95th)
        samples.sort((a, b) => a - b);
        const p5 = samples[Math.floor(samples.length * 0.05)];
        const p95 = samples[Math.floor(samples.length * 0.95)];
        const ww = Math.max(1, p95 - p5);
        const wl = (p95 + p5) / 2;

        vp.setProperties({ voiRange: { lower: wl - ww / 2, upper: wl + ww / 2 } });
        vp.render();
      } catch { /* ignore */ }
    };

    // Listen for camera changes on all MPR viewports
    const handlers: (() => void)[] = [];
    for (const vpId of MPR_VIEWPORT_IDS) {
      const el = document.getElementById(`viewport-${vpId}`);
      if (!el) continue;
      const h = () => setTimeout(() => autoWL(vpId), 30);
      el.addEventListener(cornerstone.Enums.Events.CAMERA_MODIFIED as any, h);
      handlers.push(() => el.removeEventListener(cornerstone.Enums.Events.CAMERA_MODIFIED as any, h));
    }

    return () => handlers.forEach(h => h());
  }, [activeSeries, viewportMode]);

  // Arrow keys: scroll through slices on the last-clicked viewport
  useEffect(() => {
    if (!activeSeries) return;
    let lastClickedVpId = 'axial';

    // Track which viewport was last clicked
    const handleClick = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      for (const vpId of MPR_VIEWPORT_IDS) {
        const el = document.getElementById(`viewport-${vpId}`);
        if (el?.contains(target)) { lastClickedVpId = vpId; break; }
      }
    };

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
      if (!['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) return;
      e.preventDefault();

      const engine = renderingEngineRef.current;
      if (!engine) return;

      const step = e.shiftKey ? 5 : 1;
      const volume = cornerstone.cache.getVolume(VOLUME_ID);
      const spacing = volume?.imageData?.getSpacing?.() || [1, 1, 1];
      const sliceSpacing = Math.min(spacing[0], spacing[1], spacing[2]);

      if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
        // Up/Down: scroll current viewport through slices
        const vp = engine.getViewport(lastClickedVpId) as cornerstone.Types.IVolumeViewport | undefined;
        if (!vp) return;
        const cam = vp.getCamera();
        if (!cam.viewPlaneNormal || !cam.focalPoint || !cam.position) return;
        const delta = e.key === 'ArrowDown' ? 1 : -1;
        const dist = delta * step * sliceSpacing;
        const n = cam.viewPlaneNormal;
        vp.setCamera({
          ...cam,
          focalPoint: [cam.focalPoint[0] + n[0] * dist, cam.focalPoint[1] + n[1] * dist, cam.focalPoint[2] + n[2] * dist] as cornerstone.Types.Point3,
          position: [cam.position[0] + n[0] * dist, cam.position[1] + n[1] * dist, cam.position[2] + n[2] * dist] as cornerstone.Types.Point3,
        });
        vp.render();
      } else {
        // Left/Right: scroll the OTHER two viewports (not the current one)
        // This creates a cross-navigation effect
        const otherVpIds = MPR_VIEWPORT_IDS.filter(id => id !== lastClickedVpId);
        for (const vpId of otherVpIds) {
          const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
          if (!vp) continue;
          const cam = vp.getCamera();
          if (!cam.viewPlaneNormal || !cam.focalPoint || !cam.position) continue;
          const delta = e.key === 'ArrowRight' ? 1 : -1;
          const dist = delta * step * sliceSpacing;
          const n = cam.viewPlaneNormal;
          vp.setCamera({
            ...cam,
            focalPoint: [cam.focalPoint[0] + n[0] * dist, cam.focalPoint[1] + n[1] * dist, cam.focalPoint[2] + n[2] * dist] as cornerstone.Types.Point3,
            position: [cam.position[0] + n[0] * dist, cam.position[1] + n[1] * dist, cam.position[2] + n[2] * dist] as cornerstone.Types.Point3,
          });
          vp.render();
        }
      }
    };

    document.addEventListener('mousedown', handleClick);
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('mousedown', handleClick);
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [activeSeries]);

  const handleFilesLoaded = useCallback(
    async (files: File[]) => {
      if (!isInitialized) return;

      setIsLoading(true);
      setError(null);
      setLoadingProgress('Parsing DICOM files...');

      try {
        const series = await loadDicomFiles(files);
        setSeriesList(series);

        if (series.length > 0) {
          await loadSeries(series[0]);
        } else {
          setError('No DICOM series found in the selected files.');
        }
      } catch (err: any) {
        setError(`Failed to load DICOM files: ${err.message}`);
      } finally {
        setIsLoading(false);
      }
    },
    [isInitialized]
  );

  // Open series in 2D stack viewer (single viewport, scroll through slices)
  const open2DViewer = useCallback(async (series: DicomSeriesInfo) => {
    const engine = renderingEngineRef.current;
    if (!engine) return;

    setActiveSeries(series);
    setViewportMode('stack-2d');
    setRightPanel(null);

    // Wait for layout to update
    await new Promise(r => setTimeout(r, 200));
    engine.resize(true, false);

    // Use axial viewport as a stack viewport by setting volume and scrolling
    try {
      // Load volume if not already loaded
      setIsLoading(true);
      try { cornerstone.cache.removeVolumeLoadObject(VOLUME_ID); } catch {}
      try { cornerstone.cache.purgeVolumeCache(); } catch {}

      await createVolume(VOLUME_ID, series.imageIds, (loaded, total) => {
        setLoadingProgress(`Loading: ${loaded}/${total}`);
      });

      await cornerstone.setVolumesForViewports(engine, [{ volumeId: VOLUME_ID }], ['axial']);

      const vp = engine.getViewport('axial') as cornerstone.Types.IVolumeViewport | undefined;
      if (vp) {
        vp.setProperties({ interpolationType: cornerstone.Enums.InterpolationType.LINEAR });
        // Disable MIP for 2D stack viewing
        if ('setBlendMode' in vp) {
          (vp as any).setBlendMode(cornerstone.Enums.BlendModes.COMPOSITE);
          (vp as any).resetSlabThickness?.();
        }
        vp.resetCamera();
        vp.render();
      }

      // In 2D mode: set W/L as primary tool, disable crosshairs
      setActiveTool('WindowLevel');

      // Set orientation to match the acquisition plane
      // (for coronal series, show coronal; for sagittal, show sagittal)
      const desc = series.seriesDescription?.toUpperCase() || '';
      if (desc.includes('COR')) {
        // Coronal acquisition — show as coronal
        const vpC = engine.getViewport('axial') as any;
        if (vpC?.setOrientation) {
          vpC.setOrientation(cornerstone.Enums.OrientationAxis.CORONAL);
          vpC.resetCamera();
          vpC.render();
        }
      } else if (desc.includes('SAG')) {
        const vpS = engine.getViewport('axial') as any;
        if (vpS?.setOrientation) {
          vpS.setOrientation(cornerstone.Enums.OrientationAxis.SAGITTAL);
          vpS.resetCamera();
          vpS.render();
        }
      }
    } catch (err: any) {
      setError(`Failed to open 2D viewer: ${err.message}`);
    } finally {
      setIsLoading(false);
    }
  }, [isInitialized]);

  const loadSeries = async (series: DicomSeriesInfo) => {
    const engine = renderingEngineRef.current;
    if (!engine) return;

    setActiveSeries(series);
    // If in 2D mode, switch back to MPR
    if (viewportMode === 'stack-2d') setViewportMode('standard');
    setIsLoading(true);
    setVolumeResults([]);

    await new Promise((resolve) => requestAnimationFrame(resolve));
    await new Promise((resolve) => requestAnimationFrame(resolve));

    try {
      destroyToolGroups();
      toolGroupsInitialized.current = false;
      cornerstone.cache.purgeCache();

      const axialEl = document.getElementById('viewport-axial') as HTMLDivElement;
      const sagittalEl = document.getElementById('viewport-sagittal') as HTMLDivElement;
      const coronalEl = document.getElementById('viewport-coronal') as HTMLDivElement;
      const vol3dEl = document.getElementById('viewport-3d') as HTMLDivElement;

      if (!axialEl || !sagittalEl || !coronalEl || !vol3dEl) {
        throw new Error('Viewport elements not found in DOM');
      }

      const viewportInputArray: cornerstone.Types.PublicViewportInput[] = [
        {
          viewportId: 'axial',
          type: cornerstone.Enums.ViewportType.ORTHOGRAPHIC,
          element: axialEl,
          defaultOptions: { orientation: cornerstone.Enums.OrientationAxis.AXIAL },
        },
        {
          viewportId: 'sagittal',
          type: cornerstone.Enums.ViewportType.ORTHOGRAPHIC,
          element: sagittalEl,
          defaultOptions: { orientation: cornerstone.Enums.OrientationAxis.SAGITTAL },
        },
        {
          viewportId: 'coronal',
          type: cornerstone.Enums.ViewportType.ORTHOGRAPHIC,
          element: coronalEl,
          defaultOptions: { orientation: cornerstone.Enums.OrientationAxis.CORONAL },
        },
        {
          viewportId: 'volume3d',
          type: cornerstone.Enums.ViewportType.VOLUME_3D,
          element: vol3dEl,
          defaultOptions: { background: [0.1, 0.1, 0.15] as cornerstone.Types.RGB },
        },
      ];

      engine.setViewports(viewportInputArray);
      setupToolGroups(RENDERING_ENGINE_ID);
      toolGroupsInitialized.current = true;

      setLoadingProgress(`Loading images: 0/${series.imageIds.length}`);
      await createVolume(VOLUME_ID, series.imageIds, (loaded, total) => {
        setLoadingProgress(`Loading images: ${loaded}/${total}`);
      });

      await cornerstone.setVolumesForViewports(engine, [{ volumeId: VOLUME_ID }], VIEWPORT_IDS);

      // Set LINEAR interpolation on all MPR viewports for better reformat quality
      for (const vpId of VIEWPORT_IDS) {
        const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
        if (vp) {
          vp.setProperties({ interpolationType: cornerstone.Enums.InterpolationType.LINEAR });
        }
      }

      const viewport3d = engine.getViewport('volume3d') as cornerstone.Types.IVolumeViewport;
      if (viewport3d) {
        const preset3d = (series.modality?.toUpperCase() === 'MR') ? 'MR-Default' : 'CT-Chest-Contrast-Enhanced';
        viewport3d.setProperties({ preset: preset3d });
      }

      // Modality-specific defaults
      const modality = series.modality?.toUpperCase() || '';
      const isCT = modality === 'CT';
      const isMR = modality === 'MR';

      for (const vpId of MPR_VIEWPORT_IDS) {
        const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
        if (!vp || !('setBlendMode' in vp)) continue;

        if (isCT) {
          // CT: 5mm MIP slab + coronary W/L
          (vp as any).setBlendMode(cornerstone.Enums.BlendModes.MAXIMUM_INTENSITY_BLEND);
          (vp as any).setSlabThickness(5);
          vp.setProperties({ voiRange: { lower: 0, upper: 700 } });
        } else if (isMR) {
          // MR: AVERAGE blend with thin slab for smoother through-plane appearance
          (vp as any).setBlendMode(cornerstone.Enums.BlendModes.AVERAGE_INTENSITY_BLEND);
          (vp as any).setSlabThickness(3);
          // Auto W/L from data — don't override
        }
      }

      for (const vpId of VIEWPORT_IDS) {
        const vp = engine.getViewport(vpId);
        if (vp) vp.resetCamera();
      }
      engine.renderViewports(VIEWPORT_IDS);

      setTimeout(() => {
        try { resetCrosshairsToCenter(RENDERING_ENGINE_ID); } catch { /* ignore */ }
        setTimeout(() => { try { resetCrosshairsToCenter(RENDERING_ENGINE_ID); } catch { /* ignore */ } }, 300);
      }, 500);
    } catch (err: any) {
      setError(`Failed to load series: ${err.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const handleVolumeCalculated = useCallback((name: string, volumeCm3: number) => {
    setVolumeResults((prev) => {
      const existing = prev.findIndex((r) => r.name === name);
      if (existing >= 0) {
        const next = [...prev];
        next[existing] = { name, volumeCm3 };
        return next;
      }
      return [...prev, { name, volumeCm3 }];
    });
  }, []);

  const resizeViewports = useCallback(() => {
    // Allow CSS layout to settle, then resize Cornerstone canvases + reset crosshairs
    setTimeout(() => {
      const engine = renderingEngineRef.current;
      if (engine) {
        engine.resize(true, false);
      }
      resetCrosshairsToCenter(RENDERING_ENGINE_ID);
    }, 150);
  }, []);

  const toggleRightPanel = useCallback((panel: RightPanel) => {
    setRightPanel((prev) => {
      const next = prev === panel ? null : panel;
      if (next === 'tavi') {
        // Open TAVI panel — preserve current crosshair position, zoom, pan, W/L
        setReportExpanded(false);

        // Save all camera states BEFORE mode switch (resize will change viewport dimensions)
        const engine = renderingEngineRef.current;
        const savedCameras: Record<string, any> = {};
        if (engine) {
          for (const vpId of MPR_VIEWPORT_IDS) {
            const vp = engine.getViewport(vpId);
            if (vp) savedCameras[vpId] = vp.getCamera();
          }
        }

        setViewportMode('tavi-crosshair');

        // After resize, restore saved cameras to preserve zoom/pan/position
        setTimeout(() => {
          if (engine) {
            engine.resize(true, false);
            for (const vpId of MPR_VIEWPORT_IDS) {
              const vp = engine.getViewport(vpId);
              if (vp && savedCameras[vpId]) {
                vp.setCamera(savedCameras[vpId]);
                vp.render();
              }
            }
          }
        }, 150);
      } else if (prev === 'tavi' && next !== 'tavi') {
        setViewportMode(next === 'hand-mr' ? 'hand-mr' : 'standard');
        setReportExpanded(false);
        exitDoubleObliqueMode(RENDERING_ENGINE_ID);
        resizeViewports();
      }
      if (next === 'hand-mr') {
        setViewportMode('hand-mr');
        setReportExpanded(false);
        setTimeout(() => {
          const engine = renderingEngineRef.current;
          if (engine) engine.resize(true, false);
        }, 150);
      } else if (prev === 'hand-mr' && next !== 'hand-mr' && next !== 'tavi') {
        setViewportMode('standard');
        resizeViewports();
      }
      return next;
    });
  }, [resizeViewports]);

  const handleTaviModeChange = useCallback((mode: ViewportMode) => {
    setViewportMode(mode);
    // Exit double-oblique when switching to any non-oblique mode
    if (mode === 'standard' || mode === 'tavi-crosshair') {
      exitDoubleObliqueMode(RENDERING_ENGINE_ID);
    }
    resizeViewports();
  }, [resizeViewports]);

  return (
    <div className="app">
      <header className="app-header">
        <h1>DICOM Viewer</h1>
        {activeSeries && (
          <div className="patient-info">
            <span>{activeSeries.patientName}</span>
            <span className="separator">|</span>
            <span>{activeSeries.studyDescription}</span>
            <span className="separator">|</span>
            <span>{activeSeries.seriesDescription}</span>
            <span className="separator">|</span>
            <span>{activeSeries.modality} - {activeSeries.numImages} images</span>
          </div>
        )}
        <div className="header-actions">
          <button className="open-btn" onClick={() => {
            const input = document.createElement('input');
            input.type = 'file'; input.multiple = true;
            input.onchange = (e) => { const t = e.target as HTMLInputElement; if (t.files?.length) handleFilesLoaded(Array.from(t.files)); };
            input.click();
          }} disabled={isLoading}>Open Files</button>
          <button className="open-btn" onClick={() => {
            const input = document.createElement('input');
            input.type = 'file'; input.webkitdirectory = true; input.multiple = true;
            input.onchange = (e) => { const t = e.target as HTMLInputElement; if (t.files?.length) handleFilesLoaded(Array.from(t.files)); };
            input.click();
          }} disabled={isLoading}>Open Folder</button>
        </div>
      </header>

      {activeSeries && (
        <div className="toolbar-row">
          <Toolbar renderingEngineId={RENDERING_ENGINE_ID} onReset={() => {
            // Full baseline reset: exit TAVI mode, close panels, restore standard view
            taviPanelRef.current?.resetAll();
            exitDoubleObliqueMode(RENDERING_ENGINE_ID);
            setViewportMode('standard');
            setRightPanel(null);
            setReportExpanded(false);
            // Clear segmentation overlay
            try {
              const csTools = (window as any).cornerstoneTools;
              if (csTools?.segmentation) {
                const seg = csTools.segmentation;
                try { seg.removeSegmentationRepresentations('axial'); } catch {}
                try { seg.removeSegmentationRepresentations('sagittal'); } catch {}
                try { seg.removeSegmentationRepresentations('coronal'); } catch {}
                try { seg.removeSegmentation('huThresholdSegmentation'); } catch {}
              }
            } catch {}
            resizeViewports();
          }} />
          <div className="toolbar-divider" />
          <WindowLevelPresets renderingEngineId={RENDERING_ENGINE_ID} viewportIds={MPR_VIEWPORT_IDS} modality={activeSeries?.modality} />
          <div className="toolbar-divider" />
          {viewportMode === 'tavi-oblique' && (
            <>
              <ViewAnglePresets onAngleChange={(lao, cc) => taviPanelRef.current?.setViewingAngle(lao, cc)} />
              <div className="toolbar-divider" />
            </>
          )}
          <button className={`toolbar-btn ${viewportMode === 'volume-3d' ? 'active' : ''}`} onClick={() => {
            if (viewportMode === 'volume-3d') {
              // Toggle off — go back to standard
              setViewportMode('standard');
              setRightPanel(null);
              setReportExpanded(false);
              resizeViewports();
            } else {
              // Toggle on — fullscreen 3D mode
              setViewportMode('volume-3d');
              setRightPanel('3d');
              setReportExpanded(false);
              resizeViewports();
            }
          }}>3D</button>
          <button className={`toolbar-btn ${rightPanel === 'tavi' ? 'active' : ''}`} onClick={() => toggleRightPanel('tavi')}>TAVI</button>
          <button className={`toolbar-btn ${rightPanel === 'hand-mr' ? 'active' : ''}`} onClick={() => toggleRightPanel('hand-mr')}>Hand MR</button>
        </div>
      )}

      {error && (
        <div className="error-banner">
          <span className="error-banner-icon">!</span>
          <span className="error-banner-text">{error}</span>
          <button className="error-banner-close" onClick={() => setError(null)}>×</button>
        </div>
      )}

      {!activeSeries ? (
        <DicomDropzone onFilesLoaded={handleFilesLoaded} isLoading={isLoading} />
      ) : (
        <div className={`main-content ${viewportMode === 'tavi-oblique' || viewportMode === 'tavi-crosshair' ? 'main-content--tavi-oblique' : ''} ${viewportMode === 'volume-3d' ? 'main-content--volume-3d' : ''}`}>
          {viewportMode !== 'volume-3d' && seriesList.length > 0 && (
            <SeriesPanel seriesList={seriesList} activeSeriesUID={activeSeries?.seriesInstanceUID || ''} onSelectSeries={loadSeries} onOpen2DViewer={open2DViewer} isLoading={isLoading} />
          )}

          <div style={{ flex: 1, position: 'relative', display: 'flex', flexDirection: 'column', minWidth: 0 }}>
            <ViewportGrid hide3d={false} mode={viewportMode} />

            {/* 3D mode: overlay controls on bottom-left of viewport */}
            {viewportMode === 'volume-3d' && (
              <div className="vol3d-overlay-controls">
                <RenderModeSelector renderingEngineId={RENDERING_ENGINE_ID} volumeId={VOLUME_ID} />
              </div>
            )}

            {/* Orientation labels now handled by OrientationOverlay in ViewportGrid */}

            {/* HU value probe overlay on all viewports */}
            {activeSeries && <HUProbeOverlay renderingEngineId={RENDERING_ENGINE_ID} volumeId={VOLUME_ID} />}
            {activeSeries && (
              <DicomInfoOverlay
                renderingEngineId={RENDERING_ENGINE_ID}
                patientName={activeSeries.patientName}
                studyDescription={activeSeries.studyDescription}
                seriesDescription={activeSeries.seriesDescription}
                modality={activeSeries.modality}
              />
            )}
          </div>

          {viewportMode !== 'volume-3d' && (
            <>
              <MetadataPanel series={activeSeries} isVisible={showMetadata} onToggle={() => setShowMetadata(!showMetadata)} />

              <SegmentationPanel
                renderingEngineId={RENDERING_ENGINE_ID} volumeId={VOLUME_ID}
                isVisible={showSegmentation} onToggle={() => setShowSegmentation(!showSegmentation)}
                onVolumeCalculated={handleVolumeCalculated}
              />
            </>
          )}

          {rightPanel === 'tavi' && (
            <div className={`side-panel ${reportExpanded ? 'side-panel--report-expanded' : ''}`} style={{ width: reportExpanded ? undefined : '360px' }}>
              <div className="side-panel-tabs">
                <button className={`side-panel-tab ${!reportExpanded ? 'active' : ''}`} onClick={() => { setReportExpanded(false); taviPanelRef.current?.showCapture(); }}>TAVI</button>
                <button className={`side-panel-tab ${reportExpanded ? 'active' : ''}`} onClick={() => { setReportExpanded(true); taviPanelRef.current?.showReport(); }}>Report</button>
                <button className="side-panel-close" onClick={() => { setRightPanel(null); setReportExpanded(false); setViewportMode('standard'); exitDoubleObliqueMode(RENDERING_ENGINE_ID); resizeViewports(); }}>×</button>
              </div>

              <div className="side-panel-body" style={{ padding: 0 }}>
                <TAVIPanel
                  renderingEngineId={RENDERING_ENGINE_ID}
                  volumeId={VOLUME_ID}
                  viewportMode={viewportMode}
                  onViewportModeChange={handleTaviModeChange}
                  panelRef={taviPanelRef}
                  onReportToggle={setReportExpanded}
                />
              </div>
            </div>
          )}

          {rightPanel === 'hand-mr' && (
            <div className="side-panel" style={{ width: '360px' }}>
              <div className="side-panel-tabs">
                <button className="side-panel-tab active">Hand MR</button>
                <button className="side-panel-close" onClick={() => { setRightPanel(null); setViewportMode('standard'); resizeViewports(); }}>×</button>
              </div>
              <div className="side-panel-body" style={{ padding: 0 }}>
                <HandMRPanel
                  ref={handMRPanelRef}
                  renderingEngineId={RENDERING_ENGINE_ID}
                  volumeId={VOLUME_ID}
                  seriesList={seriesList}
                  onLoadSeries={loadSeries}
                />
              </div>
            </div>
          )}

          {volumeResults.length > 0 && <VolumeStats results={volumeResults} />}
        </div>
      )}

      {isLoading && (
        <div className="loading-overlay">
          <div className="loading-card">
            <div className="spinner" />
            <p className="loading-text">{loadingProgress || 'Loading DICOM data...'}</p>
            {loadingProgress && loadingProgress.includes('/') && (() => {
              const match = loadingProgress.match(/(\d+)\/(\d+)/);
              if (!match) return null;
              const [, loaded, total] = match;
              const pct = Math.round((Number(loaded) / Number(total)) * 100);
              return (
                <>
                  <div className="loading-progress-bar">
                    <div className="loading-progress-fill" style={{ width: `${pct}%` }} />
                  </div>
                  <p className="loading-progress-text">{pct}%</p>
                </>
              );
            })()}
          </div>
        </div>
      )}
    </div>
  );
}
