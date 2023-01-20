#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-oran-smo-done ]; then
    exit 0
fi

logtstart "oran-smo"

mkdir -p $OURDIR/oran-smo
cd $OURDIR/oran-smo

myip=`getnodeip $HEAD $MGMTLAN`

#
# Install helm push plugin.
#
TAR_FILE=helm-push_0.9.0_linux_amd64.tar.gz
HELM_PLUGINS=`helm env HELM_PLUGINS`
mkdir -p $HELM_PLUGINS/helm-push
cd $HELM_PLUGINS/helm-push
wget https://github.com/chartmuseum/helm-push/releases/download/v0.9.0/helm-push_0.9.0_linux_amd64.tar.gz
tar -xzvf helm-push_0.9.0_linux_amd64.tar.gz
rm -f helm-push_0.9.0_linux_amd64.tar.gz
cd $OURDIR/oran-smo

#
# Install custom ONAP deploy/undeploy plugins.
# (https://wiki.onap.org/display/DW/OOM+Helm+%28un%29Deploy+plugins)
#
cd $OURDIR/oran-smo
git clone https://github.com/onap/oom
cd oom
helm plugin install kubernetes/helm/plugins/deploy
helm plugin install kubernetes/helm/plugins/undeploy
cd ..

#
# Deploy the SMO.
#
cd $OURDIR/oran-smo
DEPREPO=http://gerrit.o-ran-sc.org/r/it/dep
DEPBRANCH=$OSCSMOVERSION
git clone $DEPREPO -b $DEPBRANCH
cd dep
git submodule update --init --recursive --remote
git submodule update

#
# Performance hack: pre-pull image content if we might have a mirror.
#
# NB: this is just the blobs.  We (k8s) will have to hit the original
# registry for each image as it deploys to grab the manifest.  But we will
# at least have the blobs.
#
echo "$DOCKEROPTIONS" | grep registry-mirror
if [ $? -eq 0 -a -e /local/repository/etc/osc-ric-cached-image-list-${OSCSMOVERSION}.txt ]; then
    for image in `cat /local/repository/etc/osc-smo-cached-image-list-${OSCSMOVERSION}.txt` ; do
	docker pull $image
    done
fi

cd smo-install
cd helm-override
mkdir -p powder
cp -pv default/* powder/
cat <<EOF >powder/powder-oran-override.yaml
global:
  persistence:
    mountPath: /storage/nfs/deployment-1

a1policymanagement:
  enabled: false
  rics: []
EOF
yq m --inplace --overwrite powder/oran-override.yaml \
    powder/powder-oran-override.yaml
cat <<EOF >powder/powder-onap-override.yaml
global:
  persistence:
    mountPath: /storage/nfs/deployment-1
EOF
yq m --inplace --overwrite powder/oran-override.yaml \
    powder/powder-oran-override.yaml
cd ..

#
# NB: f-release nexus servers dropped the simulator 1.4.5 versions; upgrade
# to 1.5.0 .
#
if [ "$OSCSMOVERSION" = "f-release" ]; then
    cd helm-override
    cat <<EOF >powder/powder-network-simulators-override.yaml
ru-simulator:
  image:
    repository: 'nexus3.o-ran-sc.org:10002/o-ran-sc'
    name: nts-ng-o-ran-ru-fh
    tag: 1.5.0
    pullPolicy: IfNotPresent

du-simulator:
  image:
    repository: 'nexus3.o-ran-sc.org:10002/o-ran-sc'
    name: nts-ng-o-ran-du
    tag: 1.5.0
    pullPolicy: IfNotPresent

topology-server:
  image:
    repository: 'nexus3.o-ran-sc.org:10002/o-ran-sc'
    name: smo-nts-ng-topology-server
    tag: 1.5.0
    pullPolicy: IfNotPresent
EOF
    yq m --inplace --overwrite powder/network-simulators-override.yaml \
        powder/powder-network-simulators-override.yaml
    cd ..
fi

if [ -n "$OSCSMOUSECACHEDCHARTS" -a $OSCSMOUSECACHEDCHARTS -eq 1 ]; then
    helm repo add osc-smo-powder-${OSCSMOVERSION} \
        https://gitlab.flux.utah.edu/api/v4/projects/1869/packages/helm/powder-osc-smo-${OSCSMOVERSION}
    helm repo update
    kubectl create namespace strimzi-system
    helm -n strimzi-system strimzi-kafka-operator \
        osc-smo-powder-${OSCSMOVERSION}/strimzi-kafka-operator --version 0.28.0 \
        --set watchAnyNamespace=true --wait --timeout 600
    kubectl create namespace onap
    helm -n onap deploy --debug onap osc-smo-powder-${OSCSMOVERSION}/onap \
        -f /local/setup/oran-smo/dep/smo-install/helm-override/powder/onap-override.yml \
	--wait --timeout 3600
    kubectl create namespace nonrtric
    helm -n nonrtric deploy --debug nonrtric osc-smo-powder-${OSCSMOVERSION}/nonrtric \
        -f /local/setup/oran-smo/dep/smo-install/helm-override/powder/onap-override.yml \
	--wait --timeout 1200
else
    cd $OURDIR/oran-smo
    helm repo remove local
    helm repo add local http://$myip:8878/charts

    scripts/layer-1/1-build-all-charts.sh
    scripts/layer-2/2-install-oran.sh powder
    if [ -n "$INSTALLORANSCSMOSIM" -a $INSTALLORANSCSMOSIM -eq 1 ]; then
	scripts/layer-2/2-install-simulators.sh powder
    fi
fi

kubectl -n onap wait deployments --for condition=Available
# Kp8bJ4SXszM0WXlhak3eHlcse2gAw84vaoGGmJvUy2U
kubectl -n onap expose service sdnc-web-service \
    --port=8443 --target-port=8443 --name sdnc-web-service-ext \
    --external-ip=`cat /var/emulab/boot/myip`

logtend "oran-smo"
touch $OURDIR/setup-oran-smo-done
