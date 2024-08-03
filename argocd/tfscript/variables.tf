# variables.tf

variable "github_org" {
  description = "GitHub organization name"
  type        = string
}

variable "repo_name" {
  description = "GitHub repository name"
  type        = string
}

variable "github_username" {
  description = "GitHub username for authentication"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token"
  type        = string
  sensitive   = true
}

variable "app_name" {
  description = "Name of the ArgoCD application"
  type        = string
}

variable "branch" {
  description = "Git branch to use"
  type        = string
  default     = "main"
}

variable "manifest_path" {
  description = "Path to the Kubernetes manifests in the repository"
  type        = string
}

variable "target_namespace" {
  description = "Target namespace for the application"
  type        = string
}
