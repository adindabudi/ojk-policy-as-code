# Changelog

All notable changes to this sample. The version matches `initiative.metadata.version` in [`mapping/ojk-policy-mapping.json`](mapping/ojk-policy-mapping.json), so you can match an initiative in Azure to a release.

## 1.2.0 (2026-11-04)

### Fixed

- **Bicep deployment of the initiative failed** with `UnusedPolicyParameters`. The `for` loop compiled to an ARM copy loop, which evaluated each member's `[parameters('...')]` value again against the template's own parameters. The templates now build the member list with `map()`.
- **Provider versions.** The Terraform module needs azurerm 5.0.0 or later and the demo lab needs 5.5.0 or later, but `versions.tf` also allowed 4.x. The version ranges are corrected.

### Added

- Every built-in in the mapping is pinned to its major version (`definitionVersion`, for example `2.*.*`). A new major version of a built-in is now a reviewed change instead of arriving with the next deployment.
- `scripts/validate_mapping.py`: `--offline` mode for pull request checks, and checks of the version pins with a warning when a newer major version is published. It also checks the checklist CSV, and that the counts in README match the mapping.
- GitHub Actions workflow `validate.yml`: Terraform `fmt`, `validate` and TFLint, Bicep build and lint, and the offline mapping check on every pull request. An optional job checks the live built-ins and runs `terraform plan` when OpenID Connect (OIDC) to Azure is set up. Actions are pinned to commit SHAs, and Dependabot keeps them current.
- `.terraform.lock.hcl` for both Terraform folders, with checksums for Linux, Windows and macOS.
- Bicep exemption template: `enforcementMode` parameter for the narrower AI assignment, like `enforce` in Terraform.
- README: position against Azure landing zones, prerequisites and permissions, remote state, and day-2 operations.
- Repository files: MIT license, security policy with private reporting through GitHub, code of conduct (Contributor Covenant 3.0), contributing guide, support, changelog, code owners, and issue and pull request templates.

### Changed

- `queries/server-evidence.kql`: October 2026 builds, and *No data* instead of an empty value when a server has no machine configuration result.
- `queries/offshore-placements.kql`: also lists resource groups in regions that aren't approved, and AI deployments outside the narrower AI assignment of an approved placement.
- Built-in definitions verified on 2026-11-04.

## 1.1.0 (2026-10-01)

- First public version: the OJK FSI Checklist (March 2026) as one Azure Policy initiative for Azure and Azure Arc. It includes Terraform and Bicep templates, evidence queries, a demo lab, and offshore placements recorded as exemptions.
