#!/usr/bin/env bash

set -u

readonly PING_TARGET="1.1.1.1"
readonly PING_COUNT="4"
readonly PING_TIMEOUT="2"
readonly PING_DEADLINE="10"

output=$(LC_ALL=C ping -n -4 -c "$PING_COUNT" -W "$PING_TIMEOUT" -w "$PING_DEADLINE" "$PING_TARGET")
status=$?

die() {
    if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
    fi
    printf 'ping test: %s\n' "$1" >&2
    exit 1
}

# Exit 1 can still include a valid measurement.
if (( status >= 2 )); then
    die "ping exited with status $status"
fi

# iputils can add counters and a pipe suffix.
summary_re='^([0-9]+) packets transmitted, ([0-9]+) received(, \+[0-9]+ duplicates)?(, \+[0-9]+ corrupted)?(, \+[0-9]+ errors)?, ((0|[1-9][0-9]?)([.][0-9]+)?|100([.]0+)?)% packet loss(, time [0-9]+ms)?( pipe [0-9]+)?$'
rtt_re='^rtt min/avg/max/mdev = (0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)?/(0|[1-9][0-9]*)([.][0-9]+)? ms(, pipe [0-9]+)?$'

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
        loss=${BASH_REMATCH[6]}
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
    if [[ ! "$loss" =~ ^100([.][0]+)?$ ]]; then
        die "zero replies reported with inconsistent packet loss '$loss%'"
    fi
    if (( rtt_count != 0 )); then
        die "unexpected RTT statistics for a total-loss measurement"
    fi
    printf '{"result_data":{"rtt_avg_ms":null,"packet_loss_pct":100}}\n'
    exit 0
fi

if (( rtt_count == 0 )); then
    die "missing RTT statistics for a measurement with replies"
fi
if (( rtt_count > 1 )); then
    die "found more than one RTT statistics line"
fi

printf '{"result_data":{"rtt_avg_ms":%s,"packet_loss_pct":%s}}\n' "$rtt_avg" "$loss"
