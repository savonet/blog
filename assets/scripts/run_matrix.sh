#!/usr/bin/env bash
# Full 3-axis performance matrix: frame_duration × minor_heap_size × space_overhead.
# Runs all combinations in batches of MAX_PARALLEL, samples CPU+memory, plots results.
#
# Usage: ./run_matrix.sh [options]
#   -c CMD      Command to run (default: ./liquidsoap_wrapper.sh)
#   -d SECS     Duration per batch in seconds (default: 1200 = 20 min)
#   -i SECS     Sampling interval in seconds (default: 5)
#   -f SIZES    Comma-separated frame durations  (default: 0.02,0.04,0.06,0.08,0.10)
#   -H SIZES    Comma-separated minor_heap_size values in words
#               (default: 4096,8192,16384,32768,65536)
#   -O VALS     Comma-separated space_overhead values (default: 40,60,80,100,120)
#   -p N        Max parallel processes per batch (default: 5)
#   -o DIR      Output directory (default: ./results)

set -euo pipefail

COMMAND="${PERF_CMD:-./liquidsoap_wrapper.sh}"
DURATION=1200
INTERVAL=5
FRAME_SIZES="0.02,0.04,0.06,0.08,0.10"
HEAP_SIZES="4096,8192,16384,32768,65536"
OVERHEADS="40,60,80,100,120"
MAX_PARALLEL=5
RESULTS_DIR="$(cd "$(dirname "$0")" && pwd)/results"

while getopts "c:d:i:f:H:O:p:o:h" opt; do
  case $opt in
    c) COMMAND="$OPTARG" ;;
    d) DURATION="$OPTARG" ;;
    i) INTERVAL="$OPTARG" ;;
    f) FRAME_SIZES="$OPTARG" ;;
    H) HEAP_SIZES="$OPTARG" ;;
    O) OVERHEADS="$OPTARG" ;;
    p) MAX_PARALLEL="$OPTARG" ;;
    o) RESULTS_DIR="$OPTARG" ;;
    h) sed -n '3,13p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: -$OPTARG" >&2; exit 1 ;;
  esac
done

IFS=',' read -ra FRAME_ARRAY   <<< "$FRAME_SIZES"
IFS=',' read -ra HEAP_ARRAY    <<< "$HEAP_SIZES"
IFS=',' read -ra OVERHEAD_ARRAY <<< "$OVERHEADS"

heap_label() {
  local words="$1"
  local bytes=$(( words * 8 ))
  if (( bytes >= 1048576 )); then
    awk "BEGIN { printf \"%gMB\", $bytes/1048576 }"
  else
    awk "BEGIN { printf \"%gKB\", $bytes/1024 }"
  fi
}

ALL_COMBOS=()
for frame in "${FRAME_ARRAY[@]}"; do
  for heap in "${HEAP_ARRAY[@]}"; do
    for oh in "${OVERHEAD_ARRAY[@]}"; do
      ALL_COMBOS+=("$frame $heap $oh")
    done
  done
done

TOTAL=${#ALL_COMBOS[@]}
N_BATCHES=$(( (TOTAL + MAX_PARALLEL - 1) / MAX_PARALLEL ))

mkdir -p "$RESULTS_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
RUN_DIR="$RESULTS_DIR/matrix_${RUN_ID}"
mkdir -p "$RUN_DIR"

echo "=== 3-axis performance matrix ==="
echo "Run ID         : $RUN_ID"
echo "Command        : $COMMAND"
echo "frame_duration : ${FRAME_ARRAY[*]}"
printf "minor_heap_size: "
for h in "${HEAP_ARRAY[@]}"; do printf "%s($(heap_label $h)) " "$h"; done; echo
echo "space_overhead : ${OVERHEAD_ARRAY[*]}"
echo "Combinations   : $TOTAL  |  Batches: $N_BATCHES  |  Parallel: $MAX_PARALLEL"
echo "Per-batch      : ${DURATION}s ($(( DURATION / 60 ))m)  |  Total: ~$(( N_BATCHES * DURATION / 60 ))m"
echo "Output         : $RUN_DIR"
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

# ── Batch runner ───────────────────────────────────────────────────────────────
run_batch() {
  local batch_num="$1"; shift
  local combos=("$@")
  declare -A batch_pids

  echo "── Batch ${batch_num}/${N_BATCHES} ──────────────────────────────────────────────────"
  for combo in "${combos[@]}"; do
    read -r frame heap oh <<< "$combo"
    safe="${frame//./}"
    sample_file="$RUN_DIR/samples_${safe}_${heap}_${oh}.txt"
    log_file="$RUN_DIR/proc_${safe}_${heap}_${oh}.log"
    echo "  frame=$frame  heap=$heap($(heap_label $heap))  overhead=$oh"
    $COMMAND "$frame" "$heap" "$oh" >"$log_file" 2>&1 &
    pid=$!
    batch_pids["$frame/$heap/$oh"]=$pid
    monitor "$pid" "$sample_file" &
  done

  echo "  Waiting ${DURATION}s..."
  sleep "$DURATION"

  echo "  Killing batch ${batch_num} (SIGKILL)..."
  for key in "${!batch_pids[@]}"; do
    kill -9 "${batch_pids[$key]}" 2>/dev/null || true
  done
  wait
  echo "  Batch ${batch_num} complete."
  echo
}

# ── Dispatch ───────────────────────────────────────────────────────────────────
batch_num=0
batch=()
for combo in "${ALL_COMBOS[@]}"; do
  batch+=("$combo")
  if [[ ${#batch[@]} -eq $MAX_PARALLEL ]]; then
    batch_num=$(( batch_num + 1 ))
    run_batch "$batch_num" "${batch[@]}"
    batch=()
  fi
done
if [[ ${#batch[@]} -gt 0 ]]; then
  batch_num=$(( batch_num + 1 ))
  run_batch "$batch_num" "${batch[@]}"
fi

# ── Text summary ───────────────────────────────────────────────────────────────
SUMMARY="$RUN_DIR/summary.txt"
{
  echo "3-axis matrix — run $RUN_ID"
  echo "Command: $COMMAND | Duration: ${DURATION}s/batch | Interval: ${INTERVAL}s"
  printf "%-8s  %-10s  %-8s  %-8s  %7s  %8s  %8s  %8s  %9s  %9s  %9s\n" \
    "FRAME" "HEAP(w)" "HEAP" "OVERHEAD" "SAMPLES" "CPU AVG" "CPU MAX" "CPU σ" "MEM AVG" "MEM MAX" "MEM σ"
  echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────"
  for frame in "${FRAME_ARRAY[@]}"; do
    for heap in "${HEAP_ARRAY[@]}"; do
      for oh in "${OVERHEAD_ARRAY[@]}"; do
        safe="${frame//./}"
        sample_file="$RUN_DIR/samples_${safe}_${heap}_${oh}.txt"
        if [[ ! -s "$sample_file" ]]; then
          printf "%-8s  %-10s  %-8s  %-8s  %7s\n" "$frame" "$heap" "$(heap_label $heap)" "$oh" "(no data)"
          continue
        fi
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
        ' "$sample_file")
        read -r n cavg cmax cstd mavg mmax mstd <<< "$stats"
        printf "%-8s  %-10s  %-8s  %-8s  %7s  %8s  %8s  %8s  %9s  %9s  %9s\n" \
          "$frame" "$heap" "$(heap_label $heap)" "$oh" "$n" \
          "${cavg}%" "${cmax}%" "$cstd" "${mavg}MB" "${mmax}MB" "${mstd}MB"
      done
    done
  done
} | tee "$SUMMARY"

# ── Build data for plot ────────────────────────────────────────────────────────
PLOT_FILE="$RUN_DIR/matrix.png"
PLOT_SCRIPT="$RUN_DIR/plot.py"

DATA_BLOCK=""
for frame in "${FRAME_ARRAY[@]}"; do
  safe="${frame//./}"
  DATA_BLOCK+="  \"$frame\": {\n"
  for heap in "${HEAP_ARRAY[@]}"; do
    DATA_BLOCK+="    $heap: {\n"
    for oh in "${OVERHEAD_ARRAY[@]}"; do
      sample_file="$RUN_DIR/samples_${safe}_${heap}_${oh}.txt"
      if [[ ! -s "$sample_file" ]]; then
        DATA_BLOCK+="      $oh: [],\n"
        continue
      fi
      pts=$(awk 'NR>1 { printf "(%s,%s,%s),", $1, $2, $3 }' "$sample_file")
      DATA_BLOCK+="      $oh: [$pts],\n"
    done
    DATA_BLOCK+="    },\n"
  done
  DATA_BLOCK+="  },\n"
done

FRAME_LIST=$(   printf '"%s",' "${FRAME_ARRAY[@]}";   echo)
HEAP_LIST=$(    printf '%s,'   "${HEAP_ARRAY[@]}";     echo)
OVERHEAD_LIST=$(printf '%s,'   "${OVERHEAD_ARRAY[@]}"; echo)
HEAP_LABELS=""
for h in "${HEAP_ARRAY[@]}"; do HEAP_LABELS+="\"$(heap_label $h)\","; done

cat > "$PLOT_SCRIPT" <<PYEOF
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

RUN_ID      = "$RUN_ID"
OUT_FILE    = "$PLOT_FILE"
SMOOTH_W    = 20

FRAMES      = [${FRAME_LIST%,}]
HEAPS       = [${HEAP_LIST%,}]
OVERHEADS   = [${OVERHEAD_LIST%,}]
HEAP_LABELS = [${HEAP_LABELS%,}]

data = {
$(printf "%b" "$DATA_BLOCK")
}

# ── Compute averages ───────────────────────────────────────────────────────────
def avg(frame, heap, oh, col):
    pts = data.get(frame, {}).get(heap, {}).get(oh, [])
    if len(pts) < 2:
        return np.nan
    return np.array(pts)[1:, col].mean()

# ── Page 1: heatmaps — one row per frame ──────────────────────────────────────
fig1, axes1 = plt.subplots(len(FRAMES), 2,
                            figsize=(14, 3.2 * len(FRAMES)),
                            gridspec_kw={"wspace": 0.35, "hspace": 0.55})

for fi, frame in enumerate(FRAMES):
    cpu_mat = np.array([[avg(frame, h, oh, 1) for h in HEAPS] for oh in OVERHEADS])
    mem_mat = np.array([[avg(frame, h, oh, 2) for h in HEAPS] for oh in OVERHEADS])

    for col_idx, (ax, matrix, title, fmt, cmap) in enumerate([
        (axes1[fi, 0], cpu_mat, f"frame={frame}s — Avg CPU %",           "{:.1f}%",  "YlOrRd"),
        (axes1[fi, 1], mem_mat, f"frame={frame}s — Avg Memory RSS (MB)", "{:.0f}MB", "YlGnBu"),
    ]):
        vmin = np.nanmin(matrix); vmax = np.nanmax(matrix)
        im = ax.imshow(matrix, aspect="auto", cmap=cmap, origin="upper",
                       vmin=vmin, vmax=vmax)
        ax.set_xticks(range(len(HEAPS)))
        ax.set_xticklabels(HEAP_LABELS, fontsize=8)
        ax.set_yticks(range(len(OVERHEADS)))
        ax.set_yticklabels(OVERHEADS, fontsize=8)
        ax.set_xlabel("minor_heap_size", fontsize=9)
        ax.set_ylabel("space_overhead", fontsize=9)
        ax.set_title(title, fontsize=10, fontweight="bold")
        plt.colorbar(im, ax=ax, shrink=0.8)
        mid = (vmin + vmax) / 2
        for oi in range(len(OVERHEADS)):
            for hi in range(len(HEAPS)):
                v = matrix[oi, hi]
                if not np.isnan(v):
                    ax.text(hi, oi, fmt.format(v), ha="center", va="center",
                            fontsize=7.5, color="white" if v > mid else "black")

fig1.suptitle(f"CPU & Memory heatmaps by frame — run {RUN_ID}", fontsize=13, fontweight="bold")
page1 = OUT_FILE.replace(".png", "_heatmaps.png")
fig1.savefig(page1, dpi=150, bbox_inches="tight")
print(f"Heatmaps saved to {page1}")

# ── Page 2: Pareto scatter + top-10 table ─────────────────────────────────────
all_pts = []
for frame in FRAMES:
    for heap in HEAPS:
        for oh in OVERHEADS:
            cpu = avg(frame, heap, oh, 1)
            mem = avg(frame, heap, oh, 2)
            if not (np.isnan(cpu) or np.isnan(mem)):
                all_pts.append((frame, heap, oh, cpu, mem))

cpus = [p[3] for p in all_pts]; mems = [p[4] for p in all_pts]
cpu_min, cpu_max = min(cpus), max(cpus)
mem_min, mem_max = min(mems), max(mems)

def combined_score(cpu, mem):
    return (cpu - cpu_min)/(cpu_max - cpu_min) + (mem - mem_min)/(mem_max - mem_min)

def is_pareto(cpu, mem):
    return not any(c <= cpu and m <= mem and (c < cpu or m < mem)
                   for _, _, _, c, m in all_pts)

scored = sorted([(combined_score(cpu, mem), frame, heap, oh, cpu, mem)
                 for frame, heap, oh, cpu, mem in all_pts])

frame_colors = {f: plt.cm.tab10(i / len(FRAMES)) for i, f in enumerate(FRAMES)}

fig2, (ax_scatter, ax_table_host) = plt.subplots(
    1, 2, figsize=(16, 8), gridspec_kw={"width_ratios": [1.4, 1], "wspace": 0.35})

# Scatter
for frame, heap, oh, cpu, mem in all_pts:
    on_pareto = is_pareto(cpu, mem)
    ax_scatter.scatter(cpu, mem,
                       color=frame_colors[frame],
                       s=60 if on_pareto else 25,
                       alpha=1.0 if on_pareto else 0.35,
                       zorder=3 if on_pareto else 2,
                       edgecolors="black" if on_pareto else "none",
                       linewidths=0.8)

# Pareto frontier
pareto_sorted = sorted([(cpu, mem) for _, _, _, cpu, mem in all_pts if is_pareto(cpu, mem)])
ax_scatter.step([p[0] for p in pareto_sorted], [p[1] for p in pareto_sorted],
                where="post", color="black", linewidth=1.2, linestyle="--",
                alpha=0.5, label="Pareto front")

# Label top-10
labeled = set()
for rank, (score, frame, heap, oh, cpu, mem) in enumerate(scored[:10]):
    key = (round(cpu, 2), round(mem, 1))
    if key in labeled:
        continue
    labeled.add(key)
    ax_scatter.annotate(
        f"f={frame}\nh={HEAP_LABELS[HEAPS.index(heap)]}\noh={oh}",
        xy=(cpu, mem), xytext=(6, 4), textcoords="offset points",
        fontsize=6.5, color=frame_colors[frame],
        fontweight="bold" if rank == 0 else "normal",
        bbox=dict(boxstyle="round,pad=0.2", fc="white", alpha=0.75, ec="none"))

# Best star
_, bf, bh, boh, bcpu, bmem = scored[0]
ax_scatter.scatter(bcpu, bmem, marker="*", s=320, color="gold",
                   edgecolors="black", zorder=10, linewidths=1,
                   label=f"Best: f={bf} h={HEAP_LABELS[HEAPS.index(bh)]} oh={boh}")

from matplotlib.patches import Patch
legend_handles = [Patch(color=frame_colors[f], label=f"frame={f}s") for f in FRAMES]
l1 = ax_scatter.legend(handles=legend_handles, title="frame.duration",
                        fontsize=8, title_fontsize=8, loc="upper right")
ax_scatter.add_artist(l1)
ax_scatter.legend(fontsize=8, loc="lower left")
ax_scatter.set_xlabel("Avg CPU usage (%)", fontsize=11)
ax_scatter.set_ylabel("Avg Memory RSS (MB)", fontsize=11)
ax_scatter.set_title("Pareto: all frame × heap × overhead combinations\n"
                      "Bold markers = Pareto-optimal  |  ★ = best combined score",
                      fontsize=11)
ax_scatter.grid(True, alpha=0.25)

# Top-10 table
ax_table_host.axis("off")
col_labels = ["Rank", "Frame", "Heap", "Overhead", "CPU avg", "Mem avg", "Score"]
table_data = []
for rank, (score, frame, heap, oh, cpu, mem) in enumerate(scored[:15], 1):
    pareto_mark = " ◀" if is_pareto(cpu, mem) else ""
    table_data.append([
        f"{rank}{pareto_mark}",
        frame,
        HEAP_LABELS[HEAPS.index(heap)],
        str(oh),
        f"{cpu:.2f}%",
        f"{mem:.1f}MB",
        f"{score:.3f}",
    ])
table = ax_table_host.table(cellText=table_data, colLabels=col_labels,
                              loc="center", cellLoc="center")
table.auto_set_font_size(False)
table.set_fontsize(8.5)
table.scale(1.1, 1.5)
for (row, col), cell in table.get_celld().items():
    cell.set_edgecolor("#cccccc")
    if row == 0:
        cell.set_facecolor("#e0e0e0")
        cell.set_text_props(fontweight="bold")
    elif "◀" in str(table_data[row-1][0]):
        cell.set_facecolor("#fffbea")
    else:
        cell.set_facecolor("white")
ax_table_host.set_title("Top-15 by combined score (◀ = Pareto-optimal)",
                         fontsize=10, fontweight="bold", pad=12)

fig2.suptitle(f"Pareto analysis — run {RUN_ID}", fontsize=13, fontweight="bold")
page2 = OUT_FILE.replace(".png", "_pareto.png")
fig2.savefig(page2, dpi=150, bbox_inches="tight")
print(f"Pareto saved to {page2}")
PYEOF

echo
if python3 "$PLOT_SCRIPT"; then
  echo "Plots: ${PLOT_FILE/.png/_heatmaps.png}  and  ${PLOT_FILE/.png/_pareto.png}"
else
  echo "WARNING: matplotlib not available — raw data in $RUN_DIR/samples_*.txt"
fi

echo
echo "Done. Results in: $RUN_DIR"
