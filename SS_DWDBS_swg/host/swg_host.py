"""Host-side control of the SS_DWDBS square-wave generator over UDP.

Typical run:
    swg = SWG("192.168.1.128")
    swg.configure({"0A": (phase_word(25e6), start_phase(phase_word(25e6))), ...})  # -> TRIGGER state
    swg.trigger()                                                                   # -> OUTPUT (waves run)
    swg.stop()                                                                      # -> IDLE (waves held)

CLI:
    python swg_host.py status
    python swg_host.py run --freq 25e6          # configure all channels, commit, trigger
    python swg_host.py config --freq 25e6 --channels 0A 1B
    python swg_host.py trigger | stop
    python swg_host.py read 0x1000
    python swg_host.py write 0x1000 0x06666666

Packet format (big-endian), matching Udp_Cmd_Engine.sv:
    request: MAGIC u32, SEQ u16, COUNT u16, COUNT x (ADDR u32 [bit31 = read], DATA u32)
    reply:   MAGIC u32, SEQ u16, DONE u16, CODE u32, STATE u32, DONE x (RESP u32, DATA u32)
"""

import argparse
import random
import socket
import struct
import sys

MAGIC = 0x53574731          # "SWG1"
DEFAULT_IP = "192.168.1.128"
DEFAULT_PORT = 1234
MAX_OPS = 128
READ_FLAG = 0x8000_0000

# Run_Control (0x0000)
REG_ID = 0x0000
REG_STATE = 0x0004
REG_COMMAND = 0x0008
REG_TRIGGER_COUNT = 0x000C
CMD_COMMIT, CMD_TRIGGER, CMD_STOP = 1, 2, 3
STATES = {0: "IDLE", 1: "ARMED", 2: "TRIGGER", 3: "OUTPUT"}

# Channel_Regs: channel i at 0x1000 * (i + 1)
CHANNELS = ["0A", "0B", "1A", "1B", "2A", "2B", "3A", "3B"]
REG_PHASE_WORD = 0x00
REG_START_PHASE = 0x04

CODES = {0: "OK", 1: "bad magic", 2: "bad length/count", 3: "op failed"}
RESPS = {0: "OKAY", 1: "EXOKAY", 2: "SLVERR", 3: "DECERR"}

SAMPLE_RATE = 1e9           # DDS samples per second (DDR on the 500 MHz clk_quick)
MARKER_SAMPLES = 100_014    # samples from DDS start to the start marker (Top.sv default)


def channel_base(name):
    return 0x1000 * (CHANNELS.index(name.upper()) + 1)


def phase_word(freq_hz, fs=SAMPLE_RATE):
    """32-bit DDS phase increment for an output frequency."""
    return round(freq_hz / fs * 2**32) & 0xFFFF_FFFF


def start_phase(pw, samples=MARKER_SAMPLES):
    """Start phase that puts a rising edge exactly `samples` samples after the DDS starts."""
    return (0x8000_0000 - pw * samples) & 0xFFFF_FFFF


def build_request(seq, ops):
    """ops: list of ("r", addr) or ("w", addr, data)."""
    if len(ops) > MAX_OPS:
        raise ValueError(f"at most {MAX_OPS} ops per packet")
    body = b""
    for op in ops:
        if op[0] == "r":
            body += struct.pack(">II", READ_FLAG | op[1], 0)
        else:
            body += struct.pack(">II", op[1] & 0x7FFF_FFFF, op[2] & 0xFFFF_FFFF)
    return struct.pack(">IHH", MAGIC, seq & 0xFFFF, len(ops)) + body


class Reply:
    def __init__(self, data):
        if len(data) < 16:
            raise ValueError(f"reply too short ({len(data)} bytes)")
        magic, self.seq, self.done, self.code, self.state = struct.unpack(">IHHII", data[:16])
        if magic != MAGIC:
            raise ValueError(f"bad reply magic 0x{magic:08X}")
        if len(data) != 16 + 8 * self.done:
            raise ValueError(f"reply length {len(data)} does not match DONE={self.done}")
        self.results = [struct.unpack(">II", data[16 + 8 * k:24 + 8 * k]) for k in range(self.done)]

    @property
    def run_state(self):
        return self.state & 0x3

    @property
    def held(self):
        return bool(self.state & 0x100)

    def __repr__(self):
        res = ", ".join(f"{RESPS.get(r, r)}:0x{d:08X}" for r, d in self.results)
        return (f"<Reply seq={self.seq} code={CODES.get(self.code, self.code)} "
                f"state={STATES.get(self.run_state, self.run_state)} [{res}]>")


class SWGError(RuntimeError):
    pass


class SWG:
    def __init__(self, ip=DEFAULT_IP, port=DEFAULT_PORT, timeout=0.5, retries=3):
        self.addr = (ip, port)
        self.retries = retries
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.settimeout(timeout)
        self.seq = random.randrange(0x10000)

    def transact(self, ops, check=True):
        """Send one packet and return its Reply. Retries on timeout (commands are idempotent)."""
        self.seq = (self.seq + 1) & 0xFFFF
        pkt = build_request(self.seq, ops)
        for _ in range(self.retries):
            self.sock.sendto(pkt, self.addr)
            try:
                while True:
                    data, _src = self.sock.recvfrom(2048)
                    reply = Reply(data)
                    if reply.seq == self.seq:
                        break
            except socket.timeout:
                continue
            if check and reply.code != 0:
                raise SWGError(f"command failed: {reply}")
            return reply
        raise SWGError(f"no reply from {self.addr[0]}:{self.addr[1]}")

    # Raw register access
    def read(self, addr):
        return self.transact([("r", addr)]).results[0][1]

    def write(self, addr, data):
        self.transact([("w", addr, data)])

    # Run control
    def status(self):
        r = self.transact([])
        return STATES[r.run_state]

    def configure(self, channels, commit=True):
        """channels: {"0A": (phase_word, start_phase), ...}. One packet: all writes, then COMMIT."""
        ops = []
        for name, (pw, sp) in channels.items():
            base = channel_base(name)
            ops += [("w", base + REG_PHASE_WORD, pw), ("w", base + REG_START_PHASE, sp)]
        if commit:
            ops.append(("w", REG_COMMAND, CMD_COMMIT))
        return self.transact(ops)

    def commit(self):
        return self.transact([("w", REG_COMMAND, CMD_COMMIT)])

    def trigger(self):
        return self.transact([("w", REG_COMMAND, CMD_TRIGGER)])

    def stop(self):
        return self.transact([("w", REG_COMMAND, CMD_STOP)])


def _int(s):
    return int(s, 0)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--ip", default=DEFAULT_IP)
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    for name in ("config", "run"):
        c = sub.add_parser(name)
        c.add_argument("--freq", type=float, default=25e6, help="output frequency in Hz")
        c.add_argument("--samples", type=int, default=MARKER_SAMPLES,
                       help="samples from DDS start to the aligned rising edge")
        c.add_argument("--channels", nargs="+", default=CHANNELS)
    sub.add_parser("trigger")
    sub.add_parser("stop")
    r = sub.add_parser("read")
    r.add_argument("addr", type=_int)
    w = sub.add_parser("write")
    w.add_argument("addr", type=_int)
    w.add_argument("data", type=_int)
    a = p.parse_args(argv)

    swg = SWG(a.ip, a.port)
    if a.cmd == "status":
        print(swg.status())
    elif a.cmd in ("config", "run"):
        pw = phase_word(a.freq)
        sp = start_phase(pw, a.samples)
        print(f"phase_word=0x{pw:08X} start_phase=0x{sp:08X} -> {' '.join(a.channels)}")
        print(swg.configure({ch: (pw, sp) for ch in a.channels}))
        if a.cmd == "run":
            print(swg.trigger())
    elif a.cmd == "trigger":
        print(swg.trigger())
    elif a.cmd == "stop":
        print(swg.stop())
    elif a.cmd == "read":
        print(f"0x{swg.read(a.addr):08X}")
    elif a.cmd == "write":
        swg.write(a.addr, a.data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
