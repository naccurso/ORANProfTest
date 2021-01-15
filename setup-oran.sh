#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/setup-oran-done ]; then
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

logtend "oran"
touch $OURDIR/setup-oran-done
