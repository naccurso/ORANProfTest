#!/bin/sh

export E2TERM_SCTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-e2term-sctp-alpha -o jsonpath='{.items[0].spec.clusterIP}'`
export KONG_PROXY=`kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
export ONBOARDER_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-xapp-onboarder-http -o jsonpath='{.items[0].spec.clusterIP}'`
export APPMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-nbi -o jsonpath='{.items[0].spec.clusterIP}'`
if [ -z "$NEXRAN_XAPP" ]; then
    export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-rmr -o jsonpath='{.items[0].spec.clusterIP}'`
fi
export INFLUXDB_IP=`kubectl get svc -n ricxapp --field-selector metadata.name=ricxapp-influxdb -o jsonpath='{.items[0].spec.clusterIP}'`
INFLUXDB_USER=`kubectl -n ricxapp get secrets custom-influxdb-secret -o jsonpath="{.data.influxdb-user}" | base64 --decode`
INFLUXDB_PASS=`kubectl -n ricxapp get secrets custom-influxdb-secret -o jsonpath="{.data.influxdb-password}" | base64 --decode`
IARGS=""
if [ -n "$INFLUXDB_USER" ]; then
    IARGS="${INFLUXDB_USER}"
    if [ -n "$INFLUXDB_PASS" ]; then
	IARGS="${IARGS}:$INFLUXDB_PASS"
    fi
    IARGS="${IARGS}@"
fi
export INFLUXDB_URL="http://${IARGS}${INFLUXDB_IP}:8086/"
export DBAAS_IP=`kubectl -n ricplt get pods/statefulset-ricplt-dbaas-server-0 -o jsonpath='{.status.podIP}'`

echo E2TERM_SCTP=$E2TERM_SCTP
echo KONG_PROXY=$KONG_PROXY
echo ONBOARDER_HTTP=$ONBOARDER_HTTP
echo APPMGR_HTTP=$APPMGR_HTTP
echo INFLUXDB_IP=$INFLUXDB_IP
echo INFLUXDB_URL=$INFLUXDB_URL
echo NEXRAN_XAPP=$NEXRAN_XAPP
echo DBAAS_IP=$DBAAS_IP
