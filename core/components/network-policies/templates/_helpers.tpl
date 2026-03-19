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
      ports:
        - protocol: UDP
          port: 53
{{- end }}