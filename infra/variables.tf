variable "project_name" {
  description = "Base name for resources"
  default     = "doc-pipeline"
}

variable "environment" {
  description = "Deployment environment (dev, prod)"
  default     = "dev"
}

variable "location_primary" {
  description = "Location for App Service and Storage"
  default     = "Canada East"
}

variable "location_database" {
  description = "Location for PostgreSQL (to bypass quotas)"
  default     = "North Europe"
}

variable "location_ai" {
  description = "Location for AI Services"
  default     = "East US"
}

# --- SECRETS (No defaults here!) ---

variable "openai_endpoint" {
  description = "The URL for your Azure OpenAI resource"
  type        = string
}

variable "openai_key" {
  description = "The API Key for Azure OpenAI"
  type        = string
  sensitive   = true
}

variable "openai_deployment" {
  description = "The model deployment name"
  type        = string
  default     = "gpt-4o-rfp"
}

variable "openai_api_version" {
  description = "The API version for OpenAI"
  type        = string
  default     = "2025-01-01-preview"
}