#!/usr/bin/env bash

set -euo pipefail

# Configuration
LOG_FILE="${HOME}/.wasted.json"

usage() {
  cat <<EOF
Usage: wasted-stats [--top N] [--weeks] [--days] [--family] [--paths] [--threshold SECONDS] [--no-threshold]

Generates useful stats from ~/.wasted.json to identify bottlenecks.

Default output includes:
  - Top commands by total wasted time (percentages)
  - Top families (docker, git, node-pm, etc.)
  - Top paths (cwd)
  - Top 5 single longest waits
  - Weekly totals (ISO week)

Options:
  --top N   Set how many top commands to show (default 10)
  --weeks   Show weekly totals only
  --days    Show daily totals only
  --family  Aggregate and show top families as well
  --paths   Aggregate and show top directories (cwd)
  --threshold SECONDS  Highlight waits >= SECONDS (default 60)
  --no-threshold       Disable threshold alert section
EOF
}

TOP_N=10
MODE="default"
SHOW_FAMILY=false
SHOW_PATHS=false
THRESHOLD=60
SHOW_THRESHOLD=true

while [ $# -gt 0 ]; do
  case "$1" in
    --top)
      TOP_N=${2:-10}
      shift 2
      ;;
    --weeks)
      MODE="weeks"
      shift
      ;;
    --days)
      MODE="days"
      shift
      ;;
    --family)
      SHOW_FAMILY=true
      shift
      ;;
    --paths)
      SHOW_PATHS=true
      shift
      ;;
    --threshold)
      THRESHOLD=${2:-60}
      shift 2
      ;;
    --no-threshold)
      SHOW_THRESHOLD=false
      shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed. Install jq to use wasted-stats." >&2
  exit 1
fi

if [ ! -f "${LOG_FILE}" ]; then
  echo "No log at ${LOG_FILE}. Run 'wasted' first." >&2
  exit 0
fi

TOTAL_OPS=$(jq 'length' "${LOG_FILE}")
if [ "${TOTAL_OPS}" -eq 0 ]; then
  echo "No entries recorded yet." >&2
  exit 0
fi

# Prefer GNU date (gdate) if available; otherwise use BSD date
DATE_CMD="date"
if command -v gdate >/dev/null 2>&1; then
  DATE_CMD="gdate"
fi

print_top_commands() {
  local top_n="$1"
  # Aggregate by base command (first token) using jq
  jq -r '
    [ .[]
      | {base: (.command | split(" ")[0]), time: (.time_spent_seconds // 0)}
    ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.base] = ((.[$r.base] // 0) + $r.time))
    | to_entries
    | sort_by(-.value)
    | .[] | [ .key, (.value), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk -v TOP="$top_n" 'BEGIN{printf("Top commands by total wasted time\n"); printf("%-20s %12s %8s\n","command","seconds","%");}
      NR<=TOP { pct = ($2>0 && $3>0)? ($2*100.0/$3):0; printf("%-20s %12.1f %7.1f%%\n", $1, $2, pct) }'
}

print_top_paths() {
  local top_n="$1"
  jq -r '
    [ .[]
      | {path: (.cwd // "(unknown)"), time: (.time_spent_seconds // 0)}
    ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.path] = ((.[$r.path] // 0) + $r.time))
    | to_entries | sort_by(-.value)
    | .[] | [ .key, (.value), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk -v TOP="$top_n" 'BEGIN{printf("\nTop paths by total wasted time\n"); printf("%-40s %12s %8s\n","path","seconds","%");}
      NR<=TOP { pct = ($2>0 && $3>0)? ($2*100.0/$3):0; printf("%-40s %12.1f %7.1f%%\n", $1, $2, pct) }'
}

print_top_families() {
  local top_n="$1"
  jq -r '
    def fam(cmd):
      (cmd | split(" ")) as $p
      | ($p[0] // "") as $b
      | ($p[1] // "") as $s
      | if ($b == "docker" or $b == "docker-compose" or ($b=="docker" and $s=="compose")) then "docker"
        elif ($b == "npm" or $b == "yarn" or $b == "pnpm") then "node-pm"
        elif ($b == "pip" or $b == "pip3" or $b == "poetry" or $b == "uv") then "python-pm"
        elif ($b == "mvn" or $b == "gradle") then "java-build"
        elif ($b == "cargo") then "rust"
        elif ($b == "git") then "git"
        elif ($b == "brew" or $b == "apt" or $b == "apt-get" or $b == "dnf" or $b == "pacman") then "pkg-mgr"
        elif ($b == "kubectl" or $b == "k") then "k8s"
        elif ($b == "make" or $b == "cmake" or $b == "ninja") then "build"
        else $b end;
    [ .[] | {fam: fam(.command), time: (.time_spent_seconds // 0)} ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.fam] = ((.[$r.fam] // 0) + $r.time))
    | to_entries | sort_by(-.value)
    | .[] | [ .key, (.value), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk -v TOP="$top_n" 'BEGIN{printf("\nTop families by total wasted time\n"); printf("%-20s %12s %8s\n","family","seconds","%");}
      NR<=TOP { pct = ($2>0 && $3>0)? ($2*100.0/$3):0; printf("%-20s %12.1f %7.1f%%\n", $1, $2, pct) }'
}

print_top_waits() {
  jq -r '
    .[] | {dt: .datetime, cmd: .command, t: (.time_spent_seconds // 0)}
    | [ (.t), (.dt), (.cmd) ] | @tsv
  ' "${LOG_FILE}" \
  | sort -nrk1 | head -n 5 \
  | awk -F '\t' 'BEGIN{print "\nTop 5 longest single waits"; printf("%8s  %-20s  %s\n","seconds","datetime","command");}
         {printf("%8.1f  %-20s  %s\n", $1, $2, $3)}'
}

print_threshold_alerts() {
  local threshold="$1"
  jq -r --argjson th "$threshold" '
    [ .[] | select((.time_spent_seconds // 0) >= $th)
      | {t: (.time_spent_seconds // 0), dt: .datetime, cmd: .command}
    ] as $rows
    | ($rows | length) as $cnt
    | ($rows | sort_by(-.t) | .[] | [ (.t), (.dt), (.cmd) ] | @tsv) as $lines
    | "\($cnt) waits >= \($th)s" , $lines
  ' "${LOG_FILE}" \
  | awk -F '\t' 'NR==1{print "\nThreshold alerts"; print $0; next} {printf("%8.1f  %-20s  %s\n", $1, $2, $3)}'
}

print_totals_by_week() {
  # Stream dt and seconds, map dt -> ISO week, then sum by week
  jq -r '.[] | [.datetime, (.time_spent_seconds // 0)] | @tsv' "${LOG_FILE}" \
  | while IFS=$'\t' read -r dt sec; do
      if [ "${DATE_CMD}" = "gdate" ]; then
        wk=$(gdate -d "$dt" +%G-W%V)
      else
        wk=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$dt" +%G-W%V)
      fi
      printf "%s\t%s\n" "$wk" "$sec"
    done \
  | awk 'BEGIN{print "\nWeekly totals (ISO week)"; printf("%-10s %10s\n","week","seconds");}
         {sum[$1]+=$2} END{for (k in sum) printf("%-10s %10.1f\n", k, sum[k])}' \
  | sort
}

print_totals_by_day() {
  # Group by day (YYYY-MM-DD) using jq substring
  jq -r '
    .[] | {day: (.datetime[0:10]), t: (.time_spent_seconds // 0)}
    | [ (.day), (.t) ] | @tsv
  ' "${LOG_FILE}" \
  | awk 'BEGIN{print "\nDaily totals"; printf("%-10s %10s\n","day","seconds");}
         {sum[$1]+=$2} END{for (k in sum) printf("%-10s %10.1f\n", k, sum[k])}' \
  | sort
}

case "${MODE}" in
  weeks)
    print_totals_by_week
    ;;
  days)
    print_totals_by_day
    ;;
  default)
    print_top_commands "${TOP_N}"
    if [ "${SHOW_FAMILY}" = true ]; then
      print_top_families "${TOP_N}"
    fi
    if [ "${SHOW_PATHS}" = true ]; then
      print_top_paths "${TOP_N}"
    fi
    print_top_waits
    if [ "${SHOW_THRESHOLD}" = true ]; then
      print_threshold_alerts "${THRESHOLD}"
    fi
    print_totals_by_week
    ;;
esac
