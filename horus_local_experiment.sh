#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_ROOT="${SCRIPT_DIR}/logs"

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

write_last_run_metadata() {
  local run_id="$1"
  local run_dir="$2"
  cat > "${LAST_RUN_META_FILE}" <<EOF
RUN_ID=${run_id}
RUN_DIR=${run_dir}
STARTED_AT_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
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

validate_paths() {
  require_file "${ROS_SETUP_FILE}" "ROS Jazzy setup file"
  require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
  require_file "${FAST_ISAAC_SIM}" "fast_isaac_sim.py"
  require_file "${HOSPITAL_USD_EXP1RTX}" "exp1rtx USD"
  require_file "${CARTER_MULTI_NAV_SETUP_FILE}" "carter_multi_nav install setup"
  require_file "${HORUS_SDK_HOSPITAL_DEMO}" "HORUS Carter live demo"
  have_cmd "${SDK_PYTHON}" || die "Missing SDK python interpreter: ${SDK_PYTHON}"
  have_cmd tmux || die "tmux is not installed."
}

run_isaac() {
  require_file "${ROS_SETUP_FILE}" "ROS Jazzy setup file"
  require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
  require_file "${FAST_ISAAC_SIM}" "fast_isaac_sim.py"
  require_file "${HOSPITAL_USD_EXP1RTX}" "exp1rtx USD"

  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  set -u

  info "Starting Isaac Sim exp1rtx..."
  exec "${ISAAC_PYTHON}" "${FAST_ISAAC_SIM}" \
    --headless \
    --render-headless \
    --render-every 2 \
    --aa-mode 3 \
    --dlss-exec-mode 0 \
    --disable-physx-laserscan \
    --usd-path "${HOSPITAL_USD_EXP1RTX}" \
    --no-ground-plane \
    --physics-step 0.0166667 \
    --target-sim-hz 60 \
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
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u

  cd "${CARTER_MULTI_NAV_ROOT}"
  info "Starting carter_multi_nav..."
  exec ros2 launch "${CARTER_NAV_LAUNCH_PACKAGE}" "${CARTER_NAV_LAUNCH_FILE}" rviz:="${LOCAL_NAV_RVIZ}"
}

run_detector() {
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u

  cd "${CARTER_MULTI_NAV_ROOT}"
  info "Starting AprilTag detector..."
  exec ros2 launch "${CARTER_APRILTAG_LAUNCH_PACKAGE}" "${CARTER_APRILTAG_LAUNCH_FILE}"
}

run_sdk() {
  local -a extra_args=()
  set +u
  # shellcheck disable=SC1090
  source "${ROS_SETUP_FILE}"
  # shellcheck disable=SC1090
  source "${CARTER_MULTI_NAV_SETUP_FILE}"
  set -u

  if [[ "${LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING}" =~ ^(1|true|yes|on)$ ]]; then
    extra_args+=(--apriltag-semantic-labeling)
  fi

  cd "${HORUS_SDK_ROOT}"
  info "Starting HORUS Carter live demo..."
  exec "${SDK_PYTHON}" "${HORUS_SDK_HOSPITAL_DEMO}" \
    --robot-names "${LOCAL_ROBOT_NAMES}" \
    --workspace-scale "${LOCAL_WORKSPACE_SCALE}" \
    --body-mesh-mode "${LOCAL_BODY_MESH_MODE}" \
    "${extra_args[@]}"
}

start_local_exp1rtx() {
  local script_path="${SCRIPT_DIR}/horus_local_experiment.sh"
  local run_id
  local run_dir
  local reason=""

  info "Starting local exp1rtx pipeline with dedicated local launcher..."
  ensure_dirs
  validate_paths

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    die "tmux session '${RUNTIME_SESSION}' already exists. Use '$0 stop' first."
  fi
  if tmux_has_named_session "${SDK_SESSION}"; then
    die "tmux session '${SDK_SESSION}' already exists. Use '$0 stop' first."
  fi

  run_id="$(date -u +%Y%m%dT%H%M%SZ)"
  run_dir="${RUNTIME_LOG_DIR}/${run_id}"
  mkdir -p "${run_dir}"
  write_last_run_metadata "${run_id}" "${run_dir}"
  append_launcher_log "${run_dir}" "INFO" "Local exp1rtx startup initiated."

  info "Launching Isaac Sim..."
  append_launcher_log "${run_dir}" "INFO" "Launching Isaac Sim."
  tmux new-session -d -s "${RUNTIME_SESSION}" -n isaac "${script_path} _run-isaac"
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
    die "Isaac readiness failed. Run '$0 logs' to inspect ${run_dir}."
  fi
  append_launcher_log "${run_dir}" "INFO" "Isaac ready marker detected."

  info "Starting compression relays..."
  append_launcher_log "${run_dir}" "INFO" "Starting image compression relays."
  tmux new-window -t "${RUNTIME_SESSION}:" -n compress "${script_path} _run-compress"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" compress "${run_dir}/compress.log"

  info "Starting AprilTag detector..."
  append_launcher_log "${run_dir}" "INFO" "Starting AprilTag detector."
  tmux new-window -t "${RUNTIME_SESSION}:" -n detector "${script_path} _run-detector"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" detector "${run_dir}/detector.log"
  sleep "${LOCAL_BOOT_GRACE_SEC}"

  if ! check_required_windows_for_session "${RUNTIME_SESSION}" reason isaac compress detector; then
    append_launcher_log "${run_dir}" "ERROR" "Runtime stack failed after compression/detector launch: ${reason}"
    warn "Local startup failed before nav launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    die "Local runtime stack failed before nav launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  if [[ "${LOCAL_NAV_START_DELAY_SEC}" != "0" && "${LOCAL_NAV_START_DELAY_SEC}" != "0.0" ]]; then
    info "Waiting ${LOCAL_NAV_START_DELAY_SEC}s before starting nav..."
    append_launcher_log "${run_dir}" "INFO" "Waiting ${LOCAL_NAV_START_DELAY_SEC}s before starting nav."
    sleep "${LOCAL_NAV_START_DELAY_SEC}"
  fi

  info "Starting carter_multi_nav..."
  append_launcher_log "${run_dir}" "INFO" "Starting carter_multi_nav."
  tmux new-window -t "${RUNTIME_SESSION}:" -n nav "${script_path} _run-nav"
  setup_tmux_log_pipe "${RUNTIME_SESSION}" nav "${run_dir}/nav.log"
  tmux select-window -t "${RUNTIME_SESSION}:nav"
  sleep "${LOCAL_BOOT_GRACE_SEC}"

  if ! check_required_windows_for_session "${RUNTIME_SESSION}" reason isaac compress nav detector; then
    append_launcher_log "${run_dir}" "ERROR" "Runtime stack failed after nav launch: ${reason}"
    warn "Local startup failed before SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    die "Local runtime stack failed after nav launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  if [[ "${LOCAL_SDK_START_DELAY_SEC}" != "0" && "${LOCAL_SDK_START_DELAY_SEC}" != "0.0" ]]; then
    info "Waiting ${LOCAL_SDK_START_DELAY_SEC}s before starting SDK..."
    append_launcher_log "${run_dir}" "INFO" "Waiting ${LOCAL_SDK_START_DELAY_SEC}s before starting SDK."
    sleep "${LOCAL_SDK_START_DELAY_SEC}"
  fi

  info "Starting HORUS SDK demo..."
  append_launcher_log "${run_dir}" "INFO" "Starting HORUS SDK demo."
  tmux new-session -d -s "${SDK_SESSION}" -n sdk "${script_path} _run-sdk"
  tmux setw -t "${SDK_SESSION}" remain-on-exit on
  setup_tmux_log_pipe "${SDK_SESSION}" sdk "${run_dir}/sdk.log"
  sleep 2

  if ! check_required_windows_for_session "${SDK_SESSION}" reason sdk; then
    append_launcher_log "${run_dir}" "ERROR" "SDK failed after launch: ${reason}"
    warn "Local startup failed after SDK launch. Stopping '${RUNTIME_SESSION}' and '${SDK_SESSION}'."
    tmux kill-session -t "${RUNTIME_SESSION}" >/dev/null 2>&1 || true
    tmux kill-session -t "${SDK_SESSION}" >/dev/null 2>&1 || true
    die "SDK failed after launch: ${reason}. Run '$0 logs' to inspect ${run_dir}."
  fi

  append_launcher_log "${run_dir}" "INFO" "Local exp1rtx startup complete."
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

  [[ "${lines}" =~ ^[0-9]+$ ]] || die "logs expects numeric line count; got '${lines}'."
  run_dir="$(latest_run_dir)"

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    if [[ -n "${run_dir}" && -f "${run_dir}/launcher.log" ]]; then
      info "Showing launcher stage log from $(display_path "${run_dir}")"
      print_archived_logs "${run_dir}" "${lines}" launcher.log
    fi
    info "Showing last ${lines} lines from live runtime panes."
    print_live_logs_for_session "${RUNTIME_SESSION}" "${lines}" isaac compress nav detector
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
  print_archived_logs "${run_dir}" "${lines}" launcher.log isaac.log compress.log nav.log detector.log sdk.log
}

status_cmd() {
  local reason=""
  local run_dir=""

  info "Horus local launcher status"
  printf "  isaac python: %s\n" "$(display_path "${ISAAC_PYTHON}")"
  printf "  launcher: %s\n" "$(display_path "${FAST_ISAAC_SIM}")"
  printf "  usd (exp1rtx): %s\n" "$(display_path "${HOSPITAL_USD_EXP1RTX}")"
  printf "  nav root: %s\n" "$(display_path "${CARTER_MULTI_NAV_ROOT}")"
  printf "  nav setup: %s\n" "$(display_path "${CARTER_MULTI_NAV_SETUP_FILE}")"
  printf "  nav rviz: %s\n" "${LOCAL_NAV_RVIZ}"
  printf "  apriltag semantic labeling: %s\n" "${LOCAL_ENABLE_APRILTAG_SEMANTIC_LABELING}"
  printf "  horus sdk root: %s\n" "$(display_path "${HORUS_SDK_ROOT}")"
  printf "  horus demo: %s\n" "$(display_path "${HORUS_SDK_HOSPITAL_DEMO}")"
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

  if tmux_has_named_session "${RUNTIME_SESSION}"; then
    if check_required_windows_for_session "${RUNTIME_SESSION}" reason isaac compress nav detector; then
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
  start
  start-exp1rtx     Start Isaac + compress + nav + AprilTag detector + HORUS SDK locally.
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
    start|start-exp1rtx)
      start_local_exp1rtx
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
    _run-sdk)
      run_sdk
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
