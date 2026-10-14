#!/usr/bin/env python3
"""Validate deployments/*.yaml against the schema plus cross-file rules.
Usage: pip install pyyaml jsonschema && python scripts/validate_deployments.py
"""
import json
import pathlib
import sys

import yaml
from jsonschema import Draft202012Validator

ROOT = pathlib.Path(__file__).resolve().parent.parent
validator = Draft202012Validator(json.loads((ROOT / "schema/deployment.schema.json").read_text()))

errors, prefixes, names = [], {}, {}
files = sorted((ROOT / "deployments").glob("*.yaml"))

for f in files:
    try:
        doc = yaml.safe_load(f.read_text())
    except yaml.YAMLError as exc:
        errors.append(f"{f.name}: invalid YAML: {exc}")
        continue

    schema_errors = sorted(validator.iter_errors(doc), key=lambda e: list(e.path))
    for err in schema_errors:
        loc = "/".join(str(p) for p in err.path) or "<root>"
        errors.append(f"{f.name}: {loc}: {err.message}")
    if schema_errors or not isinstance(doc, dict):
        continue

    for key, registry in (("path_prefix", prefixes), ("name", names)):
        if doc[key] in registry:
            errors.append(f"{f.name}: duplicate {key} '{doc[key]}' (also in {registry[doc[key]]})")
        registry.setdefault(doc[key], f.name)

    seen = set()
    for route in doc["routes"]:
        for method in route["methods"]:
            if (route["path"], method) in seen:
                errors.append(f"{f.name}: duplicate route {method} {route['path']}")
            seen.add((route["path"], method))
        if ("scopes" in route or route.get("anonymous")) and "auth" not in doc:
            errors.append(f"{f.name}: route {route['path']} uses scopes/anonymous but deployment has no `auth`")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"OK: {len(files)} deployment file(s) valid")
