`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0
//
// TT-14B  Shared-datapath Ascon-AEAD128 core.
//
// This is the minimum-area replacement for ascon_tt_aead_bridge.
// It uses a SINGLE ascon_perm_unrolled instance and a SINGLE 320-bit
// state register for both encryption and decryption, reducing the
// cell count by ~40-50% relative to the dual-core bridge.
//
// Interface is intentionally identical to ascon_tt_aead_bridge so the
// serial frontend needs no changes.  The production top should select this
// module with a parameter:
//
//   ascon_tt_serial_frontend #(
//     .USE_SHARED_AEAD(1),
//     ...
//   )
//
// Algorithm reference: Ascon-AEAD128 (= Ascon-128a, rate=128)
//   IV  = 0x00001000808c0001
//   pa  = p12  (initialization and finalization)
//   pb  = p8   (AD and message absorption)
//
// Internal state word packing (matches ascon_round_comb.v):
//   state[319:256] = S0
//   state[255:192] = S1
//   state[191:128] = S2
//   state[127:64]  = S3
//   state[63:0]    = S4
//
// Block packing convention (matches enc_ad / dec_ad cores):
//   block[127:64] = word0  (= LOADBYTES(ptr, 8))
//   block[63:0]   = word1  (= LOADBYTES(ptr+8, 8))

module ascon_tt_aead_shared #(
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
  input  wire [127:0] tag_i,         // used only when decrypt_i=1

  // Caller keeps up to two 128-bit AD blocks and two data blocks in registers.
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

  // -----------------------------------------------------------------------
  // Constants
  // -----------------------------------------------------------------------
  localparam [63:0] IV    = 64'h00001000808c0001;
  localparam [63:0] PAD0  = 64'h0000000000000001;
  localparam [63:0] DSEP  = 64'h8000000000000000;

  // -----------------------------------------------------------------------
  // FSM states
  // -----------------------------------------------------------------------
  localparam [3:0]
    ST_IDLE         = 4'd0,
    ST_INIT_WAIT    = 4'd1,   // waiting for p12 after init
    ST_AD_XOR       = 4'd2,   // XOR AD block into state, then start p8
    ST_AD_WAIT      = 4'd3,   // waiting for p8 after AD block
    ST_AD_PAD_WAIT  = 4'd4,   // waiting for p8 after final-empty AD pad
    ST_MSG_XOR      = 4'd5,   // XOR message block, emit output, start p8
    ST_MSG_WAIT     = 4'd6,   // waiting for p8 after message block
    ST_FINAL_WAIT   = 4'd7,   // waiting for p12 during finalization
    ST_DONE         = 4'd8;

  // -----------------------------------------------------------------------
  // Registers
  // -----------------------------------------------------------------------
  reg [3:0]   state_q;
  reg [319:0] s_q;            // live Ascon 320-bit state
  reg [127:0] key_q;          // latched key (needed for finalization)
  reg         decrypt_q;

  reg [31:0]  ad_blocks_left_q;   // full 16-byte AD blocks remaining
  reg [4:0]   ad_tail_bytes_q;    // 0..15 bytes in final partial AD block
  reg         ad_present_q;       // ad_bytes_i != 0 on start

  reg [31:0]  msg_blocks_left_q;  // full 16-byte message blocks remaining
  reg [4:0]   msg_tail_bytes_q;   // 0..15 bytes in final partial message block
  reg [1:0]   ad_blk_idx_q;       // which AD input block are we on (0 or 1)
  reg [1:0]   msg_blk_idx_q;      // which message input block are we on
  reg [1:0]   out_blk_idx_q;      // which output block to write next

  reg         ad_had_tail_q;      // 1 = last AD block absorbed was a partial tail

  // Permutation control
  reg         perm_start_q;
  reg [3:0]   perm_rounds_q;
  reg [319:0] perm_in_q;
  wire        perm_busy_w;
  wire        perm_done_w;
  wire [319:0] perm_out_w;

  // -----------------------------------------------------------------------
  // Permutation instance — ONE instance shared across entire algorithm
  // -----------------------------------------------------------------------
  ascon_perm_unrolled #(
    .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
  ) u_perm (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (perm_start_q),
    .rounds_i(perm_rounds_q),
    .state_i (perm_in_q),
    .busy_o  (perm_busy_w),
    .done_o  (perm_done_w),
    .state_o (perm_out_w)
  );

  // -----------------------------------------------------------------------
  // Convenience wires on live state
  // -----------------------------------------------------------------------
  wire [63:0] s0_w = s_q[319:256];
  wire [63:0] s1_w = s_q[255:192];
  wire [63:0] s2_w = s_q[191:128];
  wire [63:0] s3_w = s_q[127:64];
  wire [63:0] s4_w = s_q[63:0];

  wire [63:0] k0_w = key_q[127:64];
  wire [63:0] k1_w = key_q[63:0];

  // Current AD block (mux over the two input registers)
  wire [127:0] ad_block_w = (ad_blk_idx_q == 2'd0) ? ad_block0_i : ad_block1_i;
  wire [63:0]  ab0_w      = ad_block_w[127:64];
  wire [63:0]  ab1_w      = ad_block_w[63:0];

  // Current message block
  wire [127:0] msg_block_w = (msg_blk_idx_q == 2'd0) ? data_block0_i : data_block1_i;
  wire [63:0]  mb0_w       = msg_block_w[127:64];
  wire [63:0]  mb1_w       = msg_block_w[63:0];

  // -----------------------------------------------------------------------
  // Byte-level masking helpers (needed for partial blocks)
  // -----------------------------------------------------------------------
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

  // Pad byte: 0x01 at position byte_index within a 64-bit word
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

  // -----------------------------------------------------------------------
  // Partial-block XOR helpers (for AD and message tails)
  //
  //  For a tail of `n` bytes split across two 64-bit words:
  //    part0_bytes = min(n, 8)
  //    part1_bytes = max(n-8, 0)
  //  After masking and XOR, apply padding at byte position n within the
  //  128-bit rate (so pad in word0 if n<8, pad in word1 if n>=8).
  //
  // "enc": state XOR data, state absorbs padded data  (enc & AD)
  // "dec": output = state XOR data (masked), state absorbs padded ciphertext
  // -----------------------------------------------------------------------

  // ---- AD partial block ----
  wire [4:0] ap0_bytes_w = (ad_tail_bytes_q > 5'd8) ? 5'd8 : ad_tail_bytes_q;
  wire [4:0] ap1_bytes_w = (ad_tail_bytes_q > 5'd8) ? (ad_tail_bytes_q - 5'd8) : 5'd0;

  wire [63:0] ap0_mask_w = byte_mask64(ap0_bytes_w);
  wire [63:0] ap1_mask_w = byte_mask64(ap1_bytes_w);

  // s0 after absorbing partial AD word0 + padding
  wire [63:0] ap_s0_w = (ad_tail_bytes_q < 5'd8) ?
                        (s0_w ^ (ab0_w & ap0_mask_w) ^ pad64(ad_tail_bytes_q)) :
                        (s0_w ^ (ab0_w & ap0_mask_w));

  // s1 after absorbing partial AD word1 + padding (if tail >= 8)
  wire [63:0] ap_s1_w = (ad_tail_bytes_q < 5'd8) ?
                        s1_w :
                        ((ad_tail_bytes_q == 5'd8) ?
                         (s1_w ^ PAD0) :
                         (s1_w ^ (ab1_w & ap1_mask_w) ^ pad64(ad_tail_bytes_q - 5'd8)));

  // ---- Message partial block ----
  wire [4:0] mp0_bytes_w = (msg_tail_bytes_q > 5'd8) ? 5'd8 : msg_tail_bytes_q;
  wire [4:0] mp1_bytes_w = (msg_tail_bytes_q > 5'd8) ? (msg_tail_bytes_q - 5'd8) : 5'd0;

  wire [63:0] mp0_mask_w = byte_mask64(mp0_bytes_w);
  wire [63:0] mp1_mask_w = byte_mask64(mp1_bytes_w);

  // Encryption: ct = (s XOR m) & mask;  new s word = s ^ m_masked ^ pad
  wire [63:0] enc_pt_s0_w = (msg_tail_bytes_q < 5'd8) ?
                            (s0_w ^ (mb0_w & mp0_mask_w) ^ pad64(msg_tail_bytes_q)) :
                            (s0_w ^ (mb0_w & mp0_mask_w));
  wire [63:0] enc_pt_s1_w = (msg_tail_bytes_q < 5'd8) ?
                            s1_w :
                            ((msg_tail_bytes_q == 5'd8) ?
                             (s1_w ^ PAD0) :
                             (s1_w ^ (mb1_w & mp1_mask_w) ^ pad64(msg_tail_bytes_q - 5'd8)));

  wire [63:0] enc_ct0_w   = (s0_w ^ mb0_w) & mp0_mask_w;
  wire [63:0] enc_ct1_w   = (s1_w ^ mb1_w) & mp1_mask_w;

  // Decryption: pt = (s XOR ct) & mask;  new s word = ct_padded ^ pad
  wire [63:0] dec_ct0_masked_w = mb0_w & mp0_mask_w;  // mb = ciphertext in dec mode
  wire [63:0] dec_ct1_masked_w = mb1_w & mp1_mask_w;

  wire [63:0] dec_pt0_w   = (s0_w ^ mb0_w) & mp0_mask_w;
  wire [63:0] dec_pt1_w   = (s1_w ^ mb1_w) & mp1_mask_w;

  wire [63:0] dec_pt_s0_w = (msg_tail_bytes_q < 5'd8) ?
                            (dec_ct0_masked_w ^ pad64(msg_tail_bytes_q)) :
                            dec_ct0_masked_w;
  wire [63:0] dec_pt_s1_w = (msg_tail_bytes_q < 5'd8) ?
                            s1_w :
                            ((msg_tail_bytes_q == 5'd8) ?
                             (dec_ct1_masked_w ^ PAD0) :
                             (dec_ct1_masked_w ^ pad64(msg_tail_bytes_q - 5'd8)));
  // Partial dec: keep upper bits of s1 unchanged
  wire [63:0] dec_pt_s1_full_w = (msg_tail_bytes_q <= 5'd8) ?
                                  dec_pt_s1_w :
                                  (dec_pt_s1_w | (s1_w & ~mp1_mask_w));

  // -----------------------------------------------------------------------
  // Helper: launch permutation
  // -----------------------------------------------------------------------
  task do_perm;
    input [3:0]   rounds;
    input [319:0] state_in;
    begin
      perm_rounds_q <= rounds;
      perm_in_q     <= state_in;
      perm_start_q  <= 1'b1;
    end
  endtask

  // -----------------------------------------------------------------------
  // Helper: compute output block, update out registers
  //   full_enc / full_dec: called for full 16-byte message blocks
  // -----------------------------------------------------------------------

  // -----------------------------------------------------------------------
  // FSM
  // -----------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= ST_IDLE;
      s_q              <= 320'd0;
      key_q            <= 128'd0;
      decrypt_q        <= 1'b0;
      ad_blocks_left_q <= 32'd0;
      ad_tail_bytes_q  <= 5'd0;
      ad_present_q     <= 1'b0;
      msg_blocks_left_q<= 32'd0;
      msg_tail_bytes_q <= 5'd0;
      ad_blk_idx_q     <= 2'd0;
      msg_blk_idx_q    <= 2'd0;
      out_blk_idx_q    <= 2'd0;
      ad_had_tail_q    <= 1'b0;
      perm_start_q     <= 1'b0;
      perm_rounds_q    <= 4'd0;
      perm_in_q        <= 320'd0;
      busy_o           <= 1'b0;
      done_o           <= 1'b0;
      auth_ok_o        <= 1'b0;
      result_tag_o     <= 128'd0;
      out_block0_o     <= 128'd0;
      out_block1_o     <= 128'd0;
    end else begin
      perm_start_q <= 1'b0;
      done_o       <= 1'b0;

      // ---- CLEAR ----
      if (clear_i) begin
        state_q          <= ST_IDLE;
        busy_o           <= 1'b0;
        auth_ok_o        <= 1'b0;
        result_tag_o     <= 128'd0;
        out_block0_o     <= 128'd0;
        out_block1_o     <= 128'd0;
      end else begin

      case (state_q)

        // ----------------------------------------------------------------
        ST_IDLE: begin
          busy_o <= 1'b0;
          if (start_i) begin
            busy_o           <= 1'b1;
            decrypt_q        <= decrypt_i;
            key_q            <= key_i;
            ad_present_q     <= (ad_bytes_i != 32'd0);
            ad_blocks_left_q <= ad_bytes_i[31:4];          // full 16-byte blocks
            ad_tail_bytes_q  <= {1'b0, ad_bytes_i[3:0]};  // 0..15 remainder bytes
            msg_blocks_left_q<= msg_bytes_i[31:4];
            msg_tail_bytes_q <= {1'b0, msg_bytes_i[3:0]};
            ad_blk_idx_q     <= 2'd0;
            msg_blk_idx_q    <= 2'd0;
            out_blk_idx_q    <= 2'd0;
            ad_had_tail_q    <= 1'b0;
            auth_ok_o        <= 1'b0;
            result_tag_o     <= 128'd0;
            out_block0_o     <= 128'd0;
            out_block1_o     <= 128'd0;

            // Initialization: state = IV || K0 || K1 || N0 || N1
            s_q <= {IV,
                    key_i[127:64], key_i[63:0],
                    nonce_i[127:64], nonce_i[63:0]};

            do_perm(4'd12, {IV,
                            key_i[127:64], key_i[63:0],
                            nonce_i[127:64], nonce_i[63:0]});
            state_q <= ST_INIT_WAIT;
          end
        end

        // ----------------------------------------------------------------
        // After p12: XOR key into S3,S4.  Then route to AD phase or msg phase.
        ST_INIT_WAIT: begin
          if (perm_done_w) begin
            // S3 ^= K0, S4 ^= K1
            s_q <= {perm_out_w[319:128],
                    perm_out_w[127:64] ^ k0_w,
                    perm_out_w[63:0]   ^ k1_w};

            if (ad_blocks_left_q != 32'd0 || ad_tail_bytes_q != 5'd0) begin
              state_q <= ST_AD_XOR;
            end else begin
              // No AD: XOR DSEP into S4, then start message phase
              s_q[63:0] <= (perm_out_w[63:0] ^ k1_w) ^ DSEP;
              state_q   <= ST_MSG_XOR;
            end
          end
        end

        // ----------------------------------------------------------------
        // XOR one AD block into S0,S1 and start p8.
        // Handles both full blocks and the tail partial block.
        // We arrive here either from INIT_WAIT or from AD_WAIT.
        ST_AD_XOR: begin
          if (ad_blocks_left_q != 32'd0) begin
            // Full 16-byte block
            s_q              <= {s0_w ^ ab0_w, s1_w ^ ab1_w, s2_w, s3_w, s4_w};
            do_perm(4'd8,      {s0_w ^ ab0_w, s1_w ^ ab1_w, s2_w, s3_w, s4_w});
            ad_blocks_left_q <= ad_blocks_left_q - 32'd1;
            ad_blk_idx_q     <= ad_blk_idx_q + 2'd1;
            state_q          <= ST_AD_WAIT;
          end else begin
            // ad_tail_bytes_q != 0 guaranteed (routing from INIT_WAIT/AD_WAIT
            // only enters ST_AD_XOR when there is more AD to process)
            s_q             <= {ap_s0_w, ap_s1_w, s2_w, s3_w, s4_w};
            do_perm(4'd8,     {ap_s0_w, ap_s1_w, s2_w, s3_w, s4_w});
            ad_tail_bytes_q <= 5'd0;
            ad_had_tail_q   <= 1'b1;
            ad_blk_idx_q    <= ad_blk_idx_q + 2'd1;
            state_q         <= ST_AD_WAIT;
          end
        end

        // ----------------------------------------------------------------
        // Wait for p8 after absorbing one AD block.
        ST_AD_WAIT: begin
          if (perm_done_w) begin
            s_q <= perm_out_w;
            if (ad_blocks_left_q != 32'd0 || ad_tail_bytes_q != 5'd0) begin
              // More AD to absorb
              state_q <= ST_AD_XOR;
            end else if (!ad_had_tail_q && ad_present_q) begin
              // All AD was in full 16-byte blocks — need the domain-separator
              // permutation with PAD0 in S0 before entering message phase.
              // (When we had a tail, the pad was already included in ap_s0_w.)
              do_perm(4'd8, {perm_out_w[319:256] ^ PAD0,
                             perm_out_w[255:192],
                             perm_out_w[191:128],
                             perm_out_w[127:64],
                             perm_out_w[63:0]});
              state_q <= ST_AD_PAD_WAIT;
            end else begin
              // Had a tail block (pad baked in): just DSEP and proceed
              s_q[63:0] <= perm_out_w[63:0] ^ DSEP;
              state_q   <= ST_MSG_XOR;
            end
          end
        end

        // ----------------------------------------------------------------
        // Wait for the extra PAD0 permutation (only when all AD was full blocks).
        ST_AD_PAD_WAIT: begin
          if (perm_done_w) begin
            s_q       <= perm_out_w;
            s_q[63:0] <= perm_out_w[63:0] ^ DSEP;
            state_q   <= ST_MSG_XOR;
          end
        end

        // ----------------------------------------------------------------
        // Process one message block (full or partial tail).
        // For encryption: ct = s XOR pt;  new s = ct || s2..s4; then p8.
        // For decryption: pt = s XOR ct;  new s = ct || s2..s4; then p8.
        // Empty message: go straight to finalization.
        ST_MSG_XOR: begin
          if (msg_blocks_left_q != 32'd0) begin
            // Full 16-byte block
            if (!decrypt_q) begin
              // Encryption
              if (out_blk_idx_q == 2'd0)
                out_block0_o <= {s0_w ^ mb0_w, s1_w ^ mb1_w};
              else
                out_block1_o <= {s0_w ^ mb0_w, s1_w ^ mb1_w};
              // state: absorb ciphertext
              s_q <= {s0_w ^ mb0_w, s1_w ^ mb1_w, s2_w, s3_w, s4_w};
              do_perm(4'd8, {s0_w ^ mb0_w, s1_w ^ mb1_w, s2_w, s3_w, s4_w});
            end else begin
              // Decryption: pt = s XOR ct
              if (out_blk_idx_q == 2'd0)
                out_block0_o <= {s0_w ^ mb0_w, s1_w ^ mb1_w};
              else
                out_block1_o <= {s0_w ^ mb0_w, s1_w ^ mb1_w};
              // state: absorb ciphertext (mb = ciphertext input)
              s_q <= {mb0_w, mb1_w, s2_w, s3_w, s4_w};
              do_perm(4'd8, {mb0_w, mb1_w, s2_w, s3_w, s4_w});
            end
            msg_blocks_left_q <= msg_blocks_left_q - 32'd1;
            msg_blk_idx_q     <= msg_blk_idx_q + 2'd1;
            out_blk_idx_q     <= out_blk_idx_q + 2'd1;
            state_q           <= ST_MSG_WAIT;

          end else if (msg_tail_bytes_q != 5'd0) begin
            // Partial tail block
            if (!decrypt_q) begin
              if (out_blk_idx_q == 2'd0)
                out_block0_o <= {enc_ct0_w, enc_ct1_w};
              else
                out_block1_o <= {enc_ct0_w, enc_ct1_w};
              s_q <= {enc_pt_s0_w, enc_pt_s1_w, s2_w, s3_w, s4_w};
            end else begin
              if (out_blk_idx_q == 2'd0)
                out_block0_o <= {dec_pt0_w, dec_pt1_w};
              else
                out_block1_o <= {dec_pt0_w, dec_pt1_w};
              s_q <= {dec_pt_s0_w, dec_pt_s1_full_w, s2_w, s3_w, s4_w};
            end
            msg_tail_bytes_q  <= 5'd0;
            out_blk_idx_q     <= out_blk_idx_q + 2'd1;
            // No p8 after partial block — go directly to finalization.
            // (The partial-block padding is already baked into s_q above.)
            // Start p12 finalization.
            do_perm(4'd12, {(!decrypt_q ? enc_pt_s0_w : dec_pt_s0_w) ^ PAD0,
                            (!decrypt_q ? enc_pt_s1_w : dec_pt_s1_full_w),
                            s2_w ^ k0_w,
                            s3_w ^ k1_w,
                            s4_w});
            state_q <= ST_FINAL_WAIT;

          end else begin
            // Empty message body — finalize directly.
            // PAD0 into S0, key into S2/S3.
            do_perm(4'd12, {s0_w ^ PAD0,
                            s1_w,
                            s2_w ^ k0_w,
                            s3_w ^ k1_w,
                            s4_w});
            state_q <= ST_FINAL_WAIT;
          end
        end

        // ----------------------------------------------------------------
        ST_MSG_WAIT: begin
          if (perm_done_w) begin
            s_q <= perm_out_w;
            if (msg_blocks_left_q != 32'd0 || msg_tail_bytes_q != 5'd0) begin
              state_q <= ST_MSG_XOR;
            end else begin
              // All message blocks done — finalize.
              // When the last block was a full block we still need PAD0 in S0.
              do_perm(4'd12, {perm_out_w[319:256] ^ PAD0,
                              perm_out_w[255:192],
                              perm_out_w[191:128] ^ k0_w,
                              perm_out_w[127:64]  ^ k1_w,
                              perm_out_w[63:0]});
              state_q <= ST_FINAL_WAIT;
            end
          end
        end

        // ----------------------------------------------------------------
        // After p12 finalization: compute tag = (S3^K0) || (S4^K1).
        ST_FINAL_WAIT: begin
          if (perm_done_w) begin
            result_tag_o <= {perm_out_w[127:64] ^ k0_w,
                             perm_out_w[63:0]   ^ k1_w};

            if (!decrypt_q) begin
              // Encryption: tag is output; always authenticated.
              auth_ok_o <= 1'b1;
            end else begin
              // Decryption: compare computed tag against supplied tag_i.
              auth_ok_o <= ({perm_out_w[127:64] ^ k0_w,
                             perm_out_w[63:0]   ^ k1_w} == tag_i);
            end
            state_q <= ST_DONE;
          end
        end

        // ----------------------------------------------------------------
        ST_DONE: begin
          done_o  <= 1'b1;
          busy_o  <= 1'b0;
          state_q <= ST_IDLE;
        end

        default: begin
          state_q <= ST_IDLE;
          busy_o  <= 1'b0;
        end

      endcase
      end // !clear_i
    end
  end

endmodule

`default_nettype wire
