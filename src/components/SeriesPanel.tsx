import { useState, useEffect, useRef } from 'react';
import * as cornerstone from '@cornerstonejs/core';
import { DicomSeriesInfo } from '../core/dicomLoader';

interface Props {
  seriesList: DicomSeriesInfo[];
  activeSeriesUID: string;
  onSelectSeries: (series: DicomSeriesInfo) => void;
  isLoading: boolean;
}

// Generate a thumbnail from the middle image of a series
async function generateThumbnail(imageId: string): Promise<string | null> {
  try {
    const image = await cornerstone.imageLoader.loadAndCacheImage(imageId);
    if (!image) return null;

    const canvas = document.createElement('canvas');
    const size = 64;
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    if (!ctx) return null;

    // Get pixel data
    const { rows, columns } = image;
    const pixelData = image.getPixelData();
    if (!pixelData || pixelData.length === 0) return null;

    // Find min/max for auto-windowing
    let min = Infinity, max = -Infinity;
    for (let i = 0; i < pixelData.length; i++) {
      if (pixelData[i] < min) min = pixelData[i];
      if (pixelData[i] > max) max = pixelData[i];
    }
    // Use percentile windowing for better contrast
    const range = max - min || 1;

    // Draw scaled image
    const imgData = ctx.createImageData(size, size);
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) {
        const srcX = Math.floor(x * columns / size);
        const srcY = Math.floor(y * rows / size);
        const srcIdx = srcY * columns + srcX;
        const val = Math.round(((pixelData[srcIdx] - min) / range) * 255);
        const clamped = Math.max(0, Math.min(255, val));
        const dstIdx = (y * size + x) * 4;
        imgData.data[dstIdx] = clamped;
        imgData.data[dstIdx + 1] = clamped;
        imgData.data[dstIdx + 2] = clamped;
        imgData.data[dstIdx + 3] = 255;
      }
    }
    ctx.putImageData(imgData, 0, 0);
    return canvas.toDataURL('image/jpeg', 0.7);
  } catch {
    return null;
  }
}

export function SeriesPanel({ seriesList, activeSeriesUID, onSelectSeries, isLoading }: Props) {
  const [thumbnails, setThumbnails] = useState<Record<string, string | null>>({});
  const loadedRef = useRef<Set<string>>(new Set());

  // Generate thumbnails for each series (middle image)
  useEffect(() => {
    for (const series of seriesList) {
      if (loadedRef.current.has(series.seriesInstanceUID)) continue;
      loadedRef.current.add(series.seriesInstanceUID);

      const midIdx = Math.floor(series.imageIds.length / 2);
      const imageId = series.imageIds[midIdx];
      if (!imageId) continue;

      generateThumbnail(imageId).then(thumb => {
        if (thumb) {
          setThumbnails(prev => ({ ...prev, [series.seriesInstanceUID]: thumb }));
        }
      });
    }
  }, [seriesList]);

  return (
    <div className="series-panel">
      <div className="series-panel-header">
        <h3>SERIES</h3>
        <span className="series-count">{seriesList.length}</span>
      </div>
      <div className="series-panel-list">
        {seriesList.map((series) => {
          const thumb = thumbnails[series.seriesInstanceUID];
          const isActive = series.seriesInstanceUID === activeSeriesUID;
          return (
            <button
              key={series.seriesInstanceUID}
              className={`series-panel-item ${isActive ? 'active' : ''}`}
              onClick={() => onSelectSeries(series)}
              disabled={isLoading}
              title={`${series.seriesDescription}\n${series.modality} - ${series.numImages} images`}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 8,
                padding: '6px 8px',
                minHeight: 52,
              }}
            >
              {/* Thumbnail */}
              <div style={{
                width: 48, height: 48, flexShrink: 0,
                background: '#111', borderRadius: 4,
                overflow: 'hidden',
                border: isActive ? '2px solid var(--accent)' : '2px solid transparent',
              }}>
                {thumb && <img src={thumb} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />}
              </div>

              {/* Info */}
              <div style={{ flex: 1, minWidth: 0, textAlign: 'left' }}>
                <div className="series-panel-item-header" style={{ marginBottom: 2 }}>
                  <span className="series-modality">{series.modality}</span>
                  <span className="series-count-badge">{series.numImages}</span>
                </div>
                <div className="series-panel-item-desc" style={{
                  fontSize: '11px',
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}>
                  {series.seriesDescription || 'Unknown'}
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
