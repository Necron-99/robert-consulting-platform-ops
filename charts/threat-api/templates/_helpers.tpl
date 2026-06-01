{{/*
Common labels
*/}}
{{- define "threat-api.labels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "threat-api.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}
