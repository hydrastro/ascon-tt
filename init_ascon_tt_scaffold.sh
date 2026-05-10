#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(pwd)}"

if [[ ! -d "$REPO" ]]; then
  echo "ERROR: repo path does not exist: $REPO"
  exit 1
fi

cd "$REPO"

mkdir -p src test docs deps

cat > .gitignore <<'EOF'
# Build/sim products
/build/
/sim_build/
*.vvp
*.vcd
*.fst

# Python/cache
__pycache__/
.pytest_cache/

# Local dependencies
/deps/ascon-rtl/

# Nix/direnv
/result
/.direnv/
/.envrc

# Patch/editor leftovers
*.rej
*.orig
*.patch
*.zip
*.tar.gz
*~
EOF

cat > flake.nix <<'EOF'
{
  description = "Tiny Tapeout ASCON AEAD project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ascon-rtl.url = "path:../ascon-rtl";
    ascon-rtl.flake = false;
  };

  outputs = { self, nixpkgs, ascon-rtl }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          gnumake
          git
          iverilog
          verilator
          yosys
          python3
        ];

        shellHook = ''
          echo "ascon-tt dev shell"
          echo "ASCON_RTL=${ascon-rtl}"
        '';
      };
    };
}
EOF

cat > info.yaml <<'EOF'
# Tiny Tapeout project metadata.
#
# This is intentionally minimal. Before submitting, compare this with the
# current official ttsky/ttihp template for your chosen shuttle.
project:
  title: "ASCON AEAD Serial Accelerator"
  author: "a b"
  discord: ""
  description: "Full Ascon-AEAD128 accelerator with a Tiny Tapeout serial byte protocol"
  language: "Verilog"
  clock_hz: 25000000
  tiles: "TBD"
  top_module: "tt_um_ascon_aead"
  source_files:
    - "project.v"
    - "ascon_tt_serial_frontend.v"
    - "ascon_tt_aead_core_stub.v"
EOF

cat > docs/info.md <<'EOF'
# ASCON AEAD Serial Accelerator

This project targets a full Ascon-AEAD128 accelerator behind a Tiny Tapeout-style
8-bit serial command/data protocol.

Current status:

- TT-1 scaffold
- Tiny Tapeout top-level ports
- serial command frontend skeleton
- placeholder AEAD core stub

The final goal is full AEAD:

- encryption
- decryption
- associated data
- partial final blocks
- tag generation
- tag verification

The final design should reuse verified logic from `ascon-rtl`, but it must not
use AXI, MMIO, NEORV32, XBUS, or large FIFOs.
EOF

cat > docs/architecture.md <<'EOF'
# ASCON Tiny Tapeout architecture

## Goal

Implement full Ascon-AEAD128 on Tiny Tapeout using a small byte-serial interface.

## Non-goals

The TT implementation must not include:

- AXI
- MMIO32
- NEORV32/XBUS
- 128-bit external data bus
- large FIFOs

## Top-level interface

The Tiny Tapeout top exposes the standard HDL user-module ports:

```verilog
module tt_um_ascon_aead (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);
```

## Proposed serial protocol

Dedicated input bus:

```text
ui_in[7:0] = command/data byte
```

Dedicated output bus:

```text
uo_out[7:0] = response/data byte
```

Bidirectional control pins:

```text
uio_in[0]  = in_valid
uio_out[0] = in_ready

uio_in[1]  = out_ready
uio_out[1] = out_valid

uio_out[2] = busy
uio_out[3] = done
uio_out[4] = auth_ok
uio_out[5] = error

uio_out[7:6] reserved
```

`uio_oe` is set for the output/status bits driven by the design.

## Initial command map

```text
0x00 NOP
0x01 SET_MODE          next byte: 0=encrypt, 1=decrypt
0x02 SET_AD_BYTES      next 4 bytes, little-endian
0x03 SET_MSG_BYTES     next 4 bytes, little-endian

0x10 LOAD_KEY          next 16 bytes
0x11 LOAD_NONCE        next 16 bytes
0x12 LOAD_AD           next ad_bytes bytes
0x13 LOAD_DATA         next msg_bytes bytes
0x14 LOAD_TAG          next 16 bytes, decrypt only

0x20 START
0x21 STATUS
0x30 READ_DATA         emits msg_bytes bytes
0x31 READ_TAG          emits 16 bytes
0x40 CLEAR
```

## Implementation plan

1. TT-1: project scaffold and protocol skeleton.
2. TT-2: byte storage frontend and command parser.
3. TT-3: shared full-AEAD FSM using one RPC=1 permutation engine.
4. TT-4: test against `ascon-rtl` vectors.
5. TT-5: OpenLane/Tiny Tapeout area/frequency loop.
EOF

cat > src/project.v <<'EOF'
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// Tiny Tapeout user module top.
//
// Keep this file thin.  The protocol implementation lives in
// ascon_tt_serial_frontend.v and the full AEAD engine will be added behind it.

module tt_um_ascon_aead (
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // Bidirectional IO input path
  output wire [7:0] uio_out,  // Bidirectional IO output path
  output wire [7:0] uio_oe,   // Bidirectional IO output enable, active high
  input  wire       ena,      // Always 1 when powered
  input  wire       clk,
  input  wire       rst_n
);

  ascon_tt_serial_frontend u_frontend (
    .clk       (clk),
    .rst_n     (rst_n),
    .ena_i     (ena),

    .cmd_data_i(ui_in),
    .resp_o    (uo_out),

    .in_valid_i(uio_in[0]),
    .in_ready_o(uio_out[0]),

    .out_ready_i(uio_in[1]),
    .out_valid_o(uio_out[1]),

    .busy_o    (uio_out[2]),
    .done_o    (uio_out[3]),
    .auth_ok_o (uio_out[4]),
    .error_o   (uio_out[5])
  );

  assign uio_out[7:6] = 2'b00;

  // Drive uio_out[5:0], keep uio[7:6] as inputs/reserved.
  assign uio_oe = 8'b0011_1111;

  // Avoid unused-input warnings for currently reserved pins.
  wire _unused = &{uio_in[7:2], 1'b0};

endmodule

`default_nettype wire
EOF

cat > src/ascon_tt_serial_frontend.v <<'EOF'
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// TT-1 serial frontend skeleton.
//
// This module intentionally implements only a tiny command/status shell.  The
// full AEAD byte-store and shared AEAD FSM will be added incrementally.

module ascon_tt_serial_frontend (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       ena_i,

  input  wire [7:0] cmd_data_i,
  output reg  [7:0] resp_o,

  input  wire       in_valid_i,
  output wire       in_ready_o,

  input  wire       out_ready_i,
  output reg        out_valid_o,

  output wire       busy_o,
  output reg        done_o,
  output reg        auth_ok_o,
  output reg        error_o
);

  localparam [7:0] CMD_NOP       = 8'h00;
  localparam [7:0] CMD_SET_MODE  = 8'h01;
  localparam [7:0] CMD_STATUS    = 8'h21;
  localparam [7:0] CMD_CLEAR     = 8'h40;

  localparam [2:0] ST_IDLE       = 3'd0;
  localparam [2:0] ST_WAIT_MODE  = 3'd1;
  localparam [2:0] ST_RESP       = 3'd2;

  reg [2:0] state_q;
  reg       mode_decrypt_q;

  wire in_fire_w  = in_valid_i && in_ready_o;
  wire out_fire_w = out_valid_o && out_ready_i;

  assign in_ready_o = ena_i && !out_valid_o;
  assign busy_o = (state_q != ST_IDLE);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      mode_decrypt_q <= 1'b0;
      resp_o <= 8'h00;
      out_valid_o <= 1'b0;
      done_o <= 1'b0;
      auth_ok_o <= 1'b0;
      error_o <= 1'b0;
    end else begin
      done_o <= 1'b0;

      if (out_fire_w) begin
        out_valid_o <= 1'b0;
        if (state_q == ST_RESP) begin
          state_q <= ST_IDLE;
        end
      end

      if (in_fire_w) begin
        case (state_q)
          ST_IDLE: begin
            case (cmd_data_i)
              CMD_NOP: begin
              end

              CMD_CLEAR: begin
                mode_decrypt_q <= 1'b0;
                resp_o <= 8'hc1;
                out_valid_o <= 1'b1;
                done_o <= 1'b0;
                auth_ok_o <= 1'b0;
                error_o <= 1'b0;
                state_q <= ST_RESP;
              end

              CMD_SET_MODE: begin
                state_q <= ST_WAIT_MODE;
              end

              CMD_STATUS: begin
                resp_o <= {2'b00, error_o, auth_ok_o, done_o, busy_o, mode_decrypt_q, 1'b1};
                out_valid_o <= 1'b1;
                state_q <= ST_RESP;
              end

              default: begin
                error_o <= 1'b1;
                resp_o <= 8'hee;
                out_valid_o <= 1'b1;
                state_q <= ST_RESP;
              end
            endcase
          end

          ST_WAIT_MODE: begin
            mode_decrypt_q <= cmd_data_i[0];
            resp_o <= {7'h25, cmd_data_i[0]};
            out_valid_o <= 1'b1;
            state_q <= ST_RESP;
          end

          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
EOF

cat > src/ascon_tt_aead_core_stub.v <<'EOF'
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// Placeholder for the future full AEAD engine.
//
// The final implementation should use a shared runtime encrypt/decrypt FSM and
// one RPC=1 Ascon permutation engine.  This stub is intentionally not used yet;
// it reserves the filename in info.yaml so the project structure is stable.

module ascon_tt_aead_core_stub (
  input  wire clk,
  input  wire rst_n,
  input  wire start_i,
  output reg  done_o
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_o <= 1'b0;
    end else begin
      done_o <= start_i;
    end
  end

endmodule

`default_nettype wire
EOF

cat > test/tb_tt_um_ascon_aead.v <<'EOF'
`timescale 1ns/1ps
`default_nettype none

module tb_tt_um_ascon_aead;
  reg [7:0] ui_in;
  wire [7:0] uo_out;
  reg [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg ena;
  reg clk;
  reg rst_n;

  integer errors;

  tt_um_ascon_aead dut (
    .ui_in(ui_in),
    .uo_out(uo_out),
    .uio_in(uio_in),
    .uio_out(uio_out),
    .uio_oe(uio_oe),
    .ena(ena),
    .clk(clk),
    .rst_n(rst_n)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  task reset_dut;
    begin
      ui_in <= 8'h00;
      uio_in <= 8'h00;
      ena <= 1'b1;
      rst_n <= 1'b0;
      repeat (5) @(posedge clk);
      rst_n <= 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  task send_byte;
    input [7:0] value;
    begin
      @(negedge clk);
      ui_in = value;
      uio_in[0] = 1'b1; // in_valid
      uio_in[1] = 1'b1; // out_ready
      #1;
      if (!uio_out[0]) begin
        $display("FAIL: in_ready low before sending %02x", value);
        errors = errors + 1;
      end
      @(posedge clk);
      @(negedge clk);
      uio_in[0] = 1'b0;
      ui_in = 8'h00;
    end
  endtask

  task expect_response;
    input [7:0] expected;
    integer timeout;
    begin
      timeout = 0;
      uio_in[1] = 1'b1; // out_ready
      while (!uio_out[1] && timeout < 20) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      #1;
      if (!uio_out[1]) begin
        $display("FAIL: timeout waiting for response %02x", expected);
        errors = errors + 1;
      end else if (uo_out !== expected) begin
        $display("FAIL: response got=%02x expected=%02x", uo_out, expected);
        errors = errors + 1;
      end
      @(posedge clk);
      @(negedge clk);
      uio_in[1] = 1'b0;
    end
  endtask

  initial begin
    errors = 0;
    reset_dut();

    if (uio_oe !== 8'b0011_1111) begin
      $display("FAIL: uio_oe got=%02x", uio_oe);
      errors = errors + 1;
    end

    send_byte(8'h01); // SET_MODE
    send_byte(8'h01); // decrypt
    expect_response(8'h4b);

    send_byte(8'h21); // STATUS
    // Status bit layout: {00,error,auth_ok,done,busy,mode,1}
    expect_response(8'h03);

    send_byte(8'h40); // CLEAR
    expect_response(8'hc1);

    send_byte(8'hff); // invalid
    expect_response(8'hee);

    if (errors == 0) begin
      $display("ALL ASCON TT SCAFFOLD TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT SCAFFOLD TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
EOF

cat > Makefile <<'EOF'
TOP := tt_um_ascon_aead
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build

IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys

SRC_FILES := \
	$(SRC_DIR)/project.v \
	$(SRC_DIR)/ascon_tt_serial_frontend.v \
	$(SRC_DIR)/ascon_tt_aead_core_stub.v

.PHONY: all clean sim lint synth sanity

all: sim lint synth

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

sim: $(BUILD_DIR)/tb_tt_um_ascon_aead.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_um_ascon_aead.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_um_ascon_aead.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -o $@ $(TEST_DIR)/tb_tt_um_ascon_aead.v $(SRC_FILES)

lint:
	$(VERILATOR) --lint-only --timing -Wall --top-module $(TOP) $(SRC_FILES)

synth: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_scaffold_stat.txt
	cat $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

sanity:
	@test -f info.yaml
	@test -f src/project.v
	@test -f docs/info.md
	@test -f docs/architecture.md
	@! find . -name '*.rej' -o -name '*.orig' -o -name '*.patch' -o -name '*.zip' -o -name '*.tar.gz' | grep -q .
	@echo "sanity OK"

clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vvp *.vcd *.fst
EOF

echo "ascon-tt scaffold installed in: $REPO"
echo
echo "Run:"
echo "  nix develop"
echo "  make sanity"
echo "  make sim"
echo "  make lint"
echo "  make synth"
echo
echo "Then commit:"
echo "  git add ."
echo "  git commit -m 'Initial Tiny Tapeout ASCON AEAD scaffold'"
