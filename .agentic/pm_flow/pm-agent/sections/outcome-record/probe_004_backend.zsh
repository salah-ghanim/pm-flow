#!/bin/zsh
# Probe: can this review session reach the local Jaeger, and Docker?
print '--- curl 16686/api/services ---'
curl -sv --max-time 5 -o /dev/null -w 'HTTP=%{http_code}\n' http://localhost:16686/api/services 2>&1 | tail -20
print "curl_exit=$?"
print '--- curl 4318 ---'
curl -s --max-time 5 -o /dev/null -w 'HTTP=%{http_code}\n' http://localhost:4318/v1/traces 2>&1
print "curl4318_exit=$?"
print '--- docker ps ---'
docker ps --format '{{.ID}} {{.Image}} {{.Ports}} {{.Status}}' 2>&1
print "docker_exit=$?"
print '--- nc 16686 ---'
nc -z -G 2 localhost 16686 2>&1
print "nc_exit=$?"
