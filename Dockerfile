FROM node:24


RUN apt-get update && apt-get install -y --no-install-recommends \
  locales \
  git \
  gh \
  vim \
  ca-certificates \
  python3 \
  python3-pip \
  python3-venv \
  bubblewrap \
  mosh \
  tmux \
  jq \
  openssh-client \
  procps \
  docker.io \
  docker-compose \
  && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
  && locale-gen en_US.UTF-8 \
  && update-locale LANG=en_US.UTF-8 \
  && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create venv
RUN python3 -m venv /opt/venv


# Put venv first in PATH
ENV PATH="/opt/venv/bin:$PATH"

# Install Python testing dependencies
RUN pip install --upgrade pip && \
  pip install pytest

# Install Codex CLI globally
RUN npm install -g npm@latest
RUN npm install -g @openai/codex
RUN npm install -g @google/gemini-cli
RUN npm install -g @anthropic-ai/claude-code

# copy entrypoint
COPY entrypoint.sh /entrypoint.sh
COPY tmux.conf /root/.tmux.conf
RUN chmod +x /entrypoint.sh

RUN mkdir -p /root/.ssh /workspace && \
  chmod 700 /root/.ssh


RUN cat <<'EOF' >/etc/profile.d/git-prompt.sh
parse_git_branch() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local branch
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)"
  [ -n "$branch" ] && printf ' (%s)' "$branch"
}

set_git_prompt() {
  local reset='\[\e[0m\]'
  local green='\[\e[0;32m\]'
  local blue='\[\e[0;34m\]'
  local yellow='\[\e[0;33m\]'
  PS1="${green}\u@\h${reset}:${blue}\w${yellow}\$(parse_git_branch)${reset}\\$ "
}

case "$-" in
  *i*) set_git_prompt ;;
  *) ;;
esac
EOF

RUN curl -fsSL https://tailscale.com/install.sh | sh && \
  rm -rf /var/lib/apt/lists/*

RUN echo "alias tmux='tmux new-session -A -s main'" >> /root/.bashrc

RUN cat <<'EOF' >> /root/.bashrc
tmux_repo() {
    local repo_dir="/workspace/repo"

    if [ ! -d "$repo_dir" ]; then
        echo "Directory not found: $repo_dir"
        return 1
    fi

    # Start tmux server if not already running
    tmux start-server

    # main session
    if ! tmux has-session -t main 2>/dev/null; then
        tmux new-session -d -s main -c "$repo_dir"
    fi

    # codex-cloud session
    if ! tmux has-session -t codex-cloud 2>/dev/null; then
        tmux new-session -d -s codex-cloud -c "$repo_dir"
        tmux send-keys -t codex-cloud 'codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox' C-m
    fi

    # codex-local session
    if ! tmux has-session -t codex-local 2>/dev/null; then
        tmux new-session -d -s codex-local -c "$repo_dir"
        tmux send-keys -t codex-local 'codex --no-alt-screen --dangerously-bypass-approvals-and-sandbox -p local -m glm-4.7-flash' C-m
    fi

    # Attach to main session
    tmux attach-session -t main
}

alias worktmux='tmux_repo'

EOF
# Set working directory
WORKDIR /workspace

# Default shell
ENTRYPOINT ["/entrypoint.sh"]
