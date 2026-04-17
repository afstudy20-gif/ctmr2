import * as cornerstone from '@cornerstonejs/core';

export interface LASegmentationParams {
  minHU: number;
  maxHU: number;
  seedIJK: [number, number, number];
  maxVoxels?: number;
}

export interface LASegmentationResult {
  voxelCount: number;
  volumeCm3: number;
  labelmapVolumeId: string;
  leaked: boolean;
  data: Uint8Array;
  dims: { dx: number; dy: number; dz: number };
  voxelToWorld: (i: number, j: number, k: number) => [number, number, number];
  voxelVolumeMm3: number;
}

/**
 * Seeded 3D flood-fill region-growing on the contrast-enhanced blood pool.
 * Based on classical LA segmentation: threshold the intracavitary HU range,
 * then connect only voxels reachable from a clinician-placed seed — equivalent
 * to Islands/connected-components filter on the thresholded volume.
 */
export async function segmentLeftAtrium(
  sourceVolumeId: string,
  params: LASegmentationParams
): Promise<LASegmentationResult | null> {
  const sourceVolume = cornerstone.cache.getVolume(sourceVolumeId);
  if (!sourceVolume?.imageData) return null;

  const imageData = sourceVolume.imageData;
  const dims = imageData.getDimensions();
  const spacing = imageData.getSpacing();
  const [dx, dy, dz] = dims;
  const stride = dx * dy;
  const total = dx * dy * dz;

  const scalars = imageData.getPointData().getScalars();
  const getHU = (idx: number): number => scalars.getTuple(idx)?.[0] ?? -1024;

  const [si, sj, sk] = params.seedIJK;
  if (si < 0 || si >= dx || sj < 0 || sj >= dy || sk < 0 || sk >= dz) return null;

  const seedIdx = sk * stride + sj * dx + si;
  const seedHU = getHU(seedIdx);
  if (seedHU < params.minHU || seedHU > params.maxHU) {
    throw new Error(
      `Seed HU ${Math.round(seedHU)} outside threshold [${params.minHU}, ${params.maxHU}]. Place seed inside contrast-enhanced blood pool.`
    );
  }

  const labelmap = new Uint8Array(total);
  const maxVoxels = params.maxVoxels ?? 5_000_000;

  // BFS flood-fill with Int32Array queue; grow by doubling
  let queue = new Int32Array(65536);
  let qHead = 0;
  let qTail = 0;
  const enqueue = (v: number) => {
    if (qTail >= queue.length) {
      const bigger = new Int32Array(queue.length * 2);
      bigger.set(queue);
      queue = bigger;
    }
    queue[qTail++] = v;
  };

  labelmap[seedIdx] = 1;
  enqueue(seedIdx);

  let count = 1;
  let leaked = false;

  while (qHead < qTail) {
    if (count > maxVoxels) {
      leaked = true;
      break;
    }
    const idx = queue[qHead++];
    const k = (idx / stride) | 0;
    const rem = idx - k * stride;
    const j = (rem / dx) | 0;
    const i = rem - j * dx;

    // 6-connected neighbors
    if (i + 1 < dx) {
      const n = idx + 1;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
    if (i - 1 >= 0) {
      const n = idx - 1;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
    if (j + 1 < dy) {
      const n = idx + dx;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
    if (j - 1 >= 0) {
      const n = idx - dx;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
    if (k + 1 < dz) {
      const n = idx + stride;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
    if (k - 1 >= 0) {
      const n = idx - stride;
      if (!labelmap[n]) {
        const hu = getHU(n);
        if (hu >= params.minHU && hu <= params.maxHU) {
          labelmap[n] = 1;
          count++;
          enqueue(n);
        }
      }
    }
  }

  const voxelVolumeMm3 = spacing[0] * spacing[1] * spacing[2];
  const volumeCm3 = (count * voxelVolumeMm3) / 1000;

  // Materialize labelmap volume
  const labelmapVolumeId = `la_labelmap_${Date.now()}`;
  const labelmapVolume = cornerstone.volumeLoader.createAndCacheDerivedLabelmapVolume(
    sourceVolumeId,
    { volumeId: labelmapVolumeId }
  );
  const lmData = labelmapVolume.voxelManager?.getCompleteScalarDataArray?.();
  if (lmData) {
    for (let i = 0; i < total; i++) (lmData as any)[i] = labelmap[i];
    labelmapVolume.voxelManager?.setCompleteScalarDataArray?.(lmData);
  }

  // vtk imageData indexToWorld helper
  const voxelToWorld = (i: number, j: number, k: number): [number, number, number] => {
    const w = imageData.indexToWorld([i, j, k]);
    return [w[0], w[1], w[2]];
  };

  return {
    voxelCount: count,
    volumeCm3,
    labelmapVolumeId,
    leaked,
    data: labelmap,
    dims: { dx, dy, dz },
    voxelToWorld,
    voxelVolumeMm3,
  };
}

/**
 * Materialize a new labelmap volume in the Cornerstone cache with the given data.
 * Useful when reapplying morphological ops / plane cuts on an existing LA mask.
 */
export function materializeLabelmap(
  sourceVolumeId: string,
  data: Uint8Array
): string | null {
  const sourceVolume = cornerstone.cache.getVolume(sourceVolumeId);
  if (!sourceVolume?.imageData) return null;
  const labelmapVolumeId = `la_labelmap_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const labelmapVolume = cornerstone.volumeLoader.createAndCacheDerivedLabelmapVolume(
    sourceVolumeId,
    { volumeId: labelmapVolumeId }
  );
  const lmData = labelmapVolume.voxelManager?.getCompleteScalarDataArray?.();
  if (lmData) {
    for (let i = 0; i < data.length; i++) (lmData as any)[i] = data[i];
    labelmapVolume.voxelManager?.setCompleteScalarDataArray?.(lmData);
  }
  return labelmapVolumeId;
}

/**
 * Convert a world coordinate to voxel IJK indices using the source volume.
 */
export function worldToIJK(
  sourceVolumeId: string,
  worldPos: number[]
): [number, number, number] | null {
  const volume = cornerstone.cache.getVolume(sourceVolumeId);
  if (!volume?.imageData) return null;
  const ijk = volume.imageData.worldToIndex(worldPos);
  const dims = volume.imageData.getDimensions();
  const i = Math.round(ijk[0]);
  const j = Math.round(ijk[1]);
  const k = Math.round(ijk[2]);
  if (i < 0 || i >= dims[0] || j < 0 || j >= dims[1] || k < 0 || k >= dims[2]) return null;
  return [i, j, k];
}
