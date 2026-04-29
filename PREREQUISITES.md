# Prerequisites

Host-side setup needed to run any of the demos.

## Required Tools

| Tool | Min version | Install (Fedora) | Install (macOS) |
|---|---|---|---|
| podman | 5.0 | `sudo dnf install podman` | `brew install podman` |
| podman-compose | 1.0 | `pip install podman-compose --user` | `brew install podman-compose` |
| Java JDK | 21 (some demos: 25) | `sudo dnf install java-21-openjdk-devel` | `brew install openjdk@21` |
| Maven | 3.9 | `sudo dnf install maven` | `brew install maven` |
| `hey` | latest | binary from GitHub releases | `brew install hey` |
| `jq` | 1.6+ | `sudo dnf install jq` | `brew install jq` |
| `curl` | any | preinstalled | preinstalled |

## Optional but Recommended

| Tool | Why |
|---|---|
| `ghz` | gRPC load testing (used in optional gRPC variant) |
| `grpcurl` | gRPC CLI client |
| `excalidraw` (web app) | Editing diagrams in `diagrams/` |

## Podman Machine (macOS)

On macOS, podman runs in a Linux VM. Configure it with enough resources:

```bash
podman machine init --cpus 4 --memory 8192 --disk-size 60
podman machine start
```

For SELinux-style bind mounts to work the same as on Fedora, the `:Z` flag is honored on the macOS VM as well — but the underlying behavior is a no-op. Configs work portably.

## Fedora Setup Notes

These are the non-obvious gotchas carried over from the prior project:

1. **Image names must be fully qualified.** `grafana/otel-lgtm` won't resolve; use `docker.io/grafana/otel-lgtm:0.8.1`.
2. **Bind mounts need `:Z` for SELinux.** Without it, the container sees `Permission denied` reading the mount.
3. **Named volumes are root-owned in rootless podman.** For Grafana, use `tmpfs:` and `user: root` in the compose file (as we do here) to sidestep this.
4. **`pip install --user` requires `~/.local/bin` on PATH.** Add to `~/.bashrc` if not already there.

## Pre-Talk Checklist

Before presenting, run:

```bash
./pre-pull.sh           # pulls all required container images
./verify-stacks.sh      # smoke-tests each demo's compose
```

This catches stale images and missing tools well before the room is full.

## Subscription Notes

- All UBI9 base images used here come from `registry.access.redhat.com/ubi9/...` and require **no Red Hat subscription**. They're free to pull and redistribute.
- `ubi9/toolbox` would require a subscription — we don't use it.
