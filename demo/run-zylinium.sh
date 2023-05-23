#!/bin/sh

set -x

SLEEPINT=$1
if [ -z "$SLEEPINT" ]; then
    SLEEPINT=4
fi

if [ -z "$NEXRAN_URL" ]; then
    export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-nbi -o jsonpath='{.items[0].spec.clusterIP}'`
    if [ -z "$NEXRAN_XAPP" ]; then
	export NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-rmr -o jsonpath='{.items[0].spec.clusterIP}'`
    fi
    if [ -z "$NEXRAN_XAPP" ]; then
	echo "ERROR: cannot find your NexRAN xApp; might need to recreate it."
	exit 1
    fi
    echo NEXRAN_XAPP=$NEXRAN_XAPP ; echo

    NEXRAN_URL=http://${NEXRAN_XAPP}:8000
fi

echo NEXRAN_XAPP=$NEXRAN_XAPP ; echo

echo Listing NodeBs: ; echo
curl -i -X GET http://${NEXRAN_XAPP}:8000/v1/nodebs ; echo ; echo

sleep $SLEEPINT

echo Creating Simulated NodeB: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"type":"eNB","id":411,"mcc":"001","mnc":"01","ul_mask_def":"0xfe00000"}' ${NEXRAN_URL}/v1/nodebs ; echo ; echo

echo Verifying NodeB: ; echo
curl -i -X GET http://${NEXRAN_XAPP}:8000/v1/nodebs/enB_macro_001_001_00019b ; echo ; echo

sleep $SLEEPINT

echo Setting default uplink mask: ; echo
curl -i -X PUT -H "Content-type: application/json" -d '{"ul_mask_def":"0x000000"}' ${NEXRAN_URL}/v1/nodebs/enB_macro_001_001_00019b ; echo ; echo ;

sleep $SLEEPINT

echo Setting an uplink schedule: ; echo
curl -i -X PUT -H "Content-type: application/json" -d '{"ul_mask_sched":[{"mask":"0x00000f","start":'`echo "import time; print(time.time() + 8)" | python`'},{"mask":"0x000000","start":'`echo "import time; print(time.time() + 28)" | python`'},{"mask":"0x00000f","start":'`echo "import time; print(time.time() + 48)" | python`'},{"mask":"0x000000","start":'`echo "import time; print(time.time() + 68)" | python`'}]}' ${NEXRAN_URL}/v1/nodebs/enB_macro_001_001_00019b ; echo ; echo ;
