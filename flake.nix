{
  description = "fannkuch-redux Go/Rust/C benchmark dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { nixpkgs, rust-overlay, ... }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          inherit (pkgs) lib stdenv;

          rustToolchain = pkgs.rust-bin.stable.latest.minimal.override {
            # The fetched Rust/C benchmarksgame programs are x86_64 SIMD
            # programs. On Apple Silicon, bench.sh cross-builds x86_64 and
            # runs via Rosetta, so include the x86_64 Darwin stdlib here.
            targets = lib.optionals (system == "aarch64-darwin") [
              "x86_64-apple-darwin"
            ];
          };
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.go
              rustToolchain
              pkgs.hyperfine
              pkgs.git
            ] ++ lib.optionals stdenv.isLinux [
              pkgs.clang
              pkgs.lld
              pkgs.llvmPackages.llvm
            ];

            shellHook = ''
              echo "fannkuch benchmark shell"
              echo "  Go:    $(go version 2>/dev/null || echo missing)"
              echo "  Rust:  $(rustc --version 2>/dev/null || echo missing)"
              echo "  Bench: ./bench.sh 12"

              case "$(uname -s)-$(uname -m)" in
                Darwin-arm64|Darwin-x86_64)
                  # Prefer Apple's universal linker for -arch x86_64 builds.
                  export CC=/usr/bin/clang
                  ;;
                Linux-x86_64)
                  export CC=clang
                  ;;
              esac
            '';
          };
        });
    };
}
