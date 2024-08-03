# terraform.tfvars

github_org       = "my-org"
repo_name        = "my-repo"
github_username  = "${github_user}"
github_token     = "${github_password}"
app_name         = "my-nginx-app"
branch           = "main"
manifest_path    = "kubernetes"
target_namespace = "default"
