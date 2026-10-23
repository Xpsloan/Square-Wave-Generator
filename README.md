# Square-Wave-Generator
customizable square wave generator with multiple outputs channels all with start synchronization. Can customize frequency up to 300 MHz, duty, and phase shift.

## Projects

- Repository root: `Playground_DWDBS_swg` Vivado project.
- [`SS_DWDBS_swg/`](SS_DWDBS_swg/): 8-channel DWDBS generator for the SP701 with
  per-channel start markers, skew-matched and locked loopback routing, and host
  control over Ethernet (UDP -> AXI4-Lite). See
  [`SS_DWDBS_swg/host/README.md`](SS_DWDBS_swg/host/README.md) for the host tools.
