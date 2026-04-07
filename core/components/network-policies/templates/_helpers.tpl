{{/*
Common labels applied to every resource rendered by this chart.

Follows the platform convention seen in cert-manager, grafana-stack, traefik,
resource-quotas, etc. — `estabilis.io/managed-by: platform` plus a component
discriminator.
*/}}
{{- define "network-policies.labels" -}}
estabilis.io/managed-by: platform
estabilis.io/component: network-policies
app.kubernetes.io/name: network-policies
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: estabilis-platform
{{- end -}}

{{/*
DNS egress rule — allows UDP 53 to kube-system (CoreDNS).
Required by every namespace. Use with: {{ include "network-policies.dns-egress" . }}
*/}}
{{- define "network-policies.dns-egress" }}
    # DNS (CoreDNS in kube-system)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
{{- end }}