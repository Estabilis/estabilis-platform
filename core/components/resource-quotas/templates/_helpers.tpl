{{/*
Common labels applied to every resource rendered by this chart.

Follows the platform convention seen in cert-manager, grafana-stack, traefik,
etc. — `estabilis.io/managed-by: platform` plus a component discriminator.
*/}}
{{- define "resource-quotas.labels" -}}
estabilis.io/managed-by: platform
estabilis.io/component: resource-quotas
app.kubernetes.io/name: resource-quotas
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: estabilis-platform
{{- end -}}
