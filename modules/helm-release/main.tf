resource "helm_release" "this" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = var.repository
  chart            = var.chart
  version          = var.chart_version
  timeout          = var.timeout
  atomic           = var.atomic
  cleanup_on_fail  = var.cleanup_on_fail
  wait             = var.wait

  values = [
    file(var.values_file)
  ]

  dynamic "set" {
    for_each = var.set_values
    content {
      name  = set.key
      value = set.value
    }
  }
}
