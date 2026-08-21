#!/usr/bin/env bash
set -euo pipefail

SCRIPT_UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/extras/systemd/caelestia-pre-sleep-lock"

if [[ ! -x "$SCRIPT_UNDER_TEST" ]]; then
    echo "Error: Script under test not found or not executable at $SCRIPT_UNDER_TEST" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RESULTS_FILE="$TMP_DIR/results"
touch "$RESULTS_FILE"

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $test_name"
        echo "PASS" >> "$RESULTS_FILE"
    else
        echo "FAIL: $test_name (expected $expected, got $actual)"
        echo "FAIL" >> "$RESULTS_FILE"
    fi
}

assert_contains() {
    local substring="$1"
    local file="$2"
    local test_name="$3"
    if grep -q "$substring" "$file"; then
        echo "PASS: $test_name"
        echo "PASS" >> "$RESULTS_FILE"
    else
        echo "FAIL: $test_name (substring '$substring' not found in output)"
        echo "Output was:"
        cat "$file"
        echo "FAIL" >> "$RESULTS_FILE"
    fi
}

echo "=== Running pre-sleep lock tests ==="

# Test 1: SDDM Greeter Session Only -> Exit 0 (Allow sleep)
(
    TEST_MOCK_DIR="$TMP_DIR/test1"
    mkdir -p "$TEST_MOCK_DIR"

    cat <<'EOF' > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="$1"
shift
if [[ "$cmd" == "list-sessions" ]]; then
    echo "1 sddm sddm seat0"
elif [[ "$cmd" == "show-session" ]]; then
    session="$1"
    param="$3"
    case "$param" in
        Active) echo "yes" ;;
        Remote) echo "no" ;;
        Type) echo "wayland" ;;
        Class) echo "greeter" ;;
        User) echo "988" ;;
        Name) echo "sddm" ;;
    esac
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=2 SESSION_RETRY_DELAY=0.01 LOGINCTL="$TEST_MOCK_DIR/loginctl" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "0" "$status" "Test 1: SDDM greeter session allows sleep (exit 0)"
    assert_contains "allowing sleep" "$LOG_FILE" "Test 1: Output mentions allowing sleep"
)

# Test 2: No Sessions Present -> Exit 0 (Allow sleep)
(
    TEST_MOCK_DIR="$TMP_DIR/test2"
    mkdir -p "$TEST_MOCK_DIR"

    cat <<'EOF' > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="$1"
if [[ "$cmd" == "list-sessions" ]]; then
    exit 0
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=2 SESSION_RETRY_DELAY=0.01 LOGINCTL="$TEST_MOCK_DIR/loginctl" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "0" "$status" "Test 2: No sessions allows sleep (exit 0)"
    assert_contains "allowing sleep" "$LOG_FILE" "Test 2: Output mentions allowing sleep"
)

# Test 3: Active User Session - Lock Successful -> Exit 0
(
    TEST_MOCK_DIR="$TMP_DIR/test3"
    mkdir -p "$TEST_MOCK_DIR"

    cat <<'EOF' > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="$1"
shift
if [[ "$cmd" == "list-sessions" ]]; then
    echo "2 1000 jules seat0"
elif [[ "$cmd" == "show-session" ]]; then
    param="$3"
    case "$param" in
        Active) echo "yes" ;;
        Remote) echo "no" ;;
        Type) echo "wayland" ;;
        Class) echo "user" ;;
        User) echo "1000" ;;
        Name) echo "jules" ;;
    esac
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    cat <<'EOF' > "$TEST_MOCK_DIR/getent"
#!/usr/bin/env bash
echo "jules:x:1000:1000::/tmp:bin/bash"
EOF
    chmod +x "$TEST_MOCK_DIR/getent"

    cat <<'EOF' > "$TEST_MOCK_DIR/setpriv"
#!/usr/bin/env bash
shift 3
exec "$@"
EOF
    chmod +x "$TEST_MOCK_DIR/setpriv"

    cat <<'EOF' > "$TEST_MOCK_DIR/caelestia-qs-ipc"
#!/usr/bin/env bash
cmd="$1"
subcmd="$2"
if [[ "$subcmd" == "safeLock" ]]; then
    exit 0
elif [[ "$subcmd" == "isLocked" ]]; then
    echo "true"
    exit 0
fi
EOF
    chmod +x "$TEST_MOCK_DIR/caelestia-qs-ipc"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=1 LOGINCTL="$TEST_MOCK_DIR/loginctl" GETENT="$TEST_MOCK_DIR/getent" SETPRIV="$TEST_MOCK_DIR/setpriv" CAELESTIA_IPC_PATH="$TEST_MOCK_DIR/caelestia-qs-ipc" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "0" "$status" "Test 3: Active user session lock succeeds (exit 0)"
    assert_contains "secure lock confirmed" "$LOG_FILE" "Test 3: Lock confirmed log"
)

# Test 4: Active User Session - Lock Times Out -> Fail Closed (Exit 1)
(
    TEST_MOCK_DIR="$TMP_DIR/test4"
    mkdir -p "$TEST_MOCK_DIR"

    cat <<'EOF' > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="$1"
shift
if [[ "$cmd" == "list-sessions" ]]; then
    echo "2 1000 jules seat0"
elif [[ "$cmd" == "show-session" ]]; then
    param="$3"
    case "$param" in
        Active) echo "yes" ;;
        Remote) echo "no" ;;
        Type) echo "wayland" ;;
        Class) echo "user" ;;
        User) echo "1000" ;;
        Name) echo "jules" ;;
    esac
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    cat <<'EOF' > "$TEST_MOCK_DIR/getent"
#!/usr/bin/env bash
echo "jules:x:1000:1000::/tmp:bin/bash"
EOF
    chmod +x "$TEST_MOCK_DIR/getent"

    cat <<'EOF' > "$TEST_MOCK_DIR/setpriv"
#!/usr/bin/env bash
shift 3
exec "$@"
EOF
    chmod +x "$TEST_MOCK_DIR/setpriv"

    cat <<'EOF' > "$TEST_MOCK_DIR/caelestia-qs-ipc"
#!/usr/bin/env bash
cmd="$1"
subcmd="$2"
if [[ "$subcmd" == "safeLock" ]]; then
    exit 0
elif [[ "$subcmd" == "isLocked" ]]; then
    echo "false"
    exit 0
fi
EOF
    chmod +x "$TEST_MOCK_DIR/caelestia-qs-ipc"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=1 LOCK_ACK_TIMEOUT_LOOPS=2 LOCK_ACK_LOOP_INTERVAL=0.01 LOGINCTL="$TEST_MOCK_DIR/loginctl" GETENT="$TEST_MOCK_DIR/getent" SETPRIV="$TEST_MOCK_DIR/setpriv" CAELESTIA_IPC_PATH="$TEST_MOCK_DIR/caelestia-qs-ipc" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "1" "$status" "Test 4: Lock timeout fails closed (exit 1)"
    assert_contains "refusing unsafe sleep" "$LOG_FILE" "Test 4: Refusing unsafe sleep log"
)

# Test 5: Disappearing-Session Race -> Exit 0 (Allow sleep)
(
    TEST_MOCK_DIR="$TMP_DIR/test5"
    mkdir -p "$TEST_MOCK_DIR"

    FLAG_FILE="$TEST_MOCK_DIR/flag"
    touch "$FLAG_FILE"

    cat <<EOF > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="\$1"
shift
if [[ "\$cmd" == "list-sessions" ]]; then
    if [[ -f "$FLAG_FILE" ]]; then
        echo "2 1000 jules seat0"
    else
        exit 0
    fi
elif [[ "\$cmd" == "show-session" ]]; then
    param="\$3"
    if [[ -f "$FLAG_FILE" ]]; then
        case "\$param" in
            Active) echo "yes" ;;
            Remote) echo "no" ;;
            Type) echo "wayland" ;;
            Class) echo "user" ;;
            User) echo "1000" ;;
            Name) echo "jules" ;;
        esac
    else
        case "\$param" in
            Active) echo "no" ;;
            Remote) echo "no" ;;
            Type) echo "wayland" ;;
            Class) echo "user" ;;
            User) echo "1000" ;;
            Name) echo "jules" ;;
        esac
    fi
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    cat <<'EOF' > "$TEST_MOCK_DIR/getent"
#!/usr/bin/env bash
echo "jules:x:1000:1000::/tmp:bin/bash"
EOF
    chmod +x "$TEST_MOCK_DIR/getent"

    cat <<'EOF' > "$TEST_MOCK_DIR/setpriv"
#!/usr/bin/env bash
shift 3
exec "$@"
EOF
    chmod +x "$TEST_MOCK_DIR/setpriv"

    cat <<EOF > "$TEST_MOCK_DIR/caelestia-qs-ipc"
#!/usr/bin/env bash
rm -f "$FLAG_FILE"
exit 1
EOF
    chmod +x "$TEST_MOCK_DIR/caelestia-qs-ipc"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=1 LOGINCTL="$TEST_MOCK_DIR/loginctl" GETENT="$TEST_MOCK_DIR/getent" SETPRIV="$TEST_MOCK_DIR/setpriv" CAELESTIA_IPC_PATH="$TEST_MOCK_DIR/caelestia-qs-ipc" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "0" "$status" "Test 5: Disappearing session race allows sleep (exit 0)"
    assert_contains "disappeared" "$LOG_FILE" "Test 5: Disappeared session log"
)

# Test 6: Bounded Session Retries (Session appears on retry) -> Exit 0
(
    TEST_MOCK_DIR="$TMP_DIR/test6"
    mkdir -p "$TEST_MOCK_DIR"

    COUNTER_FILE="$TEST_MOCK_DIR/counter"
    echo "0" > "$COUNTER_FILE"

    cat <<EOF > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="\$1"
shift
count=\$(cat "$COUNTER_FILE")
if [[ "\$cmd" == "list-sessions" ]]; then
    echo "\$((count + 1))" > "$COUNTER_FILE"
    if (( count >= 1 )); then
        echo "3 1000 jules seat0"
    fi
elif [[ "\$cmd" == "show-session" ]]; then
    param="\$3"
    case "\$param" in
        Active) echo "yes" ;;
        Remote) echo "no" ;;
        Type) echo "wayland" ;;
        Class) echo "user" ;;
        User) echo "1000" ;;
        Name) echo "jules" ;;
    esac
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    cat <<'EOF' > "$TEST_MOCK_DIR/getent"
#!/usr/bin/env bash
echo "jules:x:1000:1000::/tmp:bin/bash"
EOF
    chmod +x "$TEST_MOCK_DIR/getent"

    cat <<'EOF' > "$TEST_MOCK_DIR/setpriv"
#!/usr/bin/env bash
shift 3
exec "$@"
EOF
    chmod +x "$TEST_MOCK_DIR/setpriv"

    cat <<'EOF' > "$TEST_MOCK_DIR/caelestia-qs-ipc"
#!/usr/bin/env bash
cmd="$1"
subcmd="$2"
if [[ "$subcmd" == "safeLock" ]]; then
    exit 0
elif [[ "$subcmd" == "isLocked" ]]; then
    echo "true"
    exit 0
fi
EOF
    chmod +x "$TEST_MOCK_DIR/caelestia-qs-ipc"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=3 SESSION_RETRY_DELAY=0.01 LOGINCTL="$TEST_MOCK_DIR/loginctl" GETENT="$TEST_MOCK_DIR/getent" SETPRIV="$TEST_MOCK_DIR/setpriv" CAELESTIA_IPC_PATH="$TEST_MOCK_DIR/caelestia-qs-ipc" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "0" "$status" "Test 6: Bounded retries finds session on attempt 2 (exit 0)"
    assert_contains "secure lock confirmed" "$LOG_FILE" "Test 6: Lock confirmed log"
)

# Test 7: IPC Missing for Active User Session -> Fail Closed (Exit 1)
(
    TEST_MOCK_DIR="$TMP_DIR/test7"
    mkdir -p "$TEST_MOCK_DIR"

    cat <<'EOF' > "$TEST_MOCK_DIR/loginctl"
#!/usr/bin/env bash
cmd="$1"
shift
if [[ "$cmd" == "list-sessions" ]]; then
    echo "2 1000 jules seat0"
elif [[ "$cmd" == "show-session" ]]; then
    param="$3"
    case "$param" in
        Active) echo "yes" ;;
        Remote) echo "no" ;;
        Type) echo "wayland" ;;
        Class) echo "user" ;;
        User) echo "1000" ;;
        Name) echo "jules" ;;
    esac
fi
EOF
    chmod +x "$TEST_MOCK_DIR/loginctl"

    cat <<'EOF' > "$TEST_MOCK_DIR/getent"
#!/usr/bin/env bash
echo "jules:x:1000:1000::/tmp:bin/bash"
EOF
    chmod +x "$TEST_MOCK_DIR/getent"

    LOG_FILE="$TEST_MOCK_DIR/log.txt"
    set +e
    SESSION_RETRIES=1 LOGINCTL="$TEST_MOCK_DIR/loginctl" GETENT="$TEST_MOCK_DIR/getent" CAELESTIA_IPC_PATH="$TEST_MOCK_DIR/nonexistent-ipc" "$SCRIPT_UNDER_TEST" >"$LOG_FILE" 2>&1
    status=$?
    set -e

    assert_equals "1" "$status" "Test 7: IPC missing for active session fails closed (exit 1)"
    assert_contains "refusing unsafe sleep" "$LOG_FILE" "Test 7: Refusing unsafe sleep log"
)

echo "=== Test Summary ==="
passed_count=$(grep -c "PASS" "$RESULTS_FILE" || true)
failed_count=$(grep -c "FAIL" "$RESULTS_FILE" || true)
echo "Passed: $passed_count"
echo "Failed: $failed_count"

if (( failed_count > 0 )); then
    exit 1
fi
exit 0
