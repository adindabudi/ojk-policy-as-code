variable "subscription_id" {
  description = "Subscription for the lab. Use a non-production subscription."
  type        = string
}

variable "prefix" {
  description = "Short prefix for resource names."
  type        = string
  default     = "ojkdemo"

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.prefix))
    error_message = "prefix must be 3-10 lowercase letters or digits."
  }
}

variable "location" {
  description = "Approved in-country region."
  type        = string
  default     = "indonesiacentral"
}

variable "offshore_location" {
  description = "Region of the simulated OJK-approved offshore placement."
  type        = string
  default     = "southeastasia"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "admin_username" {
  type    = string
  default = "labadmin"
}

variable "servers" {
  description = <<-EOT
    Windows Server VMs that simulate on-premises servers. They are connected to Azure Arc by scripts/Connect-ArcLab.ps1.
    Pin image_version to an older build to simulate a server with missing security updates.
  EOT
  type = map(object({
    image_sku     = optional(string, "2016-datacenter-gensecond")
    image_version = optional(string, "latest")
    scenario      = string
  }))
  default = {
    "srv-app-01" = {
      image_version = "14393.8783.260109"
      scenario      = "not patched since January 2026"
    }
    "srv-app-02" = {
      scenario = "latest monthly update"
    }
  }

  validation {
    condition     = alltrue([for name in keys(var.servers) : length(name) <= 15])
    error_message = "Server names are also Windows computer names, so they must be 15 characters or fewer."
  }
}

variable "ai_model" {
  description = "Model deployment in the approved offshore placement."
  type = object({
    deployment_name = string
    name            = string
    version         = string
    sku             = string
    capacity        = number
  })
  default = {
    deployment_name = "gpt-5-4-mini-datazone"
    name            = "gpt-5.4-mini"
    version         = "2026-03-17"
    sku             = "DataZoneStandard"
    capacity        = 10
  }
}

variable "tags" {
  type = map(string)
  default = {
    purpose   = "ojk-policy-demo"
    lifecycle = "temporary"
  }
}
