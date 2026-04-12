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

const RENDERING_ENGINE_ID = 'myRenderingEngine';
const VOLUME_ID = 'cornerstoneStreamingImageVolume:myVolume';
const VIEWPORT_IDS = ['axial', 'sagittal', 'coronal', 'volume3d'];
const MPR_VIEWPORT_IDS = ['axial', 'sagittal', 'coronal'];

type RightPanel = null | '3d' | 'tavi';

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

  const loadSeries = async (series: DicomSeriesInfo) => {
    const engine = renderingEngineRef.current;
    if (!engine) return;

    setActiveSeries(series);
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
        viewport3d.setProperties({ preset: 'CT-Chest-Contrast-Enhanced' });
      }

      // Default: enable 5mm Slab MIP + Coronary W/L (WW700/WL350) on all MPR viewports
      // Only for CT modality — skip for MR and others
      const isCT = series.modality?.toUpperCase() === 'CT';
      for (const vpId of MPR_VIEWPORT_IDS) {
        const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
        if (vp && 'setBlendMode' in vp && isCT) {
          (vp as any).setBlendMode(cornerstone.Enums.BlendModes.MAXIMUM_INTENSITY_BLEND);
          (vp as any).setSlabThickness(5);
          (vp as cornerstone.Types.IVolumeViewport).setProperties({
            voiRange: { lower: 350 - 700 / 2, upper: 350 + 700 / 2 },
          });
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
        setViewportMode('standard');
        setReportExpanded(false);
        exitDoubleObliqueMode(RENDERING_ENGINE_ID);
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
          <WindowLevelPresets renderingEngineId={RENDERING_ENGINE_ID} viewportIds={MPR_VIEWPORT_IDS} />
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
            <SeriesPanel seriesList={seriesList} activeSeriesUID={activeSeries?.seriesInstanceUID || ''} onSelectSeries={loadSeries} isLoading={isLoading} />
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
