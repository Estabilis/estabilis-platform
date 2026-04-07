{{/*
Estabilis Platform — standard metadata helpers.

These defines are duplicated identically across every internal chart in the
platform (Option 2 from estabilis-platform-tools issue #45). Keep them in
sync — if you change one, run `git grep -A 8 "define \"estabilis.labels\""`
across core/components and apply the same edit everywhere.

Three defines:
  - estabilis.labels       — selectable identity (filtering, RBAC, Service selectors)
  - estabilis.annotations  — branding + provenance (human/audit-only, not selectable)
  - estabilis.metadata     — convenience: emits both blocks under metadata:
*/}}
{{- define "estabilis.labels" -}}
estabilis.io/component: {{ .Chart.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: estabilis-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "estabilis.annotations" -}}
estabilis.io/platform: "Estabilis Platform"
estabilis.io/chart-version: {{ .Chart.Version | quote }}
estabilis.io/website: "https://estabilis.com"
estabilis.io/source: "https://github.com/Estabilis/estabilis-platform"
estabilis.io/support: "ops@estabilis.com"
estabilis.io/license: "proprietary"
{{- end -}}

{{- define "estabilis.metadata" -}}
labels:
  {{- include "estabilis.labels" . | nindent 2 }}
annotations:
  {{- include "estabilis.annotations" . | nindent 2 }}
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