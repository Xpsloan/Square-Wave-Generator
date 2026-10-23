# Ethernet host control

The FPGA listens for UDP command packets on **192.168.1.128:1234** (MAC
02:00:00:00:00:00) on the SP701's `ethernet_1` PHY (Marvell 88E1111, RGMII).
Change the address in `Host_Control`'s parameters (`LOCAL_IP`, `UDP_PORT`, ...)
if your network needs something else.

## PC setup

Give the PC's Ethernet port a static address on the same subnet, e.g.
`192.168.1.100 / 255.255.255.0`, and connect it to the board (directly or
through a switch; 1000BASE-T). `led[1]` lights once the FPGA has configured
the PHY and blinks off briefly for every command it answers.

## Commands

```
python swg_host.py status                      # IDLE / ARMED / TRIGGER / OUTPUT
python swg_host.py run --freq 25e6             # all channels: write, COMMIT, TRIGGER
python swg_host.py config --freq 10e6 --channels 0A 0B   # write + COMMIT only
python swg_host.py trigger
python swg_host.py stop
python swg_host.py read 0x1000                 # raw register access
python swg_host.py write 0x1000 0x06666666
```

From Python: `SWG().configure({"0A": (phase_word(25e6), start_phase(phase_word(25e6))), ...})`,
then `trigger()`, `stop()`.

## Run sequence

| State   | Waves         | Next                                                     |
|---------|---------------|----------------------------------------------------------|
| IDLE    | held in reset | any channel write -> ARMED                               |
| ARMED   | held in reset | COMMIT -> TRIGGER                                        |
| TRIGGER | held in reset | TRIGGER -> OUTPUT; a channel write -> back to ARMED      |
| OUTPUT  | running       | STOP (or the North button) -> IDLE                       |

The waves are only ever released by the TRIGGER command, so no channel value
can change while a run starts. Commands that don't apply in the current state
return an error (SLVERR) and change nothing; repeating the command that got
you into the current state is accepted, so retries are safe. Writes during
OUTPUT are kept and used on the next run.

## Register map

| Address            | Register                                   |
|--------------------|--------------------------------------------|
| 0x0000             | ID (0x53574731)                            |
| 0x0004             | STATE: [1:0] state, [8] waves held         |
| 0x0008             | COMMAND: 1 COMMIT, 2 TRIGGER, 3 STOP       |
| 0x000C             | TRIGGER_COUNT                              |
| 0x1000 * (n+1)     | channel n PHASE_WORD (n = 0A,0B,1A,...,3B) |
| 0x1000 * (n+1) + 4 | channel n START_PHASE                      |

## Simulation

`sim_1/new/Host_Control_tb.sv` runs the whole Ethernet path at the pins with
an 88E1111 model. From the simulation run directory:

```
python <project>/host/tb_vectors.py emit tb_vectors.txt
(run Host_Control_tb)
python <project>/host/tb_vectors.py check tb_vectors.txt tb_replies.txt
```

## If the link misbehaves on hardware

- `led[1]` never lights: the MDIO scan found no PHY (it retries every 5 ms).
- Link up but no replies: check the PC's address/subnet and firewall (UDP 1234).
- Replies lost or corrupted at 1 Gb/s: the RX capture window is set by
  `RX_IDELAY_TAPS` in `Eth_Host_Link` (78 ps per tap, default 10).
