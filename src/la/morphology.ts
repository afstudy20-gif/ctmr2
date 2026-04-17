/**
 * 3D binary morphology + connected components on flat Uint8Array volumes.
 * All volumes are (dx, dy, dz) with index = k*dx*dy + j*dx + i.
 * Values: 0 = background, non-zero = foreground.
 */

export interface VolumeDims {
  dx: number;
  dy: number;
  dz: number;
}

export function erode3D(src: Uint8Array, dims: VolumeDims, iterations = 1): Uint8Array {
  const { dx, dy, dz } = dims;
  const stride = dx * dy;
  let cur = src;
  for (let it = 0; it < iterations; it++) {
    const out = new Uint8Array(cur.length);
    for (let k = 0; k < dz; k++) {
      for (let j = 0; j < dy; j++) {
        for (let i = 0; i < dx; i++) {
          const idx = k * stride + j * dx + i;
          if (!cur[idx]) continue;
          // 6-connected erosion: all neighbors must be foreground (or clamp at edge as background)
          if (
            i === 0 || i === dx - 1 ||
            j === 0 || j === dy - 1 ||
            k === 0 || k === dz - 1
          ) continue;
          if (
            cur[idx - 1] && cur[idx + 1] &&
            cur[idx - dx] && cur[idx + dx] &&
            cur[idx - stride] && cur[idx + stride]
          ) {
            out[idx] = 1;
          }
        }
      }
    }
    cur = out;
  }
  return cur;
}

export function dilate3D(src: Uint8Array, dims: VolumeDims, iterations = 1): Uint8Array {
  const { dx, dy, dz } = dims;
  const stride = dx * dy;
  let cur = src;
  for (let it = 0; it < iterations; it++) {
    const out = new Uint8Array(cur.length);
    for (let k = 0; k < dz; k++) {
      for (let j = 0; j < dy; j++) {
        for (let i = 0; i < dx; i++) {
          const idx = k * stride + j * dx + i;
          if (cur[idx]) {
            out[idx] = 1;
            continue;
          }
          if (
            (i > 0 && cur[idx - 1]) ||
            (i < dx - 1 && cur[idx + 1]) ||
            (j > 0 && cur[idx - dx]) ||
            (j < dy - 1 && cur[idx + dx]) ||
            (k > 0 && cur[idx - stride]) ||
            (k < dz - 1 && cur[idx + stride])
          ) {
            out[idx] = 1;
          }
        }
      }
    }
    cur = out;
  }
  return cur;
}

/**
 * Keep only the largest 6-connected foreground component.
 * Single BFS pass with Int32Array queue; component-size tallying.
 */
export function largestComponent(src: Uint8Array, dims: VolumeDims): Uint8Array {
  const { dx, dy, dz } = dims;
  const stride = dx * dy;
  const total = src.length;

  const labels = new Int32Array(total); // 0 = unvisited, >0 = component id
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

  let currentLabel = 0;
  let bestLabel = 0;
  let bestSize = 0;

  for (let start = 0; start < total; start++) {
    if (!src[start] || labels[start]) continue;
    currentLabel++;
    labels[start] = currentLabel;
    qHead = qTail = 0;
    enqueue(start);
    let size = 0;
    while (qHead < qTail) {
      const idx = queue[qHead++];
      size++;
      const k = (idx / stride) | 0;
      const rem = idx - k * stride;
      const j = (rem / dx) | 0;
      const i = rem - j * dx;
      if (i + 1 < dx) {
        const n = idx + 1;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
      if (i - 1 >= 0) {
        const n = idx - 1;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
      if (j + 1 < dy) {
        const n = idx + dx;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
      if (j - 1 >= 0) {
        const n = idx - dx;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
      if (k + 1 < dz) {
        const n = idx + stride;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
      if (k - 1 >= 0) {
        const n = idx - stride;
        if (src[n] && !labels[n]) { labels[n] = currentLabel; enqueue(n); }
      }
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = currentLabel;
    }
  }

  const out = new Uint8Array(total);
  if (bestLabel > 0) {
    for (let i = 0; i < total; i++) {
      if (labels[i] === bestLabel) out[i] = 1;
    }
  }
  return out;
}

/**
 * Morphological opening by reconstruction:
 *   erode N → keep only largest connected component → dilate N → AND with original.
 * Acts as distance-transform narrowing-cut surrogate: prunes thin cylindrical
 * branches (pulmonary veins) while preserving the LA body. Radius controls
 * which branches survive (≈ radius voxels × voxel spacing mm).
 */
export function trimThinBranches(
  src: Uint8Array,
  dims: VolumeDims,
  radius: number
): Uint8Array {
  const eroded = erode3D(src, dims, radius);
  const core = largestComponent(eroded, dims);
  const dilated = dilate3D(core, dims, radius);
  const out = new Uint8Array(src.length);
  for (let i = 0; i < src.length; i++) {
    out[i] = src[i] && dilated[i] ? 1 : 0;
  }
  return out;
}

/**
 * Cut labelmap at a plane defined by worldOrigin + normal. Remove foreground voxels
 * on the side where (worldVoxel - origin) · normal > 0.
 * voxelToWorld: function mapping (i,j,k) → world coordinates (mm).
 */
export function cutAtPlane(
  src: Uint8Array,
  dims: VolumeDims,
  voxelToWorld: (i: number, j: number, k: number) => [number, number, number],
  planeOrigin: [number, number, number],
  planeNormal: [number, number, number]
): Uint8Array {
  const { dx, dy, dz } = dims;
  const stride = dx * dy;
  const out = new Uint8Array(src.length);
  const [nx, ny, nz] = planeNormal;
  const [ox, oy, oz] = planeOrigin;
  for (let k = 0; k < dz; k++) {
    for (let j = 0; j < dy; j++) {
      for (let i = 0; i < dx; i++) {
        const idx = k * stride + j * dx + i;
        if (!src[idx]) continue;
        const [wx, wy, wz] = voxelToWorld(i, j, k);
        const dot = (wx - ox) * nx + (wy - oy) * ny + (wz - oz) * nz;
        if (dot <= 0) out[idx] = 1;
      }
    }
  }
  return out;
}

export function countVoxels(vol: Uint8Array): number {
  let n = 0;
  for (let i = 0; i < vol.length; i++) if (vol[i]) n++;
  return n;
}
