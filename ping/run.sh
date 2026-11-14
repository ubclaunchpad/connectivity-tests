#!/usr/bin/env bash
#
# Reference ping test. Runs in the probe's Debian-based Linux container with
# Bash and iputils-ping. The destination and echo count are fixed; this test
# accepts no arguments or environment configuration.

set -u

readonly PING_TARGET="1.1.1.1"
readonly PING_COUNT="4"
readonly PING_TIMEOUT="2"
readonly PING_DEADLINE="10"

output=$(LC_ALL=C ping -n -4 -c "$PING_COUNT" -W "$PING_TIMEOUT" -w "$PING_DEADLINE" "$PING_TARGET")
status=$?

die() {
    # Preserve the captured ping output for diagnosis, but never put it on
    # stdout: stdout is reserved for a successful result wrapper.
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
    fi
    printf 'ping test: %s\n' "$1" >&2
    exit 1
}

# iputils uses 0 for a completed measurement and 1 for a measurement with no
# replies. Values of 2 or greater indicate an execution error. A status of 1
# with responses is still a valid completed measurement (for example, when the
# deadline stops the run after some replies).
if (( status >= 2 )); then
    die "ping exited with status $status"
fi

# iputils writes duplicates and errors before the loss field. Newer versions
# may append the optional pipe size after the elapsed time, or on its own line.
# The loss value is constrained to a JSON-compatible decimal no greater than
# 100, so impossible percentages and leading-zero numbers are rejected here.
summary_re='^([0-9]+) packets transmitted, ([0-9]+) received(, \+[0-9]+ duplicates)?(, \+[0-9]+ errors)?, ((0|[1-9][0-9]?)([.][0-9]+)?|100([.]0+)?)% packet loss(, time [0-9]+ms)?( pipe [0-9]+)?$'
rtt_re='^rtt min/avg/max/mdev = (0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)? ms$'

summary_count=0
rtt_count=0
sent=""
received=""
loss=""
rtt_avg=""

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ $summary_re ]]; then
        summary_count=$((summary_count + 1))
        sent=${BASH_REMATCH[1]}
        received=${BASH_REMATCH[2]}
        loss=${BASH_REMATCH[5]}
    elif [[ "$line" =~ $rtt_re ]]; then
        rtt_count=$((rtt_count + 1))
        rtt_avg="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
    fi
done <<< "$output"

if (( summary_count == 0 )); then
    die "missing iputils packet statistics summary"
fi
if (( summary_count > 1 )); then
    die "found more than one packet statistics summary"
fi

if (( 10#$sent == 0 )); then
    die "packet statistics report zero transmitted packets"
fi
if (( 10#$received > 10#$sent )); then
    die "packet statistics report more replies than transmitted packets"
fi

if (( 10#$received == 0 )); then
    # A genuine total loss must be based on a real summary with sent packets
    # and no replies. iputils reports this as 100% loss.
    if [[ ! "$loss" =~ ^100([.][0]+)?$ ]]; then
        die "zero replies reported with inconsistent packet loss '$loss%'"
    fi
    if (( rtt_count != 0 )); then
        die "unexpected RTT statistics for a total-loss measurement"
    fi
    printf '{"result_data":{"rtt_avg_ms":null,"packet_loss_pct":100}}\n'
    exit 0
fi

# Any measurement with replies must have a usable average RTT.
if (( rtt_count == 0 )); then
    die "missing RTT statistics for a measurement with replies"
fi
if (( rtt_count > 1 )); then
    die "found more than one RTT statistics line"
fi

printf '{"result_data":{"rtt_avg_ms":%s,"packet_loss_pct":%s}}\n' "$rtt_avg" "$loss"
