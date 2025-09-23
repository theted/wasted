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

# Ensure a command was provided
if [ "$#" -eq 0 ]; then
  echo "Usage: wasted <command> [args...]" >&2
  exit 1
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
