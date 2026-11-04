output "custom_definition_id" {
  description = "Resource ID of the custom policy ojk-ai-approved-deployment-types. The Bicep exemption template needs it as aiPolicyDefinitionId."
  value       = azurerm_policy_definition.ai_deployment_types.id
}

output "initiative_id" {
  description = "Resource ID of the OJK initiative (policy set definition)."
  value       = local.initiative_id
}

output "assignment_id" {
  description = "Initiative assignment for management_group or subscription scope. Null for resource_group scope; use assignment_ids."
  value       = local.assignment_id
}

output "assignment_ids" {
  description = "Initiative assignments keyed by scope (management_group, subscription or resource group name)."
  value       = local.assignment_ids
}

output "assignment_principal_ids" {
  description = "Managed identities of the assignments. Grant roles only if you later add DeployIfNotExists or Modify remediation."
  value       = local.principal_ids
}

output "offshore_exemption_ids" {
  description = "Policy exemptions for approved offshore placements, keyed like offshore_exemptions."
  value       = { for key, e in azurerm_resource_group_policy_exemption.offshore : key => e.id }
}

output "offshore_ai_assignment_ids" {
  description = "Narrower AI deployment type assignments for approved offshore placements, keyed like offshore_exemptions."
  value       = { for key, a in azurerm_resource_group_policy_assignment.offshore_ai : key => a.id }
}
