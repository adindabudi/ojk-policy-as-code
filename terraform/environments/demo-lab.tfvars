# Demo lab: assigns the initiative to the lab resource groups created by examples/demo-lab.
# Run: terraform apply -var-file=environments/demo-lab.tfvars -var="subscription_id=<lab subscription id>"
scope_type           = "resource_group"
resource_group_names = ["rg-ojkdemo-idc", "rg-ojkdemo-sea-approved"]
assignment_name      = "ojk-checklist-202603"
location             = "indonesiacentral"

list_of_allowed_locations = ["indonesiacentral"]

# Location and AI deployment type controls are enforced. Everything else stays in report mode.
effect_data_location        = "Deny"
effect_preventive           = "Audit"
effect_detective            = "AuditIfNotExists"
effect_kubernetes           = "Audit"
effect_customer_managed_key = "Audit"
effect_resilience           = "Audit"
include_arc_machines        = "true"

offshore_exemptions = {
  "ojk-approved-ai-apac" = {
    resource_group_name          = "rg-ojkdemo-sea-approved"
    ojk_approval_reference       = "S-000/PB.000/2026 (example)"
    justification                = "Example only: AI inference in the Asia Pacific data zone for an approved internal use case; re-placement to Indonesia Central when the model is available in-country."
    expires_on                   = "2027-03-31T00:00:00Z"
    approved_ai_deployment_types = ["DataZoneStandard"]
  }
}
