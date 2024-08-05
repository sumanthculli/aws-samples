resource "kubernetes_manifest" "aws_provider_installer" {
  manifest = {
    apiVersion = "v1"
    kind       = "Pod"
    metadata = {
      name      = "aws-provider-installer"
      namespace = "kube-system"
    }
    spec = {
      containers = [
        {
          name  = "aws-provider-installer"
          image = "amazon/aws-secrets-manager-csi-driver-provider:latest"
          args  = ["--install"]
        }
      ]
    }
  }
}
