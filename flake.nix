{
  description = "Minimal NixOS-based OCI image for GitHub Actions self-hosted runners (Kubernetes mode)";

  inputs = {
    nixpkgs-old.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs-old, nixpkgs-stable, nixpkgs-unstable }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs-stable.lib.genAttrs supportedSystems;

      mkRunnerImage = { pkgs, version, channelName }:
        let
          # Packages included in the image
          imagePackages = with pkgs; [
            # Shell essentials
            bashInteractive
            coreutils
            gnugrep
            gnused
            gawk
            findutils
            gnutar
            gzip
            xz
            which

            # Networking & TLS
            curl
            cacert
            openssh

            # Git (required by actions/checkout)
            git
            git-lfs

            # Nix itself
            nix

            # Node.js (required by JavaScript-based GitHub Actions)
            nodejs

            # Compression (zstd required by actions/cache)
            zstd

            # glibc and stdc++ for dynamically linked binaries (like GHA's node)
            glibc
            stdenv.cc.cc.lib
          ];

          # Build a proper PATH from all included packages
          pathString = pkgs.lib.makeBinPath imagePackages;

          # Library path for nix-ld
          ldLibraryPath = pkgs.lib.makeLibraryPath [
            pkgs.glibc
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];
        in
        pkgs.dockerTools.buildLayeredImage {
          name = "nixos-ci-image";
          tag = version;

          contents = imagePackages ++ [
            pkgs.dockerTools.binSh
            pkgs.dockerTools.usrBinEnv
            pkgs.dockerTools.caCertificates
            pkgs.dockerTools.fakeNss
            pkgs.nix-ld
          ];

          # Set up directories and config files in the final layer
          extraCommands = ''
            # Create required directories
            mkdir -p tmp
            chmod 1777 tmp
            mkdir -p root
            mkdir -p home/runner/_work
            mkdir -p etc/nix
            mkdir -p nix/var/nix/profiles/per-user/root
            mkdir -p nix/var/nix/gcroots/per-user/root
            mkdir -p nix/var/nix/profiles/per-user/runner
            mkdir -p nix/var/nix/gcroots/per-user/runner

            # Symlink standard C/C++ libraries to standard paths for GHA binaries
            # (Node.js strips LD_LIBRARY_PATH in some contexts)
            mkdir -p lib lib64 usr/lib usr/lib64
            for dir in lib lib64 usr/lib usr/lib64; do
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 "$dir/libstdc++.so.6"
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 "$dir/libgcc_s.so.1"
              ln -sf ${pkgs.zlib}/lib/libz.so.1 "$dir/libz.so.1"
              ln -sf ${pkgs.glibc}/lib/libc.so.6 "$dir/libc.so.6"
              ln -sf ${pkgs.glibc}/lib/libm.so.6 "$dir/libm.so.6"
              ln -sf ${pkgs.glibc}/lib/libdl.so.2 "$dir/libdl.so.2"
              ln -sf ${pkgs.glibc}/lib/libpthread.so.0 "$dir/libpthread.so.0" 2>/dev/null || true
            done

            # Wire dynamic linker to nix-ld so foreign binaries (like GHA runner's Node)
            # find their libraries via NIX_LD_LIBRARY_PATH
            ln -sf ${pkgs.nix-ld}/libexec/nix-ld lib64/ld-linux-x86-64.so.2
            ln -sf ${pkgs.nix-ld}/libexec/nix-ld lib/ld-linux-x86-64.so.2

            # Create dummy os-release for GitHub Actions compatibility
            cat > etc/os-release <<EOF
            NAME=NixOS
            ID=nixos
            VERSION="${version}"
            VERSION_CODENAME=nixos
            PRETTY_NAME="NixOS ${version} (CI Runner)"
            EOF
            # Remove leading whitespace
            sed -i 's/^[[:space:]]*//' etc/os-release

            # Nix configuration: enable flakes and nix-command
            cat > etc/nix/nix.conf <<'EOF'
            experimental-features = nix-command flakes
            sandbox = false
            filter-syscalls = false
            build-users-group =
            EOF
            # Remove leading whitespace from heredoc
            sed -i 's/^[[:space:]]*//' etc/nix/nix.conf
          '';

          fakeRootCommands = '''';

          config = {
            Env = [
              "PATH=${pathString}:/usr/bin:/bin"
              "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
              "NIX_PATH=nixpkgs=${pkgs.path}"
              "HOME=/root"
              "USER=root"
              "NIX_LD=${pkgs.glibc}/lib/ld-linux-x86-64.so.2"
              "NIX_LD_LIBRARY_PATH=${ldLibraryPath}"
            ];
            WorkingDir = "/home/runner/_work";
            Volumes = {
              "/home/runner/_work" = { };
              "/tmp" = { };
            };
          };
        };
    in
    {
      packages = forAllSystems (system: {
        "25.11" = mkRunnerImage {
          pkgs = nixpkgs-old.legacyPackages.${system};
          version = "25.11";
          channelName = "nixos-25.11";
        };
        "26.05" = mkRunnerImage {
          pkgs = nixpkgs-stable.legacyPackages.${system};
          version = "26.05";
          channelName = "nixos-26.05";
        };
        "unstable" = mkRunnerImage {
          pkgs = nixpkgs-unstable.legacyPackages.${system};
          version = "unstable";
          channelName = "nixos-unstable";
        };

        # Aliases
        old-stable = self.packages.${system}."25.11";
        stable = self.packages.${system}."26.05";
        default = self.packages.${system}."26.05";
      });
    };
}
