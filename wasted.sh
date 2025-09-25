#!/usr/bin/env bash

set -euo pipefail

# Configuration
LOG_FILE="${HOME}/.wasted.json" # Store in home directory

# Require jq for robust JSON handling
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed. Please install jq to use 'wasted'." >&2
  echo "On Debian/Ubuntu: sudo apt-get install jq" >&2
  echo "On Fedora: sudo dnf install jq" >&2
  echo "On Arch: sudo pacman -S jq" >&2
  exit 1
fi

###############################################
# Stats mode when no arguments are provided   #
###############################################

# Render a simple ASCII table from TSV
render_table() {
  local title="${1:-}"
  awk -v TITLE="$title" -F '\t' '
    function rep(n, c,  s, i){ s=""; for(i=0;i<n;i++) s=s c; return s }
    function round1(x){ return int(x*10+0.5)/10 }
    function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
    NR==1 { header=$0; ncols=split($0, H, FS); for (i=1;i<=ncols;i++) W[i]=length(H[i]); next }
    {
      rows[NR-1]=$0; n=split($0, A, FS); if (n>ncols) ncols=n;
      for (i=1;i<=n;i++) if (length(A[i])>W[i]) W[i]=length(A[i]);
    }
    END {
      if (TITLE!="") print TITLE;
      sep="+"; for (i=1;i<=ncols;i++) sep=sep rep(W[i]+2, "-") "+"; print sep;
      split(header, H, FS);
      for (i=1;i<=ncols;i++) { printf("| % -" W[i] "s ", (i in H?H[i]:"")) } print "|";
      print sep;
      for (r=1;r<=length(rows);r++) {
        n=split(rows[r], A, FS);
        for (i=1;i<=ncols;i++) { printf("| % -" W[i] "s ", (i<=n?A[i]:"")) }
        print "|";
      }
      print sep;
      print "";
    }
  '
}

print_top_commands() {
  local top_n=10
  jq -r '
    [ .[] | {base: (.command | split(" ")[0]), time: (.time_spent_seconds // 0)} ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.base] = ((.[$r.base] // 0) + $r.time))
    | to_entries | sort_by(-.value)
    | .[] | [ .key, (.value), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk '
      function round1(x){ return int(x*10+0.5)/10 }
      function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
      BEGIN{OFS="\t"; printed=0}
      NR==1 { total=$3; print "command","seconds","%"; pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,fmt1($2),sprintf("%.1f%%", pct); printed=1; next }
      printed<10 { pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,fmt1($2),sprintf("%.1f%%", pct); printed++ }' \
  | render_table "Top commands by total wasted time (${TOTAL_OPS} commands)"
}

print_top_paths() {
  local top_n=10
  jq -r '
    [ .[] | {path: (.cwd // "(unknown)"), time: (.time_spent_seconds // 0)} ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.path] = ((.[$r.path] // 0) + $r.time))
    | to_entries | sort_by(-.value)
    | .[] | [ .key, (.value), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk '
      function round1(x){ return int(x*10+0.5)/10 }
      function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
      BEGIN{OFS="\t"; printed=0}
      NR==1 { total=$3; print "path","seconds","%"; pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,fmt1($2),sprintf("%.1f%%", pct); printed=1; next }
      printed<10 { pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,fmt1($2),sprintf("%.1f%%", pct); printed++ }' \
  | render_table "Top paths by total wasted time"
}

print_top_waits() {
  jq -r '.[] | {dt: .datetime, cmd: .command, t: (.time_spent_seconds // 0)} | [ (.t), (.dt), (.cmd) ] | @tsv' "${LOG_FILE}" \
  | sort -t $'\t' -nrk1,1 | head -n 5 \
  | awk -F '\t' '
      function round1(x){ return int(x*10+0.5)/10 }
      function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
      BEGIN{OFS="\t"; print "seconds","datetime","command"}
      {print fmt1($1), $2, $3}' \
  | render_table "Top 5 longest single waits"
}

print_threshold_alerts() {
  local threshold=60
  local count
  count=$(jq -r --argjson th "$threshold" '[ .[] | select((.time_spent_seconds // 0) >= $th) ] | length' "${LOG_FILE}")
  jq -r --argjson th "$threshold" '[ .[] | select((.time_spent_seconds // 0) >= $th) | {t: (.time_spent_seconds // 0), dt: .datetime, cmd: .command} ] | sort_by(-.t) | .[] | [ (.t), (.dt), (.cmd) ] | @tsv' "${LOG_FILE}" \
  | awk -F '\t' '
      function round1(x){ return int(x*10+0.5)/10 }
      function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
      BEGIN{OFS="\t"; print "seconds","datetime","command"}
      {print fmt1($1), $2, $3}' \
  | render_table "Threshold alerts (>= ${threshold}s, ${count} waits)"
}

print_totals_by_week() {
  # Prefer GNU date (gdate) if available; otherwise use BSD date
  DATE_CMD="date"
  if command -v gdate >/dev/null 2>&1; then DATE_CMD="gdate"; fi
  jq -r '.[] | [.datetime, (.time_spent_seconds // 0)] | @tsv' "${LOG_FILE}" \
  | while IFS=$'\t' read -r dt sec; do
      if [ "${DATE_CMD}" = "gdate" ]; then
        wk=$(gdate -d "$dt" +%G-W%V)
      else
        wk=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$dt" +%G-W%V)
      fi
      printf "%s\t%s\n" "$wk" "$sec"
    done \
  | awk 'BEGIN{OFS="\t"} function round1(x){ return int(x*10+0.5)/10 } function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) } {sum[$1]+=$2} END{for (k in sum) printf("%s\t%s\n", k, fmt1(sum[k]))}' \
  | sort -t $'\t' -k1,1 \
  | { printf "week\tseconds\n"; cat; } \
  | render_table "Weekly totals (ISO week)"
}

print_latest_commands() {
  jq -r '[ .[] | {dt: .datetime, cmd: .command, t: (.time_spent_seconds // 0), path: (.cwd // "(unknown)")} ] | sort_by(.dt) | reverse | .[:5][] | [ .dt, .cmd, (.t), .path ] | @tsv' "${LOG_FILE}" \
  | awk -F '\t' '
      function round1(x){ return int(x*10+0.5)/10 }
      function fmt1(x, y){ y=round1(x); if (y==int(y)) return int(y); else return sprintf("%.1f", y+0) }
      BEGIN{OFS="\t"; print "datetime","command","seconds","path"}
      {print $1, $2, fmt1($3), $4}' \
  | render_table "Latest 5 commands"
}

print_total_summary() {
  # Prefer GNU date (gdate) if available; otherwise use BSD date
  DATE_CMD="date"
  if command -v gdate >/dev/null 2>&1; then DATE_CMD="gdate"; fi
  local total_time total_secs_int first_dt last_dt first_unix last_unix time_diff total_days human hours mins secs cmd_label day_label
  total_time=$(jq 'map(.time_spent_seconds) | add // 0' "${LOG_FILE}")
  total_secs_int=$(awk -v t="${total_time}" 'BEGIN{printf "%.0f", t}')
  first_dt=$(jq -r '.[0].datetime' "${LOG_FILE}")
  last_dt=$(jq -r '.[-1].datetime' "${LOG_FILE}")
  if [ "${DATE_CMD}" = "gdate" ]; then
    first_unix=$(gdate -d "${first_dt}" +%s)
    last_unix=$(gdate -d "${last_dt}" +%s)
  else
    first_unix=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${first_dt}" +%s)
    last_unix=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${last_dt}" +%s)
  fi
  time_diff=$(( last_unix - first_unix ))
  if [ ${time_diff} -le 0 ]; then
    total_days=1
  else
    total_days=$(( (time_diff + 86399) / 86400 ))
  fi
  hours=$(( total_secs_int / 3600 ))
  mins=$(( (total_secs_int % 3600) / 60 ))
  secs=$(( total_secs_int % 60 ))
  human=""
  if [ "${hours}" -gt 0 ]; then if [ "${hours}" -eq 1 ]; then human+="${hours} hour"; else human+="${hours} hours"; fi; fi
  if [ "${hours}" -gt 0 ] || [ "${mins}" -gt 0 ]; then if [ -n "${human}" ]; then human+=", "; fi; if [ "${mins}" -eq 1 ]; then human+="${mins} minute"; else human+="${mins} minutes"; fi; fi
  if [ -n "${human}" ]; then human+=", "; fi
  if [ "${secs}" -eq 1 ]; then human+="${secs} second"; else human+="${secs} seconds"; fi
  local cmd_label day_label
  if [ "${TOTAL_OPS}" -eq 1 ]; then cmd_label="command"; else cmd_label="commands"; fi
  if [ "${total_days}" -eq 1 ]; then day_label="day"; else day_label="days"; fi
  echo "${human} wasted in ${TOTAL_OPS} ${cmd_label} in ${total_days} ${day_label}."
}

if [ "$#" -eq 0 ]; then
  # Stats mode
  if [ ! -f "${LOG_FILE}" ]; then
    echo "No log at ${LOG_FILE}. Run 'wasted <command>' first." >&2
    exit 0
  fi
  TOTAL_OPS=$(jq 'length' "${LOG_FILE}")
  if [ "${TOTAL_OPS}" -eq 0 ]; then
    echo "No entries recorded yet." >&2
    exit 0
  fi
  print_top_commands
  print_top_paths
  print_top_waits
  print_threshold_alerts
  print_totals_by_week
  print_latest_commands
  print_total_summary
  exit 0
fi

# Initialize log file if missing
if [ ! -f "${LOG_FILE}" ]; then
  echo "[]" > "${LOG_FILE}"
fi

# Get current datetime (UTC, ISO 8601)
DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Capture current working directory
CWD=$(pwd)

# Capture the full command line (for logging only)
FULL_COMMAND="$*"

# Start timer (seconds.nanoseconds)
START_TIME=$(date +%s.%N)

# Execute the command with original arguments; capture exit status
"$@"
CMD_STATUS=$?

# End timer
END_TIME=$(date +%s.%N)

# Calculate time spent (floating seconds)
TIME_SPENT=$(echo "${END_TIME} - ${START_TIME}" | bc -l)

# Format the time spent to one decimal place (matches README example)
TIME_SPENT_FORMATTED=$(printf "%.1f" "${TIME_SPENT}")

# Append the entry to the JSON array using jq (preserves well-formed JSON)
TMP_FILE=$(mktemp)
jq \
  --arg dt "${DATETIME}" \
  --arg cmd "${FULL_COMMAND}" \
  --arg cwd "${CWD}" \
  --argjson spent "${TIME_SPENT_FORMATTED}" \
  '. + [{datetime: $dt, time_spent_seconds: $spent, command: $cmd, cwd: $cwd}]' \
  "${LOG_FILE}" > "${TMP_FILE}"
mv "${TMP_FILE}" "${LOG_FILE}"

echo "Command '${FULL_COMMAND}' took ${TIME_SPENT_FORMATTED}s (exit ${CMD_STATUS})."
echo "Entry logged to ${LOG_FILE}"
exit ${CMD_STATUS}
