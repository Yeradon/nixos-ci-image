{
  description = "Minimal NixOS-based OCI image for GitHub Actions self-hosted runners (Kubernetes mode)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

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
        {
          default = pkgs.dockerTools.buildLayeredImage {
            name = "nixos-ci-image";
            tag = "latest";

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
              mkdir -p home/runner/_work
              mkdir -p etc/nix
              mkdir -p nix/var/nix/profiles/per-user/runner
              mkdir -p nix/var/nix/gcroots/per-user/runner

              # Symlink standard C/C++ libraries to standard paths for GHA binaries
              # (Node.js strips LD_LIBRARY_PATH in some contexts)
              mkdir -p lib64
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 lib64/libstdc++.so.6
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 lib64/libgcc_s.so.1
              ln -sf ${pkgs.zlib}/lib/libz.so.1 lib64/libz.so.1
              
              mkdir -p usr/lib64
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 usr/lib64/libstdc++.so.6
              ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libgcc_s.so.1 usr/lib64/libgcc_s.so.1
              ln -sf ${pkgs.zlib}/lib/libz.so.1 usr/lib64/libz.so.1

              # Create dummy os-release for GitHub Actions compatibility
              cat > etc/os-release <<EOF
              NAME=NixOS
              ID=nixos
              VERSION="25.11"
              VERSION_CODENAME=nixos
              PRETTY_NAME="NixOS 25.11 (CI Runner)"
              EOF
              # Remove leading whitespace
              sed -i 's/^[[:space:]]*//' etc/os-release

              # Nix configuration: enable flakes and nix-command
              cat > etc/nix/nix.conf <<'EOF'
              experimental-features = nix-command flakes
              sandbox = false
              filter-syscalls = false
              EOF
              # Remove leading whitespace from heredoc
              sed -i 's/^[[:space:]]*//' etc/nix/nix.conf
            '';

            fakeRootCommands = ''
              # Set ownership for runner home directory
              chown -R 1000:1000 home/runner
              chown -R 1000:1000 nix/var/nix/profiles/per-user/runner
              chown -R 1000:1000 nix/var/nix/gcroots/per-user/runner
            '';

            config = {
              Env = [
                "PATH=${pathString}:/usr/bin:/bin"
                "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
                "NIX_PATH=nixpkgs=${nixpkgs}"
                "HOME=/home/runner"
                "USER=runner"
                "NIX_LD=${pkgs.nix-ld}/libexec/nix-ld"
                "NIX_LD_LIBRARY_PATH=${ldLibraryPath}"
              ];
              WorkingDir = "/home/runner/_work";
              User = "1000:1000";
              Volumes = {
                "/home/runner/_work" = { };
                "/tmp" = { };
              };
            };
          };
        }
      );
    };
}
