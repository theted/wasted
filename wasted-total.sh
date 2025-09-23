#!/usr/bin/env bash

set -euo pipefail

# Options
SHORT=false
for arg in "$@"; do
  case "$arg" in
    --short|-s)
      SHORT=true
      ;;
    *)
      ;; # ignore unknowns for now
  esac
done

# Configuration
LOG_FILE="${HOME}/.wasted.json" # Store in home directory

# Check if the log file exists
if [ ! -f "${LOG_FILE}" ]; then
  echo "No wasted time data found. Run 'wasted' commands first."
  exit 0
fi

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is not installed. Please install it to use wasted-total." >&2
  echo "On Debian/Ubuntu: sudo apt-get install jq" >&2
  echo "On Fedora: sudo dnf install jq" >&2
  echo "On Arch: sudo pacman -S jq" >&2
  exit 1
fi

TOTAL_OPERATIONS=$(jq 'length' "${LOG_FILE}")

if [ "${TOTAL_OPERATIONS}" -eq 0 ]; then
  echo "No wasted time data found."
  exit 0
fi

# Sum total time (seconds), defaulting null to 0
TOTAL_TIME=$(jq 'map(.time_spent_seconds) | add // 0' "${LOG_FILE}")
# Round to nearest whole second for exact formatting
TOTAL_SECS_INT=$(awk -v t="${TOTAL_TIME}" 'BEGIN{printf "%.0f", t}')

# Get first and last datetimes (assumes append order)
FIRST_DATETIME_STR=$(jq -r '.[0].datetime' "${LOG_FILE}")
LAST_DATETIME_STR=$(jq -r '.[-1].datetime' "${LOG_FILE}")

# Convert UTC ISO 8601 to Unix timestamp for calculation
# Prefer GNU date (gdate on macOS via coreutils), otherwise use BSD date fallback
DATE_CMD="date"
if command -v gdate >/dev/null 2>&1; then
  DATE_CMD="gdate"
fi

if [ "${DATE_CMD}" = "gdate" ]; then
  FIRST_UNIX_TIME=$(gdate -d "${FIRST_DATETIME_STR}" +%s)
  LAST_UNIX_TIME=$(gdate -d "${LAST_DATETIME_STR}" +%s)
else
  # macOS/BSD date
  FIRST_UNIX_TIME=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${FIRST_DATETIME_STR}" +%s)
  LAST_UNIX_TIME=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${LAST_DATETIME_STR}" +%s)
fi

# Calculate difference in seconds
TIME_DIFFERENCE_SECONDS=$(( LAST_UNIX_TIME - FIRST_UNIX_TIME ))

# Convert to inclusive days: ceil(diff/86400), minimum 1 when there is at least 1 entry
if [ ${TIME_DIFFERENCE_SECONDS} -le 0 ]; then
  TOTAL_DAYS=1
else
  TOTAL_DAYS=$(( (TIME_DIFFERENCE_SECONDS + 86399) / 86400 ))
fi

# Short format output
if [ "${SHORT}" = true ]; then
  echo "${TOTAL_SECS_INT}s wasted in ${TOTAL_OPERATIONS} commands in ${TOTAL_DAYS} days."
  exit 0
fi

# Build human-readable total time (hours, minutes, seconds), exact integers
HOURS=$(( TOTAL_SECS_INT / 3600 ))
MINUTES=$(( (TOTAL_SECS_INT % 3600) / 60 ))
SECS=$(( TOTAL_SECS_INT % 60 ))

parts=()
if [ "${HOURS}" -gt 0 ]; then
  if [ "${HOURS}" -eq 1 ]; then parts+=("${HOURS} hour"); else parts+=("${HOURS} hours"); fi
fi
if [ "${HOURS}" -gt 0 ] || [ "${MINUTES}" -gt 0 ]; then
  if [ "${MINUTES}" -eq 1 ]; then parts+=("${MINUTES} minute"); else parts+=("${MINUTES} minutes"); fi
fi

# Always include seconds (exact)
if [ "${SECS}" -eq 1 ]; then
  parts+=(" ${SECS} second")
else
  parts+=(" ${SECS} seconds")
fi

HUMAN_TIME=$(IFS=", "; echo "${parts[*]}")

# Pluralization for commands and days
if [ "${TOTAL_OPERATIONS}" -eq 1 ]; then CMD_LABEL="command"; else CMD_LABEL="commands"; fi
if [ "${TOTAL_DAYS}" -eq 1 ]; then DAY_LABEL="day"; else DAY_LABEL="days"; fi

echo "${HUMAN_TIME} wasted in ${TOTAL_OPERATIONS} ${CMD_LABEL} in ${TOTAL_DAYS} ${DAY_LABEL}."
