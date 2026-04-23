// Shared tflint config for estabilis-platform providers.
// Plugins are auto-installed on first run by the pre-commit terraform_tflint
// hook (it runs `tflint --init` when needed). Explicit version pins below
// keep local + CI behavior consistent.

config {
  // Surface best-practice warnings but do not fail the build on them —
  // pre-commit passes --minimum-failure-severity=error so only errors block
  // the commit. Warnings show up in the output for operator awareness.
  call_module_type = "local"

  // Disable the default rule "terraform_unused_required_providers" — our
  // providers/*/versions.tf declares every provider the module graph needs,
  // including ones used only inside submodules.
  disabled_by_default = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled     = true
  version     = "0.44.0"
  source      = "github.com/terraform-linters/tflint-ruleset-aws"
  deep_check  = false
}

plugin "azurerm" {
  enabled     = true
  version     = "0.30.0"
  source      = "github.com/terraform-linters/tflint-ruleset-azurerm"
  deep_check  = false
}

// ---------------------------------------------------------------------------
// Rule overrides
// ---------------------------------------------------------------------------

// The Azure provider relies on conditional dynamic blocks with empty lists
// to disable features; that pattern trips the "unused variable" rule when
// a feature is off. Demote to warning.
rule "terraform_unused_declarations" {
  enabled = true
}

// Let operators choose validation placement; the AWS module wrappers carry
// their own validations in places we cannot duplicate.
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

// Naming convention — match lower_snake_case for everything Terraform-native.
// Azure + AWS resource names on the cloud side are controlled by locals
// (base_name) so this only lints the Terraform identifiers.
rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

// Disable rules that produce false positives with module-heavy code.
rule "terraform_module_pinned_source" {
  enabled = true
  style   = "flexible"
}
