#!/usr/bin/env python3
"""Select an async PHP install for Cargo, clangd and Zed."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
prefix = Path(sys.argv[1]).resolve()
source = Path(sys.argv[2]).resolve()
profile = sys.argv[3]
config = prefix / "bin/php-config"
if not config.is_file() or not all((prefix / name).is_file() for name in ("PHP_COMMIT", "PHP_PROFILE", ".rapira-build-id")):
    sys.exit(f"No async PHP install at {prefix}; run make build-php-{profile}")
installed_profile = (prefix / "PHP_PROFILE").read_text().strip()
if installed_profile != profile:
    sys.exit(f"Async PHP at {prefix} is {installed_profile}; run make build-php-{profile}")
subprocess.run([str(prefix / "bin/php"), "-n", str(root / "scripts/check-php.php")], check=True)
target = root / "target"
target.mkdir(exist_ok=True)
link = target / "php-async"
if link.is_symlink():
    link.unlink()
elif link.exists():
    sys.exit(f"Expected a symlink at {link}")
link.symlink_to(prefix, target_is_directory=True)

# Cargo watches this file so switching profiles invalidates the PHP bindings.
selection = target / "php-async-profile"
value = f"{prefix}\n{(prefix / '.rapira-build-id').read_text()}"
if not selection.exists() or selection.read_text() != value:
    selection.write_text(value)

includes = shlex.split(subprocess.check_output([str(config), "--includes"], text=True))
build = target / "php-build" / profile
# Use the PR checkout for navigation and its generated build headers when available.
if (build / "main/php_config.h").is_file():
    includes = [f"-I{build}", f"-I{build / 'main'}", f"-I{build / 'Zend'}"] + [
        flag.replace(str(prefix / "include/php"), str(source)) for flag in includes
    ] + includes
# Zend headers use GNU C extensions such as typeof.
args = [os.environ.get("CC", "clang"), "-xc", "-std=gnu11", *includes,
        f"-I{root / 'crates/sapi'}"]
commands = []
for path in sorted((root / "crates").rglob("*")):
    if path.suffix not in (".c", ".h"):
        continue
    extra = ["-include", "rapira_sapi.h", "-include", "ext/spl/spl_exceptions.h"] if path.name.endswith("_arginfo.h") else []
    commands.append({"directory": str(root), "file": str(path), "arguments": [*args, *extra, "-c", str(path)]})
database = target / "clangd"
database.mkdir(exist_ok=True)
(database / "compile_commands.json").write_text(json.dumps(commands, indent=2) + "\n")

# Zed terminal settings need absolute paths; generate them for this checkout.
template = root / ".zed/settings.template.json"
if template.is_file():
    settings = json.loads(template.read_text())
    settings["terminal"] = {
        "working_directory": "first_project_directory",
        "env": {
            "PHP_CONFIG": str(root / "scripts/php-config"),
            "LD_LIBRARY_PATH": str(link / "lib"),
            "PATH": str(link / "bin") + os.pathsep + os.environ.get("PATH", os.defpath),
        },
    }
    (root / ".zed/settings.json").write_text(json.dumps(settings, indent=4) + "\n")
print(f"Cargo, clangd and Zed use {prefix} (sources: {source})")
