resource "kubernetes_cluster_role" "vault_auth" {
  metadata {
    name = "vault-auth"
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts", "secrets"]
    verbs      = ["get", "list", "create", "update"]
  }

  rule {
    api_groups = ["authentication.k8s.io"]
    resources  = ["tokenreviews"]
    verbs      = ["create"]
  }
}

resource "kubernetes_cluster_role_binding" "vault_auth" {
  metadata {
    name = "vault-auth-binding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "bleachdle-sa"
    namespace = "default"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.vault_auth.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}
