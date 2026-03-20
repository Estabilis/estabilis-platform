{{- define "kyverno-policies.platform-exclude" }}
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - argocd
                - cert-manager
                - cnpg-system
                - external-dns
                - external-secrets
                - grafana
                - kube-state-metrics
                - kyverno
                - node-exporter
                - opencost
                - traefik
                - trivy-system
                - velero
{{- end }}
