# Connectivity tests

This repository holds network measurement tests for the Launchpad connectivity
project. The main system repository is
[connectivity](https://github.com/ubclaunchpad/connectivity).

Each test is a self-contained directory with two paired files: a manifest that
describes the test and its metrics, and a Bash script that performs the
measurement and emits its result.

## Layout and authoring convention

```
<test-name>/
  test.json   # manifest: identity, metric metadata, default metric
  run.sh      # measurement entry point
```

The directory name identifies the test. The two files are authored, reviewed,
and changed together: `run.sh` may only emit the metrics declared in
`test.json`, and their keys, units, nullability, and meaning must match.

Tests are invoked by the probe runner from inside the test directory with:

```bash
bash run.sh
```

A test takes no arguments and reads no test-specific configuration from the
environment. Its destination, echo count, timeouts, and other measurement
choices are fixed in `run.sh`. Changing a destination or measurement method is
a reviewable change to the test, not a runtime parameter. This keeps a test
reproducible and makes results comparable over time.

## Manifest

The manifest uses this shape:

```json
{
  "test_id": "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  "name": "Ping",
  "metrics": {
    "rtt_avg_ms": {
      "label": "Average latency",
      "type": "number",
      "unit": "ms",
      "nullable": true
    },
    "packet_loss_pct": {
      "label": "Packet loss",
      "type": "number",
      "unit": "%",
      "nullable": false
    }
  },
  "map": {
    "default_metric": "rtt_avg_ms"
  }
}
```

- `test_id` is a stable, unique UUID for the test. Never reuse or silently
  replace it: history and comparisons depend on the same test keeping the same
  identity. A materially different test needs a new ID.
- `name` is the human-readable test name.
- `metrics` describes the measurements emitted by the test. Each key is the
  exact `result_data` key in the output. `label` is human readable, `type`
  describes the value type, `unit` is the displayed unit, and `nullable` says
  whether the value can be `null`. For example, average RTT is nullable because
  no RTT exists when every echo is lost; packet loss is never nullable.
- `map.default_metric` names the metric shown when no metric is selected.

## Execution, stdout, and exit status

On a completed measurement, including a measurement with packet loss, the test
writes exactly one JSON object to stdout:

```json
{"result_data":{"rtt_avg_ms":18.4,"packet_loss_pct":0}}
```

Nothing else goes to stdout. Diagnostics and other human-readable messages go
to stderr. The wrapper is the same for every test; only the contents of
`result_data` differ.

Exit `0` means the measurement completed and stdout contains a valid result.
This includes partial loss and total loss. Total loss is a real measurement, not
an execution failure: when the summary shows packets were sent and none were
received, the result uses `"rtt_avg_ms":null` and `"packet_loss_pct":100`.

A nonzero exit means the measurement did not complete. On failure, stdout must
be empty and diagnostics must remain on stderr. Examples include an unavailable
`ping`, a `ping` exit status of 2 or greater, a missing or malformed packet
statistics summary, or replies without the RTT summary needed for an average.
A `ping` exit status of 1 is acceptable only when the captured summary is valid;
it can represent partial loss, total loss, or a deadline that stopped a run
after some replies.

## Ping reference test

The `ping/` directory is the first reference test. It runs on the probe's
Debian-based Linux container with Bash and `iputils-ping`. It sends four IPv4
echo requests to the fixed public address `1.1.1.1`, uses the numeric `C`
locale, and bounds the run's wait. It parses the real iputils packet statistics
and RTT summary, including decimal packet-loss percentages.

It does not install packages, change networking, or accept a dynamic target.
Host BSD/macOS `ping` is not supported; the test contract and parser target
iputils on Linux.

## Review and publication

Changes to a test are proposed in this public repository and reviewed before
they are made available to probes. Review should confirm that the manifest and
output agree, that the test remains deterministic, and that a completed
measurement is distinguishable from an execution failure.

Because this repository is public, do not commit credentials, private
endpoints, probe identities, exact probe locations, or real measurement data.
Do not add behavior that changes a probe or its network environment unless that
behavior has been explicitly reviewed.
