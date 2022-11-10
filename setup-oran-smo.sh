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
helm repo remove local
helm repo add local http://$myip:8878/charts

#
# Deploy the SMO.
#
DEPREPO=http://gerrit.o-ran-sc.org/r/it/dep
DEPBRANCH=$RICRELEASE
if [ $RICVERSION -eq $RICCHERRY ]; then
    DEPREPO=https://gitlab.flux.utah.edu/powderrenewpublic/dep
    DEPBRANCH=cherry-powder
elif [ $RICVERSION -eq $RICDAWN ]; then
    DEPREPO=https://gitlab.flux.utah.edu/powderrenewpublic/dep
    DEPBRANCH=dawn-powder
fi
git clone $DEPREPO -b $DEPBRANCH
cd dep
git submodule update --init --recursive --remote
git submodule update

cd smo-install
scripts/layer-1/1-build-all-charts.sh
scripts/layer-2/2-install-oran.sh
if [ -n "$INSTALLORANSCSMOSIM" -a $INSTALLORANSCSMOSIM -eq 1 ]; then
    scripts/layer-2/2-install-simulators.sh
fi

logtend "oran-smo"
touch $OURDIR/setup-oran-smo-done
