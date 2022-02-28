#!/bin/bash
# ********************************************************************
# (c) 2022 Skynet Consulting Ltd.
# ********************************************************************
# Description:
#   This script demonstrates simple multitasking in bash
# ********************************************************************
NUM_CPU=3

check_cpu() { # PID...
  ## Wait for children to exit and indicate whether all exited with 0 status.
  local errors=0
  while :; do
    debug "Checking Processes: $*"
    for pid in "$@"; do
      shift
      if kill -0 "$pid" 2>/dev/null; then
        set -- "$@" "$pid"
      elif wait "$pid"; then
        debug "$pid exited with zero exit status."
      else
        debug "$pid exited with non-zero exit status."
        ((++errors))
      fi
    done
echo "Active PIDS:$@"
    pids=$@
    (("$#" >= "${NUM_CPU}" )) || break
    # TODO: how to interrupt this sleep when a child terminates?
    echo "Sleeping"
    sleep ${WAITALL_DELAY:-1}
   done
  ((errors == 0))
}

waitall() { # PID...
  ## Wait for children to exit and indicate whether all exited with 0 status.
  local errors=0
  while :; do
    debug "Wating for Processes : $*"
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
for t in 3 5 4 4 4 4 4; do 
  debug "Main - loop - active pids=${pids}"
  sleep "$t" &
  pids="$pids $!"
  check_cpu $pids
done
waitall $pids
