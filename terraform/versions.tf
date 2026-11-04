terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 5.0.0 is the lowest version that validates this module. .terraform.lock.hcl pins the tested version.
      version = ">= 5.0.0, < 6.0.0"
    }
  }
}

provider "azurerm" {
  features {}
  # Subscription used by the provider for API calls. For management group scope,
  # use any subscription the deployment identity can read.
  subscription_id = var.subscription_id
}
