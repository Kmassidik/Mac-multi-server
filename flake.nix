{
  description = "Mac-multi-server — 1-click VPS platform on Apple Silicon (Tart + Cloudflare)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        # `nix develop` → all the CLI tooling the platform uses, without polluting the system.
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            cloudflared   # tunnel / ingress
            sshpass       # first-login key injection into new VPS
            jq            # JSON in scripts
            curl
            git
          ];
          shellHook = ''
            echo "mac-multi-server devShell ready (cloudflared, sshpass, jq via Nix)."
            echo "Not via Nix (macOS-specific): Tart → 'brew install cirruslabs/cli/tart';"
            echo "                              Swift → system toolchain (Xcode CLT)."
          '';
        };
      });
}
