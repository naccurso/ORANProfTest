#!/bin/sh

set -x

if [ -z "$TMUX" ]; then
    TMUX=1
fi
if [ -z "$SESSION" ]; then
    SESSION="ue"
fi
if [ -z "$DIRECTION" ]; then
    DIRECTION="-R"
fi
while [ -n "$1" ]; do
    if [ "$1" = "-u" ]; then
        DIRECTION=""
    fi
    shift
done

session_get() {
    ( tmux list-sessions | grep -q "^${SESSION}:" ) \
	|| tmux new-session -d -s "$SESSION"
}

session_get $SESSION

sudo ip netns add ue1

tmux send-keys -t =$SESSION:0.0 'sudo /local/setup/srslte-ric/build/srsue/src/srsue --rf.device_name=zmq --rf.device_args="tx_port=tcp://*:2001,rx_port=tcp://localhost:2000,id=ue,base_srate=23.04e6" --usim.algo=xor --usim.imsi=001010123456789 --usim.k=00112233445566778899aabbccddeeff --usim.imei=353490069873310 --log.all_level=warn --log.filename=stdout --gw.netns=ue1 |& tee /local/logs/srsue.log' C-m
tmux split-window -v
tmux send-keys -t =$SESSION:0.1 'while true ; do sleep 2 ; sudo ip netns exec ue1 ping 192.168.0.1 ; done' C-m
#tmux select-layout even-vertical
tmux split-window -v
tmux send-keys -t =$SESSION:0.2 "while true ; do sleep 2 ; sudo ip netns exec ue1 iperf3 $DIRECTION -c 192.168.0.1 -t 65536 -i 1 ; done |& tee -a /local/logs/iperf-ue.log" C-m
exec tmux attach-session -d -t $SESSION
