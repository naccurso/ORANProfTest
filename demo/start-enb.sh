#!/bin/sh

set -x

if [ -z "$E2TERM_SCTP" ]; then
    . /local/repository/demo/get-env.sh
    if [ -z "$E2TERM_SCTP" ]; then
	echo "ERROR: set E2TERM_SCTP env var to current value of the e2term service's IP address"
	exit 1
    fi
fi

if [ -z "$TMUX" ]; then
    TMUX=1
fi
if [ -z "$SESSION" ]; then
    SESSION="nodeb"
fi

session_get() {
    ( tmux list-sessions | grep -q "^${SESSION}:" ) \
	|| tmux new-session -d -s "$SESSION"
}

session_get $SESSION

tmux new-session -d -s =$SESSION
tmux send-keys -t =$SESSION:0.0 'sudo /local/setup/srslte-ric/build/srsepc/src/srsepc --spgw.sgi_if_addr=192.168.0.1 |& tee -a /local/logs/srsepc.log' C-m
sleep 1.0
tmux split-window -v -t =$SESSION:0
tmux send-keys -t $SESSION:0.1 "sudo /local/setup/srslte-ric/build/srsenb/src/srsenb --enb.n_prb=15 --enb.name=enb1 --enb.enb_id=0x19B --rf.device_name=zmq --rf.device_args='fail_on_disconnect=true,id=enb,base_srate=23.04e6,tx_port=tcp://*:2000,rx_port=tcp://localhost:2001' --ric.agent.remote_ipv4_addr=${E2TERM_SCTP} --ric.agent.local_ipv4_addr=10.10.1.1 --ric.agent.local_port=52525 --log.all_level=warn --ric.agent.log_level=debug --log.filename=stdout --slicer.enable=1 --slicer.workshare=0 |& tee -a /local/logs/srsenb.log" C-m
tmux split-window -v -t =$SESSION:0
tmux send-keys -t $SESSION:0.2 "iperf3 -s -B 192.168.0.1 -i 1 |& tee -a /local/logs/iperf-enb.log" C-m
tmux select-layout even-vertical

exec tmux attach-session -d -t $SESSION
