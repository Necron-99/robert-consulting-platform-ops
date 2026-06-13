{{/*
Common labels
*/}}
{{- define "static-site.labels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: {{ .Values.site.name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "static-site.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}

{{/*
nginx.conf — SPA routing vs standard routing
*/}}
{{- define "static-site.nginxConfig" -}}
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log {{ .Values.logging.errorLogLevel }};
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    {{- if .Values.logging.jsonFormat }}
    log_format json_combined escape=json
        '{'
            '"time":"$time_iso8601",'
            '"remote_addr":"$remote_addr",'
            '"method":"$request_method",'
            '"uri":"$request_uri",'
            '"status":$status,'
            '"bytes_sent":$bytes_sent,'
            '"request_time":$request_time,'
            '"http_referer":"$http_referer",'
            '"http_user_agent":"$http_user_agent",'
            '"namespace":"{{ .Values.namespace }}",'
            '"site":"{{ .Values.site.name }}"'
        '}';
    access_log /var/log/nginx/access.log json_combined;
    {{- else }}
    access_log /var/log/nginx/access.log combined;
    {{- end }}

    sendfile on;
    tcp_nopush on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    server {
        listen 80;
        listen [::]:80;
        server_name {{ .Values.ingress.host }};
        root {{ .Values.s3.contentPath }};
        index index.html;

        # Security headers
        add_header Content-Security-Policy "{{ .Values.headers.contentSecurityPolicy }}" always;
        add_header X-Frame-Options "{{ .Values.headers.xFrameOptions }}" always;
        add_header X-Content-Type-Options "{{ .Values.headers.xContentTypeOptions }}" always;
        add_header Referrer-Policy "{{ .Values.headers.referrerPolicy }}" always;
        add_header Strict-Transport-Security "{{ .Values.headers.strictTransportSecurity }}" always;
        add_header X-XSS-Protection "{{ .Values.headers.xXssProtection }}" always;

        {{- if .Values.metrics.enabled }}
        # nginx stub_status for prometheus-exporter sidecar
        location /nginx_status {
            stub_status on;
            access_log off;
            allow 127.0.0.1;
            deny all;
        }
        {{- end }}

        {{- if .Values.site.spaRouting }}
        # SPA routing — serve index.html for all 404s (React/Vue/Angular)
        location / {
            try_files $uri $uri/ /index.html;
        }
        {{- else }}
        # Standard routing with custom error document
        location / {
            try_files $uri $uri/ =404;
        }
        error_page 404 /{{ .Values.site.errorDocument }};
        location = /{{ .Values.site.errorDocument }} {
            internal;
        }
        {{- end }}

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            # Re-add security headers (add_header inheritance)
            add_header Content-Security-Policy "{{ .Values.headers.contentSecurityPolicy }}" always;
            add_header X-Frame-Options "{{ .Values.headers.xFrameOptions }}" always;
            add_header X-Content-Type-Options "{{ .Values.headers.xContentTypeOptions }}" always;
            add_header Strict-Transport-Security "{{ .Values.headers.strictTransportSecurity }}" always;
        }
    }
}
{{- end }}
