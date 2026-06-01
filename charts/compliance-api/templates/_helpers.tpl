{{/*
Common labels
*/}}
{{- define "compliance-api.labels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "compliance-api.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}
