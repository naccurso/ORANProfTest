#!/bin/sh

set -x

# Grab our libs
. "`dirname $0`/setup-lib.sh"

(echo "Your ${EXPTTYPE} instance setup completed on $NFQDN ." ; echo ;
 echo "Admin token for Kubernetes dashboard:" ; echo ; echo ; echo ;
 cat /var/www/profile-private/admin-token.txt  ; echo ;
 echo "Kubernetes namespaces:" ; echo ;
 kubectl get namespaces ; echo ; echo ;
 for ns in `kubectl  get namespaces --no-headers | cut -f1 -d' '` ; do
     echo "============================================================" ;
     echo "$ns" ;
     echo "============================================================" ;
     echo ;
     kubectl -n $ns get all ;
     echo ; echo ;
 done;
) > $OURDIR/setup-end.email ;
cat $OURDIR/setup-end.email \
    |  mail -s "${EXPTTYPE} Instance Setup Complete" ${SWAPPER_EMAIL} &
