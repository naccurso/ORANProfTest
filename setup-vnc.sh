#!/bin/sh

set -x

if [ -z "$EUID" ]; then
    EUID=`id -u`
fi

# Grab our libs
. "`dirname $0`/setup-lib.sh"

if [ -f $OURDIR/vnc-done ]; then
    exit 0
fi

logtstart "vnc"

if [ -f $SETTINGS ]; then
    . $SETTINGS
fi
if [ -f $LOCALSETTINGS ]; then
    . $LOCALSETTINGS
fi

cd $OURDIR
git clone https://gitlab.flux.utah.edu/emulab/novnc-setup
novnc-setup/startvnc.sh

logtend "vnc"

touch $OURDIR/vnc-done
