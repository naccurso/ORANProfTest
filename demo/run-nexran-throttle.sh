#!/bin/sh

SLEEPINT=$1
if [ -z "$SLEEPINT" ]; then
    SLEEPINT=4
fi

export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-nbi -o jsonpath='{.items[0].spec.clusterIP}'`
if [ -z "$NEXRAN_XAPP" ]; then
    export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-rmr -o jsonpath='{.items[0].spec.clusterIP}'`
fi
if [ -z "$NEXRAN_XAPP" ]; then
    echo "ERROR: failed to find nexran nbi service; aborting!"
    exit 1
fi

echo NEXRAN_XAPP=$NEXRAN_XAPP ; echo


echo Creating Simulated NodeB: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"type":"eNB","id":411,"mcc":"001","mnc":"01"}' http://${NEXRAN_XAPP}:8000/v1/nodebs ; echo ; echo ;

sleep $SLEEPINT

echo Creating "'fast'" Slice: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"name":"fast","allocation_policy":{"type":"proportional","share":512,"auto_equalize":false,"throttle":true,"throttle_threshold":50000000,"throttle_period":30,"throttle_target":5000000}}' http://${NEXRAN_XAPP}:8000/v1/slices ; echo ; echo ;

sleep $SLEEPINT

echo Creating "'slow'" Slice: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"name":"slow","allocation_policy":{"type":"proportional","share":256}}' http://${NEXRAN_XAPP}:8000/v1/slices ; echo ; echo ;

sleep $SLEEPINT

echo Binding "'fast'" Slice to NodeB: ; echo
curl -i -X POST http://${NEXRAN_XAPP}:8000/v1/nodebs/enB_macro_001_001_00019b/slices/fast ; echo ; echo ;

sleep $SLEEPINT

echo Binding "'slow'" Slice to NodeB: ; echo
curl -i -X POST http://${NEXRAN_XAPP}:8000/v1/nodebs/enB_macro_001_001_00019b/slices/slow ; echo ; echo ;

sleep $SLEEPINT

echo Creating UE 001010123456789: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"imsi":"001010123456789"}' http://${NEXRAN_XAPP}:8000/v1/ues ; echo ; echo ;

sleep $SLEEPINT

echo Binding UE "'001010123456789'" to Slice "'fast'": ; echo
curl -i -X POST http://${NEXRAN_XAPP}:8000/v1/slices/fast/ues/001010123456789 ; echo ; echo

