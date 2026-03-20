{{/*
List of platform namespaces excluded from policy evaluation.
Used as building block by the exclude helpers below.
Do NOT call directly in policy templates — use the full exclude helpers.
*/}}
{{- define "kyverno-policies.excluded-namespace-list" }}
                - argocd
                - cert-manager
                - cnpg-system
                - external-dns
                - external-secrets
                - grafana
                - kube-node-lease
                - kube-public
                - kube-state-metrics
                - kube-system
                - kyverno
                - node-exporter
                - opencost
                - traefik
                - trivy-system
                - velero
{{- end }}

{{/*
Exclude block for policies matching namespaced resources (Pod, Deployment, etc).
Filters by the namespace where the resource lives.
*/}}
{{- define "kyverno-policies.platform-exclude" }}
      exclude:
        any:
          - resources:
              namespaces:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}

{{/*
Exclude block for policies matching Namespace-kind resources (cluster-scoped).
Uses "names" instead of "namespaces" because Namespace resources
are cluster-scoped and don't have a namespace field.
*/}}
{{- define "kyverno-policies.platform-exclude-namespaces" }}
      exclude:
        any:
          - resources:
              names:
{{- include "kyverno-policies.excluded-namespace-list" . }}
{{- end }}
