# digiweb-status

A private status page for a few home Linux machines: when each last updated, what's waiting,
which kernel it runs, whether it needs a reboot, its backups, disk, memory and services. Every
machine sends a small report to one server, which turns them into a single static page.

```
each machine: digiweb-report (every morning at 6:00 and 10 min after boot)
      │  report (JSON, no secrets) over SSH; the key can only run the receiver
      ▼
status server: digiweb-status-receive NAME → /var/lib/digiweb-status/reports/NAME.json
      │  rebuilds the page (and again every hour, so a silent machine turns red)
      ▼
digiweb-status-build → /var/www/digiweb-status/index.html → nginx on port 8090
      home network + your own Tailscale devices only, with a login
```

Python 3 standard library only, nothing to `pip install`. No database, no web app: the page is
one HTML file that rebuilds itself.

## What the page shows

- **A card per machine** with an **ok / watch / down** badge: last update (when, how many
  packages), updates waiting, running kernel, reboot pending, up since, disk, memory and
  temperature; on the server also its last backup and its services.
- **A banner** listing everything that needs a look.
- **Scheduled jobs**: last run, result and next run of each machine's update and backup jobs.
- **Backups**: the backup files on the server, with size and date (listed only, not downloadable).
- **Watch list**: things like a CVE, with the kernel version each machine needs.
- **Security** (optional): known CVEs in the packages each machine has installed, with fixes
  waiting, urgent problems that have no fix yet, and anything new since the last report, each
  linked to its tracker page.

A machine is **watch** when it has updates waiting, needs a reboot, has a failed unit or a
stopped service, a job that ended badly, a disk over 85 %, no backup in 8 days, or fails a watch
item, or its security scan has fixes waiting or urgent problems. It's **down** when it hasn't reported in 48 hours.

## Keeping it private

- **No secrets in this repo, and none in the reports.** Machine names, addresses, keys and the
  page login live in `/etc/digiweb-status` on each machine (`.gitignore` covers them). The
  examples here use made-up names and addresses.
- **The page isn't on the internet.** nginx serves it on its own port (8090), which the router
  doesn't forward and the firewall only opens to the home network and Tailscale. On Tailscale,
  only listed devices get in (CI runners that join the tailnet don't), and everyone needs the
  login.
- **Machines can only drop off a report.** Each machine's SSH key is locked to
  `digiweb-status-receive` with that machine's name, so a key can't open a shell, read anything,
  or pretend to be another machine. Reports are checked (JSON, under 256 KB, known machine).
- **The reporter only reads.** os-release, uname, `/proc`, apt's log and `apt-get -s` (a dry run),
  systemctl, and the size and date of backup files. It never reads their contents.

## Files

| File | Where it goes | What it does |
|---|---|---|
| `report/digiweb-report` | every machine, `/usr/local/bin` | gathers the report and sends it |
| `report/digiweb-report.{service,timer}` | every machine | runs it at 6:00 and 10 min after boot |
| `report/report.example.json`, `report.server.example.json` | → `/etc/digiweb-status/report.json` | which jobs, services and backups to report, and where to send |
| `server/digiweb-status-receive` | status server, `/usr/local/bin` | files a report and rebuilds the page |
| `server/digiweb-status-build` | status server, `/usr/local/bin` | builds the page |
| `server/digiweb-status-build.{service,timer}` | status server | rebuilds hourly |
| `server/site.example.json` | → `/etc/digiweb-status/site.json` | the machines, time zone, thresholds and watch list |
| `server/nginx-digiweb-status.conf.example` | → `/etc/nginx/sites-available/digiweb-status` | the page's nginx site |
| `install.sh` | | `sudo ./install.sh report` or `server`: installs or updates the above |

## Setting up the status server

```bash
sudo git clone https://github.com/digable/digiweb-status /srv/src/digiweb-status
cd /srv/src/digiweb-status

# The account reports arrive as. It needs a shell for SSH to run the receiver, but no password.
sudo useradd --system --create-home --home-dir /var/lib/digiweb-status --shell /bin/sh status
sudo install -d -o status -g status /var/lib/digiweb-status/reports /var/www/digiweb-status
sudo install -d -m 700 -o status -g status /var/lib/digiweb-status/.ssh

sudo ./install.sh server
sudo ./install.sh report
sudo cp server/site.example.json /etc/digiweb-status/site.json             # then edit
sudo cp report/report.server.example.json /etc/digiweb-status/report.json  # then edit
sudo systemctl start digiweb-report        # first report, which also builds the page
```

If sshd limits who may log in (`AllowUsers` or `AllowGroups`), add `status` there.

**The page and its login.** The login is made on the server and never written down anywhere else:

```bash
sudo apt install -y apache2-utils     # for htpasswd
sudo htpasswd -c /etc/digiweb-status/htpasswd YOURNAME
sudo chown root:www-data /etc/digiweb-status/htpasswd && sudo chmod 640 /etc/digiweb-status/htpasswd
sudo cp server/nginx-digiweb-status.conf.example /etc/nginx/sites-available/digiweb-status   # then edit the allow lines
sudo ln -s /etc/nginx/sites-available/digiweb-status /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo ufw allow from 192.168.1.0/24 to any port 8090 proto tcp    # your home network
sudo ufw allow in on tailscale0 to any port 8090 proto tcp
```

## Adding a machine

On the machine:

```bash
sudo git clone https://github.com/digable/digiweb-status /opt/digiweb-status
cd /opt/digiweb-status && sudo ./install.sh report
sudo cp report/report.example.json /etc/digiweb-status/report.json    # then edit
sudo ssh-keygen -q -t ed25519 -N "" -C "digiweb-status $(hostname)" -f /etc/digiweb-status/id_ed25519
ssh-keyscan -t ed25519 SERVER_ADDRESS 2>/dev/null | sudo tee /etc/digiweb-status/known_hosts >/dev/null
sudo cat /etc/digiweb-status/id_ed25519.pub     # the public half: safe to copy
```

On the status server, add that public key for the machine's name (as in `site.json`), and add the
machine to `site.json` if it isn't there:

```bash
echo 'restrict,command="/usr/local/bin/digiweb-status-receive NAME" ssh-ed25519 AAAA... digiweb-status HOST' \
  | sudo tee -a /var/lib/digiweb-status/.ssh/authorized_keys >/dev/null
sudo chown status:status /var/lib/digiweb-status/.ssh/authorized_keys && sudo chmod 600 /var/lib/digiweb-status/.ssh/authorized_keys
```

Back on the machine: `sudo systemctl start digiweb-report`. It prints `received NAME report`.

## Security scan

Add a `security` setting to a machine's `/etc/digiweb-status/report.json`:

- Debian or Raspberry Pi OS: `"security": { "tool": "debsecan" }`, after
  `sudo apt install --no-install-recommends debsecan` (without that flag apt also installs a mail
  server). Set `REPORT=false` in `/etc/default/debsecan` so it doesn't try to mail its own report.
- Ubuntu: `"security": { "tool": "pro" }`. `pro` comes with Ubuntu; nothing to install.

The scan only reads the package list; it changes nothing. Most open CVEs on Debian are low
priority or not yet rated, so the page shows only what you can act on: fixes waiting (the next
weekly update installs them), urgent problems (high urgency or remotely exploitable) and CVEs new
since the last report. The first report only records a starting point, so "new" shows from the
second one on. `linux-libc-dev` (kernel headers, never the running kernel) is left out.

## Updating

After pushing a change, on each machine, in its checkout (`/srv/src/digiweb-status` or
`/opt/digiweb-status`):

```bash
sudo ./install.sh update
```

It pulls the latest from GitHub and reinstalls whatever that machine has (the reporter
everywhere, plus the receiver and page builder on the status server). Your settings in
`/etc/digiweb-status` are never touched.

## Trying it

`digiweb-report --print` shows the report it would send, without sending it. To build a page from
hand-made reports, point `DIGIWEB_STATUS_SITE` at a `site.json` whose `reports_dir` and `output`
are in a scratch folder, pipe reports into `digiweb-status-receive NAME`, and open the output.
