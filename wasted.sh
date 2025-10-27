#!/usr/bin/env bash

set -euo pipefail

# Configuration
LOG_FILE="${HOME}/.wasted.json" # Store in home directory
TMP_FILE=""

# Cleanup temp files on exit
cleanup() {
  if [ -n "${TMP_FILE}" ] && [ -f "${TMP_FILE}" ]; then
    rm -f "${TMP_FILE}"
  fi
}
trap cleanup EXIT

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
    function round0(x){ return int(x+0.5) }
    function isnum(s){ return (s ~ /^-?[0-9]+(\.[0-9]+)?$/) }
    function fmt_time(x,  s,h,m,out){ s=round0(x); h=int(s/3600); m=int((s%3600)/60); s=s%60; out=""; if(h>0) out=out h "h "; if(h>0||m>0) out=out m "m "; out=out s "s"; return out }
    NR==1 {
      header=$0; ncols=split($0, H, FS); for (i=1;i<=ncols;i++) W[i]=length(H[i]); next
    }
    {
      # format any column named "time" (case-insensitive) if it is numeric
      n=split($0, A, FS); if (n>ncols) ncols=n;
      for (i=1;i<=n;i++) {
        col=A[i]
        if (i in H) {
          h=H[i];
          tl=tolower(h);
          if (tl=="time" && isnum(col)) col=fmt_time(col);
        }
        A[i]=col
        if (length(A[i])>W[i]) W[i]=length(A[i]);
      }
      # rejoin formatted row for printing later
      row=""; for (i=1;i<=ncols;i++) { if (i<=n) f=A[i]; else f=""; row = (i==1?f:row FS f) }
      rows[NR-1]=row
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
    [ .[] | {base: (.command | split(" ")[0]), time: (.time_spent_seconds // 0), failed: ((.exit_code // 0) != 0)} ] as $rows
    | ($rows | map(.time) | add // 0) as $total
    | reduce $rows[] as $r ({}; .[$r.base] = {time: ((.[$r.base].time // 0) + $r.time), count: ((.[$r.base].count // 0) + 1), failed: ((.[$r.base].failed // 0) + (if $r.failed then 1 else 0 end))})
    | to_entries
    | map({key: .key, time: .value.time, count: .value.count, failed: .value.failed})
    | sort_by(-.time)
    | .[] | [ .key, (.time), (.count), (.failed), ($total) ] | @tsv
  ' "${LOG_FILE}" \
  | awk '
      BEGIN{OFS="\t"; printed=0}
      NR==1 { total=$5; print "command","time","count","failed","failed %","%"; pct = ($2>0 && total>0)? ($2*100.0/total):0; fail_pct = ($3>0)? ($4*100.0/$3):0; print $1,$2,$3,$4,sprintf("%.1f%%", fail_pct),sprintf("%.1f%%", pct); printed=1; next }
      printed<10 { pct = ($2>0 && total>0)? ($2*100.0/total):0; fail_pct = ($3>0)? ($4*100.0/$3):0; print $1,$2,$3,$4,sprintf("%.1f%%", fail_pct),sprintf("%.1f%%", pct); printed++ }' \
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
      BEGIN{OFS="\t"; printed=0}
      NR==1 { total=$3; print "path","time","%"; pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,$2,sprintf("%.1f%%", pct); printed=1; next }
      printed<10 { pct = ($2>0 && total>0)? ($2*100.0/total):0; print $1,$2,sprintf("%.1f%%", pct); printed++ }' \
  | render_table "Top paths by total wasted time"
}

print_top_waits() {
  jq -r '.[]
    | {dt: .datetime, cmd: .command, t: (.time_spent_seconds // 0)}
    | [ (.t), (.dt | fromdateiso8601 | localtime | strftime("%d/%m %H:%M")), (.cmd) ]
    | @tsv' "${LOG_FILE}" \
  | sort -t $'\t' -nrk1,1 | head -n 5 || true \
  | awk -F '\t' '
      BEGIN{OFS="\t"; print "time","date","command"}
      {print $1, $2, $3}' \
  | render_table "Top 5 longest single waits"
}

print_threshold_alerts() {
  local threshold=60
  jq -r --argjson th "$threshold" '
    [ .[]
      | select((.time_spent_seconds // 0) > $th)
      | {t: (.time_spent_seconds // 0), dt: .datetime, dtf: (.datetime | fromdateiso8601 | localtime | strftime("%d/%m %H:%M")), cmd: .command}
    ]
    | sort_by(.dt) | reverse | .[:10][]
    | [ (.t), (.dtf), (.cmd) ] | @tsv' "${LOG_FILE}" \
  | awk -F '\t' '
      BEGIN{OFS="\t"; print "time","date","command"}
      {print $1, $2, $3}' \
  | render_table "Latest 10 commands > ${threshold}s"
}

print_failed_commands() {
  local failed_count
  failed_count=$(jq '[.[] | select((.exit_code // 0) != 0)] | length' "${LOG_FILE}")
  if [ "${failed_count}" -eq 0 ]; then
    return
  fi
  jq -r '
    [ .[]
      | select((.exit_code // 0) != 0)
      | {t: (.time_spent_seconds // 0), dt: .datetime, dtf: (.datetime | fromdateiso8601 | localtime | strftime("%d/%m %H:%M")), cmd: .command, code: (.exit_code // 0)}
    ]
    | sort_by(.dt) | reverse | .[:10][]
    | [ (.dtf), (.cmd), (.t), (.code) ] | @tsv' "${LOG_FILE}" \
  | awk -F '\t' '
      BEGIN{OFS="\t"; print "date","command","time","exit"}
      {print $1, $2, $3, $4}' \
  | render_table "Latest 10 failed commands (${failed_count} total failures)"
}

print_totals_by_week() {
  # Use jq for date parsing to avoid spawning shell processes per entry
  jq -r '
    reduce .[] as $entry ({};
      ($entry.datetime | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%G-W%V")) as $week
      | .[$week] = ((.[$week] // 0) + ($entry.time_spent_seconds // 0))
    )
    | to_entries
    | sort_by(.key)
    | .[]
    | [.key, .value] | @tsv
  ' "${LOG_FILE}" \
  | { printf "week\ttime\n"; cat; } \
  | render_table "Weekly totals (ISO week)"
}

print_latest_commands() {
  jq -r '[ .[]
      | {dt: .datetime, dtf: (.datetime | fromdateiso8601 | localtime | strftime("%d/%m %H:%M")), cmd: .command, t: (.time_spent_seconds // 0), path: (.cwd // "(unknown)")}
    ]
    | sort_by(.dt) | reverse | .[:5][]
    | [ .dtf, .cmd, (.t), .path ] | @tsv' "${LOG_FILE}" \
  | awk -F '\t' '
      BEGIN{OFS="\t"; print "date","command","time","path"}
      {print $1, $2, $3, $4}' \
  | render_table "Latest 5 commands"
}

print_total_summary() {
  local total_time total_secs_int total_days human hours mins secs cmd_label day_label
  # Use jq for all calculations to avoid spawning shell processes
  read -r total_secs_int total_days <<< "$(jq -r '
    (map(.time_spent_seconds) | add // 0) as $total_time
    | ($total_time | floor) as $total_secs
    | ([.[].datetime | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m-%d")] | unique) as $dates
    | ($dates | map(strptime("%Y-%m-%d") | strftime("%u") | tonumber) | map(select(. >= 1 and . <= 5)) | length) as $weekdays
    | "\($total_secs) \($weekdays)"
  ' "${LOG_FILE}")"

  hours=$(( total_secs_int / 3600 ))
  mins=$(( (total_secs_int % 3600) / 60 ))
  secs=$(( total_secs_int % 60 ))
  human=""
  if [ "${hours}" -gt 0 ]; then
    if [ "${hours}" -eq 1 ]; then human+="${hours} hour"; else human+="${hours} hours"; fi
  fi
  if [ "${hours}" -gt 0 ] || [ "${mins}" -gt 0 ]; then
    if [ -n "${human}" ]; then human+=" "; fi
    if [ "${mins}" -eq 1 ]; then human+="${mins} minute"; else human+="${mins} minutes"; fi
  fi
  if [ -n "${human}" ]; then human+=" "; fi
  if [ "${secs}" -eq 1 ]; then human+="${secs} second"; else human+="${secs} seconds"; fi
  local cmd_label day_label
  if [ "${TOTAL_OPS}" -eq 1 ]; then cmd_label="command"; else cmd_label="commands"; fi
  if [ "${total_days}" -eq 1 ]; then day_label="day"; else day_label="days"; fi
  summary_line="${human} wasted waiting on ${TOTAL_OPS} ${cmd_label} during ${total_days} ${day_label}."
  printf "\033[31m%s\033[0m\n" "$summary_line"
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
  print_failed_commands
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

# Execute the command with alias/function support from the user's shell
# Build a safely quoted command string so alias expansion works via -c
shell_quote_args() {
  local out="" a
  for a in "$@"; do
    # wrap each arg in single quotes and escape internal single quotes
    a=$(printf "%s" "$a" | sed "s/'/'\\''/g")
    out+=" '$a'"
  done
  printf "%s" "${out# }"
}

CMD_STR=$(shell_quote_args "$@")
USER_SHELL=${SHELL:-/bin/bash}
SHELL_NAME=$(basename "$USER_SHELL")

# Temporarily disable exit on error to capture command status
set +e
if [ "$SHELL_NAME" = "zsh" ]; then
  zsh -c "source ~/.zshrc 2>/dev/null; eval ${CMD_STR}"
  CMD_STATUS=$?
elif [ "$SHELL_NAME" = "bash" ]; then
  bash -c "shopt -s expand_aliases; source ~/.bashrc 2>/dev/null; eval ${CMD_STR}"
  CMD_STATUS=$?
else
  "$@"
  CMD_STATUS=$?
fi
set -e

# End timer
END_TIME=$(date +%s.%N)

# Calculate time spent (floating seconds)
TIME_SPENT=$(echo "${END_TIME} - ${START_TIME}" | bc -l)

# Format the time spent to one decimal place (matches README example)
TIME_SPENT_FORMATTED=$(printf "%.1f" "${TIME_SPENT}")

# Append the entry to the JSON array using jq (preserves well-formed JSON)
# Wrap in a subshell with error handling to ensure CMD_STATUS is preserved
if TMP_FILE=$(mktemp) && \
   jq \
     --arg dt "${DATETIME}" \
     --arg cmd "${FULL_COMMAND}" \
     --arg cwd "${CWD}" \
     --argjson spent "${TIME_SPENT_FORMATTED}" \
     --argjson status "${CMD_STATUS}" \
     '. + [{datetime: $dt, time_spent_seconds: $spent, command: $cmd, cwd: $cwd, exit_code: $status}]' \
     "${LOG_FILE}" > "${TMP_FILE}" && \
   mv "${TMP_FILE}" "${LOG_FILE}"; then
  echo "Command '${FULL_COMMAND}' took ${TIME_SPENT_FORMATTED}s (exit ${CMD_STATUS})."
  echo "Entry logged to ${LOG_FILE}"
else
  echo "Command '${FULL_COMMAND}' took ${TIME_SPENT_FORMATTED}s (exit ${CMD_STATUS})." >&2
  echo "Warning: Failed to log entry to ${LOG_FILE}" >&2
fi

# Always exit with the original command status
exit ${CMD_STATUS}
