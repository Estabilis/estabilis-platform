{{/*
Common labels applied to all Hubble UI resources.
*/}}
{{- define "hubble-ui.labels" -}}
app.kubernetes.io/name: hubble-ui
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: cilium
app.kubernetes.io/managed-by: {{ .Release.Service }}
estabilis.io/managed-by: platform
{{- end -}}

{{/*
Selector labels — must remain stable across upgrades (Deployment.spec.selector
is immutable in Kubernetes).
*/}}
{{- define "hubble-ui.selectorLabels" -}}
app.kubernetes.io/name: hubble-ui
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Validate the mode value. Only "acns" is supported in v1; any other value
renders a hard fail during helm template / argocd render so misconfigured
downstreams break loudly instead of silently rendering nothing.
*/}}
{{- define "hubble-ui.validateMode" -}}
{{- if ne .Values.mode "acns" -}}
{{- fail (printf "hubble-ui: mode=%q is not supported. Only \"acns\" is valid in v1. BYO-CNI support is deferred — see Estabilis/estabilis-platform-tools#46." .Values.mode) -}}
{{- end -}}
{{- end -}}
