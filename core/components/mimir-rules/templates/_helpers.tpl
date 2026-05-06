{{/*
Estabilis Platform — standard metadata helpers.

These defines are duplicated identically across every internal chart in the
platform (Option 2 from estabilis-platform-tools issue #45). Keep them in
sync — if you change one, run `git grep -A 8 "define \"estabilis.labels\""`
across core/components and apply the same edit everywhere.
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
{{- include "estabilis.provenanceAnnotations" . }}
{{- end -}}

{{/*
ADR 0005 Phase 2b — supply-chain L1 provenance annotations, populated
from global.provenance.* at render time. The CLI sets these values via
helm.parameters propagated from platform-root
(see platform-root.provenanceParameters). The three-level guard keeps
helm template standalone-renderable when the values are absent.
*/}}
{{- define "estabilis.provenanceAnnotations" -}}
{{- if and .Values.global .Values.global.provenance .Values.global.provenance.gitRevision }}
estabilis.io/git-revision: {{ .Values.global.provenance.gitRevision | quote }}
estabilis.io/git-source: {{ .Values.global.provenance.gitSource | quote }}
estabilis.io/built-at: {{ .Values.global.provenance.builtAt | quote }}
estabilis.io/build-id: {{ .Values.global.provenance.buildId | quote }}
{{- end }}
{{- end -}}

{{- define "estabilis.metadata" -}}
labels:
  {{- include "estabilis.labels" . | nindent 2 }}
annotations:
  {{- include "estabilis.annotations" . | nindent 2 }}
{{- end -}}

{{/*
mimir-rules.applyOverrides — render a tier file with `alertOverrides`
applied.

Input dict:
  tier      — basename of the tier file (e.g. "tier2-degradation")
  overrides — .Values.alertOverrides map
  files     — pass `.Files` (renderer needs context to call `Files.Get`)

Behavior per rule (matched by `alert:` field):
  - override `enabled: false` → rule is dropped from output
  - any other override field  → shallow-merged onto the rule (override
    wins on conflict); providing a complex field like `labels:` REPLACES
    the entire labels map — caller provides the complete intended value
  - rule with no matching override → emitted unchanged

Group-level: a group whose rules are all dropped is omitted (avoids
empty `rules: []` blocks that Mimir Ruler logs as warnings).

Returns: YAML string of `groups:` ready to be indented into the
ConfigMap data section.
*/}}
{{- define "mimir-rules.applyOverrides" -}}
{{- $tier := .tier -}}
{{- $overrides := .overrides | default dict -}}
{{- $files := .files -}}
{{- $raw := $files.Get (printf "files/%s.yaml" $tier) -}}
{{- $parsed := fromYaml $raw -}}
{{- $newGroups := list -}}
{{- range $group := $parsed.groups -}}
  {{- $newRules := list -}}
  {{- range $rule := $group.rules -}}
    {{- $name := index $rule "alert" -}}
    {{- $override := dict -}}
    {{- if and $name (hasKey $overrides $name) -}}
      {{- $override = index $overrides $name -}}
    {{- end -}}
    {{- $disabled := false -}}
    {{- if and $override (hasKey $override "enabled") -}}
      {{- if eq (index $override "enabled") false -}}
        {{- $disabled = true -}}
      {{- end -}}
    {{- end -}}
    {{- if not $disabled -}}
      {{- $merged := dict -}}
      {{- range $k, $v := $rule -}}
        {{- $_ := set $merged $k $v -}}
      {{- end -}}
      {{- range $k, $v := $override -}}
        {{- if ne $k "enabled" -}}
          {{- $_ := set $merged $k $v -}}
        {{- end -}}
      {{- end -}}
      {{- $newRules = append $newRules $merged -}}
    {{- end -}}
  {{- end -}}
  {{- if gt (len $newRules) 0 -}}
    {{- $newGroup := dict "name" $group.name "rules" $newRules -}}
    {{- if hasKey $group "interval" -}}
      {{- $_ := set $newGroup "interval" $group.interval -}}
    {{- end -}}
    {{- $newGroups = append $newGroups $newGroup -}}
  {{- end -}}
{{- end -}}
{{- dict "groups" $newGroups | toYaml -}}
{{- end -}}
