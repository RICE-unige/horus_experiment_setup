#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FILE="${1:-${SCRIPT_DIR}/topics_base.txt}"
EXTRA_FILE="${2:-${SCRIPT_DIR}/topics_extra.txt}"
OUTPUT_FILE="${3:-${SCRIPT_DIR}/zenoh_ros2dds.json5}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "${s}"
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "${s}"
}

declare -A seen=()
declare -a topics=()

read_topics_from_file() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  local line cleaned
  while IFS= read -r line || [[ -n "${line}" ]]; do
    cleaned="${line%%#*}"
    cleaned="$(trim "${cleaned}")"
    [[ -n "${cleaned}" ]] || continue
    if [[ -z "${seen[${cleaned}]+x}" ]]; then
      topics+=("${cleaned}")
      seen["${cleaned}"]=1
    fi
  done < "${file}"
}

read_topics_from_file "${BASE_FILE}"
read_topics_from_file "${EXTRA_FILE}"

if [[ "${#topics[@]}" -eq 0 ]]; then
  echo "[ERROR] No topics found in '${BASE_FILE}' and '${EXTRA_FILE}'" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"
tmp_file="$(mktemp "${OUTPUT_FILE}.tmp.XXXXXX")"
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

{
  echo "{"
  echo "  \"plugins\": {"
  echo "    \"ros2dds\": {"
  echo "      \"allow\": {"
  echo "        \"publishers\": ["
  for i in "${!topics[@]}"; do
    topic="$(json_escape "${topics[$i]}")"
    comma=","
    if [[ "${i}" -eq "$(( ${#topics[@]} - 1 ))" ]]; then
      comma=""
    fi
    printf '          "%s"%s\n' "${topic}" "${comma}"
  done
  echo "        ],"
  echo "        \"subscribers\": ["
  for i in "${!topics[@]}"; do
    topic="$(json_escape "${topics[$i]}")"
    comma=","
    if [[ "${i}" -eq "$(( ${#topics[@]} - 1 ))" ]]; then
      comma=""
    fi
    printf '          "%s"%s\n' "${topic}" "${comma}"
  done
  echo "        ]"
  echo "      }"
  echo "    }"
  echo "  }"
  echo "}"
} > "${tmp_file}"

mv "${tmp_file}" "${OUTPUT_FILE}"
trap - EXIT

echo "[INFO] Generated ${OUTPUT_FILE}"
echo "[INFO] Topics allowlisted: ${#topics[@]}"
