# Deploying Proprio on your own GPU

**Written for the engineer who installs and runs Proprio for a robot fleet or a lab.**

Proprio runs on your hardware, next to your robots. Nothing leaves your network: the server
loads the policy checkpoint, serves control ticks over a websocket or HTTP, and writes metrics
and certificates locally. Hugging Face is used only to download checkpoints.

## 1. Pick an install

| | Docker image | pip wheel |
|---|---|---|
| Best for | servers, fleets, anything that restarts itself | lab machines, existing LeRobot environments |
| Command | `docker run --gpus all ghcr.io/zenedgex/proprio:0.1.1 ...` | `pip install proprio-0.1.1-cp312-...whl` |
| Brings its own | CUDA 12.8 runtime, torch 2.11, LeRobot 0.6.1, Python 3.12 | nothing: uses your torch and LeRobot |

Requirements either way: Linux x86_64, an NVIDIA GPU with a driver for CUDA 12.8 or newer
(R570+), 24 GB of GPU memory for pi0.5 or GR00T N1.7 (SmolVLA fits in 8 GB). For Docker,
the NVIDIA Container Toolkit.

### Docker

```sh
docker run --gpus all -d --name proprio --restart unless-stopped \
  -p 8000:8000 -p 8080:8080 -p 9100:9100 \
  -e PROPRIO_LICENSE="$(cat acme.license)" -e HF_TOKEN=hf_... \
  -v proprio-cache:/root/.cache/huggingface -v proprio-state:/var/lib/proprio \
  ghcr.io/zenedgex/proprio:0.1.1 lerobot/smolvla_base --robots 16 --budget-ms 100
docker logs -f proprio
```

Or with Prometheus: `docker compose -f docker/compose.yaml up -d` (see [docker/compose.yaml](docker/compose.yaml)).
The image is built by [the docker workflow](.github/workflows/docker.yml) from the release
wheel and the [Dockerfile](docker/Dockerfile) in this repository, so what is in it is public.

### pip

```sh
python3.12 -m venv /opt/proprio && . /opt/proprio/bin/activate
pip install torch==2.11.0 --index-url https://download.pytorch.org/whl/cu128
pip install "lerobot==0.6.1" websockets msgpack msgpack-numpy
pip install proprio-0.1.1-cp312-cp312-manylinux*_x86_64.whl      # from Releases; check SHA256SUMS
proprio licence --install acme.license
proprio serve lerobot/smolvla_base --robots 16 --budget-ms 100
```

As a system service: [systemd/proprio.service](systemd/proprio.service).

## 2. The licence key

Without a key Proprio runs in **evaluation mode**: up to 4 robots per tick, certificates marked
evaluation, no metering. A licence key is one line of text issued by ZenEdgeX for your
organization, with an expiry and a robots-per-tick cap. The engine verifies it offline against
the ZenEdgeX public key built into the wheel; no licence server, no phone-home.

```sh
proprio licence                      # what this machine runs under (exit 0 licensed, 2 evaluation)
proprio licence --install KEY        # KEY is the string or a file; stored in $PROPRIO_HOME/license
export PROPRIO_LICENSE="..."         # or pass it in the environment (Docker, systemd EnvironmentFile)
```

`PROPRIO_HOME` defaults to `~/.proprio` for pip installs and `/var/lib/proprio` in the image.
Rotate a key by installing the new one and restarting the server. Keys: hello@zenedgex.in

## 3. Run

```
proprio serve <policy> [--robots N] [--budget-ms 100] [--port 8000] [--http-port 8080] [--metrics-port 9100]
                       [--rollout-mode exact|invariant] [--device cuda|cpu|auto] [--dtype bf16] [--rename old=new ...]
```

- `<policy>`: a Hub id (`lerobot/smolvla_base`, `lerobot/pi05_base`, `nvidia/GR00T-N1.7-3B`) or a
  local checkpoint directory. Gated checkpoints need `HF_TOKEN`.
- `--robots N`: robots served per tick. Robots whose observations share a shape are batched; each
  row is bit-identical to that robot alone (`exact`), or, with `--rollout-mode invariant`, to the
  same robot alone on the invariant kernels, faster per robot, with the declared difference to
  stock eager on the certificate. Start-up records one graph per batch size, so expect 1 to 5
  minutes before `/health` goes green on first start (`--start-period` in the image covers it).
- `--budget-ms`: default tick deadline; a client may send its own `deadline` per observation.
- Ports: 8000 websocket (openpi protocol), 8080 HTTP/JSON (`POST /v1/robotics/<model>`,
  `GET /v1/models`, `/health`), 9100 Prometheus (`/metrics`, signed `/rollup`, `/health`).
  Set a port to 0 to disable that listener.

Stop with SIGTERM (`docker stop`, `systemctl stop`): in-flight ticks finish, usage is flushed.

## 4. Connect a robot

In a LeRobot control loop, replace the policy object:

```python
from proprio.client import RemotePolicy
policy = RemotePolicy("ws://gpu-box:8000", n_action_steps=50)
action = policy.select_action(batch)     # same call as before
```

The client is also in the wheel for CPU-only robot computers (`pip install` the wheel there too;
no GPU needed to use `proprio.client`). Any openpi `websocket_client_policy` works as well.
HTTP example: [HUB.md](HUB.md).

## 5. Prove it on your checkpoint

```sh
proprio certify ./my_policy --ticks 64 --out cert.json          # one robot
proprio certify ./my_policy --robots 16 --ticks 64 --out cert.json
proprio verify cert.signed.json                                  # a certificate signed by ZenEdgeX
```

`certify` exits non-zero if any tick is not bit-identical. Keep the certificate with the
deployment; it records GPU, driver, clocks, seeds and the digest of every action chunk.

## 6. Operate

- **Metrics**: scrape `:9100/metrics`. Counters `proprio_robot_ticks_total`,
  `proprio_late_total`, histograms of tick latency and batch size. `/rollup` is a signed
  summary you can archive.
- **Usage**: licensed servers append robot-tick counts to `$PROPRIO_HOME/usage.jsonl` hourly
  (or report through AWS Marketplace metering with `PROPRIO_METERING=aws`). Evaluation mode
  records nothing.
- **Logs**: stdout. `docker logs` or `journalctl -u proprio`.
- **Upgrade**: pull the new image tag or install the new wheel, keep `PROPRIO_HOME`, restart.
  Re-run `certify` after any change of wheel, driver or torch: exactness is per stack.
- **Several policies**: one server per policy, one GPU each (or share a GPU when memory allows).

## 7. Support

Issues on this repository for anything reproducible with an evaluation wheel. Licensed
customers: the support address in your agreement. Security reports: hello@zenedgex.in
