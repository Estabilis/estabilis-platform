# Backend configuration — managed by `just b4-migrate`
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-estabilis-tfstate"
    storage_account_name = "stestabilistfstatetgridb"
    container_name       = "tfstate"
    key                  = "estabilis-platform.tfstate"
  }
}
