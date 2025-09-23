#!/usr/bin/env bash

set -euo pipefail

LOG_FILE="${HOME}/.wasted.json"

if [ ! -f "${LOG_FILE}" ]; then
  echo "No log file found at ${LOG_FILE}." >&2
  exit 0
fi

if command -v jq >/dev/null 2>&1; then
  jq . "${LOG_FILE}"
else
  cat "${LOG_FILE}"
fi

