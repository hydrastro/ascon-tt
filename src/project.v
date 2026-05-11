`timescale 1ns/1ps
// TT profile defaults.
// Normal builds use the production Tiny Tapeout profile.
// Debug simulations compile with -DTT_DEBUG_DEFAULTS.
`ifndef TT_ASCON_PROFILE_DEFAULTS_VH
`define TT_ASCON_PROFILE_DEFAULTS_VH
`ifdef TT_DEBUG_DEFAULTS
`define TT_ASCON_DEF_ENABLE_PERM_DEBUG 1
`define TT_ASCON_DEF_ENABLE_DIAGNOSTICS 1
`define TT_ASCON_DEF_ENABLE_OUT_BUFFER 1
`else
`define TT_ASCON_DEF_ENABLE_PERM_DEBUG 0
`define TT_ASCON_DEF_ENABLE_DIAGNOSTICS 0
`define TT_ASCON_DEF_ENABLE_OUT_BUFFER 0
`endif
`endif

`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// Tiny Tapeout user module top.
//
// Keep this file thin.  The protocol implementation lives in
// ascon_tt_serial_frontend.v and the full AEAD engine will be added behind it.

/* verilator lint_off DECLFILENAME */
module tt_um_ascon_aead #(
  parameter integer ENABLE_OUT_BUFFER = `TT_ASCON_DEF_ENABLE_OUT_BUFFER,
 
  parameter integer MAX_DATA_BYTES = 32,
 
  parameter integer MAX_AD_BYTES = 32,
 
  parameter integer ENABLE_DIAGNOSTICS = `TT_ASCON_DEF_ENABLE_DIAGNOSTICS,
 parameter integer ENABLE_PERM_DEBUG = `TT_ASCON_DEF_ENABLE_PERM_DEBUG,
 parameter integer USE_SHARED_AEAD = 1) (
  input  wire [7:0] ui_in,    // Dedicated inputs
  output wire [7:0] uo_out,   // Dedicated outputs
  input  wire [7:0] uio_in,   // Bidirectional IO input path
  output wire [7:0] uio_out,  // Bidirectional IO output path
  output wire [7:0] uio_oe,   // Bidirectional IO output enable, active high
  input  wire       ena,      // Always 1 when powered
  input  wire       clk,
  input  wire       rst_n
);

  ascon_tt_serial_frontend #(
    .ENABLE_PERM_DEBUG(ENABLE_PERM_DEBUG),
    .USE_SHARED_AEAD(USE_SHARED_AEAD),
    .ENABLE_DIAGNOSTICS(ENABLE_DIAGNOSTICS),
    .ENABLE_OUT_BUFFER(ENABLE_OUT_BUFFER),
    .MAX_AD_BYTES(MAX_AD_BYTES),
    .MAX_DATA_BYTES(MAX_DATA_BYTES)
  ) u_frontend (
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
/* verilator lint_on DECLFILENAME */

`default_nettype wire
