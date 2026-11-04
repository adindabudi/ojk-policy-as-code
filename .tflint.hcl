# TFLint settings for both Terraform roots. Run from the repository root:
#   tflint --init --config "$(pwd)/.tflint.hcl"
#   tflint --recursive --config "$(pwd)/.tflint.hcl"
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}
