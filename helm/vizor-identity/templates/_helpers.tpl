{{/*
Compute public-facing base URL from ingress values.
Uses publicHost (external) when set, falls back to host (internal).
Scheme precedence: ingress.publicScheme (http/https) > certName-derived > http.
*/}}
{{- define "vizor-identity.publicUrl" -}}
{{- $host := coalesce .Values.ingress.publicHost .Values.ingress.host -}}
{{- $host = regexReplaceAll "^https?://" $host "" -}}
{{- if $host -}}
  {{- $configuredScheme := lower (default "" .Values.ingress.publicScheme) -}}
  {{- $scheme := ternary "https" "http" (not (empty .Values.ingress.certName)) -}}
  {{- if or (eq $configuredScheme "http") (eq $configuredScheme "https") -}}
    {{- $scheme = $configuredScheme -}}
  {{- end -}}
  {{- printf "%s://%s" $scheme $host -}}
{{- end -}}
{{- end -}}

{{- define "vizor-identity.serviceAccountName" -}}
{{- .Values.serviceAccount.name | default (printf "%s-runtime" .Release.Namespace) | default .Values.global.serviceAccountName | default "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-identity.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
