`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

module ascon_tt_aead_bridge_dual #(
  parameter integer ROUNDS_PER_CYCLE = 1
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

  output reg          busy_o,
  output reg          done_o,
  output reg          auth_ok_o,
  output reg [127:0]  result_tag_o,
  output reg [127:0]  out_block0_o,
  output reg [127:0]  out_block1_o
);

  localparam [1:0] ST_IDLE = 2'd0;
  localparam [1:0] ST_RUN  = 2'd1;

  reg [1:0] state_q;
  reg       decrypt_q;

  reg [1:0] ad_blocks_q;
  reg [1:0] data_blocks_q;
  reg [1:0] ad_idx_q;
  reg [1:0] data_in_idx_q;
  reg [1:0] data_out_idx_q;
  reg       result_seen_q;

  reg enc_start_q;
  reg dec_start_q;

  wire enc_busy_w;
  wire enc_done_w;
  wire enc_ad_ready_w;
  wire enc_pt_ready_w;
  wire enc_ct_valid_w;
  wire [127:0] enc_ct_block_w;
  wire [4:0] enc_ct_bytes_w;
  wire enc_tag_valid_w;
  wire [127:0] enc_tag_w;

  wire dec_busy_w;
  wire dec_done_w;
  wire dec_ad_ready_w;
  wire dec_ct_ready_w;
  wire dec_pt_valid_w;
  wire [127:0] dec_pt_block_w;
  wire [4:0] dec_pt_bytes_w;
  wire dec_auth_valid_w;
  wire dec_auth_ok_w;

  wire [127:0] ad_block_w = (ad_idx_q == 2'd0) ? ad_block0_i : ad_block1_i;
  wire [127:0] data_in_block_w = (data_in_idx_q == 2'd0) ? data_block0_i : data_block1_i;

  wire enc_active_w = (state_q == ST_RUN) && !decrypt_q;
  wire dec_active_w = (state_q == ST_RUN) &&  decrypt_q;

  wire enc_ad_valid_w = enc_active_w && (ad_idx_q < ad_blocks_q);
  wire dec_ad_valid_w = dec_active_w && (ad_idx_q < ad_blocks_q);

  wire enc_data_valid_w = enc_active_w && (data_in_idx_q < data_blocks_q);
  wire dec_data_valid_w = dec_active_w && (data_in_idx_q < data_blocks_q);

  wire enc_out_fire_w = enc_ct_valid_w;
  wire dec_out_fire_w = dec_pt_valid_w;

  wire enc_result_fire_w = enc_tag_valid_w;
  wire dec_result_fire_w = dec_auth_valid_w;

  function [1:0] blocks_for_bytes;
    input [31:0] bytes;
    begin
      if (bytes == 32'd0) begin
        blocks_for_bytes = 2'd0;
      end else if (bytes <= 32'd16) begin
        blocks_for_bytes = 2'd1;
      end else begin
        blocks_for_bytes = 2'd2;
      end
    end
  endfunction

  wire _unused_done = ^{enc_done_w, dec_done_w};
  wire _unused_bytes = ^{enc_ct_bytes_w, dec_pt_bytes_w};
  wire _unused_busy = ^{enc_busy_w, dec_busy_w};

  ascon_aead128_enc_ad #(
    .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
  ) u_enc (
    .clk                (clk),
    .rst_n              (rst_n),
    .start_i            (enc_start_q),
    .key_i              (key_i),
    .nonce_i            (nonce_i),
    .ad_bytes_i         (ad_bytes_i),
    .msg_bytes_i        (msg_bytes_i),
    .busy_o             (enc_busy_w),
    .done_o             (enc_done_w),
    .ad_ready_o         (enc_ad_ready_w),
    .ad_valid_i         (enc_ad_valid_w),
    .ad_block_i         (ad_block_w),
    .plaintext_ready_o  (enc_pt_ready_w),
    .plaintext_valid_i  (enc_data_valid_w),
    .plaintext_block_i  (data_in_block_w),
    .ciphertext_valid_o (enc_ct_valid_w),
    .ciphertext_ready_i (1'b1),
    .ciphertext_block_o (enc_ct_block_w),
    .ciphertext_bytes_o (enc_ct_bytes_w),
    .tag_valid_o        (enc_tag_valid_w),
    .tag_ready_i        (1'b1),
    .tag_o              (enc_tag_w)
  );

  ascon_aead128_dec_ad #(
    .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
  ) u_dec (
    .clk                (clk),
    .rst_n              (rst_n),
    .start_i            (dec_start_q),
    .key_i              (key_i),
    .nonce_i            (nonce_i),
    .ad_bytes_i         (ad_bytes_i),
    .msg_bytes_i        (msg_bytes_i),
    .tag_i              (tag_i),
    .busy_o             (dec_busy_w),
    .done_o             (dec_done_w),
    .ad_ready_o         (dec_ad_ready_w),
    .ad_valid_i         (dec_ad_valid_w),
    .ad_block_i         (ad_block_w),
    .ciphertext_ready_o (dec_ct_ready_w),
    .ciphertext_valid_i (dec_data_valid_w),
    .ciphertext_block_i (data_in_block_w),
    .plaintext_valid_o  (dec_pt_valid_w),
    .plaintext_ready_i  (1'b1),
    .plaintext_block_o  (dec_pt_block_w),
    .plaintext_bytes_o  (dec_pt_bytes_w),
    .auth_valid_o       (dec_auth_valid_w),
    .auth_ready_i       (1'b1),
    .auth_ok_o          (dec_auth_ok_w)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      decrypt_q <= 1'b0;
      ad_blocks_q <= 2'd0;
      data_blocks_q <= 2'd0;
      ad_idx_q <= 2'd0;
      data_in_idx_q <= 2'd0;
      data_out_idx_q <= 2'd0;
      result_seen_q <= 1'b0;
      enc_start_q <= 1'b0;
      dec_start_q <= 1'b0;
      busy_o <= 1'b0;
      done_o <= 1'b0;
      auth_ok_o <= 1'b0;
      result_tag_o <= 128'd0;
      out_block0_o <= 128'd0;
      out_block1_o <= 128'd0;
    end else begin
      enc_start_q <= 1'b0;
      dec_start_q <= 1'b0;
      done_o <= 1'b0;

      if (clear_i) begin
        state_q <= ST_IDLE;
        decrypt_q <= 1'b0;
        ad_blocks_q <= 2'd0;
        data_blocks_q <= 2'd0;
        ad_idx_q <= 2'd0;
        data_in_idx_q <= 2'd0;
        data_out_idx_q <= 2'd0;
        result_seen_q <= 1'b0;
        busy_o <= 1'b0;
        auth_ok_o <= 1'b0;
        result_tag_o <= 128'd0;
        out_block0_o <= 128'd0;
        out_block1_o <= 128'd0;
      end else begin
        case (state_q)
          ST_IDLE: begin
            busy_o <= 1'b0;
            if (start_i) begin
              state_q <= ST_RUN;
              busy_o <= 1'b1;
              decrypt_q <= decrypt_i;
              ad_blocks_q <= blocks_for_bytes(ad_bytes_i);
              data_blocks_q <= blocks_for_bytes(msg_bytes_i);
              ad_idx_q <= 2'd0;
              data_in_idx_q <= 2'd0;
              data_out_idx_q <= 2'd0;
              result_seen_q <= 1'b0;
              auth_ok_o <= 1'b0;
              result_tag_o <= 128'd0;
              out_block0_o <= 128'd0;
              out_block1_o <= 128'd0;
              enc_start_q <= !decrypt_i;
              dec_start_q <=  decrypt_i;
            end
          end

          ST_RUN: begin
            busy_o <= 1'b1;

            if (enc_ad_valid_w && enc_ad_ready_w) begin
              ad_idx_q <= ad_idx_q + 2'd1;
            end else if (dec_ad_valid_w && dec_ad_ready_w) begin
              ad_idx_q <= ad_idx_q + 2'd1;
            end

            if (enc_data_valid_w && enc_pt_ready_w) begin
              data_in_idx_q <= data_in_idx_q + 2'd1;
            end else if (dec_data_valid_w && dec_ct_ready_w) begin
              data_in_idx_q <= data_in_idx_q + 2'd1;
            end

            if (enc_out_fire_w) begin
              if (data_out_idx_q == 2'd0) begin
                out_block0_o <= enc_ct_block_w;
              end else begin
                out_block1_o <= enc_ct_block_w;
              end
              data_out_idx_q <= data_out_idx_q + 2'd1;
            end else if (dec_out_fire_w) begin
              if (data_out_idx_q == 2'd0) begin
                out_block0_o <= dec_pt_block_w;
              end else begin
                out_block1_o <= dec_pt_block_w;
              end
              data_out_idx_q <= data_out_idx_q + 2'd1;
            end

            if (enc_result_fire_w) begin
              result_tag_o <= enc_tag_w;
              auth_ok_o <= 1'b1;
              result_seen_q <= 1'b1;
            end else if (dec_result_fire_w) begin
              result_tag_o <= 128'd0;
              auth_ok_o <= dec_auth_ok_w;
              result_seen_q <= 1'b1;
            end

            if (result_seen_q && (data_out_idx_q >= data_blocks_q)) begin
              state_q <= ST_IDLE;
              busy_o <= 1'b0;
              done_o <= 1'b1;
            end
          end

          default: begin
            state_q <= ST_IDLE;
            busy_o <= 1'b0;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
