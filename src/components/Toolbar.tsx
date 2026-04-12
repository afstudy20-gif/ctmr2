import { useState, useEffect, useCallback } from 'react';
import * as cornerstone from '@cornerstonejs/core';
import { setActiveTool, resetCrosshairsToCenter, centerViewportsOnCrosshairs, ToolName } from '../core/toolManager';

const tools: { name: ToolName; label: string; icon: string; shortcut: string; key: string }[] = [
  { name: 'Crosshairs', label: 'Crosshairs', icon: '✛', shortcut: 'C', key: 'c' },
  { name: 'WindowLevel', label: 'W/L', icon: '◐', shortcut: 'W', key: 'w' },
  { name: 'Pan', label: 'Pan', icon: '✋', shortcut: 'H', key: 'h' },
  { name: 'Zoom', label: 'Zoom', icon: '🔍', shortcut: 'Z', key: 'z' },
  { name: 'Length', label: 'Measure', icon: '📏', shortcut: 'M', key: 'm' },
];

const MPR_VP_IDS = ['axial', 'sagittal', 'coronal'];

interface Props {
  renderingEngineId: string;
  onReset?: () => void;
}

export function Toolbar({ renderingEngineId, onReset }: Props) {
  const [activeTool, setActive] = useState<ToolName>('Crosshairs');
  const [mipEnabled, setMipEnabled] = useState(true);  // MIP on by default
  const [slabThickness, setSlabThickness] = useState(5); // mm

  const handleToolClick = useCallback((name: ToolName) => {
    setActiveTool(name);
    setActive(name);
  }, []);

  const handleCenter = useCallback(() => {
    centerViewportsOnCrosshairs(renderingEngineId);
  }, [renderingEngineId]);

  // ── Slab MIP controls ──
  const applyMip = useCallback((enabled: boolean, thickness: number) => {
    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    if (!engine) return;

    for (const vpId of MPR_VP_IDS) {
      const vp = engine.getViewport(vpId) as cornerstone.Types.IVolumeViewport | undefined;
      if (!vp || !('setBlendMode' in vp)) continue;

      if (enabled) {
        (vp as any).setBlendMode(cornerstone.Enums.BlendModes.MAXIMUM_INTENSITY_BLEND);
        (vp as any).setSlabThickness(thickness);
      } else {
        (vp as any).setBlendMode(cornerstone.Enums.BlendModes.COMPOSITE);
        (vp as any).resetSlabThickness?.();
      }
      vp.render();
    }
  }, [renderingEngineId]);

  const toggleMip = useCallback(() => {
    const newVal = !mipEnabled;
    setMipEnabled(newVal);
    applyMip(newVal, slabThickness);
  }, [mipEnabled, slabThickness, applyMip]);

  const handleSlabChange = useCallback((newThickness: number) => {
    setSlabThickness(newThickness);
    if (mipEnabled) {
      applyMip(true, newThickness);
    }
  }, [mipEnabled, applyMip]);

  const handleReset = useCallback(() => {
    // First call parent reset to clean up TAVI mode, double-oblique, etc.
    if (onReset) onReset();

    // Reset MIP
    setMipEnabled(false);
    setSlabThickness(5);
    applyMip(false, 5);

    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    if (!engine) return;

    const viewportIds = ['axial', 'sagittal', 'coronal', 'volume3d'];
    for (const vpId of viewportIds) {
      const viewport = engine.getViewport(vpId);
      if (!viewport) continue;
      viewport.resetCamera();
      viewport.render();
    }

    setTimeout(() => {
      resetCrosshairsToCenter(renderingEngineId);
    }, 100);
  }, [renderingEngineId, onReset, applyMip]);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      // Don't trigger when typing in inputs
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement || e.target instanceof HTMLTextAreaElement) return;
      if (e.ctrlKey || e.metaKey || e.altKey) return;

      if (e.key === 'f' || e.key === 'F') {
        handleCenter();
        return;
      }
      if (e.key === 'r' || e.key === 'R') {
        handleReset();
        return;
      }

      const tool = tools.find(t => t.key === e.key.toLowerCase());
      if (tool) {
        handleToolClick(tool.name);
      }
    };

    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [handleToolClick, handleCenter, handleReset]);

  return (
    <div className="toolbar">
      {tools.map((tool) => (
        <button
          key={tool.name}
          className={`toolbar-btn ${activeTool === tool.name ? 'active' : ''}`}
          onClick={() => handleToolClick(tool.name)}
          title={`${tool.label} (${tool.shortcut})`}
        >
          <span className="tool-icon">{tool.icon}</span>
          <span className="tool-label">{tool.label}</span>
          <span className="tool-shortcut">{tool.shortcut}</span>
        </button>
      ))}
      <button
        className="toolbar-btn"
        onClick={handleCenter}
        title="Center viewports on crosshairs (F)"
      >
        <span className="tool-icon">⊕</span>
        <span className="tool-label">Center</span>
        <span className="tool-shortcut">F</span>
      </button>
      <button
        className="toolbar-btn reset-btn"
        onClick={handleReset}
        title="Reset all viewports (R)"
      >
        <span className="tool-icon">↺</span>
        <span className="tool-label">Reset</span>
        <span className="tool-shortcut">R</span>
      </button>
      <div className="toolbar-divider" />
      {/* Slab MIP toggle + thickness */}
      <button
        className={`toolbar-btn ${mipEnabled ? 'active' : ''}`}
        onClick={toggleMip}
        title="Toggle Slab MIP (Maximum Intensity Projection) on MPR viewports"
      >
        <span className="tool-icon">◈</span>
        <span className="tool-label">MIP</span>
      </button>
      {mipEnabled && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 4px' }}>
          <input
            type="range"
            min={1}
            max={60}
            value={slabThickness}
            onChange={(e) => handleSlabChange(Number(e.target.value))}
            style={{ width: 80, height: 3 }}
            title={`Slab thickness: ${slabThickness}mm`}
          />
          <span style={{ fontSize: '10px', color: 'var(--text-muted)', minWidth: 30 }}>{slabThickness}mm</span>
        </div>
      )}
    </div>
  );
}
