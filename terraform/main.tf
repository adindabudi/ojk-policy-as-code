locals {
  mapping       = jsondecode(file("${path.module}/../mapping/ojk-policy-mapping.json"))
  ai_definition = jsondecode(file("${path.module}/../policies/ai-approved-deployment-types.json"))
  is_mg         = var.scope_type == "management_group"
  is_rg         = var.scope_type == "resource_group"

  # Keyed by resource group name; assigned_rg_by_id lets exemptions find the matching assignment.
  assigned_resource_groups = local.is_rg ? {
    for name in var.resource_group_names : name => "/subscriptions/${var.subscription_id}/resourceGroups/${name}"
  } : {}
  assigned_rg_by_id = { for name, id in local.assigned_resource_groups : lower(id) => name }

  custom_reference = "custom:${local.ai_definition.name}"

  members = [
    for m in local.mapping.members : {
      reference_id         = m.referenceId
      policy_definition_id = m.definitionId == local.custom_reference ? azurerm_policy_definition.ai_deployment_types.id : "/providers/Microsoft.Authorization/policyDefinitions/${m.definitionId}"
      parameter_values     = jsonencode(m.parameters)
      group_names          = m.groups
    }
  ]

  assignment_parameters = jsonencode({
    listOfAllowedLocations              = { value = var.list_of_allowed_locations }
    allowedAiDeploymentTypes            = { value = var.allowed_ai_deployment_types }
    effectDataLocation                  = { value = var.effect_data_location }
    effectPreventive                    = { value = var.effect_preventive }
    effectDetective                     = { value = var.effect_detective }
    effectKubernetes                    = { value = var.effect_kubernetes }
    effectCustomerManagedKey            = { value = var.effect_customer_managed_key }
    effectResilience                    = { value = var.effect_resilience }
    includeArcMachines                  = { value = var.include_arc_machines }
    diagnosticSettingsResourceTypes     = { value = var.diagnostic_settings_resource_types }
    serviceHealthAlertResourceGroupName = { value = var.service_health_alert_resource_group_name }
  })

  non_compliance_messages = [
    {
      reference_id = null
      content      = "Not compliant with the OJK checklist technical controls. Check the policy group (OJK-01 to OJK-09) for the checklist reference, or request an exemption with the OJK approval reference."
    },
    {
      reference_id = "dl-allowed-locations"
      content      = "Region is not approved. Placing electronic systems outside Indonesia needs OJK approval (POJK 11/2022). Record the approval as a policy exemption."
    },
    {
      reference_id = "dl-ai-deployment-types"
      content      = "AI deployment type is not approved. Global and DataZone types can process data outside Indonesia."
    },
  ]

  initiative_id = local.is_mg ? azurerm_management_group_policy_set_definition.ojk[0].id : azurerm_policy_set_definition.ojk[0].id

  assignment_ids = merge(
    { for k, a in azurerm_management_group_policy_assignment.ojk : "management_group" => a.id },
    { for k, a in azurerm_subscription_policy_assignment.ojk : "subscription" => a.id },
    { for k, a in azurerm_resource_group_policy_assignment.ojk : k => a.id },
  )

  principal_ids = merge(
    { for k, a in azurerm_management_group_policy_assignment.ojk : "management_group" => a.identity[0].principal_id },
    { for k, a in azurerm_subscription_policy_assignment.ojk : "subscription" => a.identity[0].principal_id },
    { for k, a in azurerm_resource_group_policy_assignment.ojk : k => a.identity[0].principal_id },
  )

  # Single assignment for management_group and subscription scope; null for resource_group scope.
  assignment_id = local.is_rg ? null : (local.is_mg ? azurerm_management_group_policy_assignment.ojk[0].id : azurerm_subscription_policy_assignment.ojk[0].id)
}

resource "terraform_data" "scope_check" {
  lifecycle {
    precondition {
      condition     = !local.is_mg || var.management_group_id != null
      error_message = "management_group_id is required when scope_type = management_group."
    }
    precondition {
      condition     = !local.is_rg || length(var.resource_group_names) > 0
      error_message = "resource_group_names needs at least one resource group when scope_type = resource_group."
    }
  }
}

resource "azurerm_policy_definition" "ai_deployment_types" {
  name                = local.ai_definition.name
  policy_type         = "Custom"
  mode                = local.ai_definition.properties.mode
  display_name        = local.ai_definition.properties.displayName
  description         = local.ai_definition.properties.description
  management_group_id = local.is_mg ? var.management_group_id : null
  metadata            = jsonencode(local.ai_definition.properties.metadata)
  parameters          = jsonencode(local.ai_definition.properties.parameters)
  policy_rule         = jsonencode(local.ai_definition.properties.policyRule)
}

resource "azurerm_management_group_policy_set_definition" "ojk" {
  count = local.is_mg ? 1 : 0

  name                = local.mapping.initiative.name
  management_group_id = var.management_group_id
  policy_type         = "Custom"
  display_name        = local.mapping.initiative.displayName
  description         = local.mapping.initiative.description
  metadata            = jsonencode(local.mapping.initiative.metadata)
  parameters          = jsonencode(local.mapping.initiative.parameters)

  dynamic "policy_definition_group" {
    for_each = local.mapping.groups
    content {
      name         = policy_definition_group.value.name
      display_name = policy_definition_group.value.displayName
      category     = policy_definition_group.value.category
      description  = policy_definition_group.value.description
    }
  }

  dynamic "policy_definition_reference" {
    for_each = local.members
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      reference_id         = policy_definition_reference.value.reference_id
      parameter_values     = policy_definition_reference.value.parameter_values
      policy_group_names   = policy_definition_reference.value.group_names
    }
  }
}

resource "azurerm_policy_set_definition" "ojk" {
  count = local.is_mg ? 0 : 1

  name         = local.mapping.initiative.name
  policy_type  = "Custom"
  display_name = local.mapping.initiative.displayName
  description  = local.mapping.initiative.description
  metadata     = jsonencode(local.mapping.initiative.metadata)
  parameters   = jsonencode(local.mapping.initiative.parameters)

  dynamic "policy_definition_group" {
    for_each = local.mapping.groups
    content {
      name         = policy_definition_group.value.name
      display_name = policy_definition_group.value.displayName
      category     = policy_definition_group.value.category
      description  = policy_definition_group.value.description
    }
  }

  dynamic "policy_definition_reference" {
    for_each = local.members
    content {
      policy_definition_id = policy_definition_reference.value.policy_definition_id
      reference_id         = policy_definition_reference.value.reference_id
      parameter_values     = policy_definition_reference.value.parameter_values
      policy_group_names   = policy_definition_reference.value.group_names
    }
  }
}

resource "azurerm_management_group_policy_assignment" "ojk" {
  count = local.is_mg ? 1 : 0

  name                 = var.assignment_name
  management_group_id  = var.management_group_id
  policy_definition_id = azurerm_management_group_policy_set_definition.ojk[0].id
  display_name         = local.mapping.initiative.displayName
  description          = "Bank-side technical controls from the OJK FSI checklist (Mar 2026) for Azure and Azure Arc resources."
  location             = var.location
  enforce              = var.enforce
  not_scopes           = var.not_scopes
  parameters           = local.assignment_parameters

  identity {
    type = "SystemAssigned"
  }

  dynamic "non_compliance_message" {
    for_each = local.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.reference_id
    }
  }
}

resource "azurerm_subscription_policy_assignment" "ojk" {
  count = var.scope_type == "subscription" ? 1 : 0

  name                 = var.assignment_name
  subscription_id      = "/subscriptions/${var.subscription_id}"
  policy_definition_id = azurerm_policy_set_definition.ojk[0].id
  display_name         = local.mapping.initiative.displayName
  description          = "Bank-side technical controls from the OJK FSI checklist (Mar 2026) for Azure and Azure Arc resources."
  location             = var.location
  enforce              = var.enforce
  not_scopes           = var.not_scopes
  parameters           = local.assignment_parameters

  identity {
    type = "SystemAssigned"
  }

  dynamic "non_compliance_message" {
    for_each = local.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.reference_id
    }
  }
}

resource "azurerm_resource_group_policy_assignment" "ojk" {
  for_each = local.assigned_resource_groups

  name                 = var.assignment_name
  resource_group_id    = each.value
  policy_definition_id = azurerm_policy_set_definition.ojk[0].id
  display_name         = "${local.mapping.initiative.displayName} (${each.key})"
  description          = "Bank-side technical controls from the OJK FSI checklist (Mar 2026) for Azure and Azure Arc resources in this resource group."
  location             = var.location
  enforce              = var.enforce
  not_scopes           = var.not_scopes
  parameters           = local.assignment_parameters

  identity {
    type = "SystemAssigned"
  }

  dynamic "non_compliance_message" {
    for_each = local.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.reference_id
    }
  }
}
