#!/usr/bin/env bash

# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# Terminal Colors and Styling
# ==============================================================================
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
  COLOR_RESET='\033[0m'
  COLOR_BOLD='\033[1m'
  COLOR_DIM='\033[2m'
  COLOR_RED='\033[0;31m'
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[0;33m'
  COLOR_BLUE='\033[0;34m'
  COLOR_MAGENTA='\033[0;35m'
  COLOR_CYAN='\033[0;36m'
  COLOR_WHITE='\033[1;37m'
  COLOR_BG_BLUE='\033[44m'
else
  COLOR_RESET=''
  COLOR_BOLD=''
  COLOR_DIM=''
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_MAGENTA=''
  COLOR_CYAN=''
  COLOR_WHITE=''
  COLOR_BG_BLUE=''
fi

log_info() {
  echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $*"
}

log_step() {
  echo -e "${COLOR_CYAN}${COLOR_BOLD}==>${COLOR_RESET} ${COLOR_BOLD}$*${COLOR_RESET}"
}

log_success() {
  echo -e "${COLOR_GREEN}${COLOR_BOLD}[SUCCESS]${COLOR_RESET} $*"
}

log_warn() {
  echo -e "${COLOR_YELLOW}${COLOR_BOLD}[WARN]${COLOR_RESET} $*" >&2
}

log_error() {
  echo -e "${COLOR_RED}${COLOR_BOLD}[ERROR]${COLOR_RESET} $*" >&2
}

# ==============================================================================
# Global Configuration Variables & Defaults
# ==============================================================================
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-false}"

PROJECT_ID="${PROJECT_ID:-}"
PROJECT_NUMBER="${PROJECT_NUMBER:-}"
GCE_REGION="${GCE_REGION:-us-central1}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-us-central1-c}"
CLUSTER_NAME="${CLUSTER_NAME:-substrate-poc}"
CLUSTER_VERSION="${CLUSTER_VERSION:-}"
GVISOR_NODE_MACHINE_TYPE="${GVISOR_NODE_MACHINE_TYPE:-c3-standard-4}"
NETWORK="${NETWORK:-default}"
SUBNETWORK="${SUBNETWORK:-default}"
ENABLE_DATAPLANE_V2="${ENABLE_DATAPLANE_V2:-true}"

BUCKET_NAME="${BUCKET_NAME:-}"
GCR_REPO="${GCR_REPO:-${KO_DOCKER_REPO:-}}"
KO_DEFAULTPLATFORMS="${KO_DEFAULTPLATFORMS:-linux/amd64}"

STORE_BACKEND="${STORE_BACKEND:-redis}"
ATENET_ROUTER="${ATENET_ROUTER:-envoy}"
DEPLOY_DEMO="${DEPLOY_DEMO:-counter}" # counter | none

SUBSTRATE_DIR="${SUBSTRATE_DIR:-}"
SUBSTRATE_REPO="${SUBSTRATE_REPO:-https://github.com/agent-substrate/substrate.git}"
SUBSTRATE_REPO_FALLBACK="https://github.com/rakyll/substrate.git"
SUBSTRATE_BRANCH="${SUBSTRATE_BRANCH:-main}"

# ==============================================================================
# Usage & Help
# ==============================================================================
usage() {
  cat << EOF
Substrate GCP Installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/rakyll/install-substrate.sh/main/install-substrate.sh | bash
  # Or run directly:
  ./install-substrate.sh [OPTIONS]

Options:
  --project-id ID            GCP Project ID
  --project-number NUM       GCP Project Number (auto-detected if omitted)
  --region REGION            GCP Region for regional resources (default: us-central1)
  --location ZONE            GCP Zone / Cluster Location (default: us-central1-c)
  --cluster-name NAME        GKE Cluster Name (default: substrate-poc)
  --cluster-version VER      GKE Cluster Kubernetes Version (default: GKE default)
  --machine-type TYPE        gVisor Node Pool Machine Type (default: c3-standard-4)
  --network NET              VPC Network Name (default: default)
  --subnetwork SUBNET        VPC Subnetwork Name (default: default)
  --snapshots-bucket NAME    GCS Bucket Name for snapshots (default: substrate-snapshots-\$PROJECT_ID)
  --gcr-repo REPO            Container registry for images (default: gcr.io/\$PROJECT_ID/ate-images)
  --store-backend BACKEND    Storage backend: 'redis' (Valkey) or 'postgres' (default: redis)
  --router ROUTER            Dataplane router: 'envoy' or 'agentgateway' (default: envoy)
  --demo DEMO                Deploy Counter demo application: 'counter' or 'none' (default: counter)
  --substrate-dir DIR        Path to local Substrate repository (cloned if omitted)
  --substrate-repo URL       Git URL for Substrate repository (default: https://github.com/agent-substrate/substrate.git)
  --substrate-branch BRANCH  Git branch to clone (default: main)
  --skip-bootstrap           Skip GCP infrastructure provisioning (use if GCP cluster already exists)
  -y, --yes, --non-interactive
                             Run non-interactively, accepting all defaults/flags without prompting
  --dry-run                  Preview planned configuration without making changes
  -h, --help                 Display this help message

Examples:
  # Interactive wizard (step-by-step guidance):
  ./install-substrate.sh

  # Non-interactive automated install with a specific GCP project:
  ./install-substrate.sh --project-id=my-project-123 -y

EOF
  exit 0
}

# ==============================================================================
# CLI Argument Parsing
# ==============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-id=*) PROJECT_ID="${1#*=}" ;;
      --project-id) shift; PROJECT_ID="${1:-}" ;;
      --project-number=*) PROJECT_NUMBER="${1#*=}" ;;
      --project-number) shift; PROJECT_NUMBER="${1:-}" ;;
      --region=*) GCE_REGION="${1#*=}" ;;
      --region) shift; GCE_REGION="${1:-}" ;;
      --location=*) CLUSTER_LOCATION="${1#*=}" ;;
      --location) shift; CLUSTER_LOCATION="${1:-}" ;;
      --cluster-name=*) CLUSTER_NAME="${1#*=}" ;;
      --cluster-name) shift; CLUSTER_NAME="${1:-}" ;;
      --cluster-version=*) CLUSTER_VERSION="${1#*=}" ;;
      --cluster-version) shift; CLUSTER_VERSION="${1:-}" ;;
      --machine-type=*) GVISOR_NODE_MACHINE_TYPE="${1#*=}" ;;
      --machine-type) shift; GVISOR_NODE_MACHINE_TYPE="${1:-}" ;;
      --network=*) NETWORK="${1#*=}" ;;
      --network) shift; NETWORK="${1:-}" ;;
      --subnetwork=*) SUBNETWORK="${1#*=}" ;;
      --subnetwork) shift; SUBNETWORK="${1:-}" ;;
      --snapshots-bucket=*|--bucket-name=*) BUCKET_NAME="${1#*=}" ;;
      --snapshots-bucket|--bucket-name) shift; BUCKET_NAME="${1:-}" ;;
      --gcr-repo=*|--ko-docker-repo=*) GCR_REPO="${1#*=}" ;;
      --gcr-repo|--ko-docker-repo) shift; GCR_REPO="${1:-}" ;;
      --store-backend=*) STORE_BACKEND="${1#*=}" ;;
      --store-backend) shift; STORE_BACKEND="${1:-}" ;;
      --router=*|--atenet-router=*) ATENET_ROUTER="${1#*=}" ;;
      --router|--atenet-router) shift; ATENET_ROUTER="${1:-}" ;;
      --demo=*) DEPLOY_DEMO="${1#*=}" ;;
      --demo) shift; DEPLOY_DEMO="${1:-}" ;;
      --substrate-dir=*) SUBSTRATE_DIR="${1#*=}" ;;
      --substrate-dir) shift; SUBSTRATE_DIR="${1:-}" ;;
      --substrate-repo=*) SUBSTRATE_REPO="${1#*=}" ;;
      --substrate-repo) shift; SUBSTRATE_REPO="${1:-}" ;;
      --substrate-branch=*) SUBSTRATE_BRANCH="${1#*=}" ;;
      --substrate-branch) shift; SUBSTRATE_BRANCH="${1:-}" ;;
      --skip-bootstrap) SKIP_BOOTSTRAP=true ;;
      -y|--yes|--non-interactive) NON_INTERACTIVE=true ;;
      --dry-run) DRY_RUN=true ;;
      -h|--help) usage ;;
      *)
        log_error "Unknown flag: $1"
        usage
        ;;
    esac
    shift
  done
}

# ==============================================================================
# Interactive Input Helpers (Supports Curl Pipe & Dev TTY)
# ==============================================================================
prompt_input() {
  local prompt_msg="$1"
  local default_val="${2:-}"
  local var_name="$3"
  local user_val=""

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    local current_val
    current_val="$(eval echo "\${${var_name}:-}")"
    if [[ -z "${current_val}" ]]; then
      eval "${var_name}=\"${default_val}\""
    fi
    return 0
  fi

  if [[ -n "${default_val}" ]]; then
    printf "${COLOR_BOLD}%s${COLOR_RESET} [default: ${COLOR_CYAN}%s${COLOR_RESET}]: " "${prompt_msg}" "${default_val}" >&2
  else
    printf "${COLOR_BOLD}%s${COLOR_RESET}: " "${prompt_msg}" >&2
  fi

  if [[ -e /dev/tty ]]; then
    read -r user_val </dev/tty || true
  else
    read -r user_val || true
  fi

  user_val="$(echo "${user_val}" | xargs)"

  if [[ -z "${user_val}" ]]; then
    user_val="${default_val}"
  fi

  eval "${var_name}=\"${user_val}\""
}

prompt_yes_no() {
  local prompt_msg="$1"
  local default_yes="${2:-true}" # true -> [Y/n], false -> [y/N]
  local var_name="$3"
  local choice=""

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    if [[ "${default_yes}" == "true" ]]; then
      eval "${var_name}=true"
    else
      eval "${var_name}=false"
    fi
    return 0
  fi

  local default_str="Y/n"
  if [[ "${default_yes}" != "true" ]]; then
    default_str="y/N"
  fi

  while true; do
    printf "${COLOR_BOLD}%s${COLOR_RESET} [%s]: " "${prompt_msg}" "${default_str}" >&2
    if [[ -e /dev/tty ]]; then
      read -r choice </dev/tty || true
    else
      read -r choice || true
    fi

    choice="$(echo "${choice}" | tr '[:upper:]' '[:lower:]' | xargs)"
    if [[ -z "${choice}" ]]; then
      if [[ "${default_yes}" == "true" ]]; then
        eval "${var_name}=true"
      else
        eval "${var_name}=false"
      fi
      break
    elif [[ "${choice}" =~ ^(y|yes)$ ]]; then
      eval "${var_name}=true"
      break
    elif [[ "${choice}" =~ ^(n|no)$ ]]; then
      eval "${var_name}=false"
      break
    else
      echo "Please enter 'y' or 'n'." >&2
    fi
  done
}

prompt_choice() {
  local prompt_msg="$1"
  shift
  local default_opt="$1"
  shift
  local var_name="$1"
  shift
  local options=("$@")

  if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    local current_val
    current_val="$(eval echo "\${${var_name}:-}")"
    if [[ -z "${current_val}" ]]; then
      eval "${var_name}=\"${default_opt}\""
    fi
    return 0
  fi

  echo -e "\n${COLOR_BOLD}${prompt_msg}${COLOR_RESET}" >&2
  local i=1
  local default_num=1
  for opt in "${options[@]}"; do
    local opt_val="${opt%%:*}"
    local opt_desc="${opt#*:}"
    if [[ "${opt_val}" == "${default_opt}" ]]; then
      default_num="${i}"
      printf "  ${COLOR_CYAN}%2d)${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET} - %s ${COLOR_YELLOW}(default)${COLOR_RESET}\n" "${i}" "${opt_val}" "${opt_desc}" >&2
    else
      printf "  ${COLOR_CYAN}%2d)${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET} - %s\n" "${i}" "${opt_val}" "${opt_desc}" >&2
    fi
    ((i++))
  done

  local choice_idx=""
  while true; do
    printf "${COLOR_BOLD}Select an option [1-%d]${COLOR_RESET} [default: ${COLOR_CYAN}%d${COLOR_RESET}]: " "${#options[@]}" "${default_num}" >&2
    if [[ -e /dev/tty ]]; then
      read -r choice_idx </dev/tty || true
    else
      read -r choice_idx || true
    fi
    choice_idx="$(echo "${choice_idx}" | xargs)"

    if [[ -z "${choice_idx}" ]]; then
      choice_idx="${default_num}"
    fi

    if [[ "${choice_idx}" =~ ^[0-9]+$ ]] && ((choice_idx >= 1 && choice_idx <= ${#options[@]})); then
      local selected="${options[$((choice_idx - 1))]}"
      local selected_val="${selected%%:*}"
      eval "${var_name}=\"${selected_val}\""
      break
    else
      echo "Invalid selection. Please choose a number between 1 and ${#options[@]}." >&2
    fi
  done
}

# ==============================================================================
# Step 1: Tool and Prerequisite Verification
# ==============================================================================
check_prerequisites() {
  log_step "Checking prerequisites and tools..."

  local missing_tools=()

  # Check gcloud
  if command -v gcloud >/dev/null 2>&1; then
    local gcloud_ver
    gcloud_ver="$(gcloud version 2>/dev/null | head -n1 || echo "installed")"
    log_info "Google Cloud SDK: ${COLOR_GREEN}${gcloud_ver}${COLOR_RESET}"
  else
    missing_tools+=("gcloud (Google Cloud SDK: https://cloud.google.com/sdk/docs/install)")
  fi

  # Check kubectl
  if command -v kubectl >/dev/null 2>&1; then
    local kubectl_ver
    kubectl_ver="$(kubectl version --client -o yaml 2>/dev/null | grep gitVersion | head -n1 | awk '{print $2}' || echo "installed")"
    log_info "kubectl: ${COLOR_GREEN}${kubectl_ver}${COLOR_RESET}"
  else
    missing_tools+=("kubectl (Kubernetes CLI: https://kubernetes.io/docs/tasks/tools/)")
  fi

  # Check go
  if command -v go >/dev/null 2>&1; then
    local go_ver
    go_ver="$(go version | awk '{print $3}')"
    log_info "Go compiler: ${COLOR_GREEN}${go_ver}${COLOR_RESET}"
  else
    missing_tools+=("go (Go 1.24+: https://go.dev/doc/install)")
  fi

  # Check git
  if command -v git >/dev/null 2>&1; then
    local git_ver
    git_ver="$(git --version | awk '{print $3}')"
    log_info "Git: ${COLOR_GREEN}${git_ver}${COLOR_RESET}"
  else
    missing_tools+=("git (https://git-scm.com/)")
  fi

  # Check docker (optional/recommended)
  if command -v docker >/dev/null 2>&1; then
    log_info "Docker: ${COLOR_GREEN}installed${COLOR_RESET}"
  else
    log_warn "Docker is not detected in PATH. Substrate toolchain uses ko for container builds, but docker is recommended for local workflows."
  fi

  if [[ ${#missing_tools[@]} -gt 0 ]]; then
    log_error "Missing required tools:"
    for tool in "${missing_tools[@]}"; do
      echo "  - ${tool}" >&2
    done
    echo ""
    log_error "Please install the missing tools above and rerun this installer."
    exit 1
  fi

  # Verify gcloud authentication
  log_info "Verifying Google Cloud authentication..."
  local active_account=""
  active_account="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1 || true)"
  if [[ -z "${active_account}" ]]; then
    log_warn "No active Google Cloud account detected."
    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
      log_error "Cannot authenticate gcloud in non-interactive mode. Please run 'gcloud auth login' first."
      exit 1
    fi
    log_info "Initiating gcloud authentication..."
    gcloud auth login
    active_account="$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1 || true)"
  fi
  log_success "Authenticated as: ${COLOR_WHITE}${active_account}${COLOR_RESET}"
}

# ==============================================================================
# Step 2: Interactive Configuration Wizard
# ==============================================================================
configure_interactive() {
  log_step "Configuring GCP Project & Substrate Settings"

  # --- 1. Project ID ---
  local active_project=""
  active_project="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -z "${PROJECT_ID}" ]]; then
    if [[ -n "${active_project}" ]]; then
      prompt_input "Enter GCP Project ID" "${active_project}" PROJECT_ID
    else
      prompt_input "Enter GCP Project ID" "" PROJECT_ID
    fi
  fi

  while [[ -z "${PROJECT_ID}" ]]; do
    log_error "Project ID cannot be empty."
    prompt_input "Enter GCP Project ID" "" PROJECT_ID
  done

  # Validate/Ensure GCP Project
  log_info "Checking GCP project '${PROJECT_ID}'..."
  local project_exists=true
  if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
    project_exists=false
  fi

  if [[ "${project_exists}" == "false" ]]; then
    log_warn "Project '${PROJECT_ID}' does not exist or you do not have permission to describe it."
    local create_proj=true
    prompt_yes_no "Would you like to create new GCP project '${PROJECT_ID}' now?" true create_proj
    if [[ "${create_proj}" == "true" ]]; then
      log_info "Creating project '${PROJECT_ID}'..."
      gcloud projects create "${PROJECT_ID}" --name="${PROJECT_ID}"

      # Check billing account
      local billing_account=""
      billing_account="$(gcloud billing accounts list --filter=open=true --format="value(name)" 2>/dev/null | head -n1 || true)"
      if [[ -n "${billing_account}" ]]; then
        local link_billing=true
        prompt_yes_no "Link billing account '${billing_account}' to '${PROJECT_ID}'?" true link_billing
        if [[ "${link_billing}" == "true" ]]; then
          gcloud billing projects link "${PROJECT_ID}" --billing-account="${billing_account}"
          log_success "Billing account linked."
        fi
      else
        log_warn "No open billing account found automatically. Ensure billing is enabled for '${PROJECT_ID}' before provisioning GKE."
      fi
    else
      log_error "Cannot proceed without a valid GCP Project."
      exit 1
    fi
  fi

  # Resolve Project Number
  if [[ -z "${PROJECT_NUMBER}" ]]; then
    log_info "Resolving project number for '${PROJECT_ID}'..."
    PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || true)"
  fi

  if [[ -z "${PROJECT_NUMBER}" ]]; then
    prompt_input "Enter GCP Project Number" "" PROJECT_NUMBER
  fi
  log_info "Project Number: ${COLOR_WHITE}${PROJECT_NUMBER}${COLOR_RESET}"

  # --- 2. Region & Zone ---
  if [[ "${NON_INTERACTIVE}" != "true" ]]; then
    prompt_input "Enter GCP Region" "${GCE_REGION}" GCE_REGION
    prompt_input "Enter GKE Cluster Location / Zone" "${GCE_REGION}-c" CLUSTER_LOCATION
  else
    if [[ -z "${CLUSTER_LOCATION}" ]]; then
      CLUSTER_LOCATION="${GCE_REGION}-c"
    fi
  fi

  # --- 3. GKE Cluster Settings ---
  if [[ "${NON_INTERACTIVE}" != "true" ]]; then
    prompt_input "Enter GKE Cluster Name" "${CLUSTER_NAME}" CLUSTER_NAME
    prompt_input "Enter gVisor Node Machine Type (c3-standard-4 recommended for sandboxing)" "${GVISOR_NODE_MACHINE_TYPE}" GVISOR_NODE_MACHINE_TYPE
    prompt_input "Enter VPC Network Name" "${NETWORK}" NETWORK
    prompt_input "Enter VPC Subnetwork Name" "${SUBNETWORK}" SUBNETWORK
  fi

  # --- 4. Storage & Container Registry ---
  local default_bucket="substrate-snapshots-${PROJECT_ID}"
  if [[ -z "${BUCKET_NAME}" ]]; then
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
      prompt_input "Enter GCS Snapshot Bucket Name" "${default_bucket}" BUCKET_NAME
    else
      BUCKET_NAME="${default_bucket}"
    fi
  fi

  local default_repo="gcr.io/${PROJECT_ID}/ate-images"
  if [[ -z "${GCR_REPO}" ]]; then
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
      prompt_input "Enter Container Registry for image publishing (--gcr-repo)" "${default_repo}" GCR_REPO
    else
      GCR_REPO="${default_repo}"
    fi
  fi

  # --- 5. Substrate Components & Store Backend ---
  if [[ "${NON_INTERACTIVE}" != "true" ]]; then
    prompt_choice "Select State Store Backend:" "${STORE_BACKEND}" STORE_BACKEND \
      "redis:Valkey / Redis cluster (recommended default for actor state & mailbox storage)" \
      "postgres:PostgreSQL stateful store"

    prompt_choice "Select Network Router Dataplane:" "${ATENET_ROUTER}" ATENET_ROUTER \
      "envoy:Envoy proxy router (default)" \
      "agentgateway:AgentGateway router"

    local install_demo=true
    if [[ "${DEPLOY_DEMO}" == "none" || "${DEPLOY_DEMO}" == "false" ]]; then
      install_demo=false
    fi
    prompt_yes_no "Deploy the sample Counter demo application after installation?" "${install_demo}" install_demo
    if [[ "${install_demo}" == "true" ]]; then
      DEPLOY_DEMO="counter"
    else
      DEPLOY_DEMO="none"
    fi
  fi

  # --- 6. Locate or Clone Substrate Source ---
  locate_or_clone_substrate
}

# ==============================================================================
# Locate or Clone Substrate Repository
# ==============================================================================
locate_or_clone_substrate() {
  log_step "Locating Substrate repository..."

  local found_dir=""
  local candidates=()

  if [[ -n "${SUBSTRATE_DIR}" && -d "${SUBSTRATE_DIR}" ]]; then
    candidates+=("${SUBSTRATE_DIR}")
  fi
  if [[ -d "./hack" && -f "./hack/install-ate.sh" ]]; then
    candidates+=("$(pwd)")
  fi
  if [[ -d "${HOME}/substrate" && -f "${HOME}/substrate/hack/install-ate.sh" ]]; then
    candidates+=("${HOME}/substrate")
  fi

  for dir in "${candidates[@]}"; do
    if [[ -f "${dir}/hack/install-ate.sh" && -d "${dir}/tools/setup-gcp" ]]; then
      found_dir="${dir}"
      break
    fi
  done

  if [[ -n "${found_dir}" ]]; then
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
      local use_existing=true
      prompt_yes_no "Found Substrate repository at '${found_dir}'. Use this directory?" true use_existing
      if [[ "${use_existing}" == "true" ]]; then
        SUBSTRATE_DIR="${found_dir}"
        log_info "Using Substrate repository at: ${COLOR_WHITE}${SUBSTRATE_DIR}${COLOR_RESET}"
        return 0
      fi
    else
      SUBSTRATE_DIR="${found_dir}"
      log_info "Using Substrate repository at: ${COLOR_WHITE}${SUBSTRATE_DIR}${COLOR_RESET}"
      return 0
    fi
  fi

  # Clone fresh
  local default_target="${HOME}/.substrate/src"
  if [[ -z "${SUBSTRATE_DIR}" ]]; then
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
      prompt_input "Enter directory to clone Substrate into" "${default_target}" SUBSTRATE_DIR
    else
      SUBSTRATE_DIR="${default_target}"
    fi
  fi

  if [[ -d "${SUBSTRATE_DIR}/.git" ]]; then
    log_info "Substrate repo already cloned at '${SUBSTRATE_DIR}'. Fetching updates..."
    git -C "${SUBSTRATE_DIR}" pull origin "${SUBSTRATE_BRANCH}" || true
  else
    log_info "Cloning Substrate repository into '${SUBSTRATE_DIR}'..."
    mkdir -p "$(dirname "${SUBSTRATE_DIR}")"
    if ! git clone --branch "${SUBSTRATE_BRANCH}" "${SUBSTRATE_REPO}" "${SUBSTRATE_DIR}" 2>/dev/null; then
      log_warn "Failed to clone from ${SUBSTRATE_REPO}. Trying fallback: ${SUBSTRATE_REPO_FALLBACK}..."
      git clone --branch "${SUBSTRATE_BRANCH}" "${SUBSTRATE_REPO_FALLBACK}" "${SUBSTRATE_DIR}"
    fi
  fi

  log_success "Substrate source ready at: ${COLOR_WHITE}${SUBSTRATE_DIR}${COLOR_RESET}"
}

# ==============================================================================
# Step 3: Review & Summary
# ==============================================================================
review_and_confirm() {
  echo ""
  echo -e "${COLOR_BG_BLUE}${COLOR_WHITE}${COLOR_BOLD} ============================================================================== ${COLOR_RESET}"
  echo -e "${COLOR_BG_BLUE}${COLOR_WHITE}${COLOR_BOLD}                           INSTALLATION CONFIGURATION                           ${COLOR_RESET}"
  echo -e "${COLOR_BG_BLUE}${COLOR_WHITE}${COLOR_BOLD} ============================================================================== ${COLOR_RESET}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_CYAN}%s${COLOR_RESET}\n" "GCP Project ID" "${PROJECT_ID}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "GCP Project Number" "${PROJECT_NUMBER}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "GCP Region" "${GCE_REGION}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "GKE Cluster Location" "${CLUSTER_LOCATION}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "GKE Cluster Name" "${CLUSTER_NAME}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "gVisor Node Machine Type" "${GVISOR_NODE_MACHINE_TYPE}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s / %s${COLOR_RESET}\n" "VPC Network / Subnet" "${NETWORK}" "${SUBNETWORK}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "Snapshot Bucket Name" "${BUCKET_NAME}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "Container Registry" "${GCR_REPO}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "State Store Backend" "${STORE_BACKEND}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "Network Router Dataplane" "${ATENET_ROUTER}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "Sample Demo Application" "${DEPLOY_DEMO}"
  printf "  ${COLOR_BOLD}%-26s${COLOR_RESET} : ${COLOR_WHITE}%s${COLOR_RESET}\n" "Substrate Source Dir" "${SUBSTRATE_DIR}"
  echo -e "${COLOR_BG_BLUE}${COLOR_WHITE}${COLOR_BOLD} ============================================================================== ${COLOR_RESET}"
  echo ""

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "Dry-run mode enabled. Exiting without making changes."
    exit 0
  fi

  local proceed=true
  prompt_yes_no "Proceed with installing Substrate on GCP project '${PROJECT_ID}'?" true proceed
  if [[ "${proceed}" != "true" ]]; then
    log_info "Installation aborted by user."
    exit 0
  fi
}

# ==============================================================================
# Step 4: Write Environment File (.ate-dev-env.sh)
# ==============================================================================
write_env_file() {
  log_step "Saving environment configuration..."

  local env_file="${SUBSTRATE_DIR}/.ate-dev-env.sh"

  cat > "${env_file}" << EOF
# Auto-generated by install-substrate.sh on $(date)
export PROJECT_ID="${PROJECT_ID}"
export PROJECT_NUMBER="${PROJECT_NUMBER}"
export GCE_REGION="${GCE_REGION}"
export CLUSTER_LOCATION="${CLUSTER_LOCATION}"
export CLUSTER_NAME="${CLUSTER_NAME}"
export CLUSTER_VERSION="${CLUSTER_VERSION}"
export NODE_POOL_NAME="gvisor-pool"
export NODE_POOL_VERSION="${CLUSTER_VERSION}"
export GVISOR_NODE_MACHINE_TYPE="${GVISOR_NODE_MACHINE_TYPE}"
export NETWORK="${NETWORK}"
export SUBNETWORK="${SUBNETWORK}"
export ENABLE_DATAPLANE_V2="${ENABLE_DATAPLANE_V2}"
export BUCKET_NAME="${BUCKET_NAME}"
export KO_DOCKER_REPO="${GCR_REPO}"
export KO_DEFAULTPLATFORMS="${KO_DEFAULTPLATFORMS}"
export ATE_INSTALL_STORE_BACKEND="${STORE_BACKEND}"
export ATE_ATENET_ROUTER="${ATENET_ROUTER}"
EOF

  chmod 600 "${env_file}"
  log_success "Environment saved to: ${COLOR_WHITE}${env_file}${COLOR_RESET}"

  # Also export into current environment
  # shellcheck disable=SC1090
  source "${env_file}"
}

# ==============================================================================
# Step 5: Application Default Credentials & GCP Config
# ==============================================================================
setup_gcp_auth() {
  log_step "Configuring Google Cloud CLI & Application Default Credentials (ADC)..."

  # Set active project in gcloud
  gcloud config set project "${PROJECT_ID}" --quiet

  # Check Application Default Credentials
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    log_info "Application Default Credentials (ADC) are required for setup-gcp tool."
    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
      log_warn "Attempting to run non-interactive ADC login..."
    fi
    gcloud auth application-default login --project="${PROJECT_ID}"
  else
    log_info "Application Default Credentials (ADC) already configured."
  fi

  # Configure Docker credentials if docker is installed
  if command -v docker >/dev/null 2>&1; then
    log_info "Configuring Docker authentication helper for GCP registries..."
    gcloud auth configure-docker --quiet 2>/dev/null || true
    if [[ "${GCR_REPO}" =~ pkg.dev ]]; then
      local ar_host="${GCR_REPO%%/*}"
      gcloud auth configure-docker "${ar_host}" --quiet 2>/dev/null || true
    fi
  fi

  log_success "GCP Authentication and ADC configured."
}

# ==============================================================================
# Step 6: Bootstrap GCP Infrastructure (`setup-gcp bootstrap`)
# ==============================================================================
bootstrap_gcp_infrastructure() {
  if [[ "${SKIP_BOOTSTRAP}" == "true" ]]; then
    log_step "Skipping GCP Infrastructure provisioning (--skip-bootstrap specified)."
    return 0
  fi

  log_step "Bootstrapping GCP Infrastructure (GKE, GCS, IAM, Dashboards)..."
  log_info "Running setup-gcp tool from Substrate source repository..."

  cd "${SUBSTRATE_DIR}"

  local bootstrap_cmd=(
    go run ./tools/setup-gcp bootstrap
    --project-id="${PROJECT_ID}"
    --project-number="${PROJECT_NUMBER}"
    --region="${GCE_REGION}"
    --cluster-name="${CLUSTER_NAME}"
    --cluster-location="${CLUSTER_LOCATION}"
    --network="${NETWORK}"
    --subnetwork="${SUBNETWORK}"
    --machine-type="${GVISOR_NODE_MACHINE_TYPE}"
    --bucket-name="${BUCKET_NAME}"
    --dashboard-dir="tools/setup-gcp/dashboards"
  )

  if [[ -n "${CLUSTER_VERSION}" ]]; then
    bootstrap_cmd+=(--cluster-version="${CLUSTER_VERSION}")
  fi

  log_info "Executing: ${bootstrap_cmd[*]}"
  "${bootstrap_cmd[@]}"

  log_success "GCP Infrastructure bootstrap completed successfully."
}

# ==============================================================================
# Step 7: Connect to GKE Cluster
# ==============================================================================
get_cluster_credentials() {
  log_step "Connecting to GKE Cluster..."

  gcloud container clusters get-credentials "${CLUSTER_NAME}" \
    --location "${CLUSTER_LOCATION}" \
    --project "${PROJECT_ID}"

  log_info "Verifying cluster access with kubectl..."
  kubectl cluster-info
  log_success "Connected to GKE cluster: ${COLOR_WHITE}${CLUSTER_NAME}${COLOR_RESET}"
}

# ==============================================================================
# Step 8: Build and Install `kubectl-ate` CLI
# ==============================================================================
install_cli_tools() {
  log_step "Building and installing kubectl-ate CLI tool..."

  cd "${SUBSTRATE_DIR}"
  go install ./cmd/kubectl-ate

  local gopath_bin
  gopath_bin="$(go env GOPATH)/bin"
  if [[ ":${PATH}:" != *":${gopath_bin}:"* ]]; then
    export PATH="${gopath_bin}:${PATH}"
    log_warn "Added '${gopath_bin}' to PATH for this session. Add it to your shell profile (~/.bashrc, ~/.zshrc) for future sessions."
  fi

  if command -v kubectl-ate >/dev/null 2>&1; then
    log_success "kubectl-ate installed successfully: $(which kubectl-ate)"
  else
    log_info "kubectl-ate built and will be accessed via 'go run ./cmd/kubectl-ate' during installation."
  fi
}

# ==============================================================================
# Step 9: Deploy Substrate System
# ==============================================================================
deploy_substrate_system() {
  log_step "Deploying Substrate Control Plane & Data Plane to GKE..."

  cd "${SUBSTRATE_DIR}"

  local install_args=(
    --deploy-ate-system
    --store-backend="${STORE_BACKEND}"
    --atenet-router="${ATENET_ROUTER}"
    --rollout-timeout=300s
  )

  log_info "Executing: ./hack/install-ate.sh ${install_args[*]}"
  ./hack/install-ate.sh "${install_args[@]}"

  log_success "Substrate system deployed successfully!"
}

# ==============================================================================
# Step 10: Deploy Demo Application (Optional)
# ==============================================================================
deploy_demo_application() {
  if [[ "${DEPLOY_DEMO}" != "counter" && "${DEPLOY_DEMO}" != "true" ]]; then
    log_info "Skipping demo deployment."
    return 0
  fi

  cd "${SUBSTRATE_DIR}"
  log_step "Deploying Counter Demo application..."
  ./hack/install-ate.sh --deploy-demo-counter
  log_success "Counter Demo deployed successfully!"
}

# ==============================================================================
# Step 11: Verification & Post-Install Instructions
# ==============================================================================
print_completion_summary() {
  log_step "Verifying Substrate deployment..."

  echo -e "\n${COLOR_BOLD}Cluster Workloads in 'ate-system' namespace:${COLOR_RESET}"
  kubectl get pods -n ate-system -o wide || true

  echo ""
  echo -e "${COLOR_GREEN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}${COLOR_BOLD}            Substrate Installation Completed Successfully!                    ${COLOR_RESET}"
  echo -e "${COLOR_GREEN}${COLOR_BOLD}==============================================================================${COLOR_RESET}"
  echo ""
  echo -e "${COLOR_BOLD}Cluster Details:${COLOR_RESET}"
  echo "  - Project:   ${PROJECT_ID}"
  echo "  - Cluster:   ${CLUSTER_NAME} (${CLUSTER_LOCATION})"
  echo "  - Store:     ${STORE_BACKEND}"
  echo "  - Router:    ${ATENET_ROUTER}"
  echo "  - Config:    ${SUBSTRATE_DIR}/.ate-dev-env.sh"
  echo ""
  echo -e "${COLOR_BOLD}Cloud Monitoring Dashboards:${COLOR_RESET}"
  echo "  https://console.cloud.google.com/monitoring/dashboards?project=${PROJECT_ID}"
  echo ""
  echo -e "${COLOR_BOLD}Quick Start & Verification Commands:${COLOR_RESET}"

  if [[ "${DEPLOY_DEMO}" == "counter" ]]; then
    cat << EOF

  ${COLOR_CYAN}1. Create an Atespace and Actor instance:${COLOR_RESET}
     kubectl ate create atespace demo
     kubectl ate create actor my-counter-1 -a demo --template=ate-demo-counter/counter

  ${COLOR_CYAN}2. Port-forward the Substrate Router (run in a separate terminal):${COLOR_RESET}
     kubectl port-forward -n ate-system svc/atenet-router 8000:80

  ${COLOR_CYAN}3. Send requests to invoke the Counter Actor:${COLOR_RESET}
     curl -X POST -H "Host: my-counter-1.demo.actors.resources.substrate.ate.dev" -i http://localhost:8000/
     curl -X GET  -H "Host: my-counter-1.demo.actors.resources.substrate.ate.dev" -i http://localhost:8000/

  ${COLOR_CYAN}4. Check Actor status:${COLOR_RESET}
     kubectl ate get actors -a demo

EOF
  else
    cat << EOF

  ${COLOR_CYAN}1. Manage Actors with kubectl-ate:${COLOR_RESET}
     kubectl ate --help

  ${COLOR_CYAN}2. Port-forward the Substrate Router:${COLOR_RESET}
     kubectl port-forward -n ate-system svc/atenet-router 8000:80

EOF
  fi

  echo -e "${COLOR_BOLD}Teardown / Cleanup:${COLOR_RESET}"
  echo "  If you wish to delete all GCP resources created for Substrate:"
  echo "  cd ${SUBSTRATE_DIR} && ./hack/teardown.sh --all"
  echo ""
  echo -e "${COLOR_GREEN}Enjoy building with Substrate!${COLOR_RESET}"
}

# ==============================================================================
# Main Entrypoint
# ==============================================================================
main() {
  parse_args "$@"
  check_prerequisites
  configure_interactive
  review_and_confirm
  write_env_file
  setup_gcp_auth
  bootstrap_gcp_infrastructure
  get_cluster_credentials
  install_cli_tools
  deploy_substrate_system
  deploy_demo_application
  print_completion_summary
}

main "$@"
