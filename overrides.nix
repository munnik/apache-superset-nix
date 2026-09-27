# Per-package fixups on top of the generated overlay.
#
# uv2nix's generic builders handle a wheel or an sdist that declares its build
# system properly. What is left is: sdists whose build backend is implied rather
# than declared (a setup.py and no [build-system]), and wheels carrying binaries
# that need something from nixpkgs at runtime.
{
  lib,
  pkgs,
  ...
}:
final: prev:
let
  # PEP 517 says a project with no [build-system] is built with setuptools, but
  # the lock cannot say so, so the builder has to be told per package.
  withBuildSystems =
    names: attrs:
    lib.genAttrs names (
      name:
      prev.${name}.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ attrs;
      })
    );
in
withBuildSystems [
  # Sdist-only, legacy setup.py, no declared backend.
  "pgsanity"
  "wtforms-json"
  "python-geohash"
  # Pulled in by pandas[excel], for reading ODF spreadsheets.
  "odfpy"
] (with final; [ setuptools ])
// {
  # The wheel links against libstdc++ for the Arrow C++ core.
  pyarrow = prev.pyarrow.overrideAttrs (old: {
    autoPatchelfIgnoreMissingDeps = true;
    buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.stdenv.cc.cc.lib ];
  });

  # psycopg2-binary bundles its own libpq and libssl; autoPatchelf still has to
  # be able to find a libcrypto to bind the bundled copies against.
  psycopg2-binary = prev.psycopg2-binary.overrideAttrs (old: {
    buildInputs = (old.buildInputs or [ ]) ++ [
      pkgs.openssl
      pkgs.krb5
    ];
  });
}
