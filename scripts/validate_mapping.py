#!/usr/bin/env python3
"""Validate the OJK policy mapping before you deploy it.

Always checks mapping/ojk-policy-mapping.json, the custom definitions in policies/, mapping/checklist-coverage.csv
and the counts that README.md shows between <!-- counts:... --> markers.

Without --offline it also checks every built-in against the live Azure Policy definitions: the ID exists, the
pinned major version (definitionVersion) exists, deprecated and preview state, parameters and allowed values.

Usage:
  python scripts/validate_mapping.py                          # live check, needs: az login
  python scripts/validate_mapping.py --offline                # no Azure access, for pull request checks
  python scripts/validate_mapping.py --definitions defs.json  # live check from a saved list:
                                                              #   az policy definition list -o json > defs.json
Exit code 1 means at least one error.
"""
import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAPPING = ROOT / "mapping" / "ojk-policy-mapping.json"
COVERAGE = ROOT / "mapping" / "checklist-coverage.csv"
README = ROOT / "README.md"
CUSTOM_DIR = ROOT / "policies"
API_VERSION = "2025-11-01"
PARAM_REF = re.compile(r"^\[parameters\('([^']+)'\)\]$")
VERSION_PIN = re.compile(r"^(\d+)\.\*\.\*(-preview)?$")
ARC_MARKERS = ("Microsoft.HybridCompute", "Microsoft.Kubernetes/connectedClusters", "Microsoft.AzureArcData")
COVERAGE_CATEGORIES = ("Policy - direct", "Policy - partial", "Contract", "Bank process",
                       "Microsoft evidence (STP)", "Not applicable")


def az_json(command):
    proc = subprocess.run(command, shell=True, capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        raise RuntimeError(f"'{command}' failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout or "null")


def load_builtins(path):
    if path:
        data = json.loads(Path(path).read_text(encoding="utf-8-sig"))
    else:
        data = az_json('az policy definition list --query "[?policyType==\'BuiltIn\']" -o json')
    return {d["name"]: d for d in data if d.get("policyType") == "BuiltIn"}


def load_customs():
    customs = {}
    for f in sorted(CUSTOM_DIR.glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        props = d["properties"]
        customs[d["name"]] = {"name": d["name"], "displayName": props["displayName"], "mode": props["mode"],
                              "parameters": props.get("parameters", {}), "policyRule": props["policyRule"],
                              "metadata": props.get("metadata", {})}
    return customs


def version_key(version):
    return tuple(int(part) for part in version.split("-", 1)[0].split("."))


def is_preview(version):
    return version.endswith("-preview")


def resolve_pin(name, definition, pin, errors, warnings, ref):
    """Returns the definition that a valid pin resolves to, or None when no published version matches."""
    match = VERSION_PIN.match(pin)
    major, preview = int(match.group(1)), bool(match.group(2))
    versions = definition.get("versions") or [definition.get("version")]
    candidates = sorted((v for v in versions if v and version_key(v)[0] == major and is_preview(v) == preview),
                        key=version_key)
    if not candidates:
        errors.append(f"{ref}: no published version of {name} matches {pin} (published: {', '.join(versions)})")
        return None
    latest = definition.get("version") or max(versions, key=version_key)
    if version_key(latest)[0] > major:
        warnings.append(f"{ref}: {name} has a newer major version {latest}; review it, then move the pin")
    if preview and any(version_key(v)[0] == major and not is_preview(v) for v in versions):
        warnings.append(f"{ref}: {name} has a GA version in major {major}; consider pinning {major}.*.*")
    resolved = candidates[-1]
    if resolved == definition.get("version"):
        return definition
    url = (f"https://management.azure.com/providers/Microsoft.Authorization/policyDefinitions/{name}"
           f"/versions/{resolved}?api-version={API_VERSION}")
    props = az_json(f'az rest --method get --url "{url}"')["properties"]
    return {"displayName": props.get("displayName"), "mode": props.get("mode"), "metadata": props.get("metadata"),
            "parameters": props.get("parameters"), "policyRule": props.get("policyRule"), "version": resolved}


def applies_to_arc(definition):
    if definition.get("mode") == "Microsoft.Kubernetes.Data":
        return True
    rule = json.dumps(definition.get("policyRule"))
    return any(m in rule for m in ARC_MARKERS)


def check_parameters(ref, def_id, definition, supplied, init_params, used_params, errors):
    dparams = definition.get("parameters") or {}
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


def check_coverage(group_names, errors):
    rows = list(csv.DictReader(COVERAGE.open(encoding="utf-8", newline="")))
    seen, counts = set(), {c: 0 for c in COVERAGE_CATEGORIES}
    prefixes = {g[:6] for g in group_names}
    for row in rows:
        rid = row["id"]
        if rid in seen:
            errors.append(f"coverage {rid}: duplicate id")
        seen.add(rid)
        if row["coverage"] not in counts:
            errors.append(f"coverage {rid}: unknown category '{row['coverage']}'")
        else:
            counts[row["coverage"]] += 1
        for token in re.findall(r"OJK-\d\d", row["policy_groups"]):
            if token not in prefixes:
                errors.append(f"coverage {rid}: unknown policy group {token}")
    return rows, counts


def readme_block(text, name):
    match = re.search(rf"<!-- counts:{name}:start -->(.*?)<!-- counts:{name}:end -->", text, re.S)
    return match.group(1) if match else None


def check_readme(mapping, per_group, coverage_rows, coverage_counts, errors, warnings):
    text = README.read_text(encoding="utf-8")
    members = mapping["members"]
    custom = sum(1 for m in members if m["definitionId"].startswith("custom:"))
    expected = {"policies": len(members), "builtin": len(members) - custom, "custom": custom,
                "groups": len(mapping["groups"]), "arc": sum(1 for m in members if m.get("appliesToArc"))}

    block = readme_block(text, "summary")
    found = re.search(r"\*\*(\d+) policy\*\* \((\d+) built-in dan (\d+) custom\) dalam \*\*(\d+) grup kontrol\*\*\. "
                      r"\*\*(\d+) policy\*\*", block or "")
    if not found:
        warnings.append("README: policy count sentence not found between counts:summary markers")
    else:
        actual = dict(zip(expected, map(int, found.groups())))
        for key, value in expected.items():
            if actual[key] != value:
                errors.append(f"README: {key} count says {actual[key]}, mapping has {value}")

    block = readme_block(text, "groups")
    rows = re.findall(r"^\| (OJK-\d\d) [^|]*\| *(\d+) *\| *(\d+) *\|", block or "", re.M)
    if not rows:
        warnings.append("README: control group table not found between counts:groups markers")
    by_prefix = {g[:6]: counts for g, counts in per_group.items()}
    for prefix, policies, arc in rows:
        if prefix not in by_prefix:
            errors.append(f"README: group {prefix} is not in the mapping")
        elif [int(policies), int(arc)] != by_prefix[prefix]:
            errors.append(f"README: {prefix} says {policies} policies / {arc} Arc, mapping has "
                          f"{by_prefix[prefix][0]} / {by_prefix[prefix][1]}")

    block = readme_block(text, "coverage")
    rows = re.findall(r"^\| ([^|]+?) *\| *\**(\d+)\** *\|", block or "", re.M)
    if not rows:
        warnings.append("README: checklist coverage table not found between counts:coverage markers")
    labels = {"Policy - direct": "Policy - direct", "Policy - partial": "Policy - partial",
              "Contract": "Contract", "Bank process": "Bank process",
              "Microsoft evidence": "Microsoft evidence (STP)", "Not applicable": "Not applicable"}
    for label, value in rows:
        label = label.strip().strip("*")
        if label == "Total":
            if int(value) != len(coverage_rows):
                errors.append(f"README: coverage total says {value}, CSV has {len(coverage_rows)} rows")
            continue
        key = next((v for k, v in labels.items() if label.startswith(k)), None)
        if key and int(value) != coverage_counts[key]:
            errors.append(f"README: coverage '{key}' says {value}, CSV has {coverage_counts[key]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--offline", action="store_true", help="skip the live built-in checks (no Azure access)")
    mode.add_argument("--definitions", help="JSON file from: az policy definition list -o json")
    args = ap.parse_args()

    mapping = json.loads(MAPPING.read_text(encoding="utf-8"))
    builtins = {} if args.offline else load_builtins(args.definitions)
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
            if g in per_group:
                per_group[g][0] += 1
                per_group[g][1] += int(bool(m.get("appliesToArc")))
            else:
                errors.append(f"{ref}: unknown group {g}")
        supplied = m.get("parameters") or {}
        for iname in re.findall(r"\[parameters\('([^']+)'\)\]", json.dumps(supplied)):
            used_params.add(iname)
            if iname not in init_params:
                errors.append(f"{ref}: initiative parameter '{iname}' is not defined")

        def_id = m["definitionId"]
        if def_id.startswith("custom:"):
            definition = customs.get(def_id.split(":", 1)[1])
            if not definition:
                errors.append(f"{ref}: custom definition {def_id} not found in policies/")
                continue
            if "definitionVersion" in m:
                errors.append(f"{ref}: definitionVersion is only for built-ins")
        else:
            if not VERSION_PIN.match(m.get("definitionVersion") or ""):
                errors.append(f"{ref}: built-in needs definitionVersion like 2.*.* or 1.*.*-preview, "
                              f"found {m.get('definitionVersion')!r}")
                continue
            if args.offline:
                continue
            live = builtins.get(def_id)
            if not live:
                errors.append(f"{ref}: built-in {def_id} not found")
                continue
            definition = resolve_pin(def_id, live, m.get("definitionVersion"), errors, warnings, ref)
            if not definition:
                continue
            meta = definition.get("metadata") or {}
            if meta.get("deprecated"):
                errors.append(f"{ref}: {def_id} {definition.get('version')} is deprecated")
            if meta.get("preview") or is_preview(definition.get("version") or ""):
                warnings.append(f"{ref}: {def_id} is preview")
        if definition.get("displayName") != m.get("displayName"):
            warnings.append(f"{ref}: displayName differs, live='{definition.get('displayName')}'")
        arc = applies_to_arc(definition)
        if arc != bool(m.get("appliesToArc")) and not m.get("arcVia"):
            warnings.append(f"{ref}: appliesToArc={m.get('appliesToArc')} but rule analysis says {arc}")
        check_parameters(ref, def_id, definition, supplied, init_params, used_params, errors)

    for iname in init_params:
        if iname not in used_params:
            warnings.append(f"initiative parameter '{iname}' is not used by any member")
    for g, (count, _) in per_group.items():
        if count == 0:
            warnings.append(f"group {g} has no members")

    coverage_rows, coverage_counts = check_coverage(group_names, errors)
    check_readme(mapping, per_group, coverage_rows, coverage_counts, errors, warnings)

    mode_label = "offline (structure only)" if args.offline else "live built-in definitions"
    print(f"Mode: {mode_label}")
    print(f"Members: {len(mapping['members'])} | groups: {len(group_names)} | "
          f"Arc-applicable: {sum(1 for m in mapping['members'] if m.get('appliesToArc'))} | "
          f"checklist rows: {len(coverage_rows)}")
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
