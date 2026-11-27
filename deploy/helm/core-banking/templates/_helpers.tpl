{{- define "cb.image" -}}
{{- $r := .root.Values.image.registry -}}
{{- if $r }}{{ $r }}/{{ end }}{{ .name }}:{{ .root.Values.image.tag }}
{{- end -}}

{{/* Deployment + Service + ServiceAccount for one Spring service. Expects: root, name, repo, port, replicas, env (YAML text) */}}
{{- define "cb.app" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .name }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .name }}
  labels:
    app: {{ .name }}
spec:
  replicas: {{ .replicas }}
  selector:
    matchLabels:
      app: {{ .name }}
  template:
    metadata:
      labels:
        app: {{ .name }}
    spec:
      enableServiceLinks: false   # a Service called "redis" would inject REDIS_PORT=tcp://..., which Spring tries to bind to an int
      serviceAccountName: {{ .name }}
      containers:
        - name: app
          image: {{ include "cb.image" (dict "root" .root "name" .repo) }}
          imagePullPolicy: {{ .root.Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .port }}
          env:
            - name: JAVA_TOOL_OPTIONS
              value: {{ .root.Values.javaToolOptions | quote }}
{{ .env | indent 12 }}
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: http }
            initialDelaySeconds: 20
            periodSeconds: 5
            failureThreshold: 12
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: http }
            initialDelaySeconds: 60
            periodSeconds: 10
          resources:
{{ toYaml .root.Values.resources | indent 12 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .name }}
  labels:
    app: {{ .name }}
spec:
  selector:
    app: {{ .name }}
  ports:
    - name: http
      port: {{ .port }}
      targetPort: http
{{- end -}}

{{- define "cb.env.db" -}}
- name: DB_USER
  valueFrom: { secretKeyRef: { name: {{ .Values.db.secretName }}, key: username } }
- name: DB_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ .Values.db.secretName }}, key: password } }
- name: REDIS_HOST
  value: redis
{{- end -}}
