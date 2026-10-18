# Proprio on the Hugging Face Hub (Inference Provider, in registration)

ZenEdgeX is registering as a Hugging Face Inference Provider for the `robotics` task, so a LeRobot policy
can be run exactly from its model page or from the `huggingface_hub` / `huggingface.js` clients. Status:
task schema and provider helper proposed in [huggingface.js#2679](https://github.com/huggingface/huggingface.js/pull/2679);
provider enablement pending on the Hugging Face side. This page documents what the integration does so it
can be judged before it goes live.

## The `robotics` task

One control tick of a robot policy. Request:

```json
POST https://api.zenedgex.in/v1/robotics/lerobot/smolvla_base
{
  "inputs": {
    "images": { "camera": "<base64 PNG or JPEG, or URL>" },
    "state": [0.1, -0.3, 0.8, 0.0, 0.2, 0.0],
    "instruction": "pick up the red cube and place it in the bowl"
  },
  "parameters": { "seed": 7 }
}
```

Response (header `Inference-Id: <uuid>` on every response):

```json
{ "actions": [[...], ...], "action_dim": 6, "chunk": 50, "model": "lerobot/smolvla_base", "exact": true, "tier": "exact", "latency_ms": 31.2 }
```

`actions` is the chunk of future actions in the policy's own action space, bit-identical to what the
unmodified checkpoint produces in eager execution for the same observation and seed. Through the Hub
clients the same call is `client.robotics(inputs, model=...)` once the task is merged.

## Models

`lerobot/smolvla_base`, `lerobot/pi05_base`, `nvidia/GR00T-N1.7-3B` at launch; other LeRobot
checkpoints on request (any policy that certifies EXACT can be mapped).

## Pricing

Per request (one control tick), passed through by Hugging Face with no markup. Launch price: $0.0002 per
tick (`/v1/models` always shows the current price). Evaluation runs are free.

## Data retention

None. Observations are decoded in memory, run through the policy and discarded when the actions are
returned. We keep per-request metadata only: request id, model, latency, batch size, a digest of the
returned actions (for the tick ledger and billing), never images, states or instructions. No training on
customer data.

## Latency and availability

Served from NVIDIA GPUs; per-tick engine latency 31 to 65 ms for the launch models, plus network. The
endpoint answers the Hub's periodic validation calls within the 30 s limit. Health: `GET /health`;
served models and prices: `GET /v1/models`.

## Why exact

Compilers and autotuning change a policy's actions by 0.01 to 0.3 on the same inputs (measured, see
https://zenedgex.in/proprio/); a changed action is a changed robot. Proprio keeps the policy's own
kernels and proves identity on every tick, which is what makes a hosted result usable for evaluation
and for safety reviews.

Contact: hello@zenedgex.in
