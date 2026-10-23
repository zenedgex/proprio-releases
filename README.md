# Proprio: exact inference for robot policies

Proprio runs an unmodified vision-language-action policy as a recorded device graph and
proves, tick by tick, that the actions are **bit-identical** to the policy's own eager
execution. If they are not identical, it refuses to deploy. Every run writes a Bitwise
Certificate you can read.

Measured on an RTX 4090 with unmodified LeRobot checkpoints:

| Policy | Eager p50 | Proprio p50 | Speedup | Bit-identical ticks |
|---|---|---|---|---|
| lerobot/smolvla_base | 246 ms | 38.7 ms | 6.4x | 100 / 100 |
| lerobot/pi05_base (bf16) | 266 ms | 98 ms | 2.7x | 100 / 100 |
| nvidia/GR00T-N1.7-3B | 170 ms | 63.7 ms | 2.7x | 32 / 32 |

For comparison, `torch.compile` on SmolVLA gives 4.9x to 9.2x and changes the actions by
0.07 to 0.08; TF32 and cuDNN autotuning change them by 0.01 to 0.1 for no speedup.
Details: https://zenedgex.in/proprio/

**Using LeRobot?** Install the plugin and LeRobot's own `lerobot-rollout`, `lerobot-record` and
`lerobot-eval` run your policy through Proprio, with no other change:
[lerobot-policy-proprio](https://github.com/zenedgex/lerobot-policy-proprio).

**Free for one robot**, including production and commercial use, no key needed. Fleets (many robots
per GPU) use a licence key. This repository holds the wheels only: Proprio is proprietary software
and the wheels contain compiled modules, not source. Terms: [EVALUATION-LICENSE.md](EVALUATION-LICENSE.md).

Deploying for a fleet (Docker image, licence keys, systemd, metrics): [DEPLOY.md](DEPLOY.md).

Already using LeRobot 0.6's gRPC async inference? Replace one command on the GPU machine, nothing
on the robot: [LEROBOT.md](LEROBOT.md).

## Try it on your checkpoint (five minutes)

Requirements: Linux (x86_64 or aarch64), an NVIDIA GPU, Python 3.10, 3.11 or 3.12, and a working
LeRobot 0.6 install with its policy extras (the same environment you run your policy in:
`pip install "lerobot[smolvla,pi]==0.6.1" num2words`; the extras pin a transformers release LeRobot supports). Then:

```sh
pip install proprio            # from PyPI; wheels also on the Releases page with SHA256SUMS
proprio certify lerobot/smolvla_base --ticks 32 --out cert.json
```

`certify` runs your policy eagerly and through Proprio on the same observations and noise,
compares every action chunk bit for bit, and prints one line:

```
lerobot/smolvla_base [exact] EXACT: 32/32 ticks bit-identical; eager 241.3 ms -> engine 38.1 ms (6.33x)
```

`cert.json` holds the full record: per-tick latencies, max and mean absolute error, GPU,
driver, clocks, power state, seeds, and a digest. Try your own checkpoint with its hub id or
local path (`proprio certify ./my_policy`). Gated checkpoints need your `HF_TOKEN`.

### Check the machine first

```sh
proprio doctor --policy lerobot/smolvla_base
```

Checks Python, torch, GPU and driver, graph recording, packages, licence, and what the checkpoint
needs (gated tokenizers for pi0 and pi0.5), with a one-line fix for anything missing.

### Serve it

```sh
proprio serve lerobot/smolvla_base --port 8000            # one robot
proprio serve lerobot/smolvla_base --port 8000 --robots 4 # up to 4 robots per tick (evaluation cap)
```

The server speaks the openpi websocket protocol (msgpack observation in, action chunk out).
In a LeRobot control loop, swap the policy object:

```python
from proprio.client import RemotePolicy
policy = RemotePolicy("ws://gpu-box:8000", n_action_steps=50)
action = policy.select_action(batch)   # same call as before
```

Metrics: `http://gpu-box:9100/metrics` (Prometheus), `/rollup` (signed summary), `/health`.

### Many robots per tick

With `--robots N`, robots that share an observation shape are batched into one exact tick.
Every row is bit-identical to what that robot would get alone; the certificate checks it:

```sh
proprio certify lerobot/smolvla_base --robots 4 --ticks 64
```

Evaluation mode serves up to 4 robots per tick. Licence keys (`proprio licence --install KEY`) unlock larger fleets and the
invariant tier (batched GEMMs on batch-invariant kernels, 14.8x per robot at 16 SmolVLA
robots, with the difference to stock eager declared on the certificate).

## What to report

Anything that is not `EXACT` on a LeRobot checkpoint is a bug we want: open an issue with the
`cert.json`, the policy id, GPU and driver. Also welcome: policies that fail to capture (the
engine falls back to eager and says why), speedups you measure, and what you would need to
run this on your fleet.

Issues: this repository. Direct: hello@zenedgex.in

## Status

Technical preview. Verified on RTX 4090 with LeRobot 0.6 (SmolVLA, pi0.5, GR00T N1.7). Also run on H100. Other
NVIDIA GPUs should work (the method does not depend on the card; the speedups do). Arm wheels
(aarch64) are built and install-tested; on-device Jetson numbers are next. Not yet: policies outside LeRobot (openpi direct, OpenVLA) are in progress.

Patent pending. ZenEdgeX, 2026.
