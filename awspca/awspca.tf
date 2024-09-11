# Helm provider configuration
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"  # Path to your kubeconfig file
  }
}

# AWS provider configuration
provider "aws" {
  region = "us-west-2"  # Replace with your desired region
}

# Data source to get EKS cluster info
data "aws_eks_cluster" "cluster" {
  name = "your-eks-cluster-name"  # Replace with your EKS cluster name
}

# Install AWS PCA Issuer using Helm
resource "helm_release" "aws_pca_issuer" {
  name       = "aws-pca-issuer"
  repository = "https://cert-manager.github.io/aws-privateca-issuer"
  chart      = "aws-privateca-issuer"
  namespace  = "cert-manager"
  version    = "1.2.3"  # Replace with the desired version

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-pca-issuer"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.pca_issuer_role.arn
  }
}

# Create IAM role for IRSA
resource "aws_iam_role" "pca_issuer_role" {
  name = "eks-pca-issuer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub": "system:serviceaccount:cert-manager:aws-pca-issuer"
          }
        }
      }
    ]
  })
}

# Attach necessary policies to the IAM role
resource "aws_iam_role_policy_attachment" "pca_issuer_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AWSCertificateManagerPrivateCAFullAccess"
  role       = aws_iam_role.pca_issuer_role.name
}

# Get current AWS account ID
data "aws_caller_identity" "current" {}
