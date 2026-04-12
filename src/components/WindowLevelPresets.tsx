import { useState, useRef, useEffect } from 'react';
import * as cornerstone from '@cornerstonejs/core';

interface Preset {
  name: string;
  window: number;
  level: number;
  description: string;
}

const PRESETS: Preset[] = [
  { name: 'Coronary', window: 700, level: 350, description: 'Coronary arteries (standard)' },
  { name: 'TAVI', window: 555, level: 208, description: 'Aortic valve planning' },
  { name: 'CT Angio', window: 600, level: 300, description: 'Vascular contrast' },
  { name: 'Thorax', window: 800, level: 200, description: 'Thorax overview' },
  { name: 'CT Abdomen', window: 400, level: 40, description: 'Soft tissue' },
  { name: 'CT Lung', window: 1500, level: -600, description: 'Lung parenchyma' },
  { name: 'CT Bone', window: 2000, level: 300, description: 'Bone structures' },
  { name: '100kV', window: 1800, level: 700, description: '100kV coronary protocol' },
  { name: 'Cardiac Fat', window: 170, level: -115, description: 'Epicardial fat' },
  { name: 'Mediastinum', window: 350, level: 50, description: 'Mediastinal' },
];

interface Props {
  renderingEngineId: string;
  viewportIds: string[];
}

export function WindowLevelPresets({ renderingEngineId, viewportIds }: Props) {
  const [activePreset, setActivePreset] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!isOpen) return;
    const handleClick = (e: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [isOpen]);

  const applyPreset = (preset: Preset) => {
    const engine = cornerstone.getRenderingEngine(renderingEngineId);
    if (!engine) return;

    for (const vpId of viewportIds) {
      const viewport = engine.getViewport(vpId);
      if (!viewport) continue;
      if (viewport.type === cornerstone.Enums.ViewportType.VOLUME_3D) continue;

      const properties = (viewport as cornerstone.Types.IVolumeViewport).getProperties();
      (viewport as cornerstone.Types.IVolumeViewport).setProperties({
        ...properties,
        voiRange: {
          lower: preset.level - preset.window / 2,
          upper: preset.level + preset.window / 2,
        },
      });
      viewport.render();
    }

    setActivePreset(preset.name);
    setIsOpen(false);
  };

  return (
    <div className="wl-dropdown" ref={dropdownRef}>
      <button
        className={`toolbar-btn ${isOpen ? 'active' : ''}`}
        onClick={() => setIsOpen(!isOpen)}
        title="Window/Level Presets"
      >
        <span className="tool-icon">◐</span>
        <span className="tool-label">{activePreset || 'W/L'}</span>
        <span className="wl-dropdown-arrow">{isOpen ? '▲' : '▼'}</span>
      </button>
      {isOpen && (
        <div className="wl-dropdown-menu">
          {PRESETS.map((preset) => (
            <button
              key={preset.name}
              className={`wl-dropdown-item ${activePreset === preset.name ? 'active' : ''}`}
              onClick={() => applyPreset(preset)}
            >
              <span className="wl-dropdown-name">{preset.name}</span>
              <span className="wl-dropdown-desc">W:{preset.window} L:{preset.level}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
