variable "release_name" {
  type        = string
  description = "Release name for the Helm chart"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the chart"
}

variable "create_namespace" {
  type        = bool
  default     = false
  description = "Create the namespace if it doesn't exist"
}

variable "repository" {
  type        = string
  description = "Helm chart repository URL"
}

variable "chart" {
  type        = string
  description = "Helm chart name"
}

variable "chart_version" {
  type        = string
  default     = null
  description = "Helm chart version"
}

variable "timeout" {
  type        = number
  default     = 300
  description = "Time in seconds to wait for any individual Kubernetes operation"
}

variable "atomic" {
  type        = bool
  default     = true
  description = "If set, installation process purges chart on fail"
}

variable "cleanup_on_fail" {
  type        = bool
  default     = true
  description = "Allow deletion of new resources created in this upgrade when upgrade fails"
}

variable "wait" {
  type        = bool
  default     = true
  description = "Will wait until all resources are in a ready state before marking the release as successful"
}

variable "values_file" {
  type        = string
  description = "Path to the Helm values file"
}

variable "set_values" {
  type        = map(string)
  default     = {}
  description = "Additional values to set on the Helm release"
}
