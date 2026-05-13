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
// ── ASCON-128 input/output packing ──────────────────────────────────────────
// The frontend presents data in 128-bit blocks (two 64-bit words each).
// ASCON-128 (rate=8) consumes one 64-bit word per step.  ad_phase_q and
// dat_phase_q track which half of the current 128-bit block is active:
//   phase=0 → upper 64 bits [127:64]  (bytes 0-7)
//   phase=1 → lower 64 bits [ 63: 0]  (bytes 8-15)
// The 128-bit block index (ad_idx_q / data_idx_q) advances only on phase 1→0.
//
// Similarly, ASCON-128 produces 8 bytes per step.  Two steps are packed into
// each 128-bit output register via half_block_q / out_phase_q.
//
// ASCON-128a (rate=16) consumes and produces 16 bytes per step; both halves of
// the 128-bit block are used simultaneously, so ad_phase_q / dat_phase_q / 
// out_phase_q always remain 0.
//
// ── Permutation state input ──────────────────────────────────────────────────
// perm_state_i_q is REGISTERED.  start_perm latches both perm_state_i_q and
// perm_start_q in the same clock edge (identical to ascon_aead128_enc_ad.v),
// eliminating all combinatorial timing hazards.
//
// Constants verified against ascon_aead128_enc_ad.v:
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

  localparam [63:0] ASCON_128A_IV = 64'h00001000808c0001;
  localparam [63:0] ASCON_128_IV  = 64'h80400c0600000000;
  localparam [63:0] ASCON_IV      = (ASCON_VARIANT == 0) ? ASCON_128_IV : ASCON_128A_IV;
  localparam [3:0]  PB            = (ASCON_VARIANT == 0) ? 4'd6 : 4'd8;
  localparam [63:0] ASCON_PAD0    = 64'h0000000000000001;
  localparam [63:0] ASCON_DSEP    = 64'h8000000000000000;

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

  reg [3:0]   state_q;
  reg         decrypt_q;
  reg [319:0] ascon_state_q;
  reg [127:0] key_q;
  reg [127:0] tag_q;

  // Block/tail counters — units are RATE bytes per block.
  reg [31:0]  ad_full_blocks_left_q;
  reg [4:0]   ad_final_bytes_q;
  reg         ad_present_q;

  reg [31:0]  msg_full_blocks_left_q;
  reg [4:0]   msg_final_bytes_q;

  // Input block index: selects between the two 128-bit input bus blocks (0 or 1).
  // Advances when both halves of the current block have been consumed (ASCON-128)
  // or every step (ASCON-128a).
  reg [1:0]   ad_idx_q;
  reg [1:0]   data_idx_q;

  // Phase within current 128-bit input block (ASCON-128 only).
  // 0 = upper 64 bits active, 1 = lower 64 bits active.
  reg         ad_phase_q;
  reg         dat_phase_q;

  // Output accumulator for ASCON-128.
  reg [63:0]  half_block_q;   // holds first 8-byte output word
  reg         out_phase_q;    // 0 = accumulating, 1 = second word ready
  reg [1:0]   out_idx_q;      // which 128-bit output register to write next

  reg         perm_start_q;
  reg [3:0]   perm_rounds_q;
  reg [319:0] perm_state_i_q;  // REGISTERED — latched by start_perm
  wire        perm_busy_w;
  wire        perm_done_w;
  wire [319:0] perm_state_o_w;

  assign busy_o = (state_q != ST_IDLE) || perm_busy_w;

  wire [63:0] k0_w = key_q[127:64];
  wire [63:0] k1_w = key_q[63:0];
  wire [63:0] s0_w = ascon_state_q[319:256];
  wire [63:0] s1_w = ascon_state_q[255:192];
  wire [63:0] s2_w = ascon_state_q[191:128];
  wire [63:0] s3_w = ascon_state_q[127:64];
  wire [63:0] s4_w = ascon_state_q[63:0];

  // ── Active AD word ────────────────────────────────────────────────────────
  // For ASCON-128a: always use both words of the selected block.
  // For ASCON-128:  select upper (phase=0) or lower (phase=1) 64-bit word.
  wire [127:0] ad_block_w = (ad_idx_q == 2'd0) ? ad_block0_i : ad_block1_i;
  // ad_word_w: the 8-byte chunk to absorb this step (ASCON-128)
  wire [63:0]  ad_word_w  = (ad_phase_q == 1'b0) ? ad_block_w[127:64] : ad_block_w[63:0];
  // For ASCON-128a partial block wires we still need both words:
  wire [63:0]  a0_w       = ad_block_w[127:64];
  wire [63:0]  a1_w       = ad_block_w[63:0];

  // ── Active data word ──────────────────────────────────────────────────────
  wire [127:0] data_block_w = (data_idx_q == 2'd0) ? data_block0_i : data_block1_i;
  // dat_word_w: the 8-byte chunk to process this step (ASCON-128)
  wire [63:0]  dat_word_w   = (dat_phase_q == 1'b0) ? data_block_w[127:64]
                                                     : data_block_w[63:0];
  // For ASCON-128a: both words used simultaneously
  wire [63:0]  d0_w = data_block_w[127:64];
  wire [63:0]  d1_w = data_block_w[63:0];

  // ── AD partial-block wires (ASCON-128a / ASCON-128 tails ≤ 7 bytes) ───────
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

  // ── ASCON-128 single-word AD partial tail ─────────────────────────────────
  // For ASCON-128, ad_final_bytes_q ≤ 7.  Use ad_word_w as the data source.
  wire [63:0] ad128_part_s0_w = s0_w ^ (ad_word_w & byte_mask64(ad_final_bytes_q))
                                      ^ pad64(ad_final_bytes_q);

  // ── MSG full-block output and new state ───────────────────────────────────
  // ASCON-128a:
  wire [63:0] full_x0_w     = s0_w ^ d0_w;
  wire [63:0] full_x1_w     = s1_w ^ d1_w;
  wire [63:0] full_state0_w = decrypt_q ? d0_w : full_x0_w;
  wire [63:0] full_state1_w = decrypt_q ? d1_w : full_x1_w;
  // ASCON-128 (single word):
  wire [63:0] full128_out_w   = s0_w ^ dat_word_w;       // plaintext or ciphertext
  wire [63:0] full128_state_w = decrypt_q ? dat_word_w : full128_out_w; // new x0

  // ── MSG partial-block wires (ASCON-128a) ───────────────────────────────────
  wire [4:0] msg_part0_bytes_w = (msg_final_bytes_q > 5'd8) ? 5'd8 : msg_final_bytes_q;
  wire [4:0] msg_part1_bytes_w = (msg_final_bytes_q > 5'd8) ? (msg_final_bytes_q - 5'd8) : 5'd0;
  wire [63:0] msg_part0_mask_w = byte_mask64(msg_part0_bytes_w);
  wire [63:0] msg_part1_mask_w = byte_mask64(msg_part1_bytes_w);
  wire [63:0] msg_part_d0_w    = d0_w & msg_part0_mask_w;
  wire [63:0] msg_part_d1_w    = d1_w & msg_part1_mask_w;
  wire [63:0] msg_part_out0_w  = (s0_w ^ msg_part_d0_w) & msg_part0_mask_w;
  wire [63:0] msg_part_out1_w  = (s1_w ^ msg_part_d1_w) & msg_part1_mask_w;
  wire [63:0] enc_part_s0_w = (msg_final_bytes_q < 5'd8) ?
                               (s0_w ^ msg_part_d0_w ^ pad64(msg_final_bytes_q)) :
                               (s0_w ^ msg_part_d0_w);
  wire [63:0] enc_part_s1_w = (msg_final_bytes_q < 5'd8) ?
                               s1_w :
                               ((msg_final_bytes_q == 5'd8) ?
                                (s1_w ^ ASCON_PAD0) :
                                (s1_w ^ msg_part_d1_w ^ pad64(msg_part1_bytes_w)));
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

  // ── ASCON-128 single-word MSG partial tail ────────────────────────────────
  // For ASCON-128, msg_final_bytes_q ≤ 7.
  wire [63:0] msg128_part_mask_w = byte_mask64(msg_final_bytes_q);
  wire [63:0] msg128_part_out_w  = (s0_w ^ dat_word_w) & msg128_part_mask_w;
  wire [63:0] enc128_part_s0_w   = s0_w ^ (dat_word_w & msg128_part_mask_w)
                                         ^ pad64(msg_final_bytes_q);
  wire [63:0] dec128_part_s0_w   = (s0_w & ~msg128_part_mask_w)
                                         ^ (dat_word_w & msg128_part_mask_w)
                                         ^ pad64(msg_final_bytes_q);
  wire [63:0] msg128_part_s0_w   = decrypt_q ? dec128_part_s0_w : enc128_part_s0_w;

  // ── Tag ───────────────────────────────────────────────────────────────────
  wire [127:0] calc_tag_w = {perm_state_o_w[127:64] ^ k0_w,
                              perm_state_o_w[63:0]   ^ k1_w};

  // ── Permutation ───────────────────────────────────────────────────────────
  ascon_perm_unrolled #(.ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)) u_perm (
    .clk(clk), .rst_n(rst_n),
    .start_i(perm_start_q), .rounds_i(perm_rounds_q),
    .state_i(perm_state_i_q),
    .busy_o(perm_busy_w), .done_o(perm_done_w), .state_o(perm_state_o_w)
  );

  function [63:0] byte_mask64; input [4:0] n;
    case(n) 5'd0:byte_mask64=0; 5'd1:byte_mask64=64'hff; 5'd2:byte_mask64=64'hffff;
    5'd3:byte_mask64=64'hffffff; 5'd4:byte_mask64=64'hffffffff;
    5'd5:byte_mask64=64'hffffffffff; 5'd6:byte_mask64=64'hffffffffffff;
    5'd7:byte_mask64=64'hffffffffffffff; default:byte_mask64=64'hffffffffffffffff; endcase
  endfunction

  function [63:0] pad64; input [4:0] n;
    case(n) 5'd0:pad64=64'h1; 5'd1:pad64=64'h100; 5'd2:pad64=64'h10000;
    5'd3:pad64=64'h1000000; 5'd4:pad64=64'h100000000; 5'd5:pad64=64'h10000000000;
    5'd6:pad64=64'h1000000000000; 5'd7:pad64=64'h100000000000000; default:pad64=0; endcase
  endfunction

  // start_perm: latch state and assert start simultaneously (matches enc_ad.v).
  task start_perm; input [3:0] rounds; input [319:0] state_in;
    begin
      perm_rounds_q  <= rounds;
      perm_state_i_q <= state_in;
      perm_start_q   <= 1'b1;
    end
  endtask

  task enter_message_phase; input [319:0] state_after_dsep;
    begin
      ascon_state_q <= state_after_dsep;
      if      (msg_full_blocks_left_q != 32'd0) state_q <= ST_MSG_WAIT_FULL;
      else if (msg_final_bytes_q      != 5'd0)  state_q <= ST_MSG_WAIT_PARTIAL;
      else                                       state_q <= ST_DRAIN;
    end
  endtask

  // Write a completed 128-bit word to the next output register.
  task write_out_word128; input [127:0] v;
    begin
      if (out_idx_q == 2'd0) out_block0_o <= v;
      else                   out_block1_o <= v;
      out_idx_q <= out_idx_q + 2'd1;
    end
  endtask

  // ── Reset / clear macro ───────────────────────────────────────────────────
  task do_reset;
    begin
      state_q <= ST_IDLE; decrypt_q <= 0; ascon_state_q <= 0;
      key_q <= 0; tag_q <= 0;
      ad_full_blocks_left_q <= 0; ad_final_bytes_q <= 0; ad_present_q <= 0;
      ad_idx_q <= 0; ad_phase_q <= 0;
      msg_full_blocks_left_q <= 0; msg_final_bytes_q <= 0;
      data_idx_q <= 0; dat_phase_q <= 0;
      half_block_q <= 0; out_phase_q <= 0; out_idx_q <= 0;
      perm_state_i_q <= 0;
      auth_ok_o <= 0; result_tag_o <= 0; out_block0_o <= 0; out_block1_o <= 0;
    end
  endtask

  // ── Clocked FSM ───────────────────────────────────────────────────────────
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      do_reset(); perm_start_q <= 0; perm_rounds_q <= 0; done_o <= 0;
    end else begin
      perm_start_q <= 0; done_o <= 0;

      if (clear_i) begin do_reset();
      end else case (state_q)

        // ── IDLE ─────────────────────────────────────────────────────────────
        ST_IDLE: if (start_i) begin
          decrypt_q <= decrypt_i; key_q <= key_i; tag_q <= tag_i;
          auth_ok_o <= 0; result_tag_o <= 0; out_block0_o <= 0; out_block1_o <= 0;
          ad_idx_q <= 0; ad_phase_q <= 0;
          data_idx_q <= 0; dat_phase_q <= 0;
          out_idx_q <= 0; half_block_q <= 0; out_phase_q <= 0;
          ad_present_q <= (ad_bytes_i != 0);
          // Block/tail counts depend on rate
          if (ASCON_VARIANT == 0) begin   // ASCON-128: rate=8B
            ad_full_blocks_left_q  <= {3'd0, ad_bytes_i[31:3]};
            ad_final_bytes_q       <= {2'b0, ad_bytes_i[2:0]};
            msg_full_blocks_left_q <= {3'd0, msg_bytes_i[31:3]};
            msg_final_bytes_q      <= {2'b0, msg_bytes_i[2:0]};
          end else begin                  // ASCON-128a: rate=16B
            ad_full_blocks_left_q  <= {4'd0, ad_bytes_i[31:4]};
            ad_final_bytes_q       <= {1'b0, ad_bytes_i[3:0]};
            msg_full_blocks_left_q <= {4'd0, msg_bytes_i[31:4]};
            msg_final_bytes_q      <= {1'b0, msg_bytes_i[3:0]};
          end
          ascon_state_q <= {ASCON_IV, key_i[127:64], key_i[63:0],
                                      nonce_i[127:64], nonce_i[63:0]};
          start_perm(4'd12, {ASCON_IV, key_i[127:64], key_i[63:0],
                                       nonce_i[127:64], nonce_i[63:0]});
          state_q <= ST_INIT_WAIT;
        end

        // ── INIT_WAIT ────────────────────────────────────────────────────────
        ST_INIT_WAIT: if (perm_done_w) begin
          ascon_state_q <= {perm_state_o_w[319:128],
                            perm_state_o_w[127:64] ^ k0_w,
                            perm_state_o_w[63:0]   ^ k1_w};
          if      (ad_full_blocks_left_q != 0) state_q <= ST_AD_WAIT_FULL;
          else if (ad_final_bytes_q      != 0) state_q <= ST_AD_WAIT_PARTIAL;
          else enter_message_phase({perm_state_o_w[319:128],
                                    perm_state_o_w[127:64] ^ k0_w,
                                    (perm_state_o_w[63:0] ^ k1_w) ^ ASCON_DSEP});
        end

        // ── AD_WAIT_FULL ─────────────────────────────────────────────────────
        ST_AD_WAIT_FULL: begin
          ad_full_blocks_left_q <= ad_full_blocks_left_q - 1;
          if (ASCON_VARIANT == 0) begin
            // ASCON-128: absorb one 8-byte word; advance phase and block index.
            if (ad_phase_q == 0) begin
              // Use upper 64 bits; stay on same 128-bit block next round
              ascon_state_q <= {s0_w ^ ad_word_w, s1_w, s2_w, s3_w, s4_w};
              start_perm(PB, {s0_w ^ ad_word_w, s1_w, s2_w, s3_w, s4_w});
              ad_phase_q <= 1;
              // ad_idx_q stays the same — next step uses lower 64 bits of same block
            end else begin
              // Use lower 64 bits; advance to next 128-bit block
              ascon_state_q <= {s0_w ^ ad_word_w, s1_w, s2_w, s3_w, s4_w};
              start_perm(PB, {s0_w ^ ad_word_w, s1_w, s2_w, s3_w, s4_w});
              ad_phase_q <= 0;
              ad_idx_q   <= ad_idx_q + 2'd1;
            end
          end else begin
            // ASCON-128a: absorb 16 bytes; always advance block index
            ascon_state_q <= {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w});
            ad_idx_q <= ad_idx_q + 2'd1;
          end
          state_q <= ST_AD_FULL_WAIT;
        end

        // ── AD_FULL_WAIT ──────────────────────────────────────────────────────
        ST_AD_FULL_WAIT: if (perm_done_w) begin
          ascon_state_q <= perm_state_o_w;
          if      (ad_full_blocks_left_q != 0) state_q <= ST_AD_WAIT_FULL;
          else if (ad_final_bytes_q      != 0) state_q <= ST_AD_WAIT_PARTIAL;
          else if (ad_present_q) begin
            // All-full AD: empty padding block
            ascon_state_q <= {perm_state_o_w[319:256] ^ ASCON_PAD0,
                              perm_state_o_w[255:0]};
            start_perm(PB, {perm_state_o_w[319:256] ^ ASCON_PAD0,
                            perm_state_o_w[255:0]});
            state_q <= ST_AD_EMPTY_WAIT;
          end else
            enter_message_phase({perm_state_o_w[319:64],
                                 perm_state_o_w[63:0] ^ ASCON_DSEP});
        end

        // ── AD_WAIT_PARTIAL ───────────────────────────────────────────────────
        ST_AD_WAIT_PARTIAL: begin
          if (ASCON_VARIANT == 0) begin
            // ASCON-128 tail: 0-7 bytes from ad_word_w
            ascon_state_q <= {ad128_part_s0_w, s1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {ad128_part_s0_w, s1_w, s2_w, s3_w, s4_w});
          end else begin
            ascon_state_q <= {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w});
          end
          state_q <= ST_AD_PARTIAL_WAIT;
        end

        // ── AD_PARTIAL_WAIT ───────────────────────────────────────────────────
        ST_AD_PARTIAL_WAIT: if (perm_done_w) begin
          enter_message_phase({perm_state_o_w[319:64],
                               perm_state_o_w[63:0] ^ ASCON_DSEP});
        end

        // ── AD_EMPTY_WAIT ─────────────────────────────────────────────────────
        ST_AD_EMPTY_WAIT: if (perm_done_w) begin
          enter_message_phase({perm_state_o_w[319:64],
                               perm_state_o_w[63:0] ^ ASCON_DSEP});
        end

        // ── MSG_WAIT_FULL ─────────────────────────────────────────────────────
        ST_MSG_WAIT_FULL: begin
          msg_full_blocks_left_q <= msg_full_blocks_left_q - 1;
          if (ASCON_VARIANT == 1) begin
            // ASCON-128a: 16 bytes in, 16 bytes out, one step
            write_out_word128({full_x0_w, full_x1_w});
            ascon_state_q <= {full_state0_w, full_state1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {full_state0_w, full_state1_w, s2_w, s3_w, s4_w});
            data_idx_q <= data_idx_q + 2'd1;
          end else begin
            // ASCON-128: 8 bytes in, 8 bytes out, pair into 128-bit output
            ascon_state_q <= {full128_state_w, s1_w, s2_w, s3_w, s4_w};
            start_perm(PB, {full128_state_w, s1_w, s2_w, s3_w, s4_w});
            // Advance phase and data index
            if (dat_phase_q == 0) begin
              dat_phase_q  <= 1;
              // Stay on same 128-bit data block; data_idx_q unchanged
            end else begin
              dat_phase_q  <= 0;
              data_idx_q   <= data_idx_q + 2'd1;
            end
            // Accumulate output
            if (out_phase_q == 0) begin
              half_block_q <= full128_out_w;
              out_phase_q  <= 1;
            end else begin
              write_out_word128({half_block_q, full128_out_w});
              out_phase_q  <= 0;
            end
          end
          state_q <= ST_MSG_FULL_WAIT;
        end

        // ── MSG_FULL_WAIT ─────────────────────────────────────────────────────
        ST_MSG_FULL_WAIT: if (perm_done_w) begin
          ascon_state_q <= perm_state_o_w;
          if      (msg_full_blocks_left_q != 0) state_q <= ST_MSG_WAIT_FULL;
          else if (msg_final_bytes_q      != 0) state_q <= ST_MSG_WAIT_PARTIAL;
          else                                   state_q <= ST_DRAIN;
        end

        // ── MSG_WAIT_PARTIAL ──────────────────────────────────────────────────
        ST_MSG_WAIT_PARTIAL: begin
          if (ASCON_VARIANT == 1) begin
            write_out_word128({msg_part_out0_w, msg_part_out1_w});
            ascon_state_q <= {msg_part_s0_w, msg_part_s1_w, s2_w, s3_w, s4_w};
          end else begin
            // ASCON-128 tail: 0-7 bytes from dat_word_w
            if (out_phase_q == 0)
              write_out_word128({msg128_part_out_w, 64'd0});
            else begin
              write_out_word128({half_block_q, msg128_part_out_w});
              out_phase_q <= 0;
            end
            ascon_state_q <= {msg128_part_s0_w, s1_w, s2_w, s3_w, s4_w};
          end
          data_idx_q <= data_idx_q + 2'd1;
          state_q    <= ST_DRAIN;
        end

        // ── DRAIN ─────────────────────────────────────────────────────────────
        ST_DRAIN: begin
          if (msg_final_bytes_q == 5'd0) begin
            ascon_state_q <= {s0_w ^ ASCON_PAD0, s1_w,
                              s2_w ^ k0_w, s3_w ^ k1_w, s4_w};
            start_perm(4'd12, {s0_w ^ ASCON_PAD0, s1_w,
                               s2_w ^ k0_w, s3_w ^ k1_w, s4_w});
          end else begin
            ascon_state_q <= {s0_w, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w};
            start_perm(4'd12, {s0_w, s1_w, s2_w ^ k0_w, s3_w ^ k1_w, s4_w});
          end
          state_q <= ST_FINAL_WAIT;
        end

        // ── FINAL_WAIT ────────────────────────────────────────────────────────
        ST_FINAL_WAIT: if (perm_done_w) begin
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

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule
`default_nettype wire
