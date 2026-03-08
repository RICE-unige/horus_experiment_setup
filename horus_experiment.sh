#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
ENV_DIR="${SCRIPT_DIR}/env"
LOG_DIR="${SCRIPT_DIR}/logs"

ENV_FILE="${ENV_DIR}/cloud_ros.env"
CYCLONEDDS_XML="${CONFIG_DIR}/cyclonedds.xml"
TOPICS_BASE_FILE="${CONFIG_DIR}/topics_base.txt"
TOPICS_EXTRA_FILE="${CONFIG_DIR}/topics_extra.txt"
GEN_ZENOH_CONFIG_SCRIPT="${CONFIG_DIR}/gen_zenoh_config.sh"
ZENOH_CONFIG_FILE="${CONFIG_DIR}/zenoh_ros2dds.json5"

SESSION_NAME="${HORUS_TMUX_SESSION:-horus_exp1}"
ZENOH_PORT="${ZENOH_PORT:-10000}"
ZENOH_EXTERNAL_PORT="${ZENOH_EXTERNAL_PORT:-${ZENOH_PORT}}"

ROS_SETUP_FILE="/opt/ros/jazzy/setup.bash"
ISAAC_PYTHON="${ISAAC_PYTHON:-/isaac-sim/python.sh}"

PROJECT_ROOT_OVERRIDDEN="${PROJECT_ROOT+x}"
FAST_ISAAC_SIM_OVERRIDDEN="${FAST_ISAAC_SIM+x}"
HOSPITAL_USD_OVERRIDDEN="${HOSPITAL_USD+x}"
ZENOH_ROOT_OVERRIDDEN="${ZENOH_ROOT+x}"
ZENOH_BRIDGE_OVERRIDDEN="${ZENOH_BRIDGE+x}"
ZENOH_CONNECT_SCRIPT_OVERRIDDEN="${ZENOH_CONNECT_SCRIPT+x}"

PROJECT_ROOT_CANDIDATE_1="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT_CANDIDATE_2="${HOME}/isaac-projects"
if [[ -f "${PROJECT_ROOT_CANDIDATE_1}/fast_isaac_sim.py" ]]; then
  PROJECT_ROOT_DEFAULT="${PROJECT_ROOT_CANDIDATE_1}"
else
  PROJECT_ROOT_DEFAULT="${PROJECT_ROOT_CANDIDATE_2}"
fi
PROJECT_ROOT="${PROJECT_ROOT:-${PROJECT_ROOT_DEFAULT}}"

FAST_ISAAC_SIM="${FAST_ISAAC_SIM:-${PROJECT_ROOT}/fast_isaac_sim.py}"
HOSPITAL_USD="${HOSPITAL_USD:-${PROJECT_ROOT}/hospital_experiment.usda}"
HOSPITAL_USD_EXP1A="${HOSPITAL_USD_EXP1A:-${PROJECT_ROOT}/hospital_experiment_exp1a.usda}"
HOSPITAL_USD_EXP1B="${HOSPITAL_USD_EXP1B:-${PROJECT_ROOT}/hospital_experiment_exp1b.usda}"
HOSPITAL_USD_EXP1RTX="${HOSPITAL_USD_EXP1RTX:-${PROJECT_ROOT}/hospital_experiment_rtx3_400x300.usda}"
ISAAC_PROJECTS_REPO_URL="${ISAAC_PROJECTS_REPO_URL:-https://github.com/Omotoye/isaac-projects.git}"
ISAAC_PROJECTS_REF="${ISAAC_PROJECTS_REF:-main}"

ZENOH_ROOT_DEFAULT="${HOME}/zenoh_internet_bridge"
ZENOH_ROOT_FALLBACK="${HOME}/zenoh_internet_bridge"
if [[ -n "${ZENOH_ROOT:-}" ]]; then
  ZENOH_ROOT="${ZENOH_ROOT}"
elif [[ -d "${ZENOH_ROOT_DEFAULT}" ]]; then
  ZENOH_ROOT="${ZENOH_ROOT_DEFAULT}"
else
  ZENOH_ROOT="${ZENOH_ROOT_FALLBACK}"
fi
ZENOH_BRIDGE="${ZENOH_BRIDGE:-${ZENOH_ROOT}/zenoh-bridge-ros2dds}"
ZENOH_CONNECT_SCRIPT="${ZENOH_CONNECT_SCRIPT:-${ZENOH_ROOT}/connect_to_cloud.sh}"
ZENOH_BRIDGE_VERSION="${ZENOH_BRIDGE_VERSION:-1.6.2}"

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

usage() {
  local fast_isaac_sim_display hospital_usd_display hospital_usd_exp1a_display hospital_usd_exp1b_display hospital_usd_exp1rtx_display zenoh_root_display zenoh_bridge_display zenoh_connect_display
  fast_isaac_sim_display="$(display_path "${FAST_ISAAC_SIM}")"
  hospital_usd_display="$(display_path "${HOSPITAL_USD}")"
  hospital_usd_exp1a_display="$(display_path "${HOSPITAL_USD_EXP1A}")"
  hospital_usd_exp1b_display="$(display_path "${HOSPITAL_USD_EXP1B}")"
  hospital_usd_exp1rtx_display="$(display_path "${HOSPITAL_USD_EXP1RTX}")"
  zenoh_root_display="$(display_path "${ZENOH_ROOT}")"
  zenoh_bridge_display="$(display_path "${ZENOH_BRIDGE}")"
  zenoh_connect_display="$(display_path "${ZENOH_CONNECT_SCRIPT}")"
  cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  bootstrap           Install/check dependencies and generate local env file.
  start-exp1          Start hospital experiment exp1 in tmux session '${SESSION_NAME}'.
  start-exp1a         Start hospital experiment exp1a in tmux session '${SESSION_NAME}'.
  start-exp1b         Start hospital experiment exp1b in tmux session '${SESSION_NAME}'.
  start-exp1rtx       Start hospital experiment exp1rtx in tmux session '${SESSION_NAME}'.
  stop-exp1           Stop tmux session '${SESSION_NAME}'.
  stop-exp1a          Alias of stop-exp1.
  stop-exp1b          Alias of stop-exp1.
  stop-exp1rtx        Alias of stop-exp1.
  status              Show orchestration status and key runtime info.
  print-local-connect Print local-machine zenoh bridge connect command.

Environment overrides:
  HORUS_TMUX_SESSION  (default: ${SESSION_NAME})
  ZENOH_PORT          (internal listen port, default: ${ZENOH_PORT})
  ZENOH_EXTERNAL_PORT (public/local connect port, default: ${ZENOH_EXTERNAL_PORT})
  ISAAC_PYTHON        (default: ${ISAAC_PYTHON})
  FAST_ISAAC_SIM      (default: ${fast_isaac_sim_display})
  HOSPITAL_USD        (exp1 default: ${hospital_usd_display})
  HOSPITAL_USD_EXP1A  (exp1a default: ${hospital_usd_exp1a_display})
  HOSPITAL_USD_EXP1B  (exp1b default: ${hospital_usd_exp1b_display})
  HOSPITAL_USD_EXP1RTX (exp1rtx default: ${hospital_usd_exp1rtx_display})
  ISAAC_PROJECTS_REPO_URL (default: ${ISAAC_PROJECTS_REPO_URL})
  ISAAC_PROJECTS_REF  (default: ${ISAAC_PROJECTS_REF})
  ZENOH_ROOT          (default: ${zenoh_root_display})
  ZENOH_BRIDGE        (default: ${zenoh_bridge_display})
  ZENOH_CONNECT_SCRIPT(default: ${zenoh_connect_display})
  ZENOH_BRIDGE_VERSION(default: ${ZENOH_BRIDGE_VERSION})
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

display_path() {
  local p="$1"
  if [[ "${p}" == "${HOME}"* ]]; then
    printf '~%s' "${p#${HOME}}"
  else
    printf '%s' "${p}"
  fi
}

resolve_experiment_usd() {
  local profile="$1"
  case "${profile}" in
    exp1)
      printf '%s' "${HOSPITAL_USD}"
      ;;
    exp1a)
      printf '%s' "${HOSPITAL_USD_EXP1A}"
      ;;
    exp1b)
      printf '%s' "${HOSPITAL_USD_EXP1B}"
      ;;
    exp1rtx)
      printf '%s' "${HOSPITAL_USD_EXP1RTX}"
      ;;
    *)
      die "Unsupported experiment profile '${profile}'."
      ;;
  esac
}

ensure_directories() {
  mkdir -p "${CONFIG_DIR}" "${ENV_DIR}" "${LOG_DIR}"
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

get_install_prefix() {
  local -n out_ref="$1"
  out_ref=()
  if [[ "${EUID}" -eq 0 ]]; then
    return
  fi
  if ! have_cmd sudo; then
    die "Package installation requires sudo (or run as root)."
  fi
  if sudo -n true >/dev/null 2>&1; then
    out_ref=(sudo -n)
  elif [[ -t 0 ]]; then
    out_ref=(sudo)
  else
    die "Package installation requires sudo prompt. Re-run bootstrap in an interactive shell."
  fi
}

get_ubuntu_codename() {
  if [[ ! -r /etc/os-release ]]; then
    die "Cannot read /etc/os-release to detect distribution."
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This installer currently supports Ubuntu only. Detected ID='${ID:-unknown}'."
  fi
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  [[ -n "${codename}" ]] || die "Could not detect Ubuntu codename from /etc/os-release."
  printf "%s" "${codename}"
}

ensure_ros_apt_repository() {
  local -a install_prefix=("$@")
  local ubuntu_codename
  ubuntu_codename="$(get_ubuntu_codename)"

  if [[ "${ubuntu_codename}" != "noble" ]]; then
    warn "Detected Ubuntu '${ubuntu_codename}'. ROS 2 Jazzy apt packages are expected on Ubuntu noble (24.04)."
  fi

  if apt-cache show ros-jazzy-ros-base >/dev/null 2>&1; then
    ok "ROS 2 apt repository already available."
    return
  fi

  warn "ROS 2 apt repository not found. Configuring packages.ros.org for Jazzy..."
  "${install_prefix[@]}" apt-get update
  "${install_prefix[@]}" apt-get install -y curl gnupg2 ca-certificates lsb-release

  local keyring="/usr/share/keyrings/ros-archive-keyring.gpg"
  local tmp_key
  tmp_key="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o "${tmp_key}"
  gpg --dearmor < "${tmp_key}" > "${tmp_key}.gpg"
  "${install_prefix[@]}" install -m 644 "${tmp_key}.gpg" "${keyring}"
  rm -f "${tmp_key}" "${tmp_key}.gpg"

  local arch
  arch="$(dpkg --print-architecture)"
  local ros_list_line
  ros_list_line="deb [arch=${arch} signed-by=${keyring}] http://packages.ros.org/ros2/ubuntu ${ubuntu_codename} main"

  local tmp_list
  tmp_list="$(mktemp)"
  printf "%s\n" "${ros_list_line}" > "${tmp_list}"
  "${install_prefix[@]}" install -m 644 "${tmp_list}" /etc/apt/sources.list.d/ros2.list
  rm -f "${tmp_list}"

  "${install_prefix[@]}" apt-get update
  if ! apt-cache show ros-jazzy-ros-base >/dev/null 2>&1; then
    die "ROS apt repository configured but ros-jazzy packages are still unavailable. Check distro codename and apt connectivity."
  fi
  ok "ROS 2 apt repository configured."
}

download_url() {
  local url="$1"
  local out="$2"
  if have_cmd curl; then
    curl -fsSL "${url}" -o "${out}"
  elif have_cmd wget; then
    wget -qO "${out}" "${url}"
  else
    die "Neither curl nor wget is available to download ${url}"
  fi
}

ensure_isaac_projects_checkout() {
  if [[ -f "${FAST_ISAAC_SIM}" && -f "${HOSPITAL_USD}" ]]; then
    return
  fi

  if [[ -n "${PROJECT_ROOT_OVERRIDDEN}" || -n "${FAST_ISAAC_SIM_OVERRIDDEN}" || -n "${HOSPITAL_USD_OVERRIDDEN}" ]]; then
    return
  fi

  if ! have_cmd git; then
    die "isaac-projects is missing and git is not installed. Install git or set FAST_ISAAC_SIM/HOSPITAL_USD."
  fi

  if [[ ! -d "${PROJECT_ROOT}" ]]; then
    warn "isaac-projects not found at $(display_path "${PROJECT_ROOT}"). Cloning ${ISAAC_PROJECTS_REPO_URL}..."
    git clone --depth 1 --branch "${ISAAC_PROJECTS_REF}" "${ISAAC_PROJECTS_REPO_URL}" "${PROJECT_ROOT}"
  elif [[ -d "${PROJECT_ROOT}/.git" ]]; then
    info "Found existing project checkout at $(display_path "${PROJECT_ROOT}")"
  fi
}

ensure_zenoh_bridge_assets() {
  if [[ -x "${ZENOH_BRIDGE}" && -x "${ZENOH_CONNECT_SCRIPT}" ]]; then
    return
  fi

  if [[ -n "${ZENOH_BRIDGE_OVERRIDDEN}" || -n "${ZENOH_CONNECT_SCRIPT_OVERRIDDEN}" || -n "${ZENOH_ROOT_OVERRIDDEN}" ]]; then
    return
  fi

  mkdir -p "${ZENOH_ROOT}"

  if [[ ! -x "${ZENOH_BRIDGE}" ]]; then
    local arch
    arch="$(dpkg --print-architecture)"
    local zenoh_arch
    case "${arch}" in
      amd64) zenoh_arch="x86_64" ;;
      arm64) zenoh_arch="aarch64" ;;
      *) die "Unsupported architecture '${arch}' for zenoh bridge auto-download." ;;
    esac

    local zip_name
    zip_name="zenoh-plugin-ros2dds-${ZENOH_BRIDGE_VERSION}-${zenoh_arch}-unknown-linux-gnu-standalone.zip"
    local zip_url
    zip_url="https://github.com/eclipse-zenoh/zenoh-plugin-ros2dds/releases/download/${ZENOH_BRIDGE_VERSION}/${zip_name}"
    local zip_path
    zip_path="${ZENOH_ROOT}/${zip_name}"

    warn "zenoh bridge binary not found. Downloading ${zip_name}..."
    download_url "${zip_url}" "${zip_path}"
    unzip -o "${zip_path}" -d "${ZENOH_ROOT}" >/dev/null
    chmod +x "${ZENOH_ROOT}/zenoh-bridge-ros2dds"
    ok "Installed zenoh bridge to $(display_path "${ZENOH_ROOT}/zenoh-bridge-ros2dds")"
  fi

  if [[ ! -x "${ZENOH_CONNECT_SCRIPT}" ]]; then
    cat > "${ZENOH_CONNECT_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_PATH="${SCRIPT_DIR}/zenoh-bridge-ros2dds"
PORT="${2:-10000}"
if [[ -z "${1:-}" ]]; then
  echo "Usage: $0 <CLOUD_IP> [PORT]"
  exit 1
fi
"${BRIDGE_PATH}" --no-multicast-scouting -e "tcp/${1}:${PORT}" client
EOF
    chmod +x "${ZENOH_CONNECT_SCRIPT}"
    ok "Created local connect helper at $(display_path "${ZENOH_CONNECT_SCRIPT}")"
  fi
}

ensure_topics_files() {
  require_file "${TOPICS_BASE_FILE}" "topics base file"
  if [[ ! -f "${TOPICS_EXTRA_FILE}" ]]; then
    cat > "${TOPICS_EXTRA_FILE}" <<'EOF'
# Add one regex topic per line.
# Example:
# ^/carter[123]/map$
EOF
  fi
}

write_env_file() {
  require_file "${CYCLONEDDS_XML}" "CycloneDDS config"

  cat > "${ENV_FILE}" <<EOF
# Generated by horus_experiment.sh bootstrap
# shellcheck shell=bash
source ${ROS_SETUP_FILE}
export ROS_DOMAIN_ID="\${ROS_DOMAIN_ID:-5}"
export RMW_IMPLEMENTATION="rmw_cyclonedds_cpp"
export ROS_LOCALHOST_ONLY="0"
export CYCLONEDDS_URI="file://${CYCLONEDDS_XML}"
EOF
  ok "Wrote ${ENV_FILE}"
}

install_dependencies_if_missing() {
  local packages=(
    git
    unzip
    ros-jazzy-ros-base
    ros-jazzy-rmw-cyclonedds-cpp
    ros-jazzy-image-transport
    ros-jazzy-compressed-image-transport
    tmux
  )
  local missing=()
  local pkg

  for pkg in "${packages[@]}"; do
    if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
      missing+=("${pkg}")
    fi
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    ok "Required apt packages are already installed."
    return
  fi

  local -a install_prefix=()
  get_install_prefix install_prefix
  ensure_ros_apt_repository "${install_prefix[@]}"

  warn "Installing missing packages: ${missing[*]}"
  "${install_prefix[@]}" apt-get update
  if ! "${install_prefix[@]}" apt-get install -y "${missing[@]}"; then
    die "Failed to install dependencies: ${missing[*]}. Verify ROS apt repo and Ubuntu version."
  fi
  ok "Installed missing packages."
}

validate_runtime_paths() {
  require_file "${ROS_SETUP_FILE}" "ROS Jazzy setup file"
  require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
  if [[ ! -f "${FAST_ISAAC_SIM}" ]]; then
    die "Missing fast_isaac_sim.py at ${FAST_ISAAC_SIM}. Clone isaac-projects to ~/isaac-projects or set FAST_ISAAC_SIM/PROJECT_ROOT."
  fi
  if [[ ! -x "${ZENOH_BRIDGE}" ]]; then
    die "Missing zenoh bridge at ${ZENOH_BRIDGE}. Clone/install ~/zenoh_internet_bridge or set ZENOH_BRIDGE."
  fi
  require_file "${GEN_ZENOH_CONFIG_SCRIPT}" "Zenoh config generator"
  if [[ ! -x "${GEN_ZENOH_CONFIG_SCRIPT}" ]]; then
    chmod +x "${GEN_ZENOH_CONFIG_SCRIPT}"
  fi
  if [[ ! -x "${ZENOH_CONNECT_SCRIPT}" ]]; then
    warn "Local connect script not found or not executable at ${ZENOH_CONNECT_SCRIPT}"
  fi
}

validate_experiment_profile() {
  local profile="$1"
  local usd_path
  usd_path="$(resolve_experiment_usd "${profile}")"
  if [[ ! -f "${usd_path}" ]]; then
    die "Missing ${profile} USD at ${usd_path}. Set HOSPITAL_USD/HOSPITAL_USD_EXP1A/HOSPITAL_USD_EXP1B/HOSPITAL_USD_EXP1RTX or update isaac-projects."
  fi
}

run_zenoh_config_generator() {
  ensure_topics_files
  "${GEN_ZENOH_CONFIG_SCRIPT}" "${TOPICS_BASE_FILE}" "${TOPICS_EXTRA_FILE}" "${ZENOH_CONFIG_FILE}"
}

bootstrap() {
  info "Bootstrapping Horus cloud setup for experiment 1..."
  ensure_directories
  install_dependencies_if_missing
  ensure_isaac_projects_checkout
  ensure_zenoh_bridge_assets
  validate_runtime_paths
  write_env_file
  run_zenoh_config_generator

  ok "Bootstrap complete."
  printf "\nNext step:\n"
  printf "  %s start-exp1\n" "$0"
  printf "  %s start-exp1a\n" "$0"
  printf "  %s start-exp1b\n" "$0"
  printf "  %s start-exp1rtx\n" "$0"
}

tmux_has_session() {
  tmux has-session -t "${SESSION_NAME}" >/dev/null 2>&1
}

start_experiment() {
  local profile="$1"
  local usd_path
  usd_path="$(resolve_experiment_usd "${profile}")"
  info "Starting ${profile} in tmux session '${SESSION_NAME}'..."
  local script_path="${SCRIPT_DIR}/horus_experiment.sh"
  ensure_directories
  validate_runtime_paths
  validate_experiment_profile "${profile}"
  require_file "${ENV_FILE}" "cloud ROS env file (run bootstrap first)"
  require_file "${CYCLONEDDS_XML}" "CycloneDDS config"

  have_cmd tmux || die "tmux is not installed. Run bootstrap first."
  run_zenoh_config_generator

  if tmux_has_session; then
    die "tmux session '${SESSION_NAME}' already exists. Use '$0 status' or '$0 stop-exp1' first."
  fi

  tmux new-session -d -s "${SESSION_NAME}" -n bridge "${script_path} _run-bridge ${ZENOH_PORT}"
  tmux setw -t "${SESSION_NAME}" remain-on-exit on
  tmux new-window -t "${SESSION_NAME}:" -n compress "${script_path} _run-compress ${profile}"
  tmux new-window -t "${SESSION_NAME}:" -n isaac "${script_path} _run-isaac ${profile}"
  tmux select-window -t "${SESSION_NAME}:isaac"

  ok "tmux session '${SESSION_NAME}' started."
  printf "Profile: %s\n" "${profile}"
  printf "USD: %s\n\n" "$(display_path "${usd_path}")"
  printf "\nAttach to session:\n"
  if [[ -n "${TMUX:-}" ]]; then
    printf "  tmux switch-client -t %s\n\n" "${SESSION_NAME}"
  else
    printf "  tmux attach -t %s\n\n" "${SESSION_NAME}"
  fi

  printf "ROS CLI in this shell:\n"
  printf "  source /opt/ros/jazzy/setup.bash\n"
  printf "  source %s\n\n" "$(display_path "${ENV_FILE}")"

  print_local_connect
}

start_exp1() {
  start_experiment exp1
}

start_exp1a() {
  start_experiment exp1a
}

start_exp1b() {
  start_experiment exp1b
}

start_exp1rtx() {
  start_experiment exp1rtx
}

stop_exp1() {
  info "Stopping session '${SESSION_NAME}'..."
  if tmux_has_session; then
    tmux kill-session -t "${SESSION_NAME}"
    ok "Session '${SESSION_NAME}' stopped."
  else
    warn "Session '${SESSION_NAME}' is not running."
  fi
}

status() {
  info "Horus experiment status"
  printf "  project_root: %s\n" "$(display_path "${PROJECT_ROOT}")"
  printf "  env file: %s\n" "$(display_path "${ENV_FILE}")"
  printf "  zenoh config: %s\n" "$(display_path "${ZENOH_CONFIG_FILE}")"
  printf "  zenoh bridge: %s\n" "$(display_path "${ZENOH_BRIDGE}")"
  printf "  isaac python: %s\n" "$(display_path "${ISAAC_PYTHON}")"
  printf "  launcher: %s\n" "$(display_path "${FAST_ISAAC_SIM}")"
  printf "  usd (exp1): %s\n" "$(display_path "${HOSPITAL_USD}")"
  printf "  usd (exp1a): %s\n" "$(display_path "${HOSPITAL_USD_EXP1A}")"
  printf "  usd (exp1b): %s\n" "$(display_path "${HOSPITAL_USD_EXP1B}")"
  printf "  usd (exp1rtx): %s\n" "$(display_path "${HOSPITAL_USD_EXP1RTX}")"
  printf "  session: %s\n" "${SESSION_NAME}"
  printf "  zenoh listen port (cloud internal): %s\n" "${ZENOH_PORT}"
  printf "  zenoh external port (local connect): %s\n" "${ZENOH_EXTERNAL_PORT}"

  if [[ -f "${ENV_FILE}" ]]; then
    (
      set +u
      source "${ENV_FILE}"
      printf "  ros_domain_id (effective default): %s\n" "${ROS_DOMAIN_ID:-5}"
      printf "  rmw_implementation: %s\n" "${RMW_IMPLEMENTATION:-unset}"
      printf "  ros_localhost_only: %s\n" "${ROS_LOCALHOST_ONLY:-unset}"
      printf "  cyclonedds_uri: %s\n" "${CYCLONEDDS_URI:-unset}"
    )
  else
    warn "Env file missing. Run: $0 bootstrap"
  fi

  if tmux_has_session; then
    ok "tmux session '${SESSION_NAME}' is running."
    tmux list-windows -t "${SESSION_NAME}" -F "  window=#{window_name} active=#{window_active} panes=#{window_panes}"
    tmux list-panes -a -t "${SESSION_NAME}" -F "  pane=#{pane_id} window=#{window_name} pid=#{pane_pid} cmd=#{pane_current_command}"
  else
    warn "tmux session '${SESSION_NAME}' is not running."
  fi
}

print_local_connect() {
  local cloud_ip=""
  local connect_script_display
  connect_script_display="$(display_path "${ZENOH_CONNECT_SCRIPT}")"
  if have_cmd curl; then
    cloud_ip="$(curl -fsS --max-time 2 ifconfig.me || true)"
  fi

  printf "\nLocal machine connect command:\n"
  if [[ -n "${cloud_ip}" ]]; then
    printf "  %s %s %s\n" "${connect_script_display}" "${cloud_ip}" "${ZENOH_EXTERNAL_PORT}"
    printf "  (Detected cloud public IP: %s)\n" "${cloud_ip}"
  else
    printf "  %s <CLOUD_IP> %s\n" "${connect_script_display}" "${ZENOH_EXTERNAL_PORT}"
  fi
  if [[ "${ZENOH_EXTERNAL_PORT}" != "${ZENOH_PORT}" ]]; then
    printf "  (Cloud bridge listens on internal %s; use external mapped port %s for local connect.)\n" "${ZENOH_PORT}" "${ZENOH_EXTERNAL_PORT}"
  fi
  printf "\n"
}

run_bridge() {
  local port="${1:-${ZENOH_PORT}}"
  mkdir -p "${LOG_DIR}"
  require_file "${ENV_FILE}" "cloud ROS env file"
  require_file "${ZENOH_CONFIG_FILE}" "zenoh config file"
  require_executable "${ZENOH_BRIDGE}" "zenoh bridge"

  set +u
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set -u

  info "Starting zenoh bridge on tcp/0.0.0.0:${port}"
  info "Using config: ${ZENOH_CONFIG_FILE}"
  exec "${ZENOH_BRIDGE}" -c "${ZENOH_CONFIG_FILE}" -l "tcp/0.0.0.0:${port}"
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
  local profile="${1:-exp1}"
  local -a robots=()
  require_file "${ENV_FILE}" "cloud ROS env file"
  set +u
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set -u

  have_cmd ros2 || die "ros2 command not found after sourcing ${ENV_FILE}"

  case "${profile}" in
    exp1)
      robots=(carter1 carter2 carter3)
      ;;
    exp1rtx)
      robots=(carter1 carter2 carter3)
      ;;
    exp1a|exp1b)
      robots=(carter1)
      ;;
    *)
      die "Unknown profile '${profile}' for compression relays."
      ;;
  esac

  trap 'warn "Stopping image compression relays..."; kill 0 >/dev/null 2>&1 || true' INT TERM

  local robot
  for robot in "${robots[@]}"; do
    start_one_compression_relay "${robot}" &
  done

  wait
}

run_isaac() {
  local profile="${1:-exp1}"
  local usd_path
  local -a extra_args=()
  usd_path="$(resolve_experiment_usd "${profile}")"

  require_file "${ENV_FILE}" "cloud ROS env file"
  require_executable "${ISAAC_PYTHON}" "Isaac Sim python.sh"
  require_file "${FAST_ISAAC_SIM}" "fast_isaac_sim.py"
  require_file "${usd_path}" "${profile} usd"

  set +u
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set -u

  if [[ "${profile}" == "exp1rtx" ]]; then
    extra_args+=(--disable-physx-laserscan)
  fi

  info "Starting Isaac Sim hospital experiment (${profile})..."
  info "USD path: ${usd_path}"
  exec "${ISAAC_PYTHON}" "${FAST_ISAAC_SIM}" \
    --headless \
    --render-headless \
    --render-every 2 \
    --aa-mode 3 \
    --dlss-exec-mode 0 \
    "${extra_args[@]}" \
    --usd-path "${usd_path}" \
    --no-ground-plane \
    --physics-step 0.0166667 \
    --target-sim-hz 60 \
    --max-steps -1
}

main() {
  local cmd="${1:-}"
  case "${cmd}" in
    bootstrap)
      bootstrap
      ;;
    start-exp1)
      start_exp1
      ;;
    start-exp1a)
      start_exp1a
      ;;
    start-exp1b)
      start_exp1b
      ;;
    start-exp1rtx)
      start_exp1rtx
      ;;
    stop-exp1)
      stop_exp1
      ;;
    stop-exp1a|stop-exp1b|stop-exp1rtx)
      stop_exp1
      ;;
    status)
      status
      ;;
    print-local-connect)
      print_local_connect
      ;;
    _run-bridge)
      shift
      run_bridge "${1:-${ZENOH_PORT}}"
      ;;
    _run-compress)
      shift
      run_compress "${1:-exp1}"
      ;;
    _run-isaac)
      shift
      run_isaac "${1:-exp1}"
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
