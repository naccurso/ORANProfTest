#!/bin/sh

set -x

if [ -z "$SESSION" ]; then
    SESSION="nexran"
fi

session_get() {
    ( tmux list-sessions | grep -q "^${SESSION}:" ) \
	|| tmux new-session -d -s "$SESSION"
}

session_get $SESSION

tmux new-session -d -s =$SESSION

tmux send-keys -t =$SESSION:0.0 '/local/setup/oran/dms_cli onboard /local/profile-public/nexran-config-file.json /local/setup/oran/xapp-embedded-schema.json ; /local/setup/oran/dms_cli install --xapp_chart_name=nexran --version=0.1.0 --namespace=ricxapp ; sleep 8 ; kubectl -n ricxapp wait deployments/ricxapp-nexran --for condition=Avail ; . /local/repository/demo/get-env.sh' C-m
tmux split-window -v -t =$SESSION:0
tmux send-keys -t =$SESSION:0.1 'sleep 30 ; kubectl -n ricxapp wait deployments/ricxapp-nexran --for condition=Avail ; kubectl logs -f -n ricxapp -l app=ricxapp-nexran' C-m
tmux select-window -t =$SESSION:0.0

exec tmux attach-session -d -t $SESSION
