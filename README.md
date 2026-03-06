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

## Usage

Use as a job container in your workflow:

```yaml
jobs:
  build:
    runs-on: self-hosted
    container:
      image: ghcr.io/yeradon/nixos-ci-image:latest
    steps:
      - uses: actions/checkout@v4
      - run: nix build
```

## Build Locally

```bash
# Build the image tarball
nix build

# Inspect the result
tar -tzf result | head -20

# Load into Docker (if available)
docker load < result
docker run --rm nixos-ci-image:latest nix --version

# Or push with skopeo (no Docker needed)
skopeo copy docker-archive:./result docker://ghcr.io/yeradon/nixos-ci-image:dev
```

## CI Workflows

### Build (`build.yml`)
- **Trigger**: Push to `main`, `v*` tags, PRs against `main`
- **On push**: Builds + pushes to `ghcr.io` with nixpkgs-based tags (e.g. `nixos-25.11`) and `latest`
- **On PRs**: Build-only (smoke test)

### Release (`release.yml`)
- **Trigger**: Chains off build workflow on `v*` tags
- **Action**: Re-tags the image with the version tag, creates a GitHub Release

## Configuration

The image ships with this Nix config (`/etc/nix/nix.conf`):

```ini
experimental-features = nix-command flakes
sandbox = false
filter-syscalls = false
```

Sandbox and syscall filtering are disabled because they require kernel features not typically available inside unprivileged containers.
