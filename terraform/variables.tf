variable "subscription_id" {
  description = "Subscription ID used by the azurerm provider. Also the assignment scope when scope_type = \"subscription\"."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a subscription GUID, for example 00000000-0000-0000-0000-000000000000."
  }
}

variable "scope_type" {
  description = "Where to assign the initiative: management_group (recommended), subscription (pilot) or resource_group (pilot on selected resource groups). Definitions are created at the management group for management_group, otherwise at the subscription."
  type        = string
  default     = "management_group"

  validation {
    condition     = contains(["management_group", "subscription", "resource_group"], var.scope_type)
    error_message = "scope_type must be management_group, subscription or resource_group."
  }
}

variable "management_group_id" {
  description = "Management group resource ID, for example /providers/Microsoft.Management/managementGroups/contoso (the intermediate root of an Azure landing zone). Required when scope_type = management_group."
  type        = string
  default     = null

  validation {
    condition     = var.management_group_id == null || can(regex("^/providers/Microsoft.Management/managementGroups/[^/]+$", var.management_group_id))
    error_message = "management_group_id must be a resource ID such as /providers/Microsoft.Management/managementGroups/<name>."
  }
}

variable "resource_group_names" {
  description = "Resource groups in subscription_id that get their own assignment when scope_type = resource_group. Subscription-level controls (Defender plans, security contact, Service Health alert, owner MFA) are not evaluated at this scope."
  type        = list(string)
  default     = []
}

variable "location" {
  description = "Region of the policy assignment's managed identity. Keep it in an allowed region."
  type        = string
  default     = "indonesiacentral"
}

variable "assignment_name" {
  description = "Policy assignment name (max 24 characters at management group scope)."
  type        = string
  default     = "ojk-checklist-202603"

  validation {
    condition     = length(var.assignment_name) <= 24
    error_message = "assignment_name must be 24 characters or fewer."
  }
}

variable "enforce" {
  description = "false = DoNotEnforce (evaluate only, Deny effects are not applied)."
  type        = bool
  default     = true
}

variable "not_scopes" {
  description = "Scopes excluded from the assignment, for example the Sandbox management group of an Azure landing zone."
  type        = list(string)
  default     = []
}

variable "list_of_allowed_locations" {
  description = "Regions allowed for resources and resource groups (OJK-01). Azure Arc resources keep their metadata in the region chosen at onboarding, so that region must be in this list."
  type        = list(string)
  default     = ["indonesiacentral"]

  validation {
    condition     = length(var.list_of_allowed_locations) > 0
    error_message = "list_of_allowed_locations needs at least one region."
  }
}

variable "allowed_ai_deployment_types" {
  description = "Approved Foundry / Azure OpenAI deployment sku.name values."
  type        = list(string)
  default     = ["Standard", "ProvisionedManaged"]
}

variable "effect_data_location" {
  description = "Effect of the location and AI deployment type controls (OJK-01). Start with Audit. Switch to Deny after every approved offshore placement is recorded in offshore_exemptions."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect_data_location)
    error_message = "Allowed values: Audit, Deny, Disabled."
  }
}

variable "effect_preventive" {
  description = "Effect of the configuration controls that support Deny, such as public network access, TLS versions and local authentication."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect_preventive)
    error_message = "Allowed values: Audit, Deny, Disabled."
  }
}

variable "effect_detective" {
  description = "Effect of the AuditIfNotExists controls, such as Defender plans, logs, machine configuration, update assessment and backup."
  type        = string
  default     = "AuditIfNotExists"

  validation {
    condition     = contains(["AuditIfNotExists", "Disabled"], var.effect_detective)
    error_message = "Allowed values: AuditIfNotExists, Disabled."
  }
}

variable "effect_kubernetes" {
  description = "Effect of the Kubernetes controls for AKS and Azure Arc-enabled Kubernetes clusters."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect_kubernetes)
    error_message = "Allowed values: Audit, Deny, Disabled."
  }
}

variable "effect_customer_managed_key" {
  description = "Effect of the customer-managed key controls (storage, SQL, Foundry). Audit or Disabled only, because the key choice depends on the data."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Disabled"], var.effect_customer_managed_key)
    error_message = "Allowed values: Audit, Disabled."
  }
}

variable "effect_resilience" {
  description = "Effect of the zone redundancy controls. These built-ins are in preview: set Disabled if you don't use preview policies in production."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Deny", "Disabled"], var.effect_resilience)
    error_message = "Allowed values: Audit, Deny, Disabled."
  }
}

variable "include_arc_machines" {
  description = "\"true\" evaluates Azure Arc-enabled servers in the machine configuration controls (security baseline and secure protocols)."
  type        = string
  default     = "true"

  validation {
    condition     = contains(["true", "false"], var.include_arc_machines)
    error_message = "Allowed values: \"true\", \"false\"."
  }
}

variable "diagnostic_settings_resource_types" {
  description = "Resource types that must have diagnostic settings (OJK-07)."
  type        = list(string)
  default = [
    "Microsoft.ApiManagement/service",
    "Microsoft.ContainerService/managedClusters",
    "Microsoft.Network/applicationGateways",
    "Microsoft.Network/azureFirewalls",
    "Microsoft.Web/sites",
  ]
}

variable "service_health_alert_resource_group_name" {
  description = "Resource group in each subscription where the Service Health alert rule is expected (OJK-08). rg-serviceHealthAlert matches the Azure landing zone default."
  type        = string
  default     = "rg-serviceHealthAlert"
}

variable "offshore_exemptions" {
  description = <<-EOT
    OJK-approved or temporary offshore placements, recorded as exemptions on resource groups (Part 2 B-II #9).
    Set resource_group_name (resolved in subscription_id) or resource_group_id (any subscription under the management group).
    The exemption waives only the location controls. To allow AI deployment types that process data outside the
    resource's geography, list them in approved_ai_deployment_types (for example ["DataZoneStandard"]): the resource
    group then gets its own assignment of the AI policy with only those types, so types outside the approval stay blocked.
  EOT
  type = map(object({
    resource_group_name          = optional(string)
    resource_group_id            = optional(string)
    ojk_approval_reference       = string
    justification                = string
    expires_on                   = optional(string)
    approved_ai_deployment_types = optional(list(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for e in values(var.offshore_exemptions) : (e.resource_group_name == null) != (e.resource_group_id == null)
    ])
    error_message = "Each offshore exemption needs exactly one of resource_group_name or resource_group_id."
  }

  validation {
    condition = alltrue([
      for e in values(var.offshore_exemptions) : e.expires_on == null || can(regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z$", e.expires_on))
    ])
    error_message = "expires_on must be an ISO 8601 UTC timestamp, for example 2027-03-31T00:00:00Z."
  }
}
