"""Test vectors for Host_Control_tb, built with swg_host's packet encoder.

    python tb_vectors.py emit  <vectors.txt>             # write packets for the testbench
    python tb_vectors.py check <vectors.txt> <replies.txt>  # check what the testbench received

Vector lines:  <name> <udp_port> <ok|none|badfcs> <payload hex>   (or "!button")
Reply lines:   <name> <payload hex | NONE>, plus "outputs <16 words>" and "tbcheck ..."
"""

import struct
import sys

import swg_host as h

RESET_PW = 0x0666_6666
RESET_SP = h.start_phase(RESET_PW, 100_014)
ID = 0x5357_4731
OKAY, SLVERR, DECERR = 0, 2, 3
IDLE, ARMED, TRIGGER, OUTPUT = 0, 1, 2, 3


def ch(name, reg):
    return h.channel_base(name) + reg


def scenario():
    """Yields (name, port, flag, payload, expect); expect=None means no reply."""
    regs = {}
    for c in h.CHANNELS:
        regs[ch(c, h.REG_PHASE_WORD)] = RESET_PW
        regs[ch(c, h.REG_START_PHASE)] = RESET_SP
    seq = [0]

    def pkt(ops):
        seq[0] += 1
        return h.build_request(seq[0], ops)

    def exp(code, state, results, held=None):
        return {"code": code, "state": state, "held": (state != OUTPUT) if held is None else held,
                "results": results}

    yield "status0", h.DEFAULT_PORT, "ok", pkt([]), exp(0, IDLE, [])
    yield "id", h.DEFAULT_PORT, "ok", pkt([("r", h.REG_ID)]), exp(0, IDLE, [(OKAY, ID)])
    probe = [ch("0A", 0), ch("0A", 4), ch("3B", 0), ch("3B", 4)]
    yield "defaults", h.DEFAULT_PORT, "ok", pkt([("r", a) for a in probe]), \
        exp(0, IDLE, [(OKAY, regs[a]) for a in probe])

    cmd = h.REG_COMMAND
    yield "early_trigger", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_TRIGGER)]), exp(3, IDLE, [(SLVERR, 0)])
    yield "early_commit", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_COMMIT)]), exp(3, IDLE, [(SLVERR, 0)])
    yield "stop_idle", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_STOP)]), exp(0, IDLE, [(OKAY, 0)])

    cfg = {}
    for i, c in enumerate(h.CHANNELS):
        pw = h.phase_word(1e6 * (5 + i))           # 5..12 MHz, all different
        cfg[c] = (pw, h.start_phase(pw))
    ops = []
    for c, (pw, sp) in cfg.items():
        ops += [("w", ch(c, 0), pw), ("w", ch(c, 4), sp)]
        regs[ch(c, 0)], regs[ch(c, 4)] = pw, sp
    ops.append(("w", cmd, h.CMD_COMMIT))
    yield "config", h.DEFAULT_PORT, "ok", pkt(ops), exp(0, TRIGGER, [(OKAY, 0)] * 17)

    addrs = sorted(regs)
    yield "readback", h.DEFAULT_PORT, "ok", pkt([("r", a) for a in addrs]), \
        exp(0, TRIGGER, [(OKAY, regs[a]) for a in addrs])
    yield "stop_in_trigger", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_STOP)]), exp(3, TRIGGER, [(SLVERR, 0)])

    regs[ch("1A", 0)] = 0x0ABC_0001
    yield "write_in_trigger", h.DEFAULT_PORT, "ok", pkt([("w", ch("1A", 0), 0x0ABC_0001)]), exp(0, ARMED, [(OKAY, 0)])
    yield "trigger_in_armed", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_TRIGGER)]), exp(3, ARMED, [(SLVERR, 0)])
    yield "commit2", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_COMMIT)]), exp(0, TRIGGER, [(OKAY, 0)])
    yield "commit_again", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_COMMIT)]), exp(0, TRIGGER, [(OKAY, 0)])
    yield "trigger", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_TRIGGER)]), exp(0, OUTPUT, [(OKAY, 0)])
    yield "trigger_again", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_TRIGGER)]), exp(0, OUTPUT, [(OKAY, 0)])

    regs[ch("3B", 4)] = 0x1357_9BDF
    yield "write_in_output", h.DEFAULT_PORT, "ok", \
        pkt([("w", ch("3B", 4), 0x1357_9BDF), ("r", ch("3B", 4))]), exp(0, OUTPUT, [(OKAY, 0), (OKAY, 0x1357_9BDF)])
    yield "stop", h.DEFAULT_PORT, "ok", pkt([("w", cmd, h.CMD_STOP)]), exp(0, IDLE, [(OKAY, 0)])
    yield "trigger_count", h.DEFAULT_PORT, "ok", pkt([("r", h.REG_TRIGGER_COUNT)]), exp(0, IDLE, [(OKAY, 1)])
    yield "ro_write", h.DEFAULT_PORT, "ok", pkt([("w", h.REG_STATE, 0)]), exp(3, IDLE, [(SLVERR, 0)])

    yield "bad_magic", h.DEFAULT_PORT, "ok", struct.pack(">IHH", 0xDEADBEEF, 77, 0), exp(1, IDLE, [])
    yield "bad_length", h.DEFAULT_PORT, "ok", pkt([("r", 0)])[:4] + struct.pack(">HH", 78, 2) + struct.pack(">II", 0, 0), \
        exp(2, IDLE, [])
    yield "short", h.DEFAULT_PORT, "ok", struct.pack(">I", h.MAGIC), exp(2, IDLE, [])

    yield "decerr_stops", h.DEFAULT_PORT, "ok", pkt([("r", 0x9000), ("w", ch("0A", 0), 0x1234_5678)]), \
        exp(3, IDLE, [(DECERR, 0)])
    yield "not_written", h.DEFAULT_PORT, "ok", pkt([("r", ch("0A", 0))]), exp(0, IDLE, [(OKAY, regs[ch("0A", 0)])])

    yield "max_ops", h.DEFAULT_PORT, "ok", pkt([("r", h.REG_ID)] * h.MAX_OPS), exp(0, IDLE, [(OKAY, ID)] * h.MAX_OPS)
    too_many = struct.pack(">IHH", h.MAGIC, 99, h.MAX_OPS + 1) + struct.pack(">II", h.READ_FLAG, 0) * (h.MAX_OPS + 1)
    yield "too_many", h.DEFAULT_PORT, "ok", too_many, exp(2, IDLE, [])

    yield "bad_fcs", h.DEFAULT_PORT, "badfcs", pkt([("w", ch("0A", 0), 0xBADB_AD00)]), None
    yield "after_bad_fcs", h.DEFAULT_PORT, "ok", pkt([("r", ch("0A", 0))]), exp(0, IDLE, [(OKAY, regs[ch("0A", 0)])])
    yield "wrong_port", h.DEFAULT_PORT + 1, "none", pkt([("w", ch("0A", 0), 0xBADB_AD01)]), None
    yield "after_wrong_port", h.DEFAULT_PORT, "ok", pkt([("r", ch("0A", 0))]), exp(0, IDLE, [(OKAY, regs[ch("0A", 0)])])

    regs[ch("2B", 0)] = 0x0222_2222
    yield "arm_and_fire", h.DEFAULT_PORT, "ok", \
        pkt([("w", ch("2B", 0), 0x0222_2222), ("w", cmd, h.CMD_COMMIT), ("w", cmd, h.CMD_TRIGGER)]), \
        exp(0, OUTPUT, [(OKAY, 0)] * 3)
    yield "!button", None, None, None, None
    yield "after_button", h.DEFAULT_PORT, "ok", pkt([("r", h.REG_TRIGGER_COUNT)]), exp(0, IDLE, [(OKAY, 2)])

    scenario.final_regs = regs


def emit(path):
    with open(path, "w") as f:
        for name, port, flag, payload, _ in scenario():
            if name.startswith("!"):
                f.write(name + "\n")
            else:
                f.write(f"{name} {port} {flag} {payload.hex()}\n")


def check(vec_path, rep_path):
    replies, outputs, tbcheck = {}, None, None
    for line in open(rep_path):
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "outputs":
            outputs = [int(x, 16) for x in parts[1:]]
        elif parts[0] == "tbcheck":
            tbcheck = parts[1:]
        else:
            replies[parts[0]] = parts[1] if len(parts) > 1 else "NONE"

    errors = 0

    def bad(msg):
        nonlocal errors
        errors += 1
        print("FAIL", msg)

    n = 0
    for name, _port, _flag, _payload, exp in scenario():
        if name.startswith("!"):
            continue
        n += 1
        got = replies.get(name)
        if got is None:
            bad(f"{name}: no line in replies file")
            continue
        if exp is None:
            if got != "NONE":
                bad(f"{name}: expected no reply, got {got}")
            continue
        if got == "NONE":
            bad(f"{name}: no reply")
            continue
        try:
            r = h.Reply(bytes.fromhex(got))
        except ValueError as e:
            bad(f"{name}: {e}")
            continue
        if r.code != exp["code"]:
            bad(f"{name}: code {r.code}, expected {exp['code']}")
        if r.run_state != exp["state"]:
            bad(f"{name}: state {h.STATES[r.run_state]}, expected {h.STATES[exp['state']]}")
        if r.held != exp["held"]:
            bad(f"{name}: hold_reset {r.held}, expected {exp['held']}")
        if r.results != exp["results"]:
            bad(f"{name}: results {r.results[:4]}..., expected {exp['results'][:4]}...")

    regs = scenario.final_regs
    want = []
    for c in h.CHANNELS:
        want += [regs[ch(c, 0)], regs[ch(c, 4)]]
    if outputs != want:
        bad(f"channel outputs {outputs} != {want}")
    if not tbcheck or tbcheck[0] != "PASS":
        bad(f"testbench-side checks: {tbcheck}")

    print(f"{'PASSED' if errors == 0 else 'FAILED'}: {n} packets, {errors} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    if sys.argv[1] == "emit":
        emit(sys.argv[2])
    else:
        sys.exit(check(sys.argv[2], sys.argv[3]))
