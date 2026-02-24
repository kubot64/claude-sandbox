FROM debian:bookworm-slim

ARG TARGETARCH

# 基本ツール + L7プロキシ + firewall
RUN apt-get update && apt-get install -y \
    curl \
    git \
    openssh-client \
    iptables \
    tinyproxy \
    jq \
    rsync \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Node.js LTS（Claude Code インストール用）
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# known_hosts を固定埋め込み（TOFU リスク回避）
RUN mkdir -p /etc/ssh && \
    ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts 2>/dev/null && \
    ssh-keyscan gitlab.com >> /etc/ssh/ssh_known_hosts 2>/dev/null || true

# claude ユーザー作成（非 root 実行）
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.local/bin && \
    chown -R claude:claude /home/claude

COPY entrypoint.sh /entrypoint.sh
COPY init-network.sh /init-network.sh
COPY tinyproxy.conf.tmpl /tinyproxy.conf.tmpl
RUN chmod +x /entrypoint.sh /init-network.sh

WORKDIR /workspace
ENTRYPOINT ["/entrypoint.sh"]
