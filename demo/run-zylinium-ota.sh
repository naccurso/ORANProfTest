#!/bin/sh

set -x

SLEEPINT=$1
if [ -z "$SLEEPINT" ]; then
    SLEEPINT=4
fi

if [ -z "$NEXRAN_URL" ]; then
    NEXRAN_XAPP=`kubectl get svc -n ricxapp --field-selector metadata.name=service-ricxapp-nexran-nbi -o jsonpath='{.items[0].spec.clusterIP}'`
    if [ -z "$NEXRAN_XAPP" ]; then
	echo "ERROR: cannot find your NexRAN xApp; might need to recreate it."
	exit 1
    fi
    echo NEXRAN_XAPP=$NEXRAN_XAPP ; echo

    NEXRAN_URL=http://${NEXRAN_XAPP}:8000
fi

echo Creating first NodeB: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"type":"eNB","id":1,"mcc":"001","mnc":"01","ul_mask_def":"0xfffe000"}' ${NEXRAN_URL}/v1/nodebs ; echo ; echo ;

sleep $SLEEPINT

echo Setting default uplink mask: ; echo
curl -i -X PUT -H "Content-type: application/json" -d '{"ul_mask_def":"0xfffe000"}' ${NEXRAN_URL}/v1/nodebs/enB_macro_001_001_000001 ; echo ; echo ;

sleep $SLEEPINT

echo Creating second NodeB: ; echo
curl -i -X POST -H "Content-type: application/json" -d '{"type":"eNB","id":2,"mcc":"001","mnc":"01","ul_mask_def":"0x001fff"}' ${NEXRAN_URL}/v1/nodebs ; echo ; echo ;

sleep $SLEEPINT

echo Changing default uplink mask: ; echo
curl -i -X PUT -H "Content-type: application/json" -d '{"ul_mask_def":"0x001fff"}' ${NEXRAN_URL}/v1/nodebs/enB_macro_001_001_000002 ; echo ; echo ;

sleep $SLEEPINT

echo Setting an uplink schedule: ; echo
curl -i -X PUT -H "Content-type: application/json" -d '{"ul_mask_sched":[{"mask":"0x00ffff","start":'`echo "import time; print(time.time() + 60)" | python`'},{"mask":"0x001fff","start":'`echo "import time; print(time.time() + 120)" | python`'},{"mask":"0x00ffff","start":'`echo "import time; print(time.time() + 180)" | python`'},{"mask":"0x001fff","start":'`echo "import time; print(time.time() + 240)" | python`'}]}' ${NEXRAN_URL}/v1/nodebs/enB_macro_001_001_000002 ; echo ; echo ;
