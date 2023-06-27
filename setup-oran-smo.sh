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

KAPIMINOR=`kubectl version -o yaml | yq '.serverVersion.minor'`

#
# Install helm push plugin.
#
HELM_PLUGINS=`helm env HELM_PLUGINS`
mkdir -p $HELM_PLUGINS/helm-push
cd $HELM_PLUGINS/helm-push
wget https://github.com/chartmuseum/helm-push/releases/download/v0.9.0/helm-push_0.9.0_linux_amd64.tar.gz
tar -xzvf helm-push_0.9.0_linux_amd64.tar.gz
rm -f helm-push_0.9.0_linux_amd64.tar.gz
mkdir -p $HELM_PLUGINS/helm-cm-push
cd $HELM_PLUGINS/helm-cm-push
wget https://github.com/chartmuseum/helm-push/releases/download/v0.10.4/helm-push_0.10.4_linux_amd64.tar.gz
tar -xzvf helm-push_0.10.4_linux_amd64.tar.gz
rm -f helm-push_0.10.4_linux_amd64.tar.gz
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
# g-release was not tagged.
if [ $DEPBRANCH = "g-release" ]; then
    DEPBRANCH="d1457ddedb21c4f46e20016c56e4c4cd9e8666c2"
fi
git clone $DEPREPO
cd dep
git checkout $DEPBRANCH
git submodule update --init --recursive --remote
git submodule update

if [ -n "$KAPIMINOR" -a $KAPIMINOR -ge 25 ]; then
    perl -0777 -i.original -pe \
        's/apiVersion: policy\/v1beta1\nkind: PodDisruptionBudget/apiVersion: policy\/v1\nkind: PodDisruptionBudget/igs' \
	smo-install/onap_oom/kubernetes/common/mariadb-galera/templates/pdb.yaml
    rm -fv smo-install/onap_oom/kubernetes/common/mariadb-galera/templates/pdb.yaml.original
fi

#
# Performance hack: pre-pull image content if we might have a mirror.
#
# NB: this is just the blobs.  We (k8s) will have to hit the original
# registry for each image as it deploys to grab the manifest.  But we will
# at least have the blobs.
#
BGPULL=0
echo "$DOCKEROPTIONS" | grep registry-mirror
if [ $? -eq 0 -a -e /local/repository/etc/osc-smo-cached-image-list-${OSCSMOVERSION}.txt ]; then
    for image in `cat /local/repository/etc/osc-smo-cached-image-list-${OSCSMOVERSION}.txt` ; do
	$SUDO docker pull $image
    done &
    BGPULL=1
fi

cd smo-install
cd helm-override
mkdir -p powder
cp -pv default/* powder/
cat <<EOF >powder/powder-oran-override.yaml
global:
  persistence:
    mountPath: /storage/nfs/deployment-1

nonrtric:
  persistence:
    mountPath: /storage/nfs/deployment-1

a1policymanagement:
  enabled: false
  rics: []
EOF
if [ "$OSCSMOVERSION" = "g-release" ]; then
    cat <<EOF >powder/powder-oran-override.yaml
odu-app:
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/nonrtric-rapp-ransliceassurance
odu-app-ics-version:
  image:
    repository: nexus3.o-ran-sc.org:10002/o-ran-sc/nonrtric-rapp-ransliceassurance-icsversion

EOF
fi
yq --inplace ea '. as $item ireduce ({}; . * $item )' \
    powder/oran-override.yaml \
    powder/powder-oran-override.yaml
cat <<EOF >powder/powder-onap-override.yaml
global:
  persistence:
    mountPath: /storage/nfs/deployment-1
strimzi:
  enabled: true
  storageClassName: ""
dmaap:
  message-router:
    message-router-zookeeper:
      persistence:
        mountPath: "/storage/nfs/deployment-1"
    message-router-kafka:
      persistence:
        mountPath: "/storage/nfs/deployment-1"
EOF
yq --inplace ea '. as $item ireduce ({}; . * $item )' \
    powder/onap-override.yaml \
    powder/powder-onap-override.yaml
cd ..

#
# NB: f-release nexus servers dropped the simulator 1.4.5 versions; upgrade
# to 1.5.0 .
#
if [ "$OSCSMOVERSION" = "f-release" -o "$OSCSMOVERSION" = "g-release" ]; then
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
    yq --inplace ea '. as $item ireduce ({}; . * $item )' \
        powder/network-simulators-override.yaml \
        powder/powder-network-simulators-override.yaml
    cd ..
fi

USECACHEDCHARTS=0
if [ -n "$OSCSMOUSECACHEDCHARTS" -a $OSCSMOUSECACHEDCHARTS -eq 1 ]; then
    entries=`curl -o - https://gitlab.flux.utah.edu/api/v4/projects/1869/packages/helm/powder-osc-smo-${OSCSMOVERSION}/index.yaml | yq '.entries'`
    if [ -z "$entries" -o "$entries" = "{}" -o "$entries" = "null" ]; then
	USECACHEDCHARTS=0
    else
	USECACHEDCHARTS=1
    fi
fi
#
# Need strimzi 0.29.0 for kube API >= 1.22
# And that strimzi has trouble with computing its max mem due to lack
# of cgroups v2 support, so bump its limit.
#
if [ -n "$KAPIMINOR" -a $KAPIMINOR -ge 22 ]; then
    STRIMZIVERSION=0.29.0
else
    STRIMZIVERSION=0.28.0
fi
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
    --namespace strimzi-system --version $STRIMZIVERSION \
    --set resources.limits.memory=1Gi --set resources.requests.memory=1Gi \
    --set watchAnyNamespace=true --create-namespace \
    --wait --timeout 300s
if [ ! -e /dockerdata-nfs ]; then
    $SUDO ln -s /storage/nfs /dockerdata-nfs
fi
if [ $USECACHEDCHARTS -eq 1 ]; then
    helm repo add osc-smo-powder-${OSCSMOVERSION} \
        https://gitlab.flux.utah.edu/api/v4/projects/1869/packages/helm/powder-osc-smo-${OSCSMOVERSION}
    helm repo update
    kubectl create namespace onap
    helm -n onap deploy --debug onap osc-smo-powder-${OSCSMOVERSION}/onap \
        -f $OURDIR/oran-smo/dep/smo-install/helm-override/powder/onap-override.yaml
    kubectl -n onap wait deployments --for condition=Available --all
    kubectl create namespace nonrtric
    helm -n nonrtric install --debug oran-nonrtric osc-smo-powder-${OSCSMOVERSION}/nonrtric \
        -f $OURDIR/oran-smo/dep/smo-install/helm-override/powder/oran-override.yaml
    kubectl -n nonrtric wait deployments --for condition=Available --all
    if [ -n "$INSTALLORANSCSMOSIM" -a $INSTALLORANSCSMOSIM -eq 1 ]; then
	helm install -n network --create-namespace --debug oran-simulator \
	    osc-smo-powder-f-release/ru-du-simulators \
	    -f $OURDIR/oran-smo/dep/smo-install/helm-override/powder/network-simulators-override.yaml \
	    -f $OURDIR/oran-smo/dep/smo-install/helm-override/powder/network-simulators-topology-override.yaml
    fi
else
    helm repo remove local
    helm repo add local http://$myip:8878/charts

    cd $OURDIR/oran-smo/dep/smo-install
    for f in `grep -rnl ' push -f ' | xargs` ; do
	echo "Converting $f to cm-push..."
	sed -i '' -e 's/ push -f / cm-push -f /g' $f
    done
    scripts/layer-1/1-build-all-charts.sh
    scripts/layer-2/2-install-oran.sh powder
    if [ -n "$INSTALLORANSCSMOSIM" -a $INSTALLORANSCSMOSIM -eq 1 ]; then
	scripts/layer-2/2-install-simulators.sh powder
    fi
fi

kubectl -n onap wait deployments --all --for condition=Available --timeout=60m
# Kp8bJ4SXszM0WXlhak3eHlcse2gAw84vaoGGmJvUy2U
kubectl -n onap expose service sdnc-web-service \
    --port=8443 --target-port=8443 --name sdnc-web-service-ext \
    --external-ip=`cat /var/emulab/boot/myip`

if [ $BGPULL -eq 1 ]; then
    wait
fi

logtend "oran-smo"
touch $OURDIR/setup-oran-smo-done
