# Contributing

This project welcomes contributions and suggestions: better built-in policies for a control, fixes to the templates or queries, and corrections to the checklist mapping.

## Before you start

- Open an issue first for a new control or a change of effect, so the mapping can be discussed before you write code.
- Don't commit real tenant, subscription or management group IDs, resource names, emails or OJK approval letter numbers. Use placeholders such as `<subscription-id>` instead.

## Make a change

1. **Start with the mapping.** `mapping/ojk-policy-mapping.json` is the single source for both Terraform and Bicep. For a built-in, add `definitionVersion` with its current major version, for example `2.*.*`, or `1.*.*-preview` for a preview built-in. Every member needs exactly one OJK group.
2. **Keep the templates in step.** A change in `terraform/` needs the same change in `bicep/main.mg.bicep` and `bicep/main.sub.bicep`, and the other way around. The two Bicep files differ only in scope, assignment name length and descriptions.
3. **Keep `map()` in the Bicep initiative.** Don't turn `policyDefinitions` into a `for` loop. A loop compiles to an ARM copy loop that evaluates the members' `[parameters('...')]` values a second time, and the deployment then fails with `UnusedPolicyParameters`.
4. **Update the documentation.** The counts in README sit between `counts:<name>:start` and `counts:<name>:end` markers, and `validate_mapping.py` checks them against the mapping. When controls change, add an entry to `CHANGELOG.md` and raise `initiative.metadata.version` in the mapping.

## Run the checks

```bash
python scripts/validate_mapping.py --offline          # no Azure access needed
python scripts/validate_mapping.py                    # live built-ins, needs: az login
terraform fmt -recursive
terraform -chdir=terraform init -backend=false && terraform -chdir=terraform validate
terraform -chdir=examples/demo-lab/terraform init -backend=false && terraform -chdir=examples/demo-lab/terraform validate
tflint --init --config "$(pwd)/.tflint.hcl" && tflint --recursive --config "$(pwd)/.tflint.hcl"
az bicep build --file bicep/main.mg.bicep && az bicep lint --file bicep/main.mg.bicep
```

The `validate` workflow runs the same checks on every pull request. A change that moves an effect to `Deny`, adds a preview built-in, or changes the checklist mapping also needs a test deployment at resource group scope in a non-production subscription. Describe what you tested in the pull request.
