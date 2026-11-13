# Host setup: surfacing failing checks

This host has no MTA, so cron mail from `bin/drift_cron.sh` goes nowhere.
These files show a failing check to every user who logs in instead.

| File | Installed to | Purpose |
|---|---|---|
| `genomes-db-status` | `/usr/local/bin/genomes-db-status` | Prints every `*.FAILING` marker in `/var/lib/genomes-db`; silent when healthy |
| `60-genomes-db-status` | `/etc/update-motd.d/60-genomes-db-status` | Runs it on SSH login |

`bin/drift_cron.sh` writes `/var/lib/genomes-db/drift.FAILING` alongside its
marker in `~/log`, if the directory exists and is writable.

## Install (once, as root)

```sh
cd /home/tyler/genomes_db_review
sudo install -d -o tyler -g tyler -m 755 /var/lib/genomes-db
sudo install -m 755 ops/genomes-db-status /usr/local/bin/genomes-db-status
sudo install -m 755 ops/60-genomes-db-status /etc/update-motd.d/60-genomes-db-status
# Non-login terminals (VS Code, tmux) never show the MOTD:
echo '[[ $- == *i* ]] && [ -x /usr/local/bin/genomes-db-status ] && /usr/local/bin/genomes-db-status' \
    | sudo tee -a /etc/bash.bashrc
# Seed the shared marker now rather than waiting for 07:17 tomorrow:
[ -e ~/log/genomes_db_drift.log.FAILING ] && cp ~/log/genomes_db_drift.log.FAILING /var/lib/genomes-db/drift.FAILING
```

## Check

```sh
sudo run-parts /etc/update-motd.d/ | tail    # warning appears
sudo -u anushka -i true                      # another user sees it
```

## Mail

Cron mails `MAILTO=tyler.peirce@uwa.edu.au` (top of tyler's crontab).
`drift_cron.sh` only writes to stdout when the state changes, so a check left
failing on purpose mails once, then once more when it recovers.

Route: **pending.** `msmtp` is configured for the Pawsey relay
(`smtp.pawsey.org.au`), which is firewalled from this VM until a Pawsey helpdesk
request opens it. Until then cron mail fails to send (harmless) and the login
banner is the only signal. Routes tried on 2026-11-09 that do not work, and why,
are recorded at the top of `ops/msmtprc`. In short, `pawsey.cloud`, `pawsey.org.au` and
`uwa.edu.au` all publish DMARC `p=reject`, and UWA blocks password SMTP AUTH.
Config: `ops/msmtprc`, installed to `~/.msmtprc` (600).

Install (once, as root). When debconf asks about AppArmor, the default (no) is fine:

```sh
sudo apt install msmtp msmtp-mta     # provides /usr/sbin/sendmail for cron
install -m 600 ops/msmtprc ~/.msmtprc   # as tyler; already done
```

Check:

```sh
printf 'Subject: sendmail test\n\nfrom oceanomics-genomes\n' | /usr/sbin/sendmail -v tyler.peirce@uwa.edu.au
tail ~/.msmtp.log     # AppArmor confines msmtp logs to ~/.msmtp*.log
```

Accepted with `250` is not the same as delivered: Exchange Online drops
DMARC failures after accepting them. Confirm that the message actually arrived.
