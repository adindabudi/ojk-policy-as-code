## What changes

<!-- One or two sentences. For control changes, name the OJK group (OJK-01 to OJK-09) and the checklist row. -->

## Type of change

- [ ] Control content (mapping, custom policy, effect defaults, exemptions)
- [ ] Deployment templates (Terraform or Bicep)
- [ ] Evidence queries
- [ ] Documentation only

## Checks

- [ ] `python scripts/validate_mapping.py` passes against live built-ins (0 errors), or I explain why below
- [ ] `terraform fmt -recursive` and `terraform validate` pass for both Terraform folders
- [ ] Bicep files build and lint without warnings
- [ ] Terraform and Bicep stay in step: the same change is in both, and in `main.mg.bicep` and `main.sub.bicep`
- [ ] README counts, `CHANGELOG.md` and the initiative `metadata.version` in the mapping are updated when controls change
- [ ] No real tenant, subscription or management group IDs, resource names, emails or approval letter numbers

## Notes for reviewers

<!-- Effects that move to Deny, new preview built-ins, or anything that needs a compliance team review. -->
