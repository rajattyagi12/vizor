{{- define "vizor-data-init.serviceAccountName" -}}
{{- default .Values.global.serviceAccountName "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-data-init.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
