# Proprio for LeRobot async inference (15 minutes)

**Written for LeRobot users who run a policy server on a GPU machine and a robot client on the robot.**

> **Most LeRobot users want the plugin instead:** `pip install lerobot_policy_proprio` makes
> `lerobot-rollout`, `lerobot-record`, `lerobot-eval` and LeRobot's newer `lerobot-policy-server` use
> Proprio with no other change: https://github.com/zenedgex/lerobot-policy-proprio. This page covers
> LeRobot 0.6's gRPC async-inference server (`lerobot.async_inference.policy_server`).

LeRobot's async inference splits a policy between a GPU machine (the policy server) and the robot
(the robot client), connected over gRPC. Proprio ships a policy server that speaks the same protocol
and takes the same flags. You replace one command on the GPU machine. Nothing changes on the robot.

What you get:

- **Faster ticks, same actions.** When the robot client sends its policy choice, Proprio loads that
  checkpoint and prepares it. Before serving, it checks bit for bit that its actions equal the
  checkpoint's own execution. Measured on an RTX 4090 through
  this protocol (LeRobot's robot-side messages, three 480x640 cameras), against LeRobot's own server
  on the same observations and seeds: SmolVLA and pi0.5 returned identical action chunks, 20 of 20
  each. SmolVLA: 302 ms per chunk on LeRobot's server, 53 ms on Proprio's (5.7x). pi0.5: 215 ms
  per chunk on Proprio's server (LeRobot loads pi0.5 in float32; Proprio serves exactly what
  LeRobot loads). `proprio certify` measures eager against Proprio on your own checkpoint
  (section 5).
- **Instant reconnects.** Loaded policies are cached. A robot that reconnects, or a second robot asking
  for the same checkpoint, does not wait for a reload.
- **Safe message handling.** LeRobot's server unpickles network messages with `pickle.loads`, which
  runs whatever a crafted message asks for. Proprio accepts only the types the protocol carries
  (policy specification, observations, arrays, tensors) and refuses everything else.

## 1. Install on the GPU machine

Linux with an NVIDIA GPU (driver R570 or newer), Python 3.10 to 3.12. The same environment you run
LeRobot in works.

```sh
pip install torch==2.11.0 --index-url https://download.pytorch.org/whl/cu128
pip install "lerobot[async,smolvla,pi]==0.6.1" num2words   # the policy extras pin a transformers LeRobot supports
pip install proprio                                       # Linux x86_64 and aarch64 wheels on PyPI
```

## 2. Check the machine

```sh
proprio doctor --policy lerobot/smolvla_base
```

Every line says OK, WARN or FAIL, with a fix for anything missing (a package, a transformers release
LeRobot does not support, a gated tokenizer, the GPU driver). It also runs a small self-test to
confirm Proprio works on this GPU.

## 3. Swap the server

Where you ran

```sh
python -m lerobot.async_inference.policy_server --host=0.0.0.0 --port=8080 --fps=30 \
    --inference_latency=0.033 --obs_queue_timeout=1
```

run

```sh
proprio lerobot-server --host=0.0.0.0 --port=8080 --fps=30 \
    --inference_latency=0.033 --obs_queue_timeout=1
```

Two extra flags: `--mode=eager` serves the checkpoint exactly as LeRobot's server would (useful for
side-by-side checks), and `--max_workers` sets the gRPC thread count.

## 4. Robot side: unchanged

```sh
python -m lerobot.async_inference.robot_client \
    --robot.type=so100_follower --robot.port=/dev/ttyACM0 --robot.id=arm \
    --robot.cameras="{ front: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}" \
    --task="pick up the cube" \
    --server_address=gpu-box:8080 \
    --policy_type=smolvla --pretrained_name_or_path=lerobot/smolvla_base \
    --policy_device=cuda --actions_per_chunk=50 --chunk_size_threshold=0.5 \
    --aggregate_fn_name=weighted_average
```

The first connection for a checkpoint takes as long as loading plus preparing it: under a minute
for SmolVLA, about four minutes for pi0.5 (LeRobot's own server takes about as long to load it). The
server log then says it is ready, and serves.

## 5. Prove it on your checkpoint

```sh
proprio certify your-org/your-policy --ticks 32 --out cert.json
```

The certificate compares every action chunk with the checkpoint's eager execution and records the
GPU, driver, clocks and latencies. Anything not `EXACT` on a LeRobot checkpoint is a bug report we
want: open an issue with the certificate.

## Notes

- **CPU threads on large servers.** On a machine with many cores, PyTorch's default thread count can
  slow LeRobot's eager server sharply: on a 256-thread host its SmolVLA chunk took 1178 ms, and
  302 ms with `OMP_NUM_THREADS=8`. Set it for either server; Proprio's recorded tick was 53 ms both ways.
- **Network.** gRPC without TLS, the same as LeRobot's server. Keep it on the robot's network or a VPN.
- **One robot per server**, as in LeRobot's protocol. Several robots on one GPU: use `proprio serve
  --robots N` with the openpi-compatible websocket protocol (see [DEPLOY.md](DEPLOY.md)).
- **Evaluation mode** needs no key and serves this protocol in full.
- **Supported policy types** are those LeRobot's server accepts (act, smolvla, diffusion, tdmpc,
  vqbet, pi0, pi05, groot). Verified through this server: SmolVLA and pi0.5.
- **pi0.5 camera names.** `lerobot/pi05_base` expects `base_0_rgb`, `left_wrist_0_rgb` and
  `right_wrist_0_rgb`; map your robot's cameras with the client's rename map.
