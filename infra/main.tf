terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# --- CONFIGURATION ---
# 1. Primary Location: Canada East (Must match your App Service Plan)
variable "location" { default = "Canada East" }
variable "project_name" { default = "doc-pipeline" }

# Existing Resources
variable "existing_asp_name" { default = "ASP-rfpgroup-b0bb" }
variable "existing_asp_rg"   { default = "rfp_group" }
variable "existing_di_name"  { default = "rfp-docintelligence" }
variable "existing_di_rg"    { default = "rfp_group" }

# --- DATA SOURCES ---

data "azurerm_service_plan" "existing_asp" {
  name                = var.existing_asp_name
  resource_group_name = var.existing_asp_rg
}

data "azurerm_cognitive_account" "existing_doc_intel" {
  name                = var.existing_di_name
  resource_group_name = var.existing_di_rg
}

# --- NEW RESOURCES ---

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Resource Group in Canada East
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-${random_string.suffix.result}"
  location = var.location 
}

# 1. Storage Account (Canada East)
resource "azurerm_storage_account" "sa" {
  name                     = "st${replace(var.project_name, "-", "")}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "input_container" {
  name                  = "input-pdfs"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# 2. PostgreSQL (North Europe - HARDCODED OVERRIDE)
# This resource lives in the Canada East RG, but is physically deployed in North Europe.
# This is a valid Azure configuration and bypasses your quota limits.
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "psql-${var.project_name}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = "North Europe" 
  version                = "16"
  sku_name               = "B_Standard_B1ms"
  
  administrator_login    = "psqladmin"
  administrator_password = random_password.db_password.result
  storage_mb             = 32768
  storage_tier           = "P4"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "allow-azure-access"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "docs_db" {
  name      = "documents_db"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# 3. Function App (Canada East)
resource "azurerm_linux_function_app" "func" {
  name                = "func-${var.project_name}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location # Canada East

  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  service_plan_id            = data.azurerm_service_plan.existing_asp.id

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    "DI_ENDPOINT"            = data.azurerm_cognitive_account.existing_doc_intel.endpoint
    "DI_KEY"                 = data.azurerm_cognitive_account.existing_doc_intel.primary_access_key
    "INPUT_CONTAINER_NAME"   = azurerm_storage_container.input_container.name
    "AzureWebJobsStorage"    = azurerm_storage_account.sa.primary_connection_string
    
    # DB Connection (Points to North Europe server)
    "DB_CONNECTION_STRING"   = "postgresql://psqladmin:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/documents_db"
    
    # OpenAI
    "OPENAI_ENDPOINT"        = var.openai_endpoint
    "OPENAI_KEY"             = var.openai_key
    "OPENAI_DEPLOYMENT"      = "gpt-4o-rfp"
    "OPENAI_API_VERSION"     = "2025-01-01-preview"
    
    "FUNCTIONS_WORKER_RUNTIME" = "python"
  }
}