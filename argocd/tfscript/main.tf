# main.tf

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"  # Adjust this path as needed
}

resource "kubernetes_secret" "argocd_repo_secret" {
  metadata {
    name      = "repo-secret-${var.repo_name}"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = "https://github.com/${var.github_org}/${var.repo_name}.git"
    username = var.github_username
    password = var.github_token
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "argocd_application" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.app_name
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_org}/${var.repo_name}.git"
        targetRevision = var.branch
        path           = var.manifest_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.target_namespace
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  }

  depends_on = [kubernetes_secret.argocd_repo_secret]
}
