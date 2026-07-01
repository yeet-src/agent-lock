// Pure presentation helpers — strings and color, no signals or BPF.
// Imported by the components through the `@/` alias (resolved at bundle time).
import { idx } from "yeet:tui";

export const pad = (s, n) => (s + " ".repeat(n)).slice(0, n);
export const lpad = (s, n) => (" ".repeat(n) + s).slice(-n);

// A rate as a short human string: 12, 4.2K, 1.1M (per second).
export const fmtRate = (perSec) => {
  if (perSec < 1000) return `${Math.round(perSec)}`;
  if (perSec < 1e6) return `${(perSec / 1e3).toFixed(1)}K`;
  return `${(perSec / 1e6).toFixed(1)}M`;
};

// A count as a short string: 0, 42, 1.2K, 3.4M.
export const fmtCount = (n) => {
  if (n < 1000) return `${n}`;
  if (n < 1e6) return `${(n / 1e3).toFixed(1)}K`;
  return `${(n / 1e6).toFixed(1)}M`;
};

// Collapse the user's home prefix to "~" and clip a long path to `n` cells,
// keeping the meaningful tail (filename) visible: /home/u/.ssh/id_rsa -> …/.ssh/id_rsa.
export const tildify = (path, home) =>
  home && path.indexOf(home) === 0 ? "~" + path.slice(home.length) : path;

export const clipPath = (path, n) => {
  if (path.length <= n) return path;
  return "…" + path.slice(-(n - 1));
};

// Unicode sparkline from a series of values.
const BARS = "▁▂▃▄▅▆▇█";
// `ceiling` fixes the top of the scale so a quiet stretch and a busy one look
// DIFFERENT — self-scaling (the old default) made every window look identically
// full. Pass the rolling max the caller tracks; falls back to the series max
// only when no ceiling is given (back-compat).
export const sparkline = (series, ceiling) => {
  const top = ceiling && ceiling > 0
    ? ceiling
    : series.reduce((m, v) => (v > m ? v : m), 0);
  if (top <= 0) return BARS[0].repeat(series.length);
  let out = "";
  for (const v of series) {
    const f = Math.min(1, v / top);
    out += BARS[Math.min(BARS.length - 1, Math.max(0, Math.round(f * (BARS.length - 1))))];
  }
  return out;
};

// A horizontal proportion bar of `width` cells split
// in-bounds | system | blocked | reached. Returns integer cell counts so the
// caller colours each run. System (benign permitted reads) is shown dim so the
// bar reflects reality without making routine system access look alarming.
export const splitBar = (allowed, system, blocked, reached, width) => {
  const total = allowed + system + blocked + reached;
  if (total === 0) return { a: 0, s: 0, b: 0, l: 0, rest: width };
  const a = Math.round((allowed / total) * width);
  const s = Math.round((system / total) * width);
  const l = Math.round((reached / total) * width);
  const b = Math.max(0, width - a - s - l);
  return { a, s, b, l, rest: 0 };
};

// Fractional-fill variant: a security proportion bar must never round a
// nonzero enforcement category (blocked/reached) down to ZERO cells — that
// would hide the one thing this tool exists to show. Any nonzero share gets at
// least a 1/8 sliver via the eighth-block glyphs. Returns styled runs the
// caller colours, ordered in-bounds | system | blocked | reached | track.
// `col` maps a segment key -> a color fn; `trackCol` colours the empty tail.
const HBAR = "▏▎▍▌▋▊▉█"; // 1/8 .. 8/8
const eighths = (frac, width) => {
  // Number of eighth-cells (0..width*8), min 1 for any nonzero share so a
  // lone blocked attempt still shows.
  const raw = frac * width * 8;
  return frac > 0 ? Math.max(1, Math.round(raw)) : 0;
};
export const splitBarFrac = (allowed, system, blocked, reached, width, col, trackCol) => {
  const total = allowed + system + blocked + reached;
  if (total === 0) return [trackCol("░".repeat(width))];
  const segs = [
    ["a", allowed], ["s", system], ["b", blocked], ["l", reached],
  ];
  let usedCells = 0;
  const runs = [];
  for (const [key, val] of segs) {
    let e = eighths(val / total, width);
    if (e === 0) continue;
    // Don't overrun the bar; leave room only if later nonzero segments exist.
    const remainingCells = width - usedCells;
    if (remainingCells <= 0) break;
    const full = Math.floor(e / 8);
    const rem = e % 8;
    let cells = Math.min(full, remainingCells);
    let str = "█".repeat(cells);
    if (rem > 0 && cells < remainingCells) { str += HBAR[rem - 1]; cells += 1; }
    if (str) { runs.push(col(key)(str)); usedCells += cells; }
  }
  if (usedCells < width) runs.push(trackCol("░".repeat(width - usedCells)));
  return runs;
};
