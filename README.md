BC-250 LocalAI Distributed Inference Deployment Guide (Bazzite/Fedora)

BIOS / System Setup

In BIOS, set GFX memory to 12 GB.

The LocalAI container will see all 14 GB, but you must disable the GUI if you intend to test that limit.

Optional: Turn off the GUI if you want Bazzite’s memory footprint to remain under 1 GB.

sudo systemctl set-default multi-user.target

Reminder Commands:

sudo copr enable filippor/bazzite

sudo rpm-ostree install cyan-skillfish-governor-tt

sudo systemctl enable --now cyan-skillfish-governor-tt


Probably Required: SSH for headless control

ujust toggle-ssh

Firewall Configuration:

sudo firewall-cmd --add-port=8080/tcp --permanent

sudo firewall-cmd --add-port=8080/udp --permanent

sudo firewall-cmd --reload

Network Tuning (LocalAI P2P)

echo "net.core.rmem_max=7500000" | sudo tee -a /etc/sysctl.d/10-localai-p2p.conf
echo "net.core.wmem_max=7500000" | sudo tee -a /etc/sysctl.d/10-localai-p2p.conf

sudo sysctl --system

Script Flags / Behavior:

localai-fedora-*.sh must always be run with the install flag.

There are other options, but this is all that is supported right now.

This machine must be rebooted whenever something breaks:

Worker dies → reboot

Master has dead workers → reboot

I do not have a reload flag working yet.

Examples

./localai-fedora-master.sh install

./localai-fedora-master-worker.sh install

./localai-fedora-worker.sh install

Model & Worker Behavior

(Suggested location: /home/bazzite/localai)

Reminder:


chmod +x filename.sh


to make scripts executable.


The master.sh and master-worker.sh scripts will:

Build a custom LocalAI Podman container with the exact Mesa and kernel versions required

Download Qwen 2.5 8B

Patch the YAML so the model loads automatically on first run

localai-fedora-worker.sh install    will start an RPC worker over UDP.

A single-card setup is supported, and the demo model fits on the first card.

With two workers, tensor split "1,1" inference is configured automatically.

You can choose whether the master node is also a worker.

I don't have performance comparisons for master-only vs master+worker, but I've tested both solo and dual setups.

The most I've tested is four nodes.

Localai WEBUI:  http://localhost:8080

Security Warning!

These scripts contain a hardcoded master key.
This is intentional to simplify initial setup.
I hope to add security back soon.

RPC is barely functional at this stage.

~ nightcarnage
