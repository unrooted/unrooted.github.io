{
  description = "unrooted's blog — Hugo + Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        hugo = pkgs.hugo;
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "unrooted-blog";
          version =
            if self ? rev then builtins.substring 0 7 self.rev else "dirty";
          src = self;
          nativeBuildInputs = [ hugo pkgs.dart-sass pkgs.go ];
          buildPhase = ''
            runHook preBuild
            export HUGO_CACHEDIR="$TMPDIR/hugo-cache"
            hugo --minify --gc --destination "$out"
            runHook postBuild
          '';
          dontInstall = true;
        };

        packages.site = self.packages.${system}.default;

        devShells.default = pkgs.mkShell {
          packages = [ hugo pkgs.dart-sass pkgs.go pkgs.nixpkgs-fmt ];
        };

        apps.serve = {
          type = "app";
          program = toString (pkgs.writeShellScript "serve" ''
            exec ${hugo}/bin/hugo server -D --bind 0.0.0.0 \
              --noBuildLock --renderToMemory "$@"
          '');
        };

        apps.update-theme = {
          type = "app";
          program = toString (pkgs.writeShellScript "update-theme" ''
            export PATH=${pkgs.lib.makeBinPath [ hugo pkgs.go pkgs.git ]}:$PATH
            hugo mod get -u
            hugo mod vendor
          '');
        };

        formatter = pkgs.nixpkgs-fmt;
      });
}
