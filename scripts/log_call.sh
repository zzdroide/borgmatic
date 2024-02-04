#!/bin/bash

# Runs a program, logging its call.
# From https://unix.stackexchange.com/questions/538973/bash-script-to-run-command-with-arguments-and-log-full-command-to-file

readonly logfile=/tmp/log_call.txt

"$@"; rc=$?

{
  printf "%s  [%s]  " "$(date "+%Y-%m-%d %T")" $rc
  printf "%q\n" "$@" | tr '\n' ' '
  printf "\n"
} >>$logfile
