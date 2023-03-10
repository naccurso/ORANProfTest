#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-xapp-nexran-done ]; then
    exit 0
fi

logtstart "xapp-nexran"

maybe_install_packages jq

# kubectl get pods -n ricplt  -l app=ricplt-e2term -o jsonpath='{..status.podIP}'
KONG_PROXY=`kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
APPMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`

curl --location --request GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"

#
# Onboard and deploy our NexRAN xapp.
#
# There are bugs in the initial version; and we don't have e2sm-kpm-01.02, so
# we handle both those things.
#
cd $OURDIR
git clone https://gitlab.flux.utah.edu/powderrenewpublic/nexran.git

if [ $RICVERSION -lt $RICFRELEASE ]; then
    NEXRAN_TAG="e2ap-v1"
    NEXRAN_CONTAINER_NAME="nexran-xapp"
else
    NEXRAN_TAG=latest
    NEXRAN_CONTAINER_NAME="nexran"
fi

if [ -n "$BUILDORANSC" -a "$BUILDORANSC" = "1" ]; then
    cd nexran
    if [ $RICVERSION -lt $RICFRELEASE ]; then
	git checkout e2ap-v1
    fi
    # Build this image and place it in our local repo, so that the onboard
    # file can use this repo, and the kubernetes ecosystem can pick it up.
    $SUDO docker build . --tag $HEAD:5000/nexran:$NEXRAN_TAG
    $SUDO docker push $HEAD:5000/nexran:$NEXRAN_TAG
    NEXRAN_REGISTRY=${HEAD}.cluster.local:5000
    NEXRAN_NAME="nexran"
else
    NEXRAN_REGISTRY="gitlab.flux.utah.edu:4567"
    NEXRAN_NAME="powder-profiles/oran/nexran"
    $SUDO docker pull ${NEXRAN_REGISTRY}/${NEXRAN_NAME}:${NEXRAN_TAG}
fi


MIP=`getnodeip $HEAD $MGMTLAN`

cp -p $OURDIR/nexran/etc/config-file.json $WWWPUB/nexran-config-file.json
cat <<EOF >$WWWPUB/nexran-config-file.json.mod
{
    "containers": [
	{
	    "image": {
		"registry": "$NEXRAN_REGISTRY",
		"name": "$NEXRAN_NAME",
		"tag": "$NEXRAN_TAG"
	    },
	    "name": "$NEXRAN_CONTAINER_NAME"
	}
    ]
}
EOF
jq -s 'reduce .[] as $item ({}; . * $item)' \
    $WWWPUB/nexran-config-file.json \
    $WWWPUB/nexran-config-file.json.mod \
    > $WWWPUB/nexran-config-file.json.new
if [ -s $WWWPUB/nexran-config-file.json.new ]; then
    mv $WWWPUB/nexran-config-file.json.new $WWWPUB/nexran-config-file.json
else
    echo "ERROR: could not merge nexran image values into config-file.json; aborting!"
    exit 1
fi

cat <<EOF >$WWWPUB/nexran-onboard.url
{"config-file.json_url":"http://$MIP:7998/nexran-config-file.json"}
EOF

if [ -n "$DONEXRANDEPLOY" -a $DONEXRANDEPLOY -eq 1 ]; then
    if [ $RICVERSION -gt $RICDAWN ]; then
	$OURDIR/oran/dms_cli onboard \
	    --config_file_path=$WWWPUB/nexran-config-file.json \
	    --shcema_file_path=$OURDIR/appmgr/xapp_orchestrater/dev/docs/xapp_onboarder/guide/embedded-schema.json
	$OURDIR/oran/dms_cli install \
	    --xapp_chart_name=nexran --version=0.1.0 --namespace=ricxapp
    else
        curl -L -X POST \
            "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
            --header 'Content-Type: application/json' \
  	    --data-binary "@${WWWPUB}/nexran-onboard.url"

	curl -L -X GET \
            "http://$KONG_PROXY:32080/onboard/api/v1/charts"

	curl -L -X POST \
	    "http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
	    --header 'Content-Type: application/json' \
	    --data-raw '{"xappName": "nexran"}'
    fi
fi

logtend "xapp-nexran"
touch $OURDIR/setup-xapp-nexran-done

exit 0
