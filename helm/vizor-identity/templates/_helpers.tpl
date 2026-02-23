{{- define "vizor-identity.serviceAccountName" -}}
{{- .Values.serviceAccount.name | default .Values.global.serviceAccountName | default "vizor-runtime" -}}
{{- end -}}

{{- define "vizor-identity.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
