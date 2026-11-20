# FPGA DMA Controller

32-bit DMA memory-copy engine in SystemVerilog, with a round-robin arbiter so the DMA and a CPU can share one memory port. Targets the Terasic DE10-Lite (MAX 10).

## Design

- `rtl/dma_controller.sv`: copy engine with a register interface, 4-word buffered bursts (configurable 1-16), timeout and error reporting, and a count of completed words
- `rtl/rr_arbiter.sv`: fair per-beat arbitration that holds a stalled grant until it is accepted or cancelled
- `board/de10_dma_top.sv`: board demo where a small sequencer copies 64 words of on-chip RAM and checks them. LEDR8 = pass, LEDR9 = fail
- `firmware/controllers.c`: C driver, also used for co-simulation against the RTL

Register map and bus timing are in [docs/INTERFACES.md](docs/INTERFACES.md).

## Verification

| Test | Result |
|---|---|
| Randomized regression, seeds 1 and 42 | 1,000 copies per seed, pass |
| Shared memory with a busy second requester | pass |
| Burst sizes 1, 8, 16 | 50 copies each, pass |
| C driver + Verilator RTL co-simulation | 500 copies, pass |
| Verilator lint (`-Wall`, warnings fatal) | clean |
| Yosys generic synthesis | pass |

Directed cases cover zero length, misalignment, overlapping ranges, address overflow, read/write errors, timeout, and reset mid-transfer. Logs and a waveform are in `results/`.

Not done yet: Quartus timing results and an on-board test.

## Run

```sh
iverilog -g2012 -Wall -s tb_dma -o tb_dma rtl/dma_controller.sv rtl/rr_arbiter.sv sim/tb_dma.sv
vvp tb_dma +N=1000 +SEED=1
```

For the board, open `board/de10_dma.qpf` in Quartus.
