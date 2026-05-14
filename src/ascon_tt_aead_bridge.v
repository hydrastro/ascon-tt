`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0
//
// ascon_tt_aead_bridge.v
//
// Selects between shared-datapath and dual-path AEAD cores.
//   USE_SHARED_AEAD=1 (default): ascon_tt_aead_shared  (area-efficient)
//   USE_SHARED_AEAD=0:           ascon_tt_aead_bridge_dual (reference)
//
// ASCON_VARIANT is forwarded to ascon_tt_aead_shared only.

module ascon_tt_aead_bridge #(
  parameter integer ROUNDS_PER_CYCLE = 1,
  parameter integer USE_SHARED_AEAD  = 1,
  parameter integer ASCON_VARIANT    = 1   // 0=ASCON-128, 1=ASCON-128a
) (
  input  wire         clk,
  input  wire         rst_n,
  input  wire         clear_i,
  input  wire         start_i,
  input  wire         decrypt_i,
  input  wire [127:0] key_i,
  input  wire [127:0] nonce_i,
  input  wire [31:0]  ad_bytes_i,
  input  wire [31:0]  msg_bytes_i,
  input  wire [127:0] tag_i,
  input  wire [127:0] ad_block0_i,
  input  wire [127:0] ad_block1_i,
  input  wire [127:0] data_block0_i,
  input  wire [127:0] data_block1_i,
  output wire         busy_o,
  output wire         done_o,
  output wire         auth_ok_o,
  output wire [127:0] result_tag_o,
  output wire [127:0] out_block0_o,
  output wire [127:0] out_block1_o
);

  generate
    if (USE_SHARED_AEAD != 0) begin : gen_shared
      ascon_tt_aead_shared #(
        .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE),
        .ASCON_VARIANT   (ASCON_VARIANT)
      ) u_impl (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear_i      (clear_i),
        .start_i      (start_i),
        .decrypt_i    (decrypt_i),
        .key_i        (key_i),
        .nonce_i      (nonce_i),
        .ad_bytes_i   (ad_bytes_i),
        .msg_bytes_i  (msg_bytes_i),
        .tag_i        (tag_i),
        .ad_block0_i  (ad_block0_i),
        .ad_block1_i  (ad_block1_i),
        .data_block0_i(data_block0_i),
        .data_block1_i(data_block1_i),
        .busy_o       (busy_o),
        .done_o       (done_o),
        .auth_ok_o    (auth_ok_o),
        .result_tag_o (result_tag_o),
        .out_block0_o (out_block0_o),
        .out_block1_o (out_block1_o)
      );
    end else begin : gen_dual_reference
      ascon_tt_aead_bridge_dual #(
        .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
      ) u_impl (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear_i      (clear_i),
        .start_i      (start_i),
        .decrypt_i    (decrypt_i),
        .key_i        (key_i),
        .nonce_i      (nonce_i),
        .ad_bytes_i   (ad_bytes_i),
        .msg_bytes_i  (msg_bytes_i),
        .tag_i        (tag_i),
        .ad_block0_i  (ad_block0_i),
        .ad_block1_i  (ad_block1_i),
        .data_block0_i(data_block0_i),
        .data_block1_i(data_block1_i),
        .busy_o       (busy_o),
        .done_o       (done_o),
        .auth_ok_o    (auth_ok_o),
        .result_tag_o (result_tag_o),
        .out_block0_o (out_block0_o),
        .out_block1_o (out_block1_o)
      );
    end
  endgenerate

endmodule
`default_nettype wire
