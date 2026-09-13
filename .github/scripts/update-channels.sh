#!/usr/bin/env bash
set -euo pipefail

# Find all stable release branches on nixpkgs
echo "Fetching available NixOS stable branches from upstream..."
BRANCHES=$(git ls-remote --heads https://github.com/NixOS/nixpkgs "refs/heads/nixos-[0-9][0-9].[0-9][0-9]" | awk '{print $2}' | sed 's|refs/heads/nixos-||' | sort -V)
mapfile -t STABLE_VERSIONS <<< "$BRANCHES"
NUM_STABLE=${#STABLE_VERSIONS[@]}

LATEST_STABLE="${STABLE_VERSIONS[NUM_STABLE-1]}"
OLD_STABLE="${STABLE_VERSIONS[NUM_STABLE-2]}"

echo "Upstream latest stable: ${LATEST_STABLE}"
echo "Upstream old stable:    ${OLD_STABLE}"

CURRENT_STABLE=$(grep -oP 'nixpkgs-stable\.url = "github:NixOS/nixpkgs/nixos-\K[0-9.]+' flake.nix)
CURRENT_OLD=$(grep -oP 'nixpkgs-old\.url = "github:NixOS/nixpkgs/nixos-\K[0-9.]+' flake.nix)

echo "Currently configured stable:     ${CURRENT_STABLE}"
echo "Currently configured old stable: ${CURRENT_OLD}"

NEW_RELEASE="false"

if [ "${LATEST_STABLE}" != "${CURRENT_STABLE}" ]; then
  echo "New NixOS release detected! Upgrading: ${CURRENT_STABLE} -> ${LATEST_STABLE} (old: ${CURRENT_STABLE})"
  NEW_RELEASE="true"

  # 1. Update flake.nix inputs and package definitions
  sed -i "s|github:NixOS/nixpkgs/nixos-${CURRENT_OLD}|github:NixOS/nixpkgs/nixos-${CURRENT_STABLE}|g" flake.nix
  sed -i "s|github:NixOS/nixpkgs/nixos-${CURRENT_STABLE}|github:NixOS/nixpkgs/nixos-${LATEST_STABLE}|g" flake.nix
  sed -i "s|\"${CURRENT_OLD}\" =|\"${CURRENT_STABLE}\" =|g" flake.nix
  sed -i "s|\"${CURRENT_STABLE}\" =|\"${LATEST_STABLE}\" =|g" flake.nix
  sed -i "s|version = \"${CURRENT_OLD}\"|version = \"${CURRENT_STABLE}\"|g" flake.nix
  sed -i "s|version = \"${CURRENT_STABLE}\"|version = \"${LATEST_STABLE}\"|g" flake.nix
  sed -i "s|channelName = \"nixos-${CURRENT_OLD}\"|channelName = \"nixos-${CURRENT_STABLE}\"|g" flake.nix
  sed -i "s|channelName = \"nixos-${CURRENT_STABLE}\"|channelName = \"nixos-${LATEST_STABLE}\"|g" flake.nix
  sed -i "s|old-stable = self.packages.\${system}.\"${CURRENT_OLD}\"|old-stable = self.packages.\${system}.\"${CURRENT_STABLE}\"|g" flake.nix
  sed -i "s|stable = self.packages.\${system}.\"${CURRENT_STABLE}\"|stable = self.packages.\${system}.\"${LATEST_STABLE}\"|g" flake.nix
  sed -i "s|default = self.packages.\${system}.\"${CURRENT_STABLE}\"|default = self.packages.\${system}.\"${LATEST_STABLE}\"|g" flake.nix

  # 2. Update .github/workflows/build.yml matrix
  # Shift old-stable to previous stable
  sed -i "s|version: \"${CURRENT_OLD}\"|version: \"${CURRENT_STABLE}\"|g" .github/workflows/build.yml
  sed -i "s|channel: \"nixos-${CURRENT_OLD}\"|channel: \"nixos-${CURRENT_STABLE}\"|g" .github/workflows/build.yml
  sed -i "s|tags: \"${CURRENT_OLD} old-stable nixos-${CURRENT_OLD}\"|tags: \"${CURRENT_STABLE} old-stable nixos-${CURRENT_STABLE}\"|g" .github/workflows/build.yml

  # Set stable to new latest stable
  sed -i "s|version: \"${CURRENT_STABLE}\"|version: \"${LATEST_STABLE}\"|g" .github/workflows/build.yml
  sed -i "s|channel: \"nixos-${CURRENT_STABLE}\"|channel: \"nixos-${LATEST_STABLE}\"|g" .github/workflows/build.yml
  sed -i "s|tags: \"${CURRENT_STABLE} stable latest nixos-${CURRENT_STABLE}\"|tags: \"${LATEST_STABLE} stable latest nixos-${LATEST_STABLE}\"|g" .github/workflows/build.yml

  # 3. Update README.md
  sed -i "s|${CURRENT_STABLE}|${LATEST_STABLE}|g" README.md
  sed -i "s|${CURRENT_OLD}|${CURRENT_STABLE}|g" README.md
fi

echo "Running nix flake update..."
nix flake update

HAS_CHANGES="false"
if [ -n "$(git status --porcelain)" ]; then
  HAS_CHANGES="true"
fi

echo "Summary:"
echo "  has_changes:   ${HAS_CHANGES}"
echo "  new_release:   ${NEW_RELEASE}"
echo "  latest_stable: ${LATEST_STABLE}"
echo "  old_stable:    ${CURRENT_STABLE}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "has_changes=${HAS_CHANGES}" >> "$GITHUB_OUTPUT"
  echo "new_release=${NEW_RELEASE}" >> "$GITHUB_OUTPUT"
  echo "latest_stable=${LATEST_STABLE}" >> "$GITHUB_OUTPUT"
  echo "old_stable=${CURRENT_STABLE}" >> "$GITHUB_OUTPUT"
fi
