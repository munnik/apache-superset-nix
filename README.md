# apache-superset-nix

[Apache Superset](https://superset.apache.org/) as a Nix flake.

Superset is not in nixpkgs, and it cannot easily be: it pins SQLAlchemy 1.4,
marshmallow 3, pandas 2.1, numpy < 2.3, pyarrow < 19 and msgpack < 1.1, where
nixpkgs 26.05 carries 2.0, 4.2, 2.3, 2.4, 23 and 1.1. Overriding that many
`python3Packages` by hand is how a Superset derivation ends up unbuildable a
release later.

So this flake does not fight nixpkgs' versions. `pyproject.toml` asks for
`apache-superset[postgres]==6.1.0` and nothing else, `uv.lock` pins the 157
packages that resolves to — the same versions upstream tests against — and
[uv2nix](https://github.com/pyproject-nix/uv2nix) builds that set into one
virtualenv. No Docker, no `pip install` at activation time, no network access
during the build.

## Use it

```nix
{
  inputs.apache-superset.url = "github:munnik/apache-superset-nix";

  # then either
  nixpkgs.overlays = [ inputs.apache-superset.overlays.default ];  # -> pkgs.apache-superset
  # or reach for it directly
  environment.systemPackages = [ inputs.apache-superset.packages.x86_64-linux.default ];
}
```

The result is a virtualenv whose `bin/` holds `superset`, `gunicorn` and
`celery` — enough to run the webserver, the CLI and a worker:

```console
$ nix run github:munnik/apache-superset-nix -- version
```

Superset refuses to start until `SECRET_KEY` is set, so point
`SUPERSET_CONFIG_PATH` at a `superset_config.py` of your own first.

## Bumping Superset

```console
$ nix develop           # brings uv and the right python
$ $EDITOR pyproject.toml   # change the == pin
$ uv lock
$ nix build .#apache-superset
```

`uv lock` needs the network; the build never does. If a newly locked sdist has
no declared build backend the build fails with `No module named 'setuptools'` —
add the package to the list in `overrides.nix`.

## Deliberate choices

- **`sourcePreference = "wheel"`.** The pinned versions are old enough that
  their sdists no longer compile against a current toolchain, and PyPI's wheels
  are what upstream ships and tests. Wheels are patched for the Nix store by
  pyproject.nix's `autoPatchelf` hooks.
- **Python 3.11, pinned to one minor** (`requires-python = ">=3.11,<3.12"`), so
  the lock resolves exactly one wheel per package instead of a range.
- **`rich` is added explicitly.** `superset/cli/test_db.py` imports it
  unconditionally while 6.1 declares it only under the `development` extra, so
  without it `superset --help` cannot build its command tree.

## Licence

This packaging is Apache-2.0, matching Superset itself. It only builds Superset;
it carries none of its code.
