resource "kubernetes_manifest" "presync_hook" {
  manifest = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "api-check-"
      annotations = {
        "argocd.argoproj.io/hook"        = "PreSync"
        "argocd.argoproj.io/hook-delete-policy" = "HookSucceeded"
      }
    }
    spec = {
      template = {
        metadata = {
          name = "api-check"
        }
        spec = {
          restartPolicy = "Never"
          containers = [
            {
              name  = "api-check"
              image = "curlimages/curl:latest"
              command = [
                "/bin/sh",
                "-c",
                <<-EOT
                  response=$(curl -s -o /dev/null -w "%%{http_code}" https://api.example.com/status)
                  if [ "$response" = "200" ]; then
                    echo "API check successful"
                    exit 0
                  else
                    echo "API check failed"
                    exit 1
                  fi
                EOT
              ]
            }
          ]
        }
      }
    }
  }
}
