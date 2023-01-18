#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-sdran-done ]; then
    exit 0
fi

logtstart "sdran"

mkdir -p $OURDIR/sdran
cd $OURDIR/sdran

helm repo add cord https://charts.opencord.org
helm repo add atomix https://charts.atomix.io
helm repo add onos https://charts.onosproject.org
helm repo add sdran https://sdrancharts.onosproject.org
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
if [ $ONFRICPOWDER -eq 1 ]; then
    helm repo add sdran-powder https://gitlab.flux.utah.edu/api/v4/projects/2210/packages/helm/powder
    fi
helm repo update
if [ ! $? -eq 0 ]; then
    echo "ERROR: failed to update helm with SD-RAN repos; aborting!"
    exit 1
fi

if `echo "$ONFRICVERSION" | grep -q '1\.2'`; then
    # 1.2.x values
    SDRAN_ATOMIX_CONTROLLER_VERSION="0.6.7"
    SDRAN_ATOMIX_RAFT_VERSION="0.1.8"
    SDRAN_ONOS_OPERATOR_VERSION="0.4.6"
elif `echo "$ONFRICVERSION" | grep -q '1\.3'`; then
    # 1.3.x values
    SDRAN_ATOMIX_CONTROLLER_VERSION="0.6.8"
    SDRAN_ATOMIX_RAFT_VERSION="0.1.15"
    SDRAN_ONOS_OPERATOR_VERSION="0.4.14"
else
    # 1.4.x values
    SDRAN_ATOMIX_CONTROLLER_VERSION="0.6.9"
    SDRAN_ATOMIX_RAFT_VERSION="0.1.25"
    SDRAN_ONOS_OPERATOR_VERSION="0.5.2"
fi

helm install -n kube-system atomix-controller atomix/atomix-controller --version $SDRAN_ATOMIX_CONTROLLER_VERSION --wait
helm install -n kube-system raft-storage-controller atomix/atomix-raft-storage --version $SDRAN_ATOMIX_RAFT_VERSION --wait
helm install -n kube-system onos-operator onos/onos-operator --version $SDRAN_ONOS_OPERATOR_VERSION --wait

kubectl create namespace sd-ran

helm install -n sd-ran kube-prometheus-stack prometheus-community/kube-prometheus-stack --wait

cat <<EOF >$OURDIR/sdran-values.yaml
import:
  onos-kpimon:
    enabled: true
  onos-exporter:
    enabled: true
onos-kpimon:
  logging:
    loggers:
      root:
        level: debug
onos-kpimon-v2:
  enabled: true
  logging:
    loggers:
      root:
        level: debug
onos-exporter:
  prometheus-stack:
    enabled: true
onos-exporter:
  import:
    prometheus-stack:
      enabled: true
EOF
SDRAN_CHARTREF="sdran/sd-ran"
if [ $ONFRICPOWDER -eq 1 ]; then
    SDRAN_CHARTREF="sdran-powder/sd-ran"
fi
helm install -n sd-ran sd-ran $SDRAN_CHARTREF -f $OURDIR/sdran-values.yaml --version $ONFRICVERSION --wait

logtend "sdran"
touch $OURDIR/setup-sdran-done
