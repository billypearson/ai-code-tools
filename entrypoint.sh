#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

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

mkdir -p "${TS_STATE_DIR}" /var/run/tailscale "${WORKDIR}"

start_tailscaled() {
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

clone_or_update_repo() {
  if [ -z "${GIT_REPO_URL:-}" ]; then
    log "GIT_REPO_URL not set, skipping repo clone/update"
    return 0
  fi

  mkdir -p "$(dirname "${REPO_DIR}")"

  if [ -d "${REPO_DIR}/.git" ]; then
    log "Existing repo found, updating ${REPO_DIR}"
    git -C "${REPO_DIR}" fetch --all --prune
    git -C "${REPO_DIR}" checkout "${GIT_BRANCH}"
    git -C "${REPO_DIR}" pull --ff-only origin "${GIT_BRANCH}"
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
  else
    log "Creating background Zellij session ${ZELLIJ_SESSION}"
    zellij --session "${ZELLIJ_SESSION}" action new-pane --cwd "${PWD}" >/dev/null 2>&1 || true
    # Fallback if the above command is not supported by your version:
    zellij --session "${ZELLIJ_SESSION}" --new-session-with-layout compact >/dev/null 2>&1 &
    sleep 2
    pkill -f "zellij --session ${ZELLIJ_SESSION}" || true
  fi
}

main() {
  start_tailscaled
  wait_for_socket
  tailscale_up
  wait_for_tailscale
  clone_or_update_repo
  bootstrap_zellij

  log "Container bootstrap complete"

  if [ "$#" -gt 0 ]; then
    exec "$@"
  fi

  # Keep container alive if no command was provided
  wait "${TAILSCALED_PID}"
}

main "$@"
