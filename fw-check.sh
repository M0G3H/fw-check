#!/bin/bash

# Usage message function
show_usage() {
    echo "Usage: $0 --host <IP> --proto <tcp|udp|icmp|any> --port <PORT> [--expect <allow|deny>]"
    exit 1
}

# Check if no arguments were provided
if [ $# -eq 0 ]; then
    show_usage
fi

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift ;;
        --proto) PROTO="$2"; shift ;;
        --port) PORT="$2"; shift ;;
        --expect) EXPECT="$2"; shift ;;
        *) echo "Unknown parameter: $1"; show_usage ;;
    esac
    shift
done


# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --host) HOST="$2"; shift ;;
        --proto) PROTO="$2"; shift ;;
        --port) PORT="$2"; shift ;;
        --expect) EXPECT="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Defaults
PROTO=${PROTO:-any}
PORT=${PORT:-any}
EXPECT=${EXPECT:-}

# Track test results
declare -A RESULTS
PASSED=true

# Improved TCP test with proper timeout
test_tcp() {
    if timeout 2 bash -c "echo > /dev/tcp/$HOST/$PORT"; then
        echo "✅ TCP/$PORT → ALLOWED (Host: $HOST)"
        RESULTS[tcp]=0
        return 0
    else
        echo "❌ TCP/$PORT → DENIED (Host: $HOST)"
        RESULTS[tcp]=1
        return 1
    fi
}

# Improved UDP test that actually checks for blocking
test_udp() {
    # Try sending UDP packet and see if we get any response (ICMP unreachable would indicate blocking)
    if timeout 2 bash -c "echo 'test' | nc -u -w 2 $HOST $PORT 2>&1 | grep -q 'Connection refused'"; then
        echo "❌ UDP/$PORT → DENIED (Host: $HOST) (Connection refused)"
        RESULTS[udp]=1
        return 1
    elif timeout 2 bash -c "echo 'test' | nc -u -w 2 $HOST $PORT &>/dev/null"; then
        echo "✅ UDP/$PORT → ALLOWED (Host: $HOST)"
        RESULTS[udp]=0
        return 0
    else
        echo "❌ UDP/$PORT → DENIED (Host: $HOST) (Timeout/no response)"
        RESULTS[udp]=1
        return 1
    fi
}

# Test ICMP (ping)
test_icmp() {
    if ping -c 1 -W 1 "$HOST" &>/dev/null; then
        echo "✅ ICMP → ALLOWED (Host: $HOST)"
        RESULTS[icmp]=0
        return 0
    else
        echo "❌ ICMP → DENIED (Host: $HOST)"
        RESULTS[icmp]=1
        return 1
    fi
}

# Run tests
echo "Testing firewall rules for $HOST..."
case "$PROTO" in
    tcp) test_tcp ;;
    udp) test_udp ;;
    icmp) test_icmp ;;
    any)
        test_tcp
        test_udp
        test_icmp
        ;;
    *) echo "Invalid protocol: $PROTO"; exit 1 ;;
esac

# Validate expectation (if --expect is set)
if [[ -n "$EXPECT" ]]; then
    for protocol in "${!RESULTS[@]}"; do
        if [[ "$EXPECT" == "allow" && ${RESULTS[$protocol]} -ne 0 ]] || 
           [[ "$EXPECT" == "deny" && ${RESULTS[$protocol]} -eq 0 ]]; then
            echo "✖️ $protocol result does NOT match expected: $EXPECT"
            PASSED=false
        fi
    done
    
    if $PASSED; then
        echo "✔️ All results match expected: $EXPECT"
    else
        exit 1
    fi
fi
