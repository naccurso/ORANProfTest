#!/bin/bash

set -x

# Preserve legacy main logfile location
ln -s /local/logs/setup.log /local/setup/setup-driver.log

export SRC=`dirname $0`
cd $SRC
. $SRC/setup-lib.sh

ALLNODESCRIPTS="setup-ssh.sh setup-disk-space.sh"
HEADNODESCRIPTS=""
if [ $INSTALLVNC -eq 1 ]; then
    HEADNODESCRIPTS="setup-vnc.sh"
fi
HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-nfs-server.sh setup-nginx.sh setup-ssl.sh setup-kubespray.sh setup-kubernetes-extra.sh"
if [ $INSTALLORANSC -eq 1 ]; then
    HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-oran.sh setup-xapp-kpimon.sh setup-xapp-nexran.sh setup-xapp-kpimon-go.sh"
fi
if [ $INSTALLONFSDRAN -eq 1 ]; then
    HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-sdran.sh"
fi
HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-ran.sh"
if [ $INSTALLORANSCSMO -eq 1 ]; then
    HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-oran-smo.sh"
fi
HEADNODESCRIPTS="${HEADNODESCRIPTS} setup-end.sh"
WORKERNODESCRIPTS="setup-nfs-client.sh"

# Don't run setup-driver.sh twice
if [ -f $OURDIR/setup-driver-done ]; then
    echo "setup-driver already ran; not running again"
    exit 0
fi
for script in $ALLNODESCRIPTS ; do
    cd $SRC
    $SRC/$script | tee - /local/logs/${script}.log 2>&1
    if [ ! $PIPESTATUS -eq 0 ]; then
	echo "ERROR: ${script} failed; aborting driver!"
	exit 1
    fi
done
if [ "$HOSTNAME" = "node-0" ]; then
    for script in $HEADNODESCRIPTS ; do
	cd $SRC
	$SRC/$script | tee - /local/logs/${script}.log 2>&1
	if [ ! $PIPESTATUS -eq 0 ]; then
	    echo "ERROR: ${script} failed; aborting driver!"
	    exit 1
	fi
    done
else
    for script in $WORKERNODESCRIPTS ; do
	cd $SRC
	$SRC/$script | tee - /local/logs/${script}.log 2>&1
	if [ ! $PIPESTATUS -eq 0 ]; then
	    echo "ERROR: ${script} failed; aborting driver!"
	    exit 1
	fi
    done
fi

exit 0
