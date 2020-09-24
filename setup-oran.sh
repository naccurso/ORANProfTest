#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/oran-done ]; then
    exit 0
fi

logtstart "oran"

mkdir -p $OURDIR/oran
cd $OURDIR/oran

# Login to o-ran docker registry server (both staging and release) so
# that Dockerfile base images can be pulled.
$SUDO docker login -u docker -p docker https://nexus3.o-ran-sc.org:10004
$SUDO docker login -u docker -p docker https://nexus3.o-ran-sc.org:10002
$SUDO chown -R $SWAPPER ~/.docker

#
# Custom-build any O-RAN components we might need.
#
git clone https://gerrit.o-ran-sc.org/r/ric-plt/submgr
cd submgr
git checkout f0d95262aba5c1d3770bd173d8ce054334b8a162
$SUDO docker build . -t ${HEAD}.cluster.local:5000/submgr:0.5.0
$SUDO docker push ${HEAD}.cluster.local:5000/submgr:0.5.0

#
# Deploy the platform.
#
git clone http://gerrit.o-ran-sc.org/r/it/dep -b bronze
cd dep
git submodule update --init --recursive --remote

helm init --client-only

cp RECIPE_EXAMPLE/PLATFORM/example_recipe.yaml $OURDIR/oran
cat <<EOF >$OURDIR/oran/example_recipe.yaml-override
submgr:
  image:
    registry: "node-0.cluster.local:5000"
    name: submgr
    tag: 0.5.0
EOF
yq m --inplace --overwrite $OURDIR/oran/example_recipe.yaml \
    $OURDIR/oran/example_recipe.yaml-override

cd bin
./deploy-ric-platform -f $OURDIR/oran/example_recipe.yaml
for ns in ricplt ricinfra ricxapp ; do
    kubectl get pods -n $ns
    kubectl wait pod -n $ns --for=condition=Ready --all
done

KONG_PROXY=`kubectl get svc -n ricplt | sed -nre 's/^.* *kong-proxy *NodePort *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`
E2MGR_HTTP=`kubectl get svc -n ricplt | sed -nre 's/^.* *e2mgr-http *ClusterIP *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`
APPMGR_HTTP=`kubectl get svc -n ricplt | sed -nre 's/^.* *appmgr-http *ClusterIP *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`
E2TERM_SCTP=`kubectl get svc -n ricplt | sed -nre 's/^.* *e2term-sctp.* *NodePort *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`
ONBOARDER_HTTP=`kubectl get svc -n ricplt | sed -nre 's/^.* *xapp-onboarder-http *ClusterIP *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`
RTMGR_HTTP=`kubectl get svc -n ricplt | sed -nre 's/^.* *rtmgr-http *ClusterIP *([0-9]*\.[0-9]*\.[0-9]*\.[0-9]*) .*$/\1/p'`

curl --location --request GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"

#
# Onboard and deploy our (slightly) modified scp-kpimon app.
#
cd $OURDIR/oran
git clone https://gitlab.flux.utah.edu/powderrenewpublic/ric-scp-kpimon.git
cd ric-scp-kpimon
# Build this image and place it in our local repo, so that the onboard
# file can use this repo, and the kubernetes ecosystem can pick it up.
#
# NB: The current build relies upon a non-existent image, so just use
# the newer image.
$SUDO docker pull \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:9-u18.04
$SUDO docker tag \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:9-u18.04 \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:8-u18.04
$SUDO docker build . --tag $HEAD:5000/scp-kpimon:latest
$SUDO docker push $HEAD:5000/scp-kpimon:latest

MIP=`getnodeip $HEAD $MGMTLAN`

cat <<EOF >$WWWPUB/scp-kpimon-config-file.json
{
    "json_url": "scp-kpimon",
    "xapp_name": "scp-kpimon",
    "version": "1.0.1",
    "containers": [
        {
            "name": "scp-kpimon-xapp",
            "image": {
                "registry": "${HEAD}.cluster.local:5000",
                "name": "scp-kpimon",
                "tag": "latest"
            }
        }
    ],
    "messaging": {
        "ports": [
            {
                "name": "rmr-data",
                "container": "scp-kpimon-xapp",
                "port": 4560,
                "rxMessages": [ "RIC_SUB_RESP", "RIC_SUB_FAILURE", "RIC_INDICATION", "RIC_SUB_DEL_RESP", "RIC_SUB_DEL_FAILURE" ],
                "txMessages": [ "RIC_SUB_REQ", "RIC_SUB_DEL_REQ" ],
                "policies": [1],
                "description": "rmr receive data port for scp-kpimon-xapp"
            },
            {
                "name": "rmr-route",
                "container": "scp-kpimon-xapp",
                "port": 4561,
                "description": "rmr route port for scp-kpimon-xapp"
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
cat <<EOF >$WWWPUB/scp-kpimon-onboard.url
{"config-file.json_url":"http://$MIP:7998/scp-kpimon-config-file.json"}
EOF

if [ -n "$DOKPIMONDEPLOY" -a $DOKPIMONDEPLOY -eq 1 ]; then
    curl -L -X POST \
        "http://$KONG_PROXY:32080/onboard/api/v1/onboard/download" \
        --header 'Content-Type: application/json' \
	--data-binary "@${WWWPUB}/scp-kpimon-onboard.url"

    curl -L -X GET \
        "http://$KONG_PROXY:32080/onboard/api/v1/charts"

    curl -L -X POST \
	"http://$KONG_PROXY:32080/appmgr/ric/v1/xapps" \
	--header 'Content-Type: application/json' \
	--data-raw '{"xappName": "scp-kpimon"}'
fi

logtend "oran"
touch $OURDIR/oran-done
