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
git clone http://gerrit.o-ran-sc.org/r/it/dep -b bronze
cd dep
git submodule update --init --recursive --remote

cd bin
./deploy-ric-platform -f ../RECIPE_EXAMPLE/PLATFORM/example_recipe.yaml
for ns in ricplt ricinfra ricxapp ; do
    kubectl get pods -n $ns
    kubectl wait pod -n $ns --for=condition=Ready --all
done

logtend "oran"
touch $OURDIR/oran-done
