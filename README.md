# Proprio: exact inference for robot policies (evaluation release)

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

This repository holds the **evaluation wheels** only. Proprio is proprietary software; the
wheels contain compiled modules, not source. See [EVALUATION-LICENSE.md](EVALUATION-LICENSE.md).

Deploying for a fleet (Docker image, licence keys, systemd, metrics): [DEPLOY.md](DEPLOY.md).

## Try it on your checkpoint (five minutes)

Requirements: Linux x86_64, an NVIDIA GPU, Python 3.10, 3.11 or 3.12, and a working
`lerobot>=0.6` install (the same environment you run your policy in; SmolVLA also needs `pip install num2words`). Pick the wheel for your
Python from the [latest release](https://github.com/zenedgex/proprio-releases/releases/latest) (checksums in SHA256SUMS) and:

```sh
pip install proprio-0.1.1-cp312-cp312-manylinux*_x86_64.whl   # cp310 / cp311 for other Pythons
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

Technical preview. Verified on RTX 4090 with LeRobot 0.6 (SmolVLA, pi0.5, GR00T N1.7). Other
NVIDIA GPUs should work (the method does not depend on the card; the speedups do); Jetson and
AMD are next. Not yet: policies outside LeRobot (openpi direct, OpenVLA) are in progress.

ZenEdgeX, 2026.
