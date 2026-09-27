{
  description = "Apache Superset, packaged for Nix from its own locked dependency set";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      # The lock pins the versions upstream tests against, and for those PyPI
      # has wheels. Preferring sdists would mean compiling pyarrow 18, numpy
      # 1.26 and pandas 2.1 from source - versions nixpkgs no longer carries,
      # against a toolchain three years newer than they were written for.
      overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

      # Everything the generic wheel/sdist builders cannot know on their own.
      pyprojectOverrides = import ./overrides.nix;

      mkPythonSet =
        pkgs:
        (pkgs.callPackage pyproject-nix.build.packages { python = pkgs.python311; }).overrideScope (
          lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay
            (pyprojectOverrides { inherit (pkgs) lib stdenv; inherit pkgs; })
          ]
        );

      # One venv holding superset and its closure. `superset`, `gunicorn` and
      # `celery` all end up on its bin, which is what the NixOS units call.
      mkSuperset =
        pkgs:
        (mkPythonSet pkgs).mkVirtualEnv "apache-superset-env" workspace.deps.default;
    in
    {
      packages = forAllSystems (pkgs: rec {
        apache-superset = mkSuperset pkgs;
        default = apache-superset;
      });

      overlays.default = final: _prev: { apache-superset = mkSuperset final; };

      # `nix run` gives the CLI, so `superset db upgrade` and friends can be
      # tried without a NixOS host in the loop.
      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${mkSuperset pkgs}/bin/superset";
        };
        # Re-reads requirements/base.txt for whatever version pyproject.toml
        # now pins and rewrites the constraint list from it. Needs the network;
        # the build does not.
        update-pins = {
          type = "app";
          program = "${pkgs.writers.writePython3Bin "update-pins" { } (builtins.readFile ./update-pins.py)}/bin/update-pins";
        };
      });

      devShells = forAllSystems (pkgs: {
        # Only for regenerating uv.lock; the build itself needs no network.
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.uv
            pkgs.python311
          ];
          env.UV_PYTHON_DOWNLOADS = "never";
          env.UV_PYTHON = pkgs.python311.interpreter;
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
