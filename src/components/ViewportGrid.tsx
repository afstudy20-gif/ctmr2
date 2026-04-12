import { useState, useCallback, useEffect } from 'react';
import * as cornerstone from '@cornerstonejs/core';
import { OrientationOverlay } from './OrientationOverlay';

type ViewportName = 'axial' | 'sagittal' | 'coronal' | '3d';

export type ViewportMode = 'standard' | 'tavi-crosshair' | 'tavi-oblique' | 'volume-3d' | 'hand-mr';

// Labels per mode
const LABELS: Record<ViewportMode, Record<ViewportName, string>> = {
  standard: { axial: 'Axial', sagittal: 'Sagittal', coronal: 'Coronal', '3d': '3D Volume' },
  'tavi-crosshair': { axial: 'Axial', sagittal: 'Sagittal', coronal: 'Coronal', '3d': '3D Volume' },
  'tavi-oblique': { axial: 'Reference (Longitudinal)', sagittal: 'Sagittal', coronal: 'Working (Cross-section)', '3d': '3D Volume' },
  'volume-3d': { axial: 'Axial', sagittal: 'Sagittal', coronal: 'Coronal', '3d': '3D Volume' },
  'hand-mr': { axial: 'Axial', sagittal: 'Sagittal', coronal: 'Coronal', '3d': '3D Volume' },
};

// Which viewports are visible per mode
const VISIBLE: Record<ViewportMode, Set<ViewportName>> = {
  standard: new Set(['axial', 'sagittal', 'coronal', '3d']),
  'tavi-crosshair': new Set(['axial', 'sagittal', 'coronal']),
  'tavi-oblique': new Set(['axial', 'sagittal', 'coronal']),
  'volume-3d': new Set(['3d']),
  'hand-mr': new Set(['axial', 'sagittal', 'coronal']),
};

interface Props {
  hide3d?: boolean;
  mode?: ViewportMode;
}

export function ViewportGrid({ hide3d, mode = 'standard' }: Props) {
  const [expanded, setExpanded] = useState<ViewportName | null>(null);

  const toggle = useCallback((name: ViewportName) => {
    setExpanded((prev) => (prev === name ? null : name));
  }, []);

  useEffect(() => {
    if (!expanded) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setExpanded(null);
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [expanded]);

  useEffect(() => {
    // Explicitly resize Cornerstone canvases when layout changes
    const timer = setTimeout(() => {
      const engine = cornerstone.getRenderingEngine('myRenderingEngine');
      if (engine) {
        engine.resize(true, false);
      }
    }, 80);
    return () => clearTimeout(timer);
  }, [expanded, hide3d, mode]);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.closest('.viewport')) {
        e.preventDefault();
      }
    };
    document.addEventListener('contextmenu', handler);
    return () => document.removeEventListener('contextmenu', handler);
  }, []);

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (e.button === 1) {
        const target = e.target as HTMLElement;
        if (target.closest('.viewport')) {
          e.preventDefault();
          e.stopPropagation();
        }
      }
    };
    document.addEventListener('mousedown', handler);
    document.addEventListener('auxclick', handler);
    return () => {
      document.removeEventListener('mousedown', handler);
      document.removeEventListener('auxclick', handler);
    };
  }, []);

  const visibleSet = VISIBLE[mode];
  const labels = LABELS[mode];

  const gridClass = mode === 'volume-3d'
    ? 'viewport-grid viewport-grid--3d-only'
    : mode === 'tavi-oblique'
      ? 'viewport-grid viewport-grid--double-oblique'
      : mode === 'tavi-crosshair'
        ? 'viewport-grid viewport-grid--mpr-only'
        : hide3d
          ? 'viewport-grid viewport-grid--mpr-only'
          : expanded
            ? 'viewport-grid viewport-grid--fullscreen'
            : 'viewport-grid';

  // Always render all 4 viewports so Cornerstone DOM elements persist across mode switches.
  // Visibility is controlled purely by CSS classes.
  // Map viewport name to Cornerstone viewport ID
  const allViewports: { id: string; name: ViewportName; csId: string }[] = [
    { id: 'viewport-axial', name: 'axial', csId: 'axial' },
    { id: 'viewport-sagittal', name: 'sagittal', csId: 'sagittal' },
    { id: 'viewport-coronal', name: 'coronal', csId: 'coronal' },
    { id: 'viewport-3d', name: '3d', csId: 'volume3d' },
  ];

  const RENDERING_ENGINE_ID = 'myRenderingEngine';

  return (
    <div className={gridClass}>
      {allViewports.map((vp) => {
        const isVisible = visibleSet.has(vp.name) && !(hide3d && vp.name === '3d');
        const isHidden = !isVisible || (expanded && expanded !== vp.name);
        return (
          <div
            key={vp.name}
            className={`viewport-container ${vp.name === '3d' ? 'viewport-container-3d' : ''} ${isHidden ? 'viewport-hidden' : ''} ${expanded === vp.name ? 'viewport-expanded' : ''}`}
          >
            <div className="viewport-label">
              <span className={`viewport-label-dot viewport-label-dot--${vp.name}`} />
              {labels[vp.name]}
            </div>
            {mode === 'standard' && isVisible && (
              <button
                className="viewport-fullscreen-btn"
                onClick={() => toggle(vp.name)}
                title={expanded === vp.name ? 'Exit fullscreen (Esc)' : 'Fullscreen'}
              >
                {expanded === vp.name ? '⊡' : '⊞'}
              </button>
            )}
            <div id={vp.id} className="viewport" />
            {isVisible && (
              <OrientationOverlay
                viewportId={vp.csId}
                renderingEngineId={RENDERING_ENGINE_ID}
                is3d={vp.name === '3d'}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
