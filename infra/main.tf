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

# --- RANDOMNESS ---
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

# --- RESOURCE GROUP ---
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location_primary
}

# --- 1. STORAGE ACCOUNT ---
resource "azurerm_storage_account" "sa" {
  name                     = "st${replace(var.project_name, "-", "")}${var.environment}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_application_insights" "app_insights" {
  name                = "appin-${var.project_name}-${var.environment}"
  location            = var.location_primary
  resource_group_name = azurerm_resource_group.rg.name
  application_type    = "web"
}

resource "azurerm_storage_container" "input_container" {
  name                  = "input-pdfs"
  storage_account_name  = azurerm_storage_account.sa.name
  container_access_type = "private"
}

# --- 2. AI SERVICES (Document Intelligence) ---
resource "azurerm_cognitive_account" "doc_intel" {
  name                = "cog-di-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  location            = var.location_ai 
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "FormRecognizer"
  sku_name            = "S0"
}

# --- 3. DATABASE (PostgreSQL) ---
resource "azurerm_postgresql_flexible_server" "postgres" {
  name                   = "psql-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = var.location_database
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

# --- 4. COMPUTE (App Service Plan & Function) ---
resource "azurerm_service_plan" "asp" {
  name                = "asp-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  sku_name            = "Y1" 
}

resource "azurerm_linux_function_app" "func" {
  name                = "func-${var.project_name}-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key
  service_plan_id            = azurerm_service_plan.asp.id

  site_config {
    application_stack {
      python_version = "3.10"
    }
  }

  app_settings = {
    # Generated Settings
    "DI_ENDPOINT"            = azurerm_cognitive_account.doc_intel.endpoint
    "DI_KEY"                 = azurerm_cognitive_account.doc_intel.primary_access_key
    "INPUT_CONTAINER_NAME"   = azurerm_storage_container.input_container.name
    "AzureWebJobsStorage"    = azurerm_storage_account.sa.primary_connection_string
    "DB_CONNECTION_STRING"   = "postgresql://psqladmin:${random_password.db_password.result}@${azurerm_postgresql_flexible_server.postgres.fqdn}:5432/documents_db"
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.app_insights.connection_string
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.app_insights.instrumentation_key
    
    # Secrets from Variables
    "OPENAI_ENDPOINT"        = var.openai_endpoint
    "OPENAI_KEY"             = var.openai_key
    "OPENAI_DEPLOYMENT"      = var.openai_deployment
    "OPENAI_API_VERSION"     = var.openai_api_version
    
    "FUNCTIONS_WORKER_RUNTIME" = "python"
  }
}