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
COPY frontdoor.sh /frontdoor.sh
RUN chmod +x /frontdoor.sh

RUN mkdir -p /root/.ssh /workspace && \
    chmod 700 /root/.ssh && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts && \
    chmod 644 /root/.ssh/known_hosts

RUN curl -fsSL https://tailscale.com/install.sh | sh && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Default shell
ENTRYPOINT ["/frontdoor.sh"]
