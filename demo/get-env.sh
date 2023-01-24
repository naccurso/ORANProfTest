#!/bin/sh

E2TERM_SCTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-e2term-sctp-alpha -o jsonpath='{.items[0].spec.clusterIP}'`
KONG_PROXY=`kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
ONBOARDER_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-xapp-onboarder-http -o jsonpath='{.items[0].spec.clusterIP}'`
APPMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-rmr -o jsonpath='{.items[0].spec.clusterIP}'`
INFLUXDB_IP=`kubectl get svc -n ricplt --field-selector metadata.name=ricplt-influxdb -o jsonpath='{.items[0].spec.clusterIP}'`

echo E2TERM_SCTP=$E2TERM_SCTP
echo KONG_PROXY=$KONG_PROXY
echo ONBOARDER_HTTP=$ONBOARDER_HTTP
echo APPMGR_HTTP=$APPMGR_HTTP
echo INFLUXDB_IP=$INFLUXDB_IP
echo NEXRAN_XAPP=$NEXRAN_XAPP

if [ -n "$tcsh" ]; then
    setenv E2TERM_SCTP "$E2TERM_SCTP"
    setenv KONG_PROXY "$KONG_PROXY"
    setenv ONBOARDER_HTTP "$ONBOARDER_HTTP"
    setenv APPMGR_HTTP "$APPMGR_HTTP"
    setenv NEXRAN_XAPP "$NEXRAN_XAPP"
    setenv INFLUXDB_IP "$INFLUXDB_IP"
else
    export E2TERM_SCTP
    export KONG_PROXY
    export ONBOARDER_HTTP
    export APPMGR_HTTP
    export NEXRAN_XAPP
    export INFLUXDB_IP
fi
