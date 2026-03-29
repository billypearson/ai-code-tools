#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    log "Required command not found: ${cmd}"
    exit 1
  fi
}

cleanup() {
  local exit_code=$?

  if [[ -n "${TAILSCALED_PID:-}" ]] && kill -0 "${TAILSCALED_PID}" >/dev/null 2>&1; then
    log "Stopping tailscaled"
    kill "${TAILSCALED_PID}" >/dev/null 2>&1 || true
    wait "${TAILSCALED_PID}" >/dev/null 2>&1 || true
  fi

  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

# Required / optional config
: "${TS_AUTHKEY:?TS_AUTHKEY is required}"
: "${TS_STATE_DIR:=/var/lib/tailscale}"
: "${TS_SOCKET:=/var/run/tailscale/tailscaled.sock}"
: "${TS_HOSTNAME:=node24-ai-tools}"
: "${TAILSCALE_EXTRA_ARGS:=--ssh}"
: "${WORKDIR:=/workspace}"
: "${REPO_DIR:=${WORKDIR}/repo}"
: "${ZELLIJ_SESSION:=repo}"
: "${GIT_BRANCH:=main}"
: "${GIT_CLONE_DEPTH:=1}"
: "${REPO_REMOTE_NAME:=origin}"
: "${GIT_RESET_HARD:=0}"

mkdir -p "${TS_STATE_DIR}" /var/run/tailscale "${WORKDIR}"

start_tailscaled() {
  require_cmd tailscaled
  log "Starting tailscaled"
  tailscaled \
    --state="${TS_STATE_DIR}/tailscaled.state" \
    --socket="${TS_SOCKET}" &
  TAILSCALED_PID=$!
}

wait_for_socket() {
  for _ in $(seq 1 60); do
    if [ -S "${TS_SOCKET}" ]; then
      return 0
    fi
    sleep 1
  done
  log "tailscaled socket did not appear"
  exit 1
}

tailscale_up() {
  require_cmd tailscale
  log "Bringing Tailscale up as ${TS_HOSTNAME}"
  tailscale --socket="${TS_SOCKET}" up \
    --auth-key="${TS_AUTHKEY}" \
    --hostname="${TS_HOSTNAME}" \
    ${TAILSCALE_EXTRA_ARGS}
}

wait_for_tailscale() {
  for _ in $(seq 1 60); do
    if tailscale --socket="${TS_SOCKET}" status >/dev/null 2>&1; then
      TS_IP="$(tailscale --socket="${TS_SOCKET}" ip -4 | head -n1 || true)"
      log "Tailscale is online${TS_IP:+ at ${TS_IP}}"
      return 0
    fi
    sleep 1
  done
  log "Tailscale did not come online in time"
  exit 1
}

prepare_git_ssh() {
  if [ -d /root/.ssh ]; then
    chmod 700 /root/.ssh || true
    if [ -f /root/.ssh/known_hosts ]; then
      chmod 644 /root/.ssh/known_hosts || true
    fi
  fi
}

clone_or_update_repo() {
  if [ -z "${GIT_REPO_URL:-}" ]; then
    log "GIT_REPO_URL not set, skipping repo clone/update"
    return 0
  fi

  require_cmd git
  prepare_git_ssh
  mkdir -p "$(dirname "${REPO_DIR}")"

  if [ -d "${REPO_DIR}/.git" ]; then
    log "Existing repo found, updating ${REPO_DIR}"
    git -C "${REPO_DIR}" remote set-url "${REPO_REMOTE_NAME}" "${GIT_REPO_URL}" || true
    git -C "${REPO_DIR}" fetch --all --prune
    git -C "${REPO_DIR}" checkout "${GIT_BRANCH}"
    if [ "${GIT_RESET_HARD}" = "1" ]; then
      git -C "${REPO_DIR}" reset --hard "${REPO_REMOTE_NAME}/${GIT_BRANCH}"
    else
      git -C "${REPO_DIR}" pull --ff-only "${REPO_REMOTE_NAME}" "${GIT_BRANCH}"
    fi
  else
    log "Cloning ${GIT_REPO_URL} into ${REPO_DIR}"
    git clone \
      --branch "${GIT_BRANCH}" \
      --depth "${GIT_CLONE_DEPTH}" \
      "${GIT_REPO_URL}" "${REPO_DIR}"
  fi
}

bootstrap_zellij() {
  if ! command -v zellij >/dev/null 2>&1; then
    log "zellij not installed, skipping session bootstrap"
    return 0
  fi

  cd "${REPO_DIR:-$WORKDIR}"

  if zellij list-sessions 2>/dev/null | grep -qx "${ZELLIJ_SESSION}"; then
    log "Zellij session ${ZELLIJ_SESSION} already exists"
    return 0
  fi

  log "Creating detached Zellij session ${ZELLIJ_SESSION}"
  if zellij options --session "${ZELLIJ_SESSION}" --default-cwd "${PWD}" >/dev/null 2>&1; then
    return 0
  fi

  nohup sh -c "cd '${PWD}' && exec zellij -s '${ZELLIJ_SESSION}'" >/tmp/zellij-bootstrap.log 2>&1 &
  sleep 2
}

show_connection_info() {
  local name="${TS_HOSTNAME}"
  log "Connect with: ssh root@${name}"
  log "Then attach with: zellij attach ${ZELLIJ_SESSION}"
}

main() {
  start_tailscaled
  wait_for_socket
  tailscale_up
  wait_for_tailscale
  clone_or_update_repo
  bootstrap_zellij
  show_connection_info

  log "Container bootstrap complete"

  if [ "$#" -gt 0 ]; then
    exec "$@"
  fi

  wait "${TAILSCALED_PID}"
}

main "$@"
