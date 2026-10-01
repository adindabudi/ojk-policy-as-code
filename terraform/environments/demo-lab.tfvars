# Demo lab: assigns the initiative to the lab resource groups created by examples/demo-lab.
# Run: terraform apply -var-file=environments/demo-lab.tfvars -var="subscription_id=<lab subscription id>"
scope_type           = "resource_group"
resource_group_names = ["rg-ojkdemo-idc", "rg-ojkdemo-sea-approved"]
assignment_name      = "ojk-checklist-202603"
location             = "indonesiacentral"

list_of_allowed_locations = ["indonesiacentral"]

# Phase 1: report only.
effect_data_location        = "Audit"
effect_preventive           = "Audit"
effect_detective            = "AuditIfNotExists"
effect_kubernetes           = "Audit"
effect_customer_managed_key = "Audit"
effect_resilience           = "Audit"
include_arc_machines        = "true"

# Record OJK-approved offshore placements here before you move effect_data_location to Deny.
offshore_exemptions = {}