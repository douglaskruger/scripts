#!/bin/bash
# ********************************************************************
# (c) 2022 Skynet Consulting Ltd.
# ********************************************************************
# Description:
#   This script demonstrates simple multitasking in bash
# ********************************************************************
waitall() { 
  ## Wait for children to exit and indicate whether all exited with 0 status.
  local errors=0
  while :; do
    debug "Processes remaining: $*"
    for pid in "$@"; do
      shift
      if kill -0 "$pid" 2>/dev/null; then
        debug "$pid is still alive."
        set -- "$@" "$pid"
      elif wait "$pid"; then
        debug "$pid exited with zero exit status."
      else
        debug "$pid exited with non-zero exit status."
        ((++errors))
      fi
    done
    (("$#" > 0)) || break
    # TODO: how to interrupt this sleep when a child terminates?
    sleep ${WAITALL_DELAY:-1}
   done
  ((errors == 0))
}

debug() { echo "DEBUG: $*" >&2; }

pids=""
for t in 3 5 4; do 
  sleep "$t" &
  pids="$pids $!"
done
waitall $pids
