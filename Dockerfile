FROM node:24
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  gh \
  vim \
  ca-certificates \
  python3 \
  python3-pip \
  python3-venv \
  bubblewrap \
  mosh \
  jq \
  openssh-client \
  procps \
  && rm -rf /var/lib/apt/lists/*

# Create venv
RUN python3 -m venv /opt/venv

# Put venv first in PATH
ENV PATH="/opt/venv/bin:$PATH"

# Copy persisted Codex auth/config files into container
COPY zellij /usr/local/bin/zellij
RUN chmod +x /usr/local/bin/zellij

# Install Codex CLI globally
RUN npm install -g npm@latest
RUN npm install -g @openai/codex
RUN npm i -g @openai/codex
RUN npm install -g @google/gemini-cli
RUN npm install -g @anthropic-ai/claude-code
RUN npx get-shit-done-cc --claude --global
RUN npx get-shit-done-cc --gemini --global
RUN npx get-shit-done-cc --codex --global

# COPY requirements.txt requirements.txt
# RUN python3 -m pip install --upgrade pip && \
#     pip install -r requirements.txt

# copy entrypoint
COPY entrypoint.sh /entrypoint.sh
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

# Set working directory
WORKDIR /workspace

# Default shell
ENTRYPOINT ["/entrypoint.sh"]
