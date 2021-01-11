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
# NB: The current build relies upon a non-existent image, so just use
# the newer image.
#
$SUDO docker pull \
    nexus3.o-ran-sc.org:10002/o-ran-sc/bldr-ubuntu18-c-go:1.9.0
$SUDO docker tag \
    nexus3.o-ran-sc.org:10002/o-ran-sc/bldr-ubuntu18-c-go:1.9.0 \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:1.9.0
$SUDO docker tag \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:1.9.0 \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:9-u18.04
$SUDO docker tag \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:9-u18.04 \
    nexus3.o-ran-sc.org:10004/o-ran-sc/bldr-ubuntu18-c-go:8-u18.04

#
# Custom-build the O-RAN components we might need.  Bronze release is
# pretty much ok, but there are two components that need upgrades from
# master:
#
# * e2term must not attempt to decode the E2SMs (it only supported
#   E2SM-gNB-NRT when it was decoding them)
# * submgr must not decode the E2SMs.
#
#git clone https://gerrit.o-ran-sc.org/r/ric-plt/e2
git clone https://gitlab.flux.utah.edu/powderrenewpublic/e2
cd e2
#git checkout 3f5c142bdef909687e4634ef5af22b4b280ecddf
cd RIC-E2-TERMINATION
$SUDO docker build -f Dockerfile -t ${HEAD}.cluster.local:5000/e2term:5.4.8 .
$SUDO docker push ${HEAD}.cluster.local:5000/e2term:5.4.8
cd ../..

git clone https://gerrit.o-ran-sc.org/r/ric-plt/submgr
cd submgr
git checkout f0d95262aba5c1d3770bd173d8ce054334b8a162
$SUDO docker build . -t ${HEAD}.cluster.local:5000/submgr:0.5.0
$SUDO docker push ${HEAD}.cluster.local:5000/submgr:0.5.0
cd ..

#
# Deploy the platform.
#
git clone http://gerrit.o-ran-sc.org/r/it/dep -b bronze
cd dep
git submodule update --init --recursive --remote

helm init --client-only --stable-repo-url "https://charts.helm.sh/stable"

cp RECIPE_EXAMPLE/PLATFORM/example_recipe.yaml $OURDIR/oran
cat <<EOF >$OURDIR/oran/example_recipe.yaml-override
e2term:
  alpha:
    image:
      registry: "${HEAD}.cluster.local:5000"
      name: e2term
      tag: 5.4.8
submgr:
  image:
    registry: "${HEAD}.cluster.local:5000"
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

# kubectl get pods -n ricplt  -l app=ricplt-e2term -o jsonpath='{..status.podIP}'
KONG_PROXY=`kubectl get svc -n ricplt -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].spec.clusterIP}'`
E2MGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-e2mgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
APPMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-appmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`
E2TERM_SCTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-e2term-sctp-alpha -o jsonpath='{.items[0].spec.clusterIP}'`
ONBOARDER_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-xapp-onboarder-http -o jsonpath='{.items[0].spec.clusterIP}'`
RTMGR_HTTP=`kubectl get svc -n ricplt --field-selector metadata.name=service-ricplt-rtmgr-http -o jsonpath='{.items[0].spec.clusterIP}'`

curl --location --request GET "http://$KONG_PROXY:32080/onboard/api/v1/charts"

#
# Onboard and deploy our modified scp-kpimon app.
#
# There are bugs in the initial version; and we don't have e2sm-kpm-01.02, so
# we handle both those things.
#
cd $OURDIR/oran
git clone https://gitlab.flux.utah.edu/powderrenewpublic/ric-scp-kpimon.git
cd ric-scp-kpimon
git checkout revert-to-e2sm-kpm-01.00
# Build this image and place it in our local repo, so that the onboard
# file can use this repo, and the kubernetes ecosystem can pick it up.
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
    "appenv": { "ranList":"enB_macro_661_8112_0019b0" },
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
