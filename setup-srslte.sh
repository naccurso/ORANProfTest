#!/bin/sh

set -x

export SRC=`dirname $0`
cd $SRC
. $SRC/setup-lib.sh

if [ -f $OURDIR/setup-srslte-done ]; then
    echo "setup-srslte already ran; not running again"
    exit 0
fi

cd $OURDIR

$SRC/setup-e2-bindings.sh

$SRC/setup-asn1c.sh

logtstart "srslte"

#
# srsLTE build
#
cd $OURDIR

maybe_install_packages \
    autoconf make libtool-bin cmake libfftw3-dev libmbedtls-dev libboost-program-options-dev \
    libconfig++-dev libsctp-dev libzmq3-dev iperf3

if [ ! -e srslte-ric ]; then
    git clone https://gitlab.flux.utah.edu/powderrenewpublic/srslte-ric
fi
cd srslte-ric
E2APVERSION="v02.03"
if [ $RICVERSION -lt $RICFRELEASE ]; then
    E2APVERSION="v01.01"
    git checkout oran-ric-e2ap-v1
fi
mkdir -p build
cd build
cmake ../ \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DRIC_GENERATED_E2AP_BINDING_DIR=$OURDIR/E2AP-${E2APVERSION} \
    -DRIC_GENERATED_E2SM_KPM_BINDING_DIR=$OURDIR/E2SM-KPM \
    -DRIC_GENERATED_E2SM_NI_BINDING_DIR=$OURDIR/E2SM-NI \
    -DRIC_GENERATED_E2SM_GNB_NRT_BINDING_DIR=$OURDIR/E2SM-GNB-NRT
NCPUS=`grep proc /proc/cpuinfo | wc -l`
if [ -n "$NCPUS" ]; then
    make -j$NCPUS
else
    make
fi
$SUDO make install
$SUDO ./srslte_install_configs.sh service

# Fix ue1's IP addr, for simulated demos.
$SUDO sed -ie 's/^\(ue1.*\),dynamic/\1,192.168.0.2/' \
    /etc/srslte/user_db.csv

maybe_install_packages crudini



logtend "srslte"
touch $OURDIR/setup-srslte-done
