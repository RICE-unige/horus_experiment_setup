#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_ROOT="${SCRIPT_DIR}/logs"
SESSION_HISTORY_FILE="${LOG_ROOT}/session_history.tsv"
SESSION_HISTORY_CSV_FILE="${LOG_ROOT}/session_history.csv"

RUNTIME_SESSION="${HORUS_LOCAL_TMUX_SESSION:-horus_local_exp1}"
SDK_SESSION="${HORUS_LOCAL_SDK_SESSION:-${RUNTIME_SESSION}_sdk}"
STARTUP_TIMEOUT_SEC="${STARTUP_TIMEOUT_SEC:-180}"
LOG_TAIL_LINES_DEFAULT="${LOG_TAIL_LINES_DEFAULT:-120}"
LOCAL_BOOT_GRACE_SEC="${LOCAL_BOOT_GRACE_SEC:-5}"
LOCAL_NAV_START_DELAY_SEC="${LOCAL_NAV_START_DELAY_SEC:-20}"
LOCAL_SDK_START_DELAY_SEC="${LOCAL_SDK_START_DELAY_SEC:-10}"
LOCAL_PROBE_TIMEOUT_SEC="${LOCAL_PROBE_TIMEOUT_SEC:-180}"

RUNTIME_LOG_DIR="${LOG_ROOT}/${RUNTIME_SESSION}"
LAST_RUN_META_FILE="${RUNTIME_LOG_DIR}/last_run.env"

ROS_SETUP_FILE="/opt/ros/jazzy/setup.bash"

ISAAC_PYTHON_CANDIDATE_1="${HOME}/isaac-sim/python.sh"
ISAAC_PYTHON_CANDIDATE_2="/isaac-sim/python.sh"
if [[ -x "${ISAAC_PYTHON_CANDIDATE_1}" ]]; then
  ISAAC_PYTHON_DEFAULT="${ISAAC_PYTHON_CANDIDATE_1}"
else
  ISAAC_PYTHON_DEFAULT="${ISAAC_PYTHON_CANDIDATE_2}"
fi
ISAAC_PYTHON="${ISAAC_PYTHON:-${ISAAC_PYTHON_DEFAULT}}"

PROJECT_ROOT_CANDIDATE_1="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT_CANDIDATE_2="${HOME}/isaac-projects"
if [[ -f "${PROJECT_ROOT_CANDIDATE_1}/fast_isaac_sim.py" ]]; then
  PROJECT_ROOT_DEFAULT="${PROJECT_ROOT_CANDIDATE_1}"
else
  PROJECT_ROOT_DEFAULT="${PROJECT_ROOT_CANDIDATE_2}"
fi
PROJECT_ROOT="${PROJECT_ROOT:-${PROJECT_ROOT_DEFAULT}}"
FAST_ISAAC_SIM="${FAST_ISAAC_SIM:-${PROJECT_ROOT}/fast_isaac_sim.py}"
HOSPITAL_USD_EXP1RTX="${HOSPITAL_USD_EXP1RTX:-${PROJECT_ROOT}/hospital_experiment_rtx3_400x300.usda}"
OFFICE_USD="${OFFICE_USD:-${PROJECT_ROOT}/office_experiment.usda}"
DEFAULT_LOCAL_PROFILE="${DEFAULT_LOCAL_PROFILE:-hospital}"
OFFICE_CARTER1_POSE="${OFFICE_CARTER1_POSE:--3,-6,0,3.141592653589793}"
OFFICE_CARTER2_POSE="${OFFICE_CARTER2_POSE:-2.5,0,0,3.141592653589793}"
OFFICE_CARTER3_POSE="${OFFICE_CARTER3_POSE:--2,5,0,3.141592653589793}"

CARTER_MULTI_NAV_ROOT_CANDIDATE_1="${SCRIPT_DIR}/../carter_multi_nav"
CARTER_MULTI_NAV_ROOT_CANDIDATE_2="${HOME}/carter_multi_nav"
if [[ -d "${CARTER_MULTI_NAV_ROOT_CANDIDATE_1}" ]]; then
  CARTER_MULTI_NAV_ROOT_DEFAULT="$(cd "${CARTER_MULTI_NAV_ROOT_CANDIDATE_1}" && pwd)"
else
  CARTER_MULTI_NAV_ROOT_DEFAULT="${CARTER_MULTI_NAV_ROOT_CANDIDATE_2}"
fi
CARTER_MULTI_NAV_ROOT="${CARTER_MULTI_NAV_ROOT:-${CARTER_MULTI_NAV_ROOT_DEFAULT}}"
CARTER_MULTI_NAV_SETUP_FILE="${CARTER_MULTI_NAV_SETUP_FILE:-${CARTER_MULTI_NAV_ROOT}/install/setup.bash}"
CARTER_NAV_LAUNCH_PACKAGE="${CARTER_NAV_LAUNCH_PACKAGE:-carter_multi_nav}"
CARTER_NAV_LAUNCH_FILE="${CARTER_NAV_LAUNCH_FILE:-multi_carter_mapping_nav.launch.py}"
CARTER_APRILTAG_LAUNCH_PACKAGE="${CARTER_APRILTAG_LAUNCH_PACKAGE:-carter_multi_nav}"
CARTER_APRILTAG_LAUNCH_FILE="${CARTER_APRILTAG_LAUNCH_FILE:-april_tag_detector.launch.py}"
LOCAL_NAV_RVIZ="${LOCAL_NAV_RVIZ:-true}"
LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING="${LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING:-true}"

HORUS_SDK_ROOT_CANDIDATE_1="${SCRIPT_DIR}/../horus_sdk"
HORUS_SDK_ROOT_CANDIDATE_2="${HOME}/horus_sdk"
if [[ -f "${HORUS_SDK_ROOT_CANDIDATE_1}/python/examples/sdk_hospital_carter_live_demo.py" ]]; then
  HORUS_SDK_ROOT_DEFAULT="$(cd "${HORUS_SDK_ROOT_CANDIDATE_1}" && pwd)"
else
  HORUS_SDK_ROOT_DEFAULT="${HORUS_SDK_ROOT_CANDIDATE_2}"
fi
HORUS_SDK_ROOT="${HORUS_SDK_ROOT:-${HORUS_SDK_ROOT_DEFAULT}}"
HORUS_SDK_HOSPITAL_DEMO="${HORUS_SDK_HOSPITAL_DEMO:-${HORUS_SDK_ROOT}/python/examples/sdk_hospital_carter_live_demo.py}"
HORUS_FETCH_ROBOT_DESCRIPTION_ASSETS="${HORUS_FETCH_ROBOT_DESCRIPTION_ASSETS:-${HORUS_SDK_ROOT}/python/examples/tools/fetch_robot_description_assets.py}"
HORUS_FAKE_ROBOT_DESCRIPTION_TUTORIAL_SUITE="${HORUS_FAKE_ROBOT_DESCRIPTION_TUTORIAL_SUITE:-${HORUS_SDK_ROOT}/python/examples/fake_tf_robot_description_suite.py}"
HORUS_SDK_TUTORIAL_DEMO="${HORUS_SDK_TUTORIAL_DEMO:-${HORUS_SDK_ROOT}/python/examples/sdk_robot_description_tutorial_demo.py}"
SDK_PYTHON="${SDK_PYTHON:-python3}"

LOCAL_ROBOT_NAMES="${LOCAL_ROBOT_NAMES:-carter1,carter2,carter3}"
LOCAL_WORKSPACE_SCALE="${LOCAL_WORKSPACE_SCALE:-0.04}"
LOCAL_TF_TOPIC="${LOCAL_TF_TOPIC:-/tf}"
LOCAL_TF_STATIC_TOPIC="${LOCAL_TF_STATIC_TOPIC:-/tf_static}"
LOCAL_SHARED_MAP_TOPIC="${LOCAL_SHARED_MAP_TOPIC:-/shared_map}"
LOCAL_BODY_MESH_MODE="${LOCAL_BODY_MESH_MODE:-preview_mesh}"

if [[ -t 1 ]]; then
  C_RESET="$(printf '\033[0m')"
  C_INFO="$(printf '\033[1;34m')"
  C_OK="$(printf '\033[0;32m')"
  C_WARN="$(printf '\033[1;33m')"
  C_ERR="$(printf '\033[0;31m')"
else
  C_RESET=""
  C_INFO=""
  C_OK=""
  C_WARN=""
  C_ERR=""
fi

info() {
  printf "%b[INFO]%b %s\n" "${C_INFO}" "${C_RESET}" "$*"
}

ok() {
  printf "%b[OK]%b %s\n" "${C_OK}" "${C_RESET}" "$*"
}

warn() {
  printf "%b[WARN]%b %s\n" "${C_WARN}" "${C_RESET}" "$*"
}

error() {
  printf "%b[ERROR]%b %s\n" "${C_ERR}" "${C_RESET}" "$*" >&2
}

die() {
  error "$*"
  exit 1
}

display_path() {
  local p="$1"
  if [[ "${p}" == "${HOME}"* ]]; then
    printf '~%s' "${p#${HOME}}"
  else
    printf '%s' "${p}"
  fi
}

ensure_session_history_file() {
  if [[ ! -f "${SESSION_HISTORY_FILE}" ]]; then
    mkdir -p "${LOG_ROOT}"
    printf "session_id\tsession_type\tstarted_at_utc\tstopped_at_utc\tduration_sec\tduration_hms\tfinal_status\truntime_session\tsdk_session\trun_dir\n" > "${SESSION_HISTORY_FILE}"
  fi
  sync_session_history_csv
}

sync_session_history_csv() {
  [[ -f "${SESSION_HISTORY_FILE}" ]] || return 0
  awk -F'\t' '
    function csv_escape(value, text) {
      text = value
      gsub(/"/, "\"\"", text)
      return "\"" text "\""
    }
    {
      for (i = 1; i <= NF; i++) {
        printf "%s%s", (i > 1 ? "," : ""), csv_escape($i)
      }
      printf "\n"
    }
  ' "${SESSION_HISTORY_FILE}" > "${SESSION_HISTORY_CSV_FILE}"
}

session_meta_value() {
  local key="$1"
  [[ -f "${LAST_RUN_META_FILE}" ]] || return 0
  awk -F= -v key="${key}" '$1==key { print substr($0, index($0, "=") + 1) }' "${LAST_RUN_META_FILE}" | tail -n 1
}

format_duration_hms() {
  local total_sec="${1:-0}"
  local hours minutes seconds
  (( total_sec >= 0 )) || total_sec=0
  hours=$(( total_sec / 3600 ))
  minutes=$(( (total_sec % 3600) / 60 ))
  seconds=$(( total_sec % 60 ))
  printf '%02d:%02d:%02d' "${hours}" "${minutes}" "${seconds}"
}

append_session_history_start() {
  local session_id="$1"
  local session_type="$2"
  local started_at_utc="$3"
  local run_dir="$4"
  ensure_session_history_file
  printf "%s\t%s\t%s\t\t\t\trunning\t%s\t%s\t%s\n" \
    "${session_id}" \
    "${session_type}" \
    "${started_at_utc}" \
    "${RUNTIME_SESSION}" \
    "${SDK_SESSION}" \
    "${run_dir}" >> "${SESSION_HISTORY_FILE}"
  sync_session_history_csv
}

write_last_run_metadata() {
  local run_id="$1"
  local run_dir="$2"
  local profile="$3"
  local started_at_utc="$4"
  local started_at_epoch="$5"
  cat > "${LAST_RUN_META_FILE}" <<EOF
RUN_ID=${run_id}
RUN_DIR=${run_dir}
PROFILE=${profile}
STARTED_AT_UTC=${started_at_utc}
STARTED_AT_EPOCH=${started_at_epoch}
ACTIVE=1
FINAL_STATUS=running
EOF
}

finalize_last_run_metadata() {
  local run_id="$1"
  local run_dir="$2"
  local profile="$3"
  local started_at_utc="$4"
  local started_at_epoch="$5"
  local stopped_at_utc="$6"
  local stopped_at_epoch="$7"
  local duration_sec="$8"
  local duration_hms="$9"
  local final_status="${10}"
  cat > "${LAST_RUN_META_FILE}" <<EOF
RUN_ID=${run_id}
RUN_DIR=${run_dir}
PROFILE=${profile}
STARTED_AT_UTC=${started_at_utc}
STARTED_AT_EPOCH=${started_at_epoch}
ACTIVE=0
FINAL_STATUS=${final_status}
STOPPED_AT_UTC=${stopped_at_utc}
STOPPED_AT_EPOCH=${stopped_at_epoch}
DURATION_SEC=${duration_sec}
DURATION_HMS=${duration_hms}
EOF
}

finalize_session_history() {
  local final_status="${1:-stopped}"
  local run_id run_dir profile started_at_utc started_at_epoch stopped_at_utc stopped_at_epoch duration_sec duration_hms tmp_file

  [[ -f "${LAST_RUN_META_FILE}" ]] || return 0
  if [[ "$(session_meta_value ACTIVE)" != "1" ]]; then
    return 0
  fi

  run_id="$(session_meta_value RUN_ID)"
  run_dir="$(session_meta_value RUN_DIR)"
  profile="$(session_meta_value PROFILE)"
  started_at_utc="$(session_meta_value STARTED_AT_UTC)"
  started_at_epoch="$(session_meta_value STARTED_AT_EPOCH)"

  [[ -n "${run_id}" ]] || return 0
  stopped_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  stopped_at_epoch="$(date -u +%s)"
  if [[ -n "${started_at_epoch}" && "${started_at_epoch}" =~ ^[0-9]+$ ]]; then
    duration_sec=$(( stopped_at_epoch - started_at_epoch ))
  else
    duration_sec=0
  fi
  duration_hms="$(format_duration_hms "${duration_sec}")"

  ensure_session_history_file
  tmp_file="$(mktemp)"
  awk -F'\t' -v OFS='\t' \
    -v run_id="${run_id}" \
    -v stopped_at_utc="${stopped_at_utc}" \
    -v duration_sec="${duration_sec}" \
    -v duration_hms="${duration_hms}" \
    -v final_status="${final_status}" \
    'NR == 1 { print; next }
     $1 == run_id { $4 = stopped_at_utc; $5 = duration_sec; $6 = duration_hms; $7 = final_status }
     { print }' "${SESSION_HISTORY_FILE}" > "${tmp_file}"
  mv "${tmp_file}" "${SESSION_HISTORY_FILE}"
  sync_session_history_csv

  finalize_last_run_metadata \
    "${run_id}" \
    "${run_dir}" \
    "${profile}" \
    "${started_at_utc}" \
    "${started_at_epoch}" \
    "${stopped_at_utc}" \
    "${stopped_at_epoch}" \
    "${duration_sec}" \
    "${duration_hms}" \
    "${final_status}"
}

session_profile_for_checks() {
  local profile=""
  profile="$(session_meta_value PROFILE)"
  if [[ -n "${profile}" ]]; then
    printf '%s' "${profile}"
    return 0
  fi
  normalize_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}"
}

set_profile_runtime_windows() {
  local profile="$1"
  local -n runtime_ref="$2"
  case "${profile}" in
    tutorial)
      runtime_ref=(tutorial)
      ;;
    *)
      runtime_ref=(isaac compress nav detector)
      ;;
  esac
}

set_profile_archived_logs() {
  local profile="$1"
  local -n logs_ref="$2"
  case "${profile}" in
    tutorial)
      logs_ref=(launcher.log tutorial.log sdk.log)
      ;;
    *)
      logs_ref=(launcher.log isaac.log compress.log nav.log detector.log sdk.log)
      ;;
  esac
}

sanitize_snap_gui_env() {
  # VS Code snap shells can leak GTK/SNAP env into tmux, which breaks rviz2.
  unset GTK_PATH
  unset SNAP
  unset SNAP_ARCH
  unset SNAP_COMMON
  unset SNAP_CONTEXT
  unset SNAP_COOKIE
  unset SNAP_DATA
  unset SNAP_INSTANCE_KEY
  unset SNAP_INSTANCE_NAME
  unset SNAP_LIBRARY_PATH
  unset SNAP_NAME
  unset SNAP_REAL_HOME
  unset SNAP_REEXEC
  unset SNAP_REVISION
  unset SNAP_USER_COMMON
  unset SNAP_USER_DATA
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_file() {
  local path="$1"
  local label="$2"
  [[ -f "${path}" ]] || die "Missing ${label}: ${path}"
}

require_executable() {
  local path="$1"
  local label="$2"
  [[ -x "${path}" ]] || die "Missing executable ${label}: ${path}"
}

ensure_dirs() {
  mkdir -p "${LOG_ROOT}" "${RUNTIME_LOG_DIR}"
}

tmux_has_named_session() {
  local target_session="$1"
  tmux has-session -t "${target_session}" >/dev/null 2>&1
}

setup_tmux_log_pipe() {
  local target_session="$1"
  local window="$2"
  local log_file="$3"
  local cmd
  cmd="cat >> $(printf '%q' "${log_file}")"
  tmux pipe-pane -o -t "${target_session}:${window}" "${cmd}"
}

append_launcher_log() {
  local run_dir="$1"
  local level="$2"
  shift 2
  printf "[%s] [%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${level}" "$*" >> "${run_dir}/launcher.log"
}

latest_run_dir() {
  local run_dir=""
  if [[ -f "${LAST_RUN_META_FILE}" ]]; then
    run_dir="$(awk -F= '$1=="RUN_DIR"{print substr($0,9)}' "${LAST_RUN_META_FILE}" | tail -n 1)"
  fi
  if [[ -z "${run_dir}" ]]; then
    run_dir="$(ls -1dt "${RUNTIME_LOG_DIR}"/* 2>/dev/null | head -n 1 || true)"
  fi
  printf '%s' "${run_dir}"
}

check_required_windows_for_session() {
  local target_session="$1"
  local -n reason_ref="$2"
  shift 2
  local -a windows=("$@")
  local window pane_line dead dead_status pane_id

  reason_ref=""
  for window in "${windows[@]}"; do
    pane_line="$(tmux list-panes -t "${target_session}:${window}" -F "#{pane_dead} #{pane_dead_status} #{pane_id}" 2>/dev/null | head -n 1 || true)"
    if [[ -z "${pane_line}" ]]; then
      reason_ref="missing pane in window '${window}'"
      return 1
    fi
    read -r dead dead_status pane_id <<< "${pane_line}"
    if [[ "${dead}" != "0" ]]; then
      reason_ref="window '${window}' pane ${pane_id} exited (status=${dead_status})"
      return 1
    fi
  done
  return 0
}

wait_for_log_pattern() {
  local target_session="$1"
  local timeout_sec="$2"
  local label="$3"
  local log_file="$4"
  local pattern="$5"
  shift 5
  local -a windows=("$@")
  local start_ts now elapsed reason=""

  info "Waiting for ${label} (timeout=${timeout_sec}s)..."
  start_ts="$(date +%s)"
  while true; do
    if [[ -f "${log_file}" ]] && grep -qF "${pattern}" "${log_file}"; then
      ok "${label} is ready."
      return 0
    fi

    if ! check_required_windows_for_session "${target_session}" reason "${windows[@]}"; then
      error "${label} failed before it became ready: ${reason}"
      return 1
    fi

    now="$(date +%s)"
    elapsed=$(( now - start_ts ))
    if (( elapsed >= timeout_sec )); then
      error "${label} timed out after ${timeout_sec}s."
      error "Expected log pattern: ${pattern}"
      return 1
    fi

    sleep 1
  done
}

normalize_local_profile() {
  local raw="${1:-${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}}"
  local normalized
  normalized="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"
  case "${normalized}" in
    ""|hospital|exp1rtx)
      printf 'hospital'
      ;;
    office)
      printf 'office'
      ;;
    tutorial)
      printf 'tutorial'
      ;;
    *)
      return 1
      ;;
  esac
}

build_profile_script_cmd() {
  local profile="$1"
  local subcommand="$2"
  printf 'LOCAL_PROFILE=%q %q %q' "${profile}" "${SCRIPT_DIR}/horus_local_experiment.sh" "${subcommand}"
}

resolve_local_profile() {
  local requested="${1:-${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}}"
  ACTIVE_PROFILE="$(normalize_local_profile "${requested}")" || die "Unsupported local profile: ${requested}"
  ACTIVE_PROFILE_LABEL="${ACTIVE_PROFILE}"
  ACTIVE_USD_PATH=""
  ACTIVE_ISAAC_ARGS=()
  ACTIVE_NAV_ARGS=()
  ACTIVE_SDK_ARGS=()

  case "${ACTIVE_PROFILE}" in
    hospital)
      ACTIVE_USD_PATH="${HOSPITAL_USD_EXP1RTX}"
      ACTIVE_ISAAC_ARGS=(
        --disable-physx-laserscan
        --usd-path "${ACTIVE_USD_PATH}"
      )
      ACTIVE_SDK_ARGS=(
        --apriltag-scene-profile hospital
      )
      ;;
    office)
      ACTIVE_USD_PATH="${OFFICE_USD}"
      ACTIVE_ISAAC_ARGS=(
        --disable-physx-laserscan
        --robot-profile single-front-camera-rtx-front-laserscan
        --profile-camera-width 400
        --profile-camera-height 300
        --usd-path "${ACTIVE_USD_PATH}"
      )
      ACTIVE_NAV_ARGS=(
        "carter1_pose:=${OFFICE_CARTER1_POSE}"
        "carter2_pose:=${OFFICE_CARTER2_POSE}"
        "carter3_pose:=${OFFICE_CARTER3_POSE}"
      )
      ACTIVE_SDK_ARGS=(
        --apriltag-scene-profile office
      )
      ;;
    tutorial)
      ;;
  esac
}

validate_paths() {
  local profile="${1:-${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}}"
  resolve_local_profile "${profile}"
  have_cmd "${SDK_PYTHON}" || die "Missing SDK python interpreter: ${SDK_PYTHON}"
  have_cmd tmux || die "tmux is not installed."

  case "${ACTIVE_PROFILE}" in
    tutorial)
      require_file "${HORUS_FETCH_ROBOT_DESCRIPTION_ASSETS}" "HORUS fetch robot description assets script"
      require_file "${HORUS_FAKE_ROBOT_DESCRIPTION_TUTORIAL_SUITE}" "HORUS fake robot description tutorial suite"
      require_file "${HORUS_SDK_TUTORIAL_DEMO}" "HORUS robot description tutorial demo"
      ;;
    *)
      require_file "${ROS_SETUP_FILE}" "ROS Jazzy setup file"
      require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
      require_file "${FAST_ISAAC_SIM}" "fast_isaac_sim.py"
      require_file "${ACTIVE_USD_PATH}" "${ACTIVE_PROFILE_LABEL} USD"
      require_file "${CARTER_MULTI_NAV_SETUP_FILE}" "carter_multi_nav install setup"
      require_file "${HORUS_SDK_HOSPITAL_DEMO}" "HORUS Carter live demo"
      ;;
  esac
}

run_isaac() {
  resolve_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}"
  require_file "${ROS_SETUP_FILE}" "ROS Jazzy setup file"
  require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
  require_file "${FAST_ISAAC_SIM}" "fast_isaac_sim.py"
  require_file "${ACTIVE_USD_PATH}" "${ACTIVE_PROFILE_LABEL} USD"

  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  set -u

  info "Starting Isaac Sim ${ACTIVE_PROFILE_LABEL}..."
  exec "${ISAAC_PYTHON}" "${FAST_ISAAC_SIM}" \
    --headless \
    --render-headless \
    --render-every 2 \
    --aa-mode 3 \
    --dlss-exec-mode 0 \
    --no-ground-plane \
    --physics-step 0.0166667 \
    --target-sim-hz 60 \
    "${ACTIVE_ISAAC_ARGS[@]}" \
    --max-steps -1
}

start_one_compression_relay() {
  local robot="$1"
  local in_topic="/${robot}/front_stereo_camera/left/image_raw"
  local out_topic="/${robot}/front_stereo_camera/left/image_raw/compressed"
  info "Starting image compression relay: ${in_topic} -> ${out_topic}"
  ros2 run image_transport republish \
    --ros-args \
    -r __node:="${robot}_image_republisher" \
    -p in_transport:=raw \
    -p out_transport:=compressed \
    -r in:="${in_topic}" \
    -r out/compressed:="${out_topic}"
}

run_compress() {
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  set -u

  have_cmd ros2 || die "ros2 command not found after sourcing ${ROS_SETUP_FILE}"

  trap 'warn "Stopping image compression relays..."; kill 0 >/dev/null 2>&1 || true' INT TERM

  start_one_compression_relay carter1 &
  start_one_compression_relay carter2 &
  start_one_compression_relay carter3 &
  wait
}

run_nav() {
  resolve_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}"
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u
  sanitize_snap_gui_env

  cd "${CARTER_MULTI_NAV_ROOT}"
  info "Starting carter_multi_nav for ${ACTIVE_PROFILE_LABEL}..."
  exec ros2 launch "${CARTER_NAV_LAUNCH_PACKAGE}" "${CARTER_NAV_LAUNCH_FILE}" rviz:="${LOCAL_NAV_RVIZ}" "${ACTIVE_NAV_ARGS[@]}"
}

run_detector() {
  resolve_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}"
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u

  cd "${CARTER_MULTI_NAV_ROOT}"
  info "Starting AprilTag detector for ${ACTIVE_PROFILE_LABEL}..."
  exec ros2 launch "${CARTER_APRILTAG_LAUNCH_PACKAGE}" "${CARTER_APRILTAG_LAUNCH_FILE}"
}

run_tutorial_suite() {
  cd "${HORUS_SDK_ROOT}"
  info "Fetching robot description assets..."
  "${SDK_PYTHON}" "${HORUS_FETCH_ROBOT_DESCRIPTION_ASSETS}" --force
  info "Starting fake robot description tutorial suite..."
  exec "${SDK_PYTHON}" "${HORUS_FAKE_ROBOT_DESCRIPTION_TUTORIAL_SUITE}" \
    --robot-profile real_models \
    --map-3d-mode off
}

run_tutorial_sdk() {
  cd "${HORUS_SDK_ROOT}"
  info "Starting HORUS robot description tutorial demo..."
  exec "${SDK_PYTHON}" "${HORUS_SDK_TUTORIAL_DEMO}" \
    --robot-profile real_models \
    --workspace-scale 0.1 \
    --collision-opaque \
    --map-3d-mode off
}

run_sdk() {
  local -a extra_args=()
  resolve_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}"
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u

  if [[ "${LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING}" =~ ^(1|true|yes|on)$ ]]; then
    extra_args+=(--apriltag-semantic-labeling)
  fi
  extra_args+=("${ACTIVE_SDK_ARGS[@]}")

  cd "${HORUS_SDK_ROOT}"
  info "Starting HORUS Carter live demo for ${ACTIVE_PROFILE_LABEL}..."
  exec "${SDK_PYTHON}" "${HORUS_SDK_HOSPITAL_DEMO}" \
    --robot-names "${LOCAL_ROBOT_NAMES}" \
    --workspace-scale "${LOCAL_WORKSPACE_SCALE}" \
    --body-mesh-mode "${LOCAL_BODY_MESH_MODE}" \
    "${extra_args[@]}"
}

start_local_profile() {
  local requested_profile="${1:-${DEFAULT_LOCAL_PROFILE}}"
  local script_path="${SCRIPT_DIR}/horus_local_experiment.sh"
  local run_id
  local run_dir
  local reason=""
  local started_at_utc
  local started_at_epoch

  resolve_local_profile "${requested_profile}"
  info "Starting local ${ACTIVE_PROFILE_LABEL} pipeline with dedicated local launcher..."
  ensure_dirs
  validate_paths "${ACTIVE_PROFILE}"

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    die "tmux session '${RUNTIME_SESSION}' already exists. Use '$0 stop' first."
  fi
  if tmux_has_named_session "${SDK_SESSION}"; then
    die "tmux session '${SDK_SESSION}' already exists. Use '$0 stop' first."
  fi

  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  run_dir="${RUNTIME_LOG_DIR}/${run_id}"
  mkdir -p "${run_dir}"
  started_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  started_at_epoch="$(date -u +%s)"
  write_last_run_metadata "${run_id}" "${run_dir}" "${ACTIVE_PROFILE}" "${started_at_utc}" "${started_at_epoch}"
  append_session_history_start "${run_id}" "${ACTIVE_PROFILE}" "${started_at_utc}" "${run_dir}"
  append_launcher_log "${run_dir}" "INFO" "Local ${ACTIVE_PROFILE_LABEL} startup initiated."

  if [[ "${ACTIVE_PROFILE}" == "tutorial" ]]; then
    info "Starting tutorial fake data suite..."
    append_launcher_log "${run_dir}" "INFO" "Starting tutorial fake data suite."
    tmux new-session -d -s "${RUNTIME_SESSION}" -n tutorial "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-tutorial-suite")"
    tmux setw -t "${RUNTIME_SESSION}" remain-on-exit on
    setup_tmux_log_pipe "${RUNTIME_SESSION}" tutorial "${run_dir}/tutorial.log"
    sleep "${LOCAL_BOOT_GRACE_SEC}"

    if ! check_required_windows_for_session "${RUNTIME_SESSION}" reason tutorial; then
      append_launcher_log "${run_dir}" "ERROR" "Tutorial fake data suite failed after launch: ${reason}"
      warn "Tutorial startup failed before SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
      tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
      tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
      finalize_session_history startup_failed
      die "Tutorial fake data suite failed after launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
    fi

    info "Starting tutorial SDK demo..."
    append_launcher_log "${run_dir}" "INFO" "Starting tutorial SDK demo."
    tmux new-session -d -s "${SDK_SESSION}" -n sdk "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-tutorial-sdk")"
    tmux setw -t "${SDK_SESSION}" remain-on-exit on
    setup_tmux_log_pipe "${SDK_SESSION}" sdk "${run_dir}/sdk.log"
    sleep 2

    if ! check_required_windows_for_session "${SDK_SESSION}" reason sdk; then
      append_launcher_log "${run_dir}" "ERROR" "Tutorial SDK failed after launch: ${reason}"
      warn "Tutorial startup failed after SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
      tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
      tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
      finalize_session_history startup_failed
      die "Tutorial SDK failed after launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
    fi

    append_launcher_log "${run_dir}" "INFO" "Local tutorial startup complete."
    ok "Local runtime session '${RUNTIME_SESSION}' started."
    ok "Local SDK session '${SDK_SESSION}' started."
    printf "Logs: %s\n" "$(display_path "${run_dir}")"
    printf "Attach runtime: tmux attach -t %s\n" "${RUNTIME_SESSION}"
    printf "Attach sdk: tmux attach -t %s\n" "${SDK_SESSION}"
    return
  fi

  info "Launching Isaac Sim..."
  append_launcher_log "${run_dir}" "INFO" "Launching Isaac Sim for profile '${ACTIVE_PROFILE_LABEL}'."
  tmux new-session -d -s "${RUNTIME_SESSION}" -n isaac "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-isaac")"
  tmux setw -t "${RUNTIME_SESSION}" remain-on-exit on
  setup_tmux_log_pipe "${RUNTIME_SESSION}" isaac "${run_dir}/isaac.log"

  if ! wait_for_log_pattern \
    "${RUNTIME_SESSION}" \
    "${STARTUP_TIMEOUT_SEC}" \
    "Isaac scene load" \
    "${run_dir}/isaac.log" \
    "Startup phase: ready topic received: topic=/clock" \
    isaac; then
    append_launcher_log "${run_dir}" "ERROR" "Isaac readiness failed."
    warn "Local startup failed before nav launch. Stopping '${RUNTIME_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    finalize_session_history startup_failed
    die "Isaac readiness failed. Run '$0 logs' to inspect ${run_dir}."
  fi
  append_launcher_log "${run_dir}" "INFO" "Isaac ready marker detected."

  info "Starting compression relays..."
  append_launcher_log "${run_dir}" "INFO" "Starting image compression relays."
  tmux new-window -t "${RUNTIME_SESSION}:" -n compress "${script_path} _run-compress"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" compress "${run_dir}/compress.log"

  info "Starting AprilTag detector..."
  append_launcher_log "${run_dir}" "INFO" "Starting AprilTag detector."
  tmux new-window -t "${RUNTIME_SESSION}:" -n detector "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-detector")"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" detector "${run_dir}/detector.log"
  sleep "${LOCAL_BOOT_GRACE_SEC}"

  if ! check_required_windows_for_session "${RUNTIME_SESSION}" reason isaac compress detector; then
    append_launcher_log "${run_dir}" "ERROR" "Runtime stack failed after compression/detector launch: ${reason}"
    warn "Local startup failed before nav launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    finalize_session_history startup_failed
    die "Local runtime stack failed before nav launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  if [[ "${LOCAL_NAV_START_DELAY_SEC}" != "0" && "${LOCAL_NAV_START_DELAY_SEC}" != "0.0" ]]; then
    info "Waiting ${LOCAL_NAV_START_DELAY_SEC}s before starting nav..."
    append_launcher_log "${run_dir}" "INFO" "Waiting ${LOCAL_NAV_START_DELAY_SEC}s before starting nav."
    sleep "${LOCAL_NAV_START_DELAY_SEC}"
  fi

  info "Starting carter_multi_nav..."
  append_launcher_log "${run_dir}" "INFO" "Starting carter_multi_nav for profile '${ACTIVE_PROFILE_LABEL}'."
  tmux new-window -t "${RUNTIME_SESSION}:" -n nav "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-nav")"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" nav "${run_dir}/nav.log"
  tmux select-window -t "${RUNTIME_SESSION}:nav"
  sleep "${LOCAL_BOOT_GRACE_SEC}"

  if ! check_required_windows_for_session "${RUNTIME_SESSION}" reason isaac compress nav detector; then
    append_launcher_log "${run_dir}" "ERROR" "Runtime stack failed after nav launch: ${reason}"
    warn "Local startup failed before SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    finalize_session_history startup_failed
    die "Local runtime stack failed after nav launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  if [[ "${LOCAL_SDK_START_DELAY_SEC}" != "0" && "${LOCAL_SDK_START_DELAY_SEC}" != "0.0" ]]; then
    info "Waiting ${LOCAL_SDK_START_DELAY_SEC}s before starting SDK..."
    append_launcher_log "${run_dir}" "INFO" "Waiting ${LOCAL_SDK_START_DELAY_SEC}s before starting SDK."
    sleep "${LOCAL_SDK_START_DELAY_SEC}"
  fi

  info "Starting HORUS SDK demo..."
  append_launcher_log "${run_dir}" "INFO" "Starting HORUS SDK demo for profile '${ACTIVE_PROFILE_LABEL}'."
  tmux new-session -d -s "${SDK_SESSION}" -n sdk "$(build_profile_script_cmd "${ACTIVE_PROFILE}" "_run-sdk")"
  tmux setw -t "${SDK_SESSION}" remain-on-exit on
  setup_tmux_log_pipe "${SDK_SESSION}" sdk "${run_dir}/sdk.log"
  sleep 2

  if ! check_required_windows_for_session "${SDK_SESSION}" reason sdk; then
    append_launcher_log "${run_dir}" "ERROR" "SDK failed after launch: ${reason}"
    warn "Local startup failed after SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    finalize_session_history startup_failed
    die "SDK failed after launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  append_launcher_log "${run_dir}" "INFO" "Local ${ACTIVE_PROFILE_LABEL} startup complete."
  ok "Local runtime session '${RUNTIME_SESSION}' started."
  ok "Local SDK session '${SDK_SESSION}' started."
  printf "Logs: %s\n" "$(display_path "${run_dir}")"
  printf "Attach runtime: tmux attach -t %s\n" "${RUNTIME_SESSION}"
  printf "Attach sdk: tmux attach -t %s\n" "${SDK_SESSION}"
}

stop_all() {
  local stopped=0
  if tmux_has_named_session "${SDK_SESSION}"; then
    tmux kill-session -t "${SDK_SESSION}"
    stopped=1
  fi
  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    tmux kill-session -t "${RUNTIME_SESSION}"
    stopped=1
  fi
  if [[ "${stopped}" -eq 1 || "$(session_meta_value ACTIVE)" == "1" ]]; then
    finalize_session_history stopped
  fi
  if [[ "${stopped}" -eq 1 ]]; then
    ok "Stopped local sessions."
  else
    warn "Local sessions are not running."
  fi
}

print_live_logs_for_session() {
  local target_session="$1"
  local lines="$2"
  shift 2
  local window
  for window in "$@"; do
    if tmux list-panes -t "${target_session}:${window}" >/dev/null 2>&1; then
      printf "\n===== %s (tmux:%s:%s) =====\n" "${window}" "${target_session}" "${window}"
      tmux capture-pane -p -t "${target_session}:${window}" -S "-${lines}" | tail -n "${lines}"
    fi
  done
}

print_archived_logs() {
  local run_dir="$1"
  local lines="$2"
  shift 2
  local log_file
  for log_file in "$@"; do
    if [[ -f "${run_dir}/${log_file}" ]]; then
      printf "\n===== %s =====\n" "${log_file}"
      tail -n "${lines}" "${run_dir}/${log_file}"
    fi
  done
}

logs_cmd() {
  local lines="${1:-${LOG_TAIL_LINES_DEFAULT}}"
  local run_dir=""
  local showed_live=0
  local active_profile=""
  local -a runtime_windows=()
  local -a archived_logs=()

  [[ "${lines}" =~ ^[0-9]+$ ]] || die "logs expects numeric line count; got '${lines}'."
  run_dir="$(latest_run_dir)"
  active_profile="$(session_profile_for_checks)" || active_profile="${DEFAULT_LOCAL_PROFILE}"
  set_profile_runtime_windows "${active_profile}" runtime_windows
  set_profile_archived_logs "${active_profile}" archived_logs

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    if [[ -n "${run_dir}" && -f "${run_dir}/launcher.log" ]]; then
      info "Showing launcher stage log from $(display_path "${run_dir}")"
      print_archived_logs "${run_dir}" "${lines}" launcher.log
    fi
    info "Showing last ${lines} lines from live runtime panes."
    print_live_logs_for_session "${RUNTIME_SESSION}" "${lines}" "${runtime_windows[@]}"
    showed_live=1
  fi
  if tmux_has_named_session "${SDK_SESSION}"; then
    if [[ "${showed_live}" -eq 0 ]]; then
      info "Showing last ${lines} lines from live panes."
    fi
    print_live_logs_for_session "${SDK_SESSION}" "${lines}" sdk
    showed_live=1
  fi
  if [[ "${showed_live}" -eq 1 ]]; then
    return
  fi

  if [[ -z "${run_dir}" || ! -d "${run_dir}" ]]; then
    die "No running sessions and no archived logs found under $(display_path "${RUNTIME_LOG_DIR}")."
  fi
  info "Showing archived logs from $(display_path "${run_dir}")"
  print_archived_logs "${run_dir}" "${lines}" "${archived_logs[@]}"
}

status_cmd() {
  local reason=""
  local run_dir=""
  local default_profile=""
  local active_profile=""
  local -a runtime_windows=()

  default_profile="$(normalize_local_profile "${LOCAL_PROFILE:-${DEFAULT_LOCAL_PROFILE}}")" || default_profile="${DEFAULT_LOCAL_PROFILE}"
  active_profile="$(session_profile_for_checks)" || active_profile="${default_profile}"
  set_profile_runtime_windows "${active_profile}" runtime_windows

  info "Horus local launcher status"
  printf "  default profile: %s\n" "${default_profile}"
  printf "  isaac python: %s\n" "$(display_path "${ISAAC_PYTHON}")"
  printf "  launcher: %s\n" "$(display_path "${FAST_ISAAC_SIM}")"
  printf "  usd (hospital): %s\n" "$(display_path "${HOSPITAL_USD_EXP1RTX}")"
  printf "  usd (office): %s\n" "$(display_path "${OFFICE_USD}")"
  printf "  nav root: %s\n" "$(display_path "${CARTER_MULTI_NAV_ROOT}")"
  printf "  nav setup: %s\n" "$(display_path "${CARTER_MULTI_NAV_SETUP_FILE}")"
  printf "  nav rviz: %s\n" "${LOCAL_NAV_RVIZ}"
  printf "  apriltag semantic labeling: %s\n" "${LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING}"
  printf "  horus sdk root: %s\n" "$(display_path "${HORUS_SDK_ROOT}")"
  printf "  horus demo: %s\n" "$(display_path "${HORUS_SDK_HOSPITAL_DEMO}")"
  printf "  tutorial fake suite: %s\n" "$(display_path "${HORUS_FAKE_ROBOT_DESCRIPTION_TUTORIAL_SUITE}")"
  printf "  tutorial demo: %s\n" "$(display_path "${HORUS_SDK_TUTORIAL_DEMO}")"
  printf "  session history csv: %s\n" "$(display_path "${SESSION_HISTORY_CSV_FILE}")"
  printf "  runtime session: %s\n" "${RUNTIME_SESSION}"
  printf "  sdk session: %s\n" "${SDK_SESSION}"
  printf "  startup timeout sec: %s\n" "${STARTUP_TIMEOUT_SEC}"
  printf "  nav start delay sec: %s\n" "${LOCAL_NAV_START_DELAY_SEC}"
  printf "  sdk start delay sec: %s\n" "${LOCAL_SDK_START_DELAY_SEC}"
  printf "  ros_domain_id: %s\n" "${ROS_DOMAIN_ID:-<unset>}"
  printf "  rmw_implementation: %s\n" "${RMW_IMPLEMENTATION:-<unset>}"
  printf "  cyclonedds_uri: %s\n" "${CYCLONEDDS_URI:-<unset>}"

  run_dir="$(latest_run_dir)"
  if [[ -n "${run_dir}" ]]; then
    printf "  latest logs: %s\n" "$(display_path "${run_dir}")"
  fi
  printf "  last profile: %s\n" "${active_profile}"
  if [[ -f "${LAST_RUN_META_FILE}" ]]; then
    printf "  last session id: %s\n" "$(session_meta_value RUN_ID)"
    printf "  last session status: %s\n" "$(session_meta_value FINAL_STATUS)"
    printf "  last started at utc: %s\n" "$(session_meta_value STARTED_AT_UTC)"
    if [[ -n "$(session_meta_value STOPPED_AT_UTC)" ]]; then
      printf "  last stopped at utc: %s\n" "$(session_meta_value STOPPED_AT_UTC)"
      printf "  last duration: %s (%ss)\n" "$(session_meta_value DURATION_HMS)" "$(session_meta_value DURATION_SEC)"
    fi
  fi

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    if check_required_windows_for_session "${RUNTIME_SESSION}" reason "${runtime_windows[@]}"; then
      printf "  runtime health: healthy\n"
    else
      printf "  runtime health: unhealthy (%s)\n" "${reason}"
    fi
    tmux list-panes -t "${RUNTIME_SESSION}" -F "  runtime pane=#{pane_id} window=#{window_name} dead=#{pane_dead} dead_status=#{pane_dead_status} pid=#{pane_pid} cmd=#{pane_current_command}"
  else
    printf "  runtime health: not running\n"
  fi

  if tmux_has_named_session "${SDK_SESSION}"; then
    if check_required_windows_for_session "${SDK_SESSION}" reason sdk; then
      printf "  sdk health: healthy\n"
    else
      printf "  sdk health: unhealthy (%s)\n" "${reason}"
    fi
    tmux list-panes -t "${SDK_SESSION}" -F "  sdk pane=#{pane_id} window=#{window_name} dead=#{pane_dead} dead_status=#{pane_dead_status} pid=#{pane_pid} cmd=#{pane_current_command}"
  else
    printf "  sdk health: not running\n"
  fi
}

usage() {
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  start [hospital|office|tutorial]
  start-exp1rtx     Alias for 'start hospital'.
  start-hospital    Start the local hospital profile.
  start-office      Start the local office profile.
  start-tutorial    Start the local tutorial profile.
  stop              Stop both tmux sessions.
  stop-exp1rtx      Alias of stop.
  logs [lines]      Show live or archived logs.
  status            Show launcher status.

Notes:
  - This script does not source the cloud env file.
  - It does not force ROS_DOMAIN_ID.
  - It uses your current shell/tmux ROS environment as-is.
EOF
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    start)
      shift
      start_local_profile "${1:-hospital}"
      ;;
    start-exp1rtx|start-hospital)
      start_local_profile hospital
      ;;
    start-office)
      start_local_profile office
      ;;
    start-tutorial)
      start_local_profile tutorial
      ;;
    stop|stop-exp1rtx)
      stop_all
      ;;
    logs)
      shift
      logs_cmd "${1:-${LOG_TAIL_LINES_DEFAULT}}"
      ;;
    status)
      status_cmd
      ;;
    _run-isaac)
      run_isaac
      ;;
    _run-compress)
      run_compress
      ;;
    _run-nav)
      run_nav
      ;;
    _run-detector)
      run_detector
      ;;
    _run-tutorial-suite)
      run_tutorial_suite
      ;;
    _run-sdk)
      run_sdk
      ;;
    _run-tutorial-sdk)
      run_tutorial_sdk
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      die "Unknown command: ${cmd}. Use --help."
      ;;
  esac
}

main "$@"
