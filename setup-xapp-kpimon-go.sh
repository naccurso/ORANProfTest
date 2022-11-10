#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-xapp-kpimon-go-done ]; then
    exit 0
fi

logtstart "xapp-kpimon-go"

# kubectl get pods -n ricplt  -l app=ricplt-e2term -o jsonpath='{..status.podIP}'
KONG_PROXY=`kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
APPMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
ONBOARDER_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-xapp-onboarder-http -o jsonpath='{.items[0].spec.clusterIP}'`

curl --location --request GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"

#
# Onboard and deploy our modified scp-kpimon app.
#
# There are bugs in the initial version; and we don't have e2sm-kpm-01.02, so
# we handle both those things.
#
cd $OURDIR

if [ -n "$BUILDORANSC" -a "$BUILDORANSC" = "1" ]; then
    git clone https://gitlab.flux.utah.edu/powderrenewpublic/kpimon-go.git
    cd kpimon-go
    git checkout powder
    # Build this image and place it in our local repo, so that the onboard
    # file can use this repo, and the kubernetes ecosystem can pick it up.
    $SUDO docker build . --tag $HEAD:5000/kpimon-go:powder
    $SUDO docker push $HEAD:5000/kpimon-go:powder
    KPIMON_REGISTRY=${HEAD}.cluster.local:5000
    KPIMON_NAME="kpimon-go"
    KPIMON_TAG=powder
else
    KPIMON_REGISTRY="gitlab.flux.utah.edu:4567"
    KPIMON_NAME="powder-profiles/oran/kpimon-go"
    KPIMON_TAG=latest
    $SUDO docker pull ${KPIMON_REGISTRY}/${KPIMON_NAME}:${KPIMON_TAG}
fi

MIP=`getnodeip $HEAD $MGMTLAN`

cat <<EOF >$WWWPUB/kpimon-go-config-file.json
{
    "json_url": "kpimon-go",
    "xapp_name": "kpimon-go",
    "version": "1.0.0",
    "containers": [
        {
            "name": "kpimon-go-xapp",
            "image": {
                "registry": "${KPIMON_REGISTRY}",
                "name": "${KPIMON_NAME}",
                "tag": "${KPIMON_TAG}"
            }
        }
    ],
    "messaging": {
        "ports": [
            {
                "name": "http",
                "container": "xappkpimon",
                "port": 8080,
        	"description": "http service"
	    },
            {
                "name": "rmr-data",
                "container": "kpimon-go-xapp",
                "port": 4560,
                "rxMessages": [ "RIC_SUB_RESP", "RIC_SUB_FAILURE", "RIC_INDICATION", "RIC_SUB_DEL_RESP", "RIC_SUB_DEL_FAILURE" ],
                "txMessages": [ "RIC_SUB_REQ", "RIC_SUB_DEL_REQ" ],
                "policies": [1],
                "description": "rmr receive data port for kpimon-go-xapp"
            },
            {
                "name": "rmr-route",
                "container": "kpimon-go-xapp",
                "port": 4561,
                "description": "rmr route port for kpimon-go-xapp"
            }
        ]
    },
    "rmr": {
        "protPort": "tcp:4560",
        "maxSize": 2072,
        "numWorkers": 1,
        "txMessages": [ "RIC_SUB_REQ", "RIC_SUB_DEL_REQ" ],
        "rxMessages": [ "RIC_SUB_RESP", "RIC_SUB_FAILURE", "RIC_INDICATION", "RIC_SUB_DEL_RESP", "RIC_SUB_DEL_FAILURE" ],
	"policies": [1]
    }
}
EOF
cat <<EOF >$WWWPUB/kpimon-go-onboard.url
{"config-file.json_url":"http://$MIP:7998/kpimon-go-config-file.json"}
EOF

if [ -n "$DOKPIMONGODEPLOY" -a $DOKPIMONGODEPLOY -eq 1 ]; then
    if [ $RICVERSION -gt $RICDAWN ]; then
	$OURDIR/oran/dms_cli onboard \
	    --config_file_path=$WWWPUB/kpimon-go-config-file.json \
	    --shcema_file_path=$OURDIR/appmgr/xapp_orchestrater/dev/docs/xapp_onboarder/guide/embedded-schema.json
	$OURDIR/oran/dms_cli install \
	    --xapp_chart_name=kpimon-go --version=1.0.0 --namespace=ricxapp
    else
	curl -L -X POST \
            "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
            --header 'Content-Type: application/json' \
	    --data-binary "@${WWWPUB}/kpimon-go-onboard.url"

	curl -L -X GET \
            "http://$KONG_PROXY:32080/onboard/api/v1/charts"

	curl -L -X POST \
	    "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
	    --header 'Content-Type: application/json' \
	    --data-raw '{"xappName": "kpimon-go"}'
    fi
fi

logtend "xapp-kpimon-go"
touch $OURDIR/setup-xapp-kpimon-go-done

exit 0
