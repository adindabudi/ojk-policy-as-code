# OJK-approved or temporary offshore placement (Part 2 B-II #9, POJK 11/2022 Art. 35(2) and 36(1)(j)).
# The exemption waives only the location controls and carries the OJK approval reference in metadata.
# AI deployment types are not waived by default: list the approved types to give the resource group a
# narrower AI policy assignment, so types outside the approval (for example Global*) stay blocked.
locals {
  location_reference_ids = ["dl-allowed-locations", "dl-allowed-rg-locations"]

  offshore_targets = {
    for key, e in var.offshore_exemptions : key => {
      rg_id                        = coalesce(e.resource_group_id, "/subscriptions/${var.subscription_id}/resourceGroups/${coalesce(e.resource_group_name, "-")}")
      ojk_approval_reference       = e.ojk_approval_reference
      justification                = e.justification
      expires_on                   = e.expires_on
      approved_ai_deployment_types = e.approved_ai_deployment_types
      narrow_ai                    = length(e.approved_ai_deployment_types) > 0
    }
  }
}

resource "terraform_data" "exemption_scope_check" {
  for_each = local.is_rg ? local.offshore_targets : {}

  lifecycle {
    precondition {
      condition     = contains(keys(local.assigned_rg_by_id), lower(each.value.rg_id))
      error_message = "Offshore exemption ${each.key}: with scope_type = resource_group, the resource group must also be listed in resource_group_names."
    }
  }
}

resource "azurerm_resource_group_policy_exemption" "offshore" {
  for_each = local.offshore_targets

  name                 = each.key
  resource_group_id    = each.value.rg_id
  policy_assignment_id = local.is_rg ? try(azurerm_resource_group_policy_assignment.ojk[local.assigned_rg_by_id[lower(each.value.rg_id)]].id, null) : local.assignment_id
  exemption_category   = "Waiver"
  display_name         = "OJK offshore placement - ${each.value.ojk_approval_reference}"
  description          = each.value.justification
  expires_on           = each.value.expires_on

  policy_definition_reference_ids = concat(
    local.location_reference_ids,
    each.value.narrow_ai ? ["dl-ai-deployment-types"] : [],
  )

  metadata = jsonencode({
    ojkApprovalReference      = each.value.ojk_approval_reference
    checklistReference        = "Part 2 B-II #9 / A-I #1"
    approvedAiDeploymentTypes = each.value.approved_ai_deployment_types
  })

  depends_on = [terraform_data.exemption_scope_check]
}

# Narrower AI guardrail for the approved placement. It has no expiry: when the exemption expires,
# the initiative's default list applies again on top of this one, so the stricter list wins.
resource "azurerm_resource_group_policy_assignment" "offshore_ai" {
  for_each = { for key, t in local.offshore_targets : key => t if t.narrow_ai }

  name                 = substr("ojk-ai-${each.key}", 0, 64)
  resource_group_id    = each.value.rg_id
  policy_definition_id = azurerm_policy_definition.ai_deployment_types.id
  display_name         = "OJK approved AI deployment types - ${each.value.ojk_approval_reference}"
  description          = "AI deployment types approved for this offshore placement: ${join(", ", each.value.approved_ai_deployment_types)}."
  enforce              = var.enforce

  parameters = jsonencode({
    effect                 = { value = var.effect_data_location }
    allowedDeploymentTypes = { value = each.value.approved_ai_deployment_types }
  })

  non_compliance_message {
    content = "AI deployment type is outside the OJK approval for this placement (${each.value.ojk_approval_reference}). Approved types: ${join(", ", each.value.approved_ai_deployment_types)}."
  }

  depends_on = [terraform_data.exemption_scope_check]
}
