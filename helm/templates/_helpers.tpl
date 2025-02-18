{{- define "bleachdle.fullname" -}}
{{ .Release.Name }}
{{- end }}

{{- define "bleachdle.labels" -}}
app: {{ .Chart.Name }}
release: {{ .Release.Name }}
{{- end }}

{{- define "bleachdle.selectorLabels" -}}
app: {{ .Chart.Name }}
release: {{ .Release.Name }}
{{- end }}
