#!/bin/bash
# Installs (or updates) digiweb-status from this checkout.
#
#   sudo ./install.sh report     every machine: the reporter and its daily timer
#   sudo ./install.sh server     the status server only: the receiver, page builder and its hourly timer
#   sudo ./install.sh update     pull the latest from GitHub and reinstall what this machine has
#
# Never touches /etc/digiweb-status (your settings, keys and the page login).
set -euo pipefail

# Everything is inside main(), so bash has read the whole file before running any of it: `update`
# replaces this file with git pull while it runs.
main() {
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

case "${1:-}" in
update)
    git pull --ff-only -q
    echo "now at $(git log -1 --format='%h %s (%cd)' --date=short)"
    # Run the freshly pulled installer for each part this machine already has
    if [ -x /usr/local/bin/digiweb-status-receive ]; then ./install.sh server; fi
    if [ -x /usr/local/bin/digiweb-report ]; then ./install.sh report; fi
    ;;
report)
    install -m 755 report/digiweb-report /usr/local/bin/digiweb-report
    install -m 644 report/digiweb-report.service report/digiweb-report.timer /etc/systemd/system/
    install -d -m 755 /etc/digiweb-status
    systemctl daemon-reload
    systemctl enable --now digiweb-report.timer >/dev/null
    echo "reporter installed; settings go in /etc/digiweb-status/report.json"
    ;;
server)
    install -m 755 server/digiweb-status-receive server/digiweb-status-build /usr/local/bin/
    install -m 644 server/digiweb-status-build.service server/digiweb-status-build.timer /etc/systemd/system/
    install -d -m 755 /etc/digiweb-status
    systemctl daemon-reload
    if id status >/dev/null 2>&1; then systemctl enable --now digiweb-status-build.timer >/dev/null; fi
    echo "server parts installed; settings go in /etc/digiweb-status/site.json"
    ;;
*)
    echo "usage: sudo ./install.sh report|server|update"; exit 1 ;;
esac
}

main "$@"
exit
