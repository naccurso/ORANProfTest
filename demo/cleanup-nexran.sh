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

echo Listing NodeBs: ; echo
curl -i -X GET http://${NEXRAN_XAPP}:8000/v1/nodebs ; echo ; echo
echo Listing Slices: ; echo
curl -i -X GET http://${NEXRAN_XAPP}:8000/v1/slices ; echo ; echo
echo Listing Ues: ; echo
curl -i -X GET http://${NEXRAN_XAPP}:8000/v1/ues ; echo ; echo

sleep $SLEEPINT

echo Deleting "'fast'" slice: ; echo
curl -i -X DELETE http://${NEXRAN_XAPP}:8000/v1/slices/fast ; echo ; echo

sleep $SLEEPINT

echo Deleting "'slow'" slice: ; echo
curl -i -X DELETE http://${NEXRAN_XAPP}:8000/v1/slices/slow ; echo ; echo

sleep $SLEEPINT

echo Deleting "'enB_macro_001_001_00019b'" NodeB: ; echo
curl -i -X DELETE http://${NEXRAN_XAPP}:8000/v1/nodebs/enB_macro_001_001_00019b ; echo ; echo

