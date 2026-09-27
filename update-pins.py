"""Refresh requirements/upstream-base.txt and the uv constraints from it.

Superset's dependency ranges are not the versions Superset is tested with, so
the resolver is held to the pins upstream publishes in requirements/base.txt.
After bumping the `apache-superset==` pin in pyproject.toml, run this to fetch
that release's base.txt and flatten it into [tool.uv] constraint-dependencies.
"""

import re
import sys
import tomllib
import urllib.request
from pathlib import Path

# The working directory, not __file__: this runs from the Nix
# store, and what it rewrites is the checkout it was called from.
ROOT = Path.cwd()
PYPROJECT = ROOT / "pyproject.toml"
UPSTREAM = ROOT / "requirements" / "upstream-base.txt"

BEGIN = "constraint-dependencies = [\n"
END = "]\n"


def superset_version() -> str:
    deps = tomllib.loads(PYPROJECT.read_text())["project"]["dependencies"]
    for dep in deps:
        if m := re.match(r"^apache-superset\b.*==\s*([0-9][^\s,]*)", dep):
            return m.group(1)
    sys.exit("no pinned apache-superset== in pyproject.toml dependencies")


def main() -> None:
    if not PYPROJECT.is_file():
        sys.exit(f"no pyproject.toml in {ROOT}; run this from the flake root")
    version = superset_version()
    url = (
        "https://raw.githubusercontent.com/apache/superset/"
        f"{version}/requirements/base.txt"
    )
    print(f"fetching {url}")
    with urllib.request.urlopen(url) as response:  # noqa: S310
        base = response.read().decode()
    if "==" not in base:
        sys.exit(f"{url} does not look like a pinned requirements file")

    UPSTREAM.parent.mkdir(exist_ok=True)
    UPSTREAM.write_text(base)

    pin = re.compile(r"^([A-Za-z0-9._-]+)==([^\s;]+)")
    pins = sorted(
        (
            f"{m.group(1)}=={m.group(2)}"
            for line in base.splitlines()
            if (m := pin.match(line))
        ),
        key=str.lower,
    )
    block = "".join(f'  "{pin}",\n' for pin in pins)

    text = PYPROJECT.read_text()
    start = text.index(BEGIN) + len(BEGIN)
    stop = text.index(END, start)
    PYPROJECT.write_text(text[:start] + block + text[stop:])

    print(
        f"{len(pins)} constraints written for Superset {version}; "
        "now run `uv lock`"
    )


if __name__ == "__main__":
    main()
