// Status masthead — three rails:
//   1. brand + jail state + the directory
//   2. the ROI line: a hero count (escapes blocked) with the jail-held verdict
//   3. the proportion bar + per-category tallies + access-rate sparkline
// All tinted as rails via the container bg for reliable full-width fills.
import { Box, Text, bold, fg, bg, idx, C, sep } from "@/lib/theme.js";
import { fmtCount, fmtRate, sparkline, splitBarFrac } from "@/lib/format.js";

// Colour map for the fractional proportion bar (keys from splitBarFrac).
const barCol = (k) =>
  k === "a" ? fg(C.safe) : k === "s" ? fg(C.system)
  : k === "b" ? fg(C.block) : fg(C.leak);

const BAR_W = 30;

// Raised key/value chip on the rail.
const chip = (label, value, color) => [
  bg(C.railHi)(fg(C.textDim)(` ${label} `)),
  bg(C.railHi)(bold(fg(color)(`${value} `))),
];

export default ({ stats, mode, dir }) => (
  <Box direction="column" height="3">
    {/* row 1 — masthead */}
    <Box height="1" direction="row" bg={C.rail}>
      <Text break="none">
        {() => {
          const on = mode === "jail";
          const badge = on
            ? bold(fg(C.safe)(" ⊟ JAILED "))
            : bold(bg(C.leak)(fg(idx(231))(" ⚠ AUDIT · UNCONFINED ")));
          return [
            bold(fg(C.brand)(" ▢ agent-lock")), fg(C.brandDim)(" ⌁ "), badge,
            sep, fg(C.textDim)("confined to "), fg(C.text)(dir),
          ];
        }}
      </Text>
    </Box>

    {/* row 2 — the ROI hero line */}
    <Box height="1" direction="row" bg={C.rail}>
      <Text break="none">
        {() => {
          const s = stats.get();
          const on = mode === "jail";
          if (on && s.blocked > 0 && s.reached === 0) {
            return [
              " ", bold(fg(C.safe)("✓ ")),
              bold(fg(C.safe)(fmtCount(s.blocked))),
              fg(C.text)(" escape attempts blocked"),
              fg(C.textDim)(" — the jail is holding."),
              s.sensitiveHits > 0
                ? [sep, fg(C.fire)("🔥 "), bold(fg(C.fire)(fmtCount(s.sensitiveHits))), fg(C.textDim)(" at sensitive files")]
                : "",
            ];
          }
          if (s.reached > 0) {
            return [
              " ", bold(fg(C.leak)("⚠ ")),
              bold(fg(C.leak)(fmtCount(s.reached))),
              fg(C.text)(" out-of-bounds reads got through"),
              fg(C.textDim)(on ? "" : " — run without --audit to block them."),
            ];
          }
          return [" ", fg(C.textDim)("watching "), fg(C.text)("omp"),
                  fg(C.textDim)(" — no escape attempts yet.")];
        }}
      </Text>
    </Box>

    {/* row 3 — proportion bar + tallies + sparkline */}
    <Box height="1" direction="row" bg={C.rail}>
      <Text break="none">
        {() => {
          const s = stats.get();
          // Fractional fill: a lone blocked/reached attempt still shows a sliver
          // instead of rounding away — the whole point of a security bar.
          const bar = splitBarFrac(
            s.allowed, s.system || 0, s.blocked, s.reached, BAR_W,
            barCol, fg(C.frame),
          );
          const win = s.spark.slice(-20);
          const rate = s.spark.length ? s.spark[s.spark.length - 1] : 0;
          // Scale the 20-bucket (~8s) display against the FULL 80-bucket (~32s)
          // history peak, not the window's own max. Now a lull reads as low bars
          // and a burst spikes — self-scaling per-window made every stretch look
          // equally full, hiding exactly the rise this line is meant to show.
          const ceil = s.spark.reduce((m, v) => (v > m ? v : m), 0);
          return [
            " ", ...bar, "  ",
            bold(fg(C.safe)(fmtCount(s.allowed))), fg(C.textDim)(" in-bounds"), sep,
            bold(fg(C.block)(fmtCount(s.blocked))), fg(C.textDim)(" blocked"),
            s.reached > 0 ? [sep, bold(fg(C.leak)(fmtCount(s.reached))), fg(C.leak)(" reached")] : "",
            sep, fg(C.system)(`${fmtCount(s.system || 0)} system`),
            sep, fg(C.safeDim)(sparkline(win, ceil)), fg(C.textDim)(` ${fmtRate(rate)}/s`),
          ];
        }}
      </Text>
    </Box>
  </Box>
);
