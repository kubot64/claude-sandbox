# AGENTS.md

## Cursor Cloud specific instructions

### Overview

claude-sandbox is a pure Bash CLI tool that runs Claude Code inside a Docker container with network-restriction (tinyproxy + iptables). The codebase has no package manager or lockfile — all scripts are Bash.

### Lint & Test commands

See `README.md § テスト` for the authoritative commands. Quick reference:

- **Lint**: `shellcheck claude-sandbox entrypoint.sh init-network.sh install.sh tests/helpers/mocks.bash tests/helpers/docker.bash`
- **Unit tests** (no Docker): `bash tests/run_all.sh --unit-only`
- **Full suite** (Docker required): `bash tests/run_all.sh --integration`

### Docker integration tests in Cloud Agent VMs

The Cloud Agent VM runs Docker-in-Docker (Firecracker VM → container → Docker). This causes `iptables` inside the sandbox container to fail with `TABLE_ADD failed (Operation not supported)` because the kernel does not support nf_tables features. As a result, **firewall integration tests (firewall.bats tests 4, 6, 7) are expected to fail** in this environment. The remaining integration tests (exit_code, ssh_tmpfs) and all unit tests pass normally.

To start the Docker daemon before running integration tests:

```bash
sudo dockerd &>/tmp/dockerd.log &
sleep 3
sudo chmod 666 /var/run/docker.sock
```

### Building the Docker image

```bash
docker build -t claude-sandbox .
```

The image must exist before running integration tests. `run_all.sh --integration` auto-builds it if missing.
