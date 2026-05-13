`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0
//
// ascon_tt_aead_shared.v — shared-datapath ASCON AEAD core.
//
// ASCON_VARIANT = 0  →  ASCON-128  (IV=0x80400c0600000000, rate=8B,  PB=6)
// ASCON_VARIANT = 1  →  ASCON-128a (IV=0x00001000808c0001, rate=16B, PB=8)
//
// ROUNDS_PER_CYCLE: 1 = min-area, 8 = max-perf.
//
// perm_state_i_q is REGISTERED (like ascon_aead128_enc_ad.v / dec_ad.v).
// The start_perm task latches both perm_start_q and perm_state_i_q in the same
// clock edge, so the permutation always sees the correct state_i. This avoids
// the timing hazards that arise from combinatorial state_i muxes.
//
// Constants (all verified against ascon_aead128_enc_ad.v):
//   ASCON_128A_IV = 64'h00001000808c0001
//   ASCON_128_IV  = 64'h80400c0600000000
//   ASCON_PAD0    = 64'h0000000000000001
//   ASCON_DSEP    = 64'h8000000000000000

module ascon_tt_aead_shared #(
  parameter integer ROUNDS_PER_CYCLE = 1,
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
  output reg          done_o,
  output reg          auth_ok_o,
  output reg  [127:0] result_tag_o,
  output reg  [127:0] out_block0_o,
  output reg  [127:0] out_block1_o
);

  // ── Variant constants ─────────────────────────────────────────────────────
  localparam [63:0] ASCON_128A_IV = 64'h00001000808c0001;
  localparam [63:0] ASCON_128_IV  = 64'h80400c0600000000;
  localparam [63:0] ASCON_IV      = (ASCON_VARIANT == 0) ? ASCON_128_IV : ASCON_128A_IV;
  localparam [3:0]  PB            = (ASCON_VARIANT == 0) ? 4'd6 : 4'd8;

  localparam [63:0] ASCON_PAD0    = 64'h0000000000000001;
  localparam [63:0] ASCON_DSEP    = 64'h8000000000000000;

  // ── FSM states ────────────────────────────────────────────────────────────
  localparam [3:0] ST_IDLE             = 4'd0;
  localparam [3:0] ST_INIT_WAIT        = 4'd1;
  localparam [3:0] ST_AD_WAIT_FULL     = 4'd2;
  localparam [3:0] ST_AD_FULL_WAIT     = 4'd3;
  localparam [3:0] ST_AD_WAIT_PARTIAL  = 4'd4;
  localparam [3:0] ST_AD_PARTIAL_WAIT  = 4'd5;
  localparam [3:0] ST_AD_EMPTY_WAIT    = 4'd6;
  localparam [3:0] ST_MSG_WAIT_FULL    = 4'd7;
  localparam [3:0] ST_MSG_FULL_WAIT    = 4'd8;
  localparam [3:0] ST_MSG_WAIT_PARTIAL = 4'd9;
  localparam [3:0] ST_DRAIN            = 4'd10;
  localparam [3:0] ST_FINAL_WAIT       = 4'd11;

  // ── Registers ─────────────────────────────────────────────────────────────
  reg [3:0]   state_q;
  reg         decrypt_q;
  reg [319:0] ascon_state_q;
  reg [127:0] key_q;
  reg [127:0] tag_q;

  reg [31:0]  ad_full_blocks_left_q;
  reg [4:0]   ad_final_bytes_q;
  reg         ad_present_q;
  reg [1:0]   ad_idx_q;

  reg [31:0]  msg_full_blocks_left_q;
  reg [4:0]   msg_final_bytes_q;
  reg [1:0]   data_idx_q;
  reg [1:0]   out_idx_q;

  reg         perm_start_q;
  reg [3:0]   perm_rounds_q;
  reg [319:0] perm_state_i_q;  // REGISTERED — latched by start_perm, same edge as start_q
  wire        perm_busy_w;
  wire        perm_done_w;
  wire [319:0] perm_state_o_w;

  assign busy_o = (state_q != ST_IDLE) || perm_busy_w;

  // ── State-word convenience wires ──────────────────────────────────────────
  wire [63:0] k0_w = key_q[127:64];
  wire [63:0] k1_w = key_q[63:0];

  wire [63:0] s0_w = ascon_state_q[319:256];
  wire [63:0] s1_w = ascon_state_q[255:192];
  wire [63:0] s2_w = ascon_state_q[191:128];
  wire [63:0] s3_w = ascon_state_q[127:64];
  wire [63:0] s4_w = ascon_state_q[63:0];

  // ── Input block mux ───────────────────────────────────────────────────────
  wire [127:0] ad_block_w   = (ad_idx_q   == 2'd0) ? ad_block0_i   : ad_block1_i;
  wire [127:0] data_block_w = (data_idx_q == 2'd0) ? data_block0_i : data_block1_i;

  wire [63:0] a0_w = ad_block_w[127:64];
  wire [63:0] a1_w = ad_block_w[63:0];
  wire [63:0] d0_w = data_block_w[127:64];
  wire [63:0] d1_w = data_block_w[63:0];

  // ── AD partial-block combinatorial (identical to enc_ad.v) ────────────────
  wire [4:0] ad_part0_bytes_w = (ad_final_bytes_q > 5'd8) ? 5'd8 : ad_final_bytes_q;
  wire [4:0] ad_part1_bytes_w = (ad_final_bytes_q > 5'd8) ? (ad_final_bytes_q - 5'd8) : 5'd0;
  wire [63:0] ad_part0_mask_w = byte_mask64(ad_part0_bytes_w);
  wire [63:0] ad_part1_mask_w = byte_mask64(ad_part1_bytes_w);
  wire [63:0] ad_part_a0_w    = a0_w & ad_part0_mask_w;
  wire [63:0] ad_part_a1_w    = a1_w & ad_part1_mask_w;
  wire [63:0] ad_part_s0_w = (ad_final_bytes_q < 5'd8) ?
                              (s0_w ^ ad_part_a0_w ^ pad64(ad_final_bytes_q)) :
                              (s0_w ^ ad_part_a0_w);
  wire [63:0] ad_part_s1_w = (ad_final_bytes_q < 5'd8) ?
                              s1_w :
                              ((ad_final_bytes_q == 5'd8) ?
                               (s1_w ^ ASCON_PAD0) :
                               (s1_w ^ ad_part_a1_w ^ pad64(ad_part1_bytes_w)));

  // ── MSG full-block combinatorial ──────────────────────────────────────────
  wire [63:0] full_x0_w = s0_w ^ d0_w;
  wire [63:0] full_x1_w = s1_w ^ d1_w;
  // For ASCON-128: x1 is NOT in the rate; state x1 stays as-is.
  // For ASCON-128a: x1 IS in the rate; state x1 = ciphertext word (decrypt) or x1^pt (encrypt).
  wire [63:0] full_state0_w = decrypt_q ? d0_w : full_x0_w;
  wire [63:0] full_state1_w = (ASCON_VARIANT == 0) ? s1_w :
                              (decrypt_q ? d1_w : full_x1_w);

  // ── MSG partial-block combinatorial (identical to enc_ad.v / dec_ad.v) ────
  wire [4:0] msg_part0_bytes_w = (msg_final_bytes_q > 5'd8) ? 5'd8 : msg_final_bytes_q;
  wire [4:0] msg_part1_bytes_w = (msg_final_bytes_q > 5'd8) ? (msg_final_bytes_q - 5'd8) : 5'd0;
  wire [63:0] msg_part0_mask_w = byte_mask64(msg_part0_bytes_w);
  wire [63:0] msg_part1_mask_w = byte_mask64(msg_part1_bytes_w);
  wire [63:0] msg_part_d0_w    = d0_w & msg_part0_mask_w;
  wire [63:0] msg_part_d1_w    = d1_w & msg_part1_mask_w;

  wire [63:0] msg_part_out0_w = (s0_w ^ msg_part_d0_w) & msg_part0_mask_w;
  wire [63:0] msg_part_out1_w = (s1_w ^ msg_part_d1_w) & msg_part1_mask_w;

  // Encrypt partial state (from enc_ad.v)
  wire [63:0] enc_part_s0_w = (msg_final_bytes_q < 5'd8) ?
                               (s0_w ^ msg_part_d0_w ^ pad64(msg_final_bytes_q)) :
                               (s0_w ^ msg_part_d0_w);
  wire [63:0] enc_part_s1_w = (msg_final_bytes_q < 5'd8) ?
                               s1_w :
                               ((msg_final_bytes_q == 5'd8) ?
                                (s1_w ^ ASCON_PAD0) :
                                (s1_w ^ msg_part_d1_w ^ pad64(msg_part1_bytes_w)));

  // Decrypt partial state (from dec_ad.v)
  wire [63:0] dec_part_s0_w = (msg_final_bytes_q < 5'd8) ?
                               ((s0_w & ~msg_part0_mask_w) ^ msg_part_d0_w ^ pad64(msg_final_bytes_q)) :
                               msg_part_d0_w;
  wire [63:0] dec_part_s1_w = (msg_final_bytes_q < 5'd8) ?
                               s1_w :
                               ((msg_final_bytes_q == 5'd8) ?
                                (s1_w ^ ASCON_PAD0) :
                                ((s1_w & ~msg_part1_mask_w) ^ msg_part_d1_w ^ pad64(msg_part1_bytes_w)));

  wire [63:0] msg_part_s0_w = decrypt_q ? dec_part_s0_w : enc_part_s0_w;
  wire [63:0] msg_part_s1_w = decrypt_q ? dec_part_s1_w : enc_part_s1_w;

  // ── Tag ───────────────────────────────────────────────────────────────────
  wire [127:0] calc_tag_w = {perm_state_o_w[127:64] ^ k0_w,
                              perm_state_o_w[63:0]   ^ k1_w};

  // ── Permutation ───────────────────────────────────────────────────────────
  ascon_perm_unrolled #(
    .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
  ) u_perm (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (perm_start_q),
    .rounds_i (perm_rounds_q),
    .state_i  (perm_state_i_q),    // REGISTERED input
    .busy_o   (perm_busy_w),
    .done_o   (perm_done_w),
    .state_o  (perm_state_o_w)
  );

  // ── Helper functions ──────────────────────────────────────────────────────
  function [63:0] byte_mask64;
    input [4:0] n;
    begin
      case (n)
        5'd0:    byte_mask64 = 64'h0000000000000000;
        5'd1:    byte_mask64 = 64'h00000000000000ff;
        5'd2:    byte_mask64 = 64'h000000000000ffff;
        5'd3:    byte_mask64 = 64'h0000000000ffffff;
        5'd4:    byte_mask64 = 64'h00000000ffffffff;
        5'd5:    byte_mask64 = 64'h000000ffffffffff;
        5'd6:    byte_mask64 = 64'h0000ffffffffffff;
        5'd7:    byte_mask64 = 64'h00ffffffffffffff;
        default: byte_mask64 = 64'hffffffffffffffff;
      endcase
    end
  endfunction

  function [63:0] pad64;
    input [4:0] byte_index;
    begin
      case (byte_index)
        5'd0:    pad64 = 64'h0000000000000001;
        5'd1:    pad64 = 64'h0000000000000100;
        5'd2:    pad64 = 64'h0000000000010000;
        5'd3:    pad64 = 64'h0000000001000000;
        5'd4:    pad64 = 64'h0000000100000000;
        5'd5:    pad64 = 64'h0000010000000000;
        5'd6:    pad64 = 64'h0001000000000000;
        5'd7:    pad64 = 64'h0100000000000000;
        default: pad64 = 64'h0000000000000000;
      endcase
    end
  endfunction

  // ── Tasks ─────────────────────────────────────────────────────────────────
  // start_perm: latch state and assert start in the same clock edge.
  // The permutation sees start_i=1 and correct state_i simultaneously
  // at the NEXT clock edge — identical to enc_ad.v / dec_ad.v.
  task start_perm;
    input [3:0]   rounds;
    input [319:0] state_in;
    begin
      perm_rounds_q  <= rounds;
      perm_state_i_q <= state_in;
      perm_start_q   <= 1'b1;
    end
  endtask

  task enter_message_phase;
    input [319:0] state_after_dsep;
    begin
      ascon_state_q <= state_after_dsep;
      if (msg_full_blocks_left_q != 32'd0)
        state_q <= ST_MSG_WAIT_FULL;
      else if (msg_final_bytes_q != 5'd0)
        state_q <= ST_MSG_WAIT_PARTIAL;
      else
        state_q <= ST_DRAIN;
    end
  endtask

  task write_out_block;
    input [127:0] block_value;
    begin
      if (out_idx_q == 2'd0) out_block0_o <= block_value;
      else                   out_block1_o <= block_value;
      out_idx_q <= out_idx_q + 2'd1;
    end
  endtask

  // ── Clocked FSM ───────────────────────────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q                <= ST_IDLE;
      decrypt_q              <= 1'b0;
      ascon_state_q          <= 320'd0;
      key_q                  <= 128'd0;
      tag_q                  <= 128'd0;
      ad_full_blocks_left_q  <= 32'd0;
      ad_final_bytes_q       <= 5'd0;
      ad_present_q           <= 1'b0;
      ad_idx_q               <= 2'd0;
      msg_full_blocks_left_q <= 32'd0;
      msg_final_bytes_q      <= 5'd0;
      data_idx_q             <= 2'd0;
      out_idx_q              <= 2'd0;
      perm_start_q           <= 1'b0;
      perm_rounds_q          <= 4'd0;
      perm_state_i_q         <= 320'd0;
      done_o                 <= 1'b0;
      auth_ok_o              <= 1'b0;
      result_tag_o           <= 128'd0;
      out_block0_o           <= 128'd0;
      out_block1_o           <= 128'd0;
    end else begin
      perm_start_q <= 1'b0;
      done_o       <= 1'b0;

      if (clear_i) begin
        state_q                <= ST_IDLE;
        decrypt_q              <= 1'b0;
        ascon_state_q          <= 320'd0;
        key_q                  <= 128'd0;
        tag_q                  <= 128'd0;
        ad_full_blocks_left_q  <= 32'd0;
        ad_final_bytes_q       <= 5'd0;
        ad_present_q           <= 1'b0;
        ad_idx_q               <= 2'd0;
        msg_full_blocks_left_q <= 32'd0;
        msg_final_bytes_q      <= 5'd0;
        data_idx_q             <= 2'd0;
        out_idx_q              <= 2'd0;
        perm_state_i_q         <= 320'd0;
        auth_ok_o              <= 1'b0;
        result_tag_o           <= 128'd0;
        out_block0_o           <= 128'd0;
        out_block1_o           <= 128'd0;
      end else begin
        case (state_q)

          // ── IDLE ──────────────────────────────────────────────────────────
          ST_IDLE: begin
            if (start_i) begin
              decrypt_q <= decrypt_i;
              key_q     <= key_i;
              tag_q     <= tag_i;
              auth_ok_o    <= 1'b0;
              result_tag_o <= 128'd0;
              out_block0_o <= 128'd0;
              out_block1_o <= 128'd0;
              ad_idx_q     <= 2'd0;
              data_idx_q   <= 2'd0;
              out_idx_q    <= 2'd0;
              ad_present_q <= (ad_bytes_i != 32'd0);

              // Block / tail counts depend on rate
              // ASCON-128  (rate=8B):  blocks = bytes>>3, tail = bytes[2:0]
              // ASCON-128a (rate=16B): blocks = bytes>>4, tail = bytes[3:0]
              if (ASCON_VARIANT == 0) begin
                ad_full_blocks_left_q  <= {3'd0, ad_bytes_i[31:3]};
                ad_final_bytes_q       <= {2'b0, ad_bytes_i[2:0]};
                msg_full_blocks_left_q <= {3'd0, msg_bytes_i[31:3]};
                msg_final_bytes_q      <= {2'b0, msg_bytes_i[2:0]};
              end else begin
                ad_full_blocks_left_q  <= {4'd0, ad_bytes_i[31:4]};
                ad_final_bytes_q       <= {1'b0, ad_bytes_i[3:0]};
                msg_full_blocks_left_q <= {4'd0, msg_bytes_i[31:4]};
                msg_final_bytes_q      <= {1'b0, msg_bytes_i[3:0]};
              end

              ascon_state_q <= {ASCON_IV,
                                key_i[127:64], key_i[63:0],
                                nonce_i[127:64], nonce_i[63:0]};
              start_perm(4'd12, {ASCON_IV,
                                 key_i[127:64], key_i[63:0],
                                 nonce_i[127:64], nonce_i[63:0]});
              state_q <= ST_INIT_WAIT;
            end
          end

          // ── INIT_WAIT: PA=12 done; XOR key into x3,x4 ────────────────────
          ST_INIT_WAIT: begin
            if (perm_done_w) begin
              ascon_state_q <= {perm_state_o_w[319:128],
                                perm_state_o_w[127:64] ^ k0_w,
                                perm_state_o_w[63:0]   ^ k1_w};
              if (ad_full_blocks_left_q != 32'd0) begin
                state_q <= ST_AD_WAIT_FULL;
              end else if (ad_final_bytes_q != 5'd0) begin
                state_q <= ST_AD_WAIT_PARTIAL;
              end else begin
                enter_message_phase({perm_state_o_w[319:128],
                                     perm_state_o_w[127:64] ^ k0_w,
                                     (perm_state_o_w[63:0] ^ k1_w) ^ ASCON_DSEP});
              end
            end
          end

          // ── AD_WAIT_FULL: absorb one full AD block, start PB perm ─────────
          ST_AD_WAIT_FULL: begin
            ad_full_blocks_left_q <= ad_full_blocks_left_q - 32'd1;
            ad_idx_q              <= ad_idx_q + 2'd1;
            if (ASCON_VARIANT == 0) begin
              ascon_state_q <= {s0_w ^ a0_w, s1_w, s2_w, s3_w, s4_w};
              start_perm(PB, {s0_w ^ a0_w, s1_w, s2_w, s3_w, s4_w});
            end else begin
              ascon_state_q <= {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w};
              start_perm(PB, {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w});
            end
            state_q <= ST_AD_FULL_WAIT;
          end

          // ── AD_FULL_WAIT: PB done for a full AD block ─────────────────────
          ST_AD_FULL_WAIT: begin
            if (perm_done_w) begin
              ascon_state_q <= perm_state_o_w;
              if (ad_full_blocks_left_q != 32'd0) begin
                state_q <= ST_AD_WAIT_FULL;
              end else if (ad_final_bytes_q != 5'd0) begin
                state_q <= ST_AD_WAIT_PARTIAL;
              end else if (ad_present_q) begin
                // All AD was exactly full blocks: absorb empty tail (PAD0 into x0)
                ascon_state_q <= {perm_state_o_w[319:256] ^ ASCON_PAD0,
                                  perm_state_o_w[255:0]};
                start_perm(PB, {perm_state_o_w[319:256] ^ ASCON_PAD0,
                                perm_state_o_w[255:0]});
                state_q <= ST_AD_EMPTY_WAIT;
              end else begin
                enter_message_phase({perm_state_o_w[319:64],
                                     perm_state_o_w[63:0] ^ ASCON_DSEP});
              end
            end
          end

          // ── AD_WAIT_PARTIAL: absorb partial AD tail, start PB perm ────────
          ST_AD_WAIT_PARTIAL: begin
            ad_idx_q      <= ad_idx_q + 2'd1;
            ascon_state_q <= {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w});
            state_q <= ST_AD_PARTIAL_WAIT;
          end

          // ── AD_PARTIAL_WAIT: PB done; apply DSEP → message phase ──────────
          ST_AD_PARTIAL_WAIT: begin
            if (perm_done_w) begin
              enter_message_phase({perm_state_o_w[319:64],
                                   perm_state_o_w[63:0] ^ ASCON_DSEP});
            end
          end

          // ── AD_EMPTY_WAIT: PB done for empty-tail pad; DSEP → msg ─────────
          ST_AD_EMPTY_WAIT: begin
            if (perm_done_w) begin
              enter_message_phase({perm_state_o_w[319:64],
                                   perm_state_o_w[63:0] ^ ASCON_DSEP});
            end
          end

          // ── MSG_WAIT_FULL: process one full message block ──────────────────
          ST_MSG_WAIT_FULL: begin
            // Output: XOR state with input (gives plaintext for dec, ciphertext for enc)
            if (ASCON_VARIANT == 0)
              write_out_block({full_x0_w, 64'd0});
            else
              write_out_block({full_x0_w, full_x1_w});

            ascon_state_q          <= {full_state0_w, full_state1_w, s2_w, s3_w, s4_w};
            msg_full_blocks_left_q <= msg_full_blocks_left_q - 32'd1;
            data_idx_q             <= data_idx_q + 2'd1;
            start_perm(PB, {full_state0_w, full_state1_w, s2_w, s3_w, s4_w});
            state_q <= ST_MSG_FULL_WAIT;
          end

          // ── MSG_FULL_WAIT: PB done for a full message block ───────────────
          ST_MSG_FULL_WAIT: begin
            if (perm_done_w) begin
              ascon_state_q <= perm_state_o_w;
              if (msg_full_blocks_left_q != 32'd0)
                state_q <= ST_MSG_WAIT_FULL;
              else if (msg_final_bytes_q != 5'd0)
                state_q <= ST_MSG_WAIT_PARTIAL;
              else
                state_q <= ST_DRAIN;
            end
          end

          // ── MSG_WAIT_PARTIAL: process partial tail; no perm after ─────────
          ST_MSG_WAIT_PARTIAL: begin
            write_out_block({msg_part_out0_w, msg_part_out1_w});
            ascon_state_q <= {msg_part_s0_w, msg_part_s1_w, s2_w, s3_w, s4_w};
            data_idx_q    <= data_idx_q + 2'd1;
            state_q       <= ST_DRAIN;
          end

          // ── DRAIN: finalization — add pad (if empty tail), XOR key, PA=12 ─
          ST_DRAIN: begin
            if (msg_final_bytes_q == 5'd0) begin
              ascon_state_q <= {s0_w ^ ASCON_PAD0, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w};
              start_perm(4'd12, {s0_w ^ ASCON_PAD0, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w});
            end else begin
              ascon_state_q <= {s0_w, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w};
              start_perm(4'd12, {s0_w, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w});
            end
            state_q <= ST_FINAL_WAIT;
          end

          // ── FINAL_WAIT: PA=12 done; emit tag or check auth ────────────────
          ST_FINAL_WAIT: begin
            if (perm_done_w) begin
              if (decrypt_q) begin
                auth_ok_o    <= (calc_tag_w == tag_q);
                result_tag_o <= 128'd0;
              end else begin
                auth_ok_o    <= 1'b1;
                result_tag_o <= calc_tag_w;
              end
              done_o  <= 1'b1;
              state_q <= ST_IDLE;
            end
          end

          default: state_q <= ST_IDLE;

        endcase
      end
    end
  end

endmodule
`default_nettype wire
