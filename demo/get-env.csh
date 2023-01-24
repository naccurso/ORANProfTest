#!/bin/csh

setenv E2TERM_SCTP `kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-e2term-sctp-alpha -o jsonpath='{.items[0].spec.clusterIP}'`
setenv KONG_PROXY `kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
setenv ONBOARDER_HTTP `kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-xapp-onboarder-http -o jsonpath='{.items[0].spec.clusterIP}'`
setenv APPMGR_HTTP `kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
setenv NEXRAN_XAPP `kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-rmr -o jsonpath='{.items[0].spec.clusterIP}'`
setenv INFLUXDB_IP `kubectl get svc -n ricplt --field-selector metadata.name=ricplt-influxdb -o jsonpath='{.items[0].spec.clusterIP}'`

echo E2TERM_SCTP=$E2TERM_SCTP
echo KONG_PROXY=$KONG_PROXY
echo ONBOARDER_HTTP=$ONBOARDER_HTTP
echo APPMGR_HTTP=$APPMGR_HTTP
echo INFLUXDB_IP=$INFLUXDB_IP
echo NEXRAN_XAPP=$NEXRAN_XAPP
