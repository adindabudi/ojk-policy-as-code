#!/usr/bin/env python3
"""Validate mapping/ojk-policy-mapping.json against live Azure Policy built-in definitions.

Usage:
  python scripts/validate_mapping.py                      # calls: az policy definition list
  python scripts/validate_mapping.py --definitions defs.json
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPPING = ROOT / "mapping" / "ojk-policy-mapping.json"
CUSTOM_DIR = ROOT / "policies"
PARAM_REF = re.compile(r"^\[parameters\('([^']+)'\)\]$")
ARC_MARKERS = ("Microsoft.HybridCompute", "Microsoft.Kubernetes/connectedClusters", "Microsoft.AzureArcData")


def load_builtins(path):
    if path:
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    else:
        out = subprocess.run(
            'az policy definition list --query "[?policyType==\'BuiltIn\']" -o json',
            shell=True, capture_output=True, text=True, encoding="utf-8", check=True,
        ).stdout
        data = json.loads(out)
    return {d["name"]: d for d in data if d.get("policyType") == "BuiltIn"}


def load_customs():
    customs = {}
    for f in CUSTOM_DIR.glob("*.json"):
        d = json.loads(f.read_text(encoding="utf-8"))
        props = d["properties"]
        customs[d["name"]] = {"name": d["name"], "displayName": props["displayName"], "mode": props["mode"],
                              "parameters": props.get("parameters", {}), "policyRule": props["policyRule"],
                              "metadata": props.get("metadata", {})}
    return customs


def applies_to_arc(definition):
    if definition.get("mode") == "Microsoft.Kubernetes.Data":
        return True
    rule = json.dumps(definition.get("policyRule"))
    return any(m in rule for m in ARC_MARKERS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--definitions", help="JSON file from: az policy definition list -o json")
    args = ap.parse_args()

    mapping = json.loads(MAPPING.read_text(encoding="utf-8"))
    builtins = load_builtins(args.definitions)
    customs = load_customs()
    init_params = mapping["initiative"]["parameters"]
    group_names = [g["name"] for g in mapping["groups"]]
    errors, warnings = [], []
    used_params, seen_refs = set(), set()
    per_group = {g: [0, 0] for g in group_names}

    for m in mapping["members"]:
        ref = m["referenceId"]
        if ref in seen_refs:
            errors.append(f"{ref}: duplicate referenceId")
        seen_refs.add(ref)
        for g in m["groups"]:
            if g not in per_group:
                errors.append(f"{ref}: unknown group {g}")

        def_id = m["definitionId"]
        if def_id.startswith("custom:"):
            definition = customs.get(def_id.split(":", 1)[1])
            if not definition:
                errors.append(f"{ref}: custom definition {def_id} not found in policies/")
                continue
        else:
            definition = builtins.get(def_id)
            if not definition:
                errors.append(f"{ref}: built-in {def_id} not found")
                continue
            meta = definition.get("metadata") or {}
            if meta.get("deprecated"):
                errors.append(f"{ref}: {def_id} is deprecated")
            if meta.get("preview"):
                warnings.append(f"{ref}: {def_id} is preview")
        if definition.get("displayName") != m.get("displayName"):
            warnings.append(f"{ref}: displayName differs, live='{definition.get('displayName')}'")

        arc = applies_to_arc(definition)
        if arc != bool(m.get("appliesToArc")) and not m.get("arcVia"):
            warnings.append(f"{ref}: appliesToArc={m.get('appliesToArc')} but rule analysis says {arc}")
        for g in m["groups"]:
            if g in per_group:
                per_group[g][0] += 1
                per_group[g][1] += int(bool(m.get("appliesToArc")))

        dparams = definition.get("parameters") or {}
        supplied = m.get("parameters") or {}
        for pname, pdef in dparams.items():
            if "defaultValue" not in pdef and pname not in supplied:
                errors.append(f"{ref}: required parameter '{pname}' not supplied")
        for pname, pval in supplied.items():
            if pname not in dparams:
                errors.append(f"{ref}: parameter '{pname}' is not defined by {def_id}")
                continue
            pdef = dparams[pname]
            allowed = pdef.get("allowedValues")
            value = pval.get("value")
            match = PARAM_REF.match(value) if isinstance(value, str) else None
            if match:
                iname = match.group(1)
                used_params.add(iname)
                ip = init_params.get(iname)
                if not ip:
                    errors.append(f"{ref}: initiative parameter '{iname}' is not defined")
                    continue
                if ip["type"].lower() != pdef.get("type", "").lower():
                    errors.append(f"{ref}: type mismatch {iname}={ip['type']} vs {pname}={pdef.get('type')}")
                if allowed:
                    iallowed = ip.get("allowedValues")
                    if not iallowed:
                        errors.append(f"{ref}: '{iname}' has no allowedValues but '{pname}' is restricted to {allowed}")
                    else:
                        extra = [v for v in iallowed if v not in allowed]
                        if extra:
                            errors.append(f"{ref}: '{iname}' allows {extra}, not accepted by '{pname}' {allowed}")
            elif allowed and value not in allowed:
                errors.append(f"{ref}: value {value!r} for '{pname}' not in {allowed}")

    for iname in init_params:
        if iname not in used_params:
            warnings.append(f"initiative parameter '{iname}' is not used by any member")
    for g, (count, _) in per_group.items():
        if count == 0:
            warnings.append(f"group {g} has no members")

    print(f"Members: {len(mapping['members'])} | groups: {len(group_names)} | "
          f"Arc-applicable: {sum(1 for m in mapping['members'] if m.get('appliesToArc'))}")
    for g, (count, arc) in per_group.items():
        print(f"  {g:<28} policies={count:>2}  arc={arc:>2}")
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"Result: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
