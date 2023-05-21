#!/bin/sh

set -x

if [ -z "$SESSION" ]; then
    SESSION="oran"
fi

session_get() {
    ( tmux list-sessions | grep -q "^${SESSION}:" ) \
	|| tmux new-session -d -s "$SESSION"
}

session_get $SESSION

tmux new-session -d -s =$SESSION
tmux send-keys -t =$SESSION:0.0 'kubectl logs -f -n ricplt -l app=ricplt-e2term-alpha' C-m
tmux split-window -v -t =$SESSION:0
tmux send-keys -t $SESSION:0.1 'kubectl logs -f -n ricplt -l app=ricplt-e2mgr' C-m
tmux split-window -v -t =$SESSION:0
tmux send-keys -t $SESSION:0.2 'kubectl logs -f -n ricplt -l app=ricplt-submgr' C-m
tmux split-window -v -t =$SESSION:0
tmux send-keys -t $SESSION:0.3 'kubectl logs -f -n ricplt -l app=ricplt-rtmgr' C-m
tmux select-layout -t =$SESSION:0 even-vertical

exec tmux attach-session -d -t $SESSION
