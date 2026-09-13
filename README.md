# nixos-ci-image

Minimal, Nix-built OCI container image for **GitHub Actions self-hosted runners**.

Provides the bare-bones environment CI jobs need to check out repositories and run `nix` commands — no Docker daemon required at build time or runtime.

## What's Inside

| Category | Packages |
|---|---|
| Shell | `bash`, `coreutils`, `gnugrep`, `gnused`, `gawk`, `findutils`, `gnutar`, `gzip`, `xz`, `zstd`, `which` |
| Networking | `curl`, `cacert`, `openssh` |
| Git | `git`, `git-lfs` |
| Nix | `nix` (flakes & nix-command enabled) |
| Node.js | `nodejs` (required by JS-based GitHub Actions) |

## Available Channels & Image Tags

Images are built and pushed to GitHub Container Registry (`ghcr.io/yeradon/nixos-ci-image`) for multiple NixOS release streams:

| Stream | Description | Available Tags |
|---|---|---|
| **Current Stable** | Latest official NixOS release | `:latest`, `:stable`, `:26.05`, `:nixos-26.05`, `:26.05-<rev>` |
| **Old Stable** | Previous supported NixOS release | `:old-stable`, `:25.11`, `:nixos-25.11`, `:25.11-<rev>` |
| **Unstable** | Rolling bleeding-edge packages | `:unstable`, `:nixos-unstable`, `:unstable-<rev>` |

## Usage

Use as a job container in your GitHub Actions workflow:

```yaml
jobs:
  build:
    runs-on: self-hosted
    container:
      image: ghcr.io/yeradon/nixos-ci-image:latest # Or :stable, :26.05, :old-stable, :unstable
    steps:
      - uses: actions/checkout@v4
      - run: nix build
```

## Build Locally

```bash
# Build default (current stable)
nix build

# Or build a specific channel
nix build .#26.05
nix build .#25.11
nix build .#unstable

# Inspect the result
tar -tzf result | head -20

# Load into Docker (if available)
docker load < result
docker run --rm nixos-ci-image:latest nix --version
```

## Workflows & Automation

### 1. Build & Push (`build.yml`)
- **Trigger**: Push to `main`, PRs, or manual dispatch.
- **Matrix**: Concurrently builds each stream (`26.05`, `25.11`, `unstable`) and pushes their respective tags and pinned commit revision tags to `ghcr.io`.

### 2. Auto-Update Channels & Dependencies (`update-flake.yml`)
- **Trigger**: Every Monday at 04:00 UTC, or manually via `workflow_dispatch`.
- **New Release Detection**: Checks upstream `NixOS/nixpkgs` for new stable releases (e.g. `26.11`). When detected, shifts channels (moves current stable to old-stable, promotes the new release to stable), updates all files, and opens a Pull Request.
- **Weekly Maintenance**: Bumps revisions in `flake.lock` and opens an automated PR.

## Configuration

The image ships with this Nix config (`/etc/nix/nix.conf`):

```ini
experimental-features = nix-command flakes
sandbox = false
filter-syscalls = false
```

Sandbox and syscall filtering are disabled because they require kernel features not typically available inside unprivileged containers.

## License

MIT License. See [LICENSE](LICENSE) for details.
