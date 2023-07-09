#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

./borgmatic_wrapper.py
sudo ./smarthealthc/run_and_report.sh
