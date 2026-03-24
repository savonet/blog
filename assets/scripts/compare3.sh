#!/usr/bin/env bash
# Three-way comparison: baseline vs top-1 vs top-2, parallel, fixed duration.
#
# Usage: ./compare3.sh [options]
#   -c CMD      Command to run (default: ./liquidsoap_wrapper.sh)
#   -d SECS     Duration in seconds (default: 10800 = 3h)
#   -i SECS     Sampling interval (default: 5)
#   -o DIR      Output directory (default: ./results)

set -euo pipefail

COMMAND="${PERF_CMD:-./liquidsoap_wrapper.sh}"
DURATION=10800
INTERVAL=5
RESULTS_DIR="$(cd "$(dirname "$0")" && pwd)/results"

# baseline: current default
BASE_FRAME=0.02; BASE_HEAP=32768; BASE_OH=80

# top-1 (Pareto #1): best combined score
TOP1_FRAME=0.10; TOP1_HEAP=16384; TOP1_OH=40

# top-2 (Pareto #2): best memory
TOP2_FRAME=0.02; TOP2_HEAP=4096;  TOP2_OH=80

while getopts "c:d:i:o:h" opt; do
  case $opt in
    c) COMMAND="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    o) RESULTS_DIR="$OPTARG" ;;
    h) sed -n '3,7p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$RESULTS_DIR/compare3_${RUN_ID}"
mkdir -p "$RUN_DIR"

echo "=== Three-way comparison ==="
echo "Run ID   : $RUN_ID"
echo "Baseline : frame=${BASE_FRAME}  heap=${BASE_HEAP}w  overhead=${BASE_OH}"
echo "Top-1    : frame=${TOP1_FRAME}  heap=${TOP1_HEAP}w  overhead=${TOP1_OH}"
echo "Top-2    : frame=${TOP2_FRAME}  heap=${TOP2_HEAP}w  overhead=${TOP2_OH}"
echo "Duration : ${DURATION}s ($(( DURATION / 3600 ))h$(( (DURATION % 3600) / 60 ))m)"
echo "Output   : $RUN_DIR"
echo

# ── Monitor ────────────────────────────────────────────────────────────────────
monitor() {
  local pid="$1"
  local sample_file="$2"
  local start_time
  start_time=$(date +%s)
  local end_time=$(( start_time + DURATION ))

  while kill -0 "$pid" 2>/dev/null && [[ $(date +%s) -lt $end_time ]]; do
    read -r cpu rss < <(ps -p "$pid" -o %cpu=,rss= 2>/dev/null) || break
    cpu="${cpu// /}"; rss="${rss// /}"
    if [[ -n "$cpu" && -n "$rss" ]]; then
      elapsed=$(( $(date +%s) - start_time ))
      rss_mb=$(awk "BEGIN { printf \"%.1f\", $rss / 1024 }")
      echo "$elapsed $cpu $rss_mb" >> "$sample_file"
    fi
    sleep "$INTERVAL"
  done
}

# ── Launch all three ───────────────────────────────────────────────────────────
BASE_SAMPLES="$RUN_DIR/baseline.txt"
TOP1_SAMPLES="$RUN_DIR/top1.txt"
TOP2_SAMPLES="$RUN_DIR/top2.txt"

echo "Starting baseline (frame=${BASE_FRAME}, heap=${BASE_HEAP}, overhead=${BASE_OH})..."
$COMMAND "$BASE_FRAME" "$BASE_HEAP" "$BASE_OH" >"$RUN_DIR/baseline.log" 2>&1 &
BASE_PID=$!
monitor "$BASE_PID" "$BASE_SAMPLES" &

echo "Starting top-1    (frame=${TOP1_FRAME}, heap=${TOP1_HEAP}, overhead=${TOP1_OH})..."
$COMMAND "$TOP1_FRAME" "$TOP1_HEAP" "$TOP1_OH" >"$RUN_DIR/top1.log" 2>&1 &
TOP1_PID=$!
monitor "$TOP1_PID" "$TOP1_SAMPLES" &

echo "Starting top-2    (frame=${TOP2_FRAME}, heap=${TOP2_HEAP}, overhead=${TOP2_OH})..."
$COMMAND "$TOP2_FRAME" "$TOP2_HEAP" "$TOP2_OH" >"$RUN_DIR/top2.log" 2>&1 &
TOP2_PID=$!
monitor "$TOP2_PID" "$TOP2_SAMPLES" &

echo
echo "Running for ${DURATION}s ($(( DURATION / 3600 ))h$(( (DURATION % 3600) / 60 ))m)..."
sleep "$DURATION"

echo
echo "Stopping processes (SIGKILL)..."
kill -9 "$BASE_PID" "$TOP1_PID" "$TOP2_PID" 2>/dev/null || true
wait

# ── Text summary ───────────────────────────────────────────────────────────────
SUMMARY="$RUN_DIR/summary.txt"
{
  echo "Three-way comparison — run $RUN_ID"
  echo "Duration: ${DURATION}s  |  Interval: ${INTERVAL}s"
  echo
  printf "%-42s  %8s  %8s  %8s  %8s  %9s  %9s  %9s\n" \
    "" "SAMPLES" "CPU AVG" "CPU MAX" "CPU σ" "MEM AVG" "MEM MAX" "MEM σ"
  echo "──────────────────────────────────────────────────────────────────────────────────────────"

  print_row() {
    local tag="$1" sf="$2"
    if [[ ! -s "$sf" ]]; then
      printf "%-42s  (no data)\n" "$tag"; return
    fi
    local stats
    stats=$(awk '
      BEGIN { cs=0;cs2=0;ms=0;ms2=0;cmax=0;mmax=0;n=0 }
      NR>1 { c=$2+0; m=$3+0
        if(c>cmax) cmax=c; if(m>mmax) mmax=m
        cs+=c; cs2+=c*c; ms+=m; ms2+=m*m; n++ }
      END { if(n==0){print "0 0 0 0 0 0 0";exit}
        ca=cs/n; ma=ms/n
        cv=(cs2/n)-(ca*ca); mv=(ms2/n)-(ma*ma)
        printf "%d %.2f %.2f %.2f %.1f %.1f %.1f\n",
          n,ca,cmax,(cv>0)?sqrt(cv):0,ma,mmax,(mv>0)?sqrt(mv):0 }
    ' "$sf")
    read -r n cavg cmax cstd mavg mmax mstd <<< "$stats"
    printf "%-42s  %8s  %8s  %8s  %8s  %9s  %9s  %9s\n" \
      "$tag" "$n" "${cavg}%" "${cmax}%" "$cstd" "${mavg}MB" "${mmax}MB" "${mstd}MB"
  }

  print_row "baseline (f=${BASE_FRAME}/h=${BASE_HEAP}/oh=${BASE_OH})" "$BASE_SAMPLES"
  print_row "top-1    (f=${TOP1_FRAME}/h=${TOP1_HEAP}/oh=${TOP1_OH})" "$TOP1_SAMPLES"
  print_row "top-2    (f=${TOP2_FRAME}/h=${TOP2_HEAP}/oh=${TOP2_OH})" "$TOP2_SAMPLES"
  echo "──────────────────────────────────────────────────────────────────────────────────────────"
} | tee "$SUMMARY"

# ── Plot ───────────────────────────────────────────────────────────────────────
PLOT_FILE="$RUN_DIR/comparison.png"

python3 - \
  "$BASE_SAMPLES" "$TOP1_SAMPLES" "$TOP2_SAMPLES" \
  "$BASE_FRAME" "$BASE_HEAP" "$BASE_OH" \
  "$TOP1_FRAME" "$TOP1_HEAP" "$TOP1_OH" \
  "$TOP2_FRAME" "$TOP2_HEAP" "$TOP2_OH" \
  "$RUN_ID" "$PLOT_FILE" "$DURATION" <<'PYEOF'
import sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

(base_f, top1_f, top2_f,
 bf, bh, boh,
 t1f, t1h, t1oh,
 t2f, t2h, t2oh,
 run_id, out_file, duration) = sys.argv[1:]

SMOOTH = 60   # 5-min rolling average at 5s interval

COLORS = ["#E07B39", "#3A86C8", "#4BAE7F"]   # orange, blue, green
LABELS = [
    f"baseline  f={bf}/h={bh}/oh={boh}",
    f"top-1     f={t1f}/h={t1h}/oh={t1oh}",
    f"top-2     f={t2f}/h={t2h}/oh={t2oh}",
]
BOX_LABELS = [
    f"baseline\nf={bf}\nh={bh}/oh={boh}",
    f"top-1\nf={t1f}\nh={t1h}/oh={t1oh}",
    f"top-2\nf={t2f}\nh={t2h}/oh={t2oh}",
]

def load(path):
    try:
        pts = np.loadtxt(path)
        if pts.ndim < 2 or len(pts) < 2:
            return None
        return pts[1:]
    except Exception:
        return None

datasets = [load(base_f), load(top1_f), load(top2_f)]

fig, axes = plt.subplots(2, 2, figsize=(16, 9),
                          gridspec_kw={"width_ratios": [3, 1], "hspace": 0.38, "wspace": 0.28})
ax_cpu, ax_cpu_box = axes[0]
ax_mem, ax_mem_box = axes[1]

def plot_series(ax, ax_box, col, ylabel, unit):
    box_data, box_colors, box_labels = [], [], []
    for pts, color, label, blabel in zip(datasets, COLORS, LABELS, BOX_LABELS):
        if pts is None:
            continue
        t    = pts[:, 0] / 3600.0
        vals = pts[:, col]
        w    = min(SMOOTH, len(vals))
        sm   = np.convolve(vals, np.ones(w) / w, mode="valid")
        ax.plot(t, vals, color=color, alpha=0.10, linewidth=0.6)
        ax.plot(t[w - 1:], sm, color=color, linewidth=2.2,
                label=f"{label}  (avg {vals.mean():.2f}{unit}, σ={vals.std():.2f})")
        box_data.append(vals); box_colors.append(color); box_labels.append(blabel)

    ax.set_ylabel(ylabel, fontsize=11)
    ax.set_ylim(bottom=0)
    ax.xaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax.yaxis.set_minor_locator(ticker.AutoMinorLocator())
    ax.grid(True, which="major", alpha=0.25)
    ax.grid(True, which="minor", alpha=0.08)
    ax.legend(fontsize=9, loc="upper right", framealpha=0.9)

    bp = ax_box.boxplot(box_data, patch_artist=True, widths=0.5,
                        medianprops=dict(color="black", linewidth=2))
    for patch, color in zip(bp["boxes"], box_colors):
        patch.set_facecolor(color); patch.set_alpha(0.7)
    ax_box.set_xticks(range(1, len(box_labels) + 1))
    ax_box.set_xticklabels(box_labels, fontsize=7)
    ax_box.set_ylabel(ylabel, fontsize=10)
    ax_box.set_ylim(bottom=0)
    ax_box.grid(True, axis="y", alpha=0.25)
    ax_box.yaxis.set_minor_locator(ticker.AutoMinorLocator())

    # Annotate deltas vs baseline
    if len(box_data) >= 2:
        lines = []
        for i in range(1, len(box_data)):
            delta = box_data[i].mean() - box_data[0].mean()
            sign = "+" if delta >= 0 else ""
            lines.append(f"Δ{i} = {sign}{delta:.2f}{unit}")
        ax_box.set_title("  ".join(lines), fontsize=8, color="dimgray")

plot_series(ax_cpu, ax_cpu_box, 1, "CPU usage (%)", "%")
plot_series(ax_mem, ax_mem_box, 2, "Memory RSS (MB)", "MB")

ax_mem.set_xlabel("Time (hours)", fontsize=11)
ax_cpu.set_title("CPU — thin: raw 5 s samples · thick: 5 min rolling average", fontsize=10)
ax_mem.set_title("Memory RSS — thin: raw · thick: 5 min rolling average", fontsize=10)

fig.suptitle(
    f"Three-way comparison — run {run_id}  ({int(duration)//3600}h)\n"
    f"Baseline: f={bf}/h={bh}/oh={boh}    "
    f"Top-1: f={t1f}/h={t1h}/oh={t1oh}    "
    f"Top-2: f={t2f}/h={t2h}/oh={t2oh}",
    fontsize=12, fontweight="bold"
)
fig.savefig(out_file, dpi=150, bbox_inches="tight")
print(f"Plot saved to {out_file}")
PYEOF

echo
echo "Done. Results in: $RUN_DIR"
