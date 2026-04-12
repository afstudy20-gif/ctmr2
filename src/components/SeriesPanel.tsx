import { DicomSeriesInfo } from '../core/dicomLoader';

interface Props {
  seriesList: DicomSeriesInfo[];
  activeSeriesUID: string;
  onSelectSeries: (series: DicomSeriesInfo) => void;
  isLoading: boolean;
}

export function SeriesPanel({ seriesList, activeSeriesUID, onSelectSeries, isLoading }: Props) {
  return (
    <div className="series-panel">
      <div className="series-panel-header">
        <h3>Series</h3>
        <span className="series-count">{seriesList.length}</span>
      </div>
      <div className="series-panel-list">
        {seriesList.map((series) => (
          <button
            key={series.seriesInstanceUID}
            className={`series-panel-item ${series.seriesInstanceUID === activeSeriesUID ? 'active' : ''}`}
            onClick={() => onSelectSeries(series)}
            disabled={isLoading}
            title={`${series.seriesDescription}\n${series.modality} - ${series.numImages} images`}
          >
            <div className="series-panel-item-header">
              <span className="series-modality">{series.modality}</span>
              <span className="series-count-badge">{series.numImages}</span>
            </div>
            <div className="series-panel-item-desc">{series.seriesDescription || 'Unknown'}</div>
          </button>
        ))}
      </div>
    </div>
  );
}
