`timescale 1ns/1ps
// SPDX-License-Identifier: Apache-2.0
//
// Phase 2.4 Ascon-AEAD128 decryption core with associated-data support.
//
// Scope of this module:
//   - Decryption only.
//   - Associated data supported.
//   - Arbitrary associated-data and ciphertext/plaintext lengths in bytes.
//   - Inputs/outputs use internal Ascon 64-bit word order, not CPU byte order.
//   - The bus/wrapper is responsible for packing raw bytes into the internal
//     little-endian Ascon words used here.
//
// Authentication contract:
//   This is a streaming high-throughput decryption core. It emits plaintext
//   before the final tag verdict is available. Downstream software/wrappers
//   must not commit plaintext until auth_valid_o && auth_ok_o has been seen.
//
// Packing convention:
//   key_i[127:64]          = K0 = LOADBYTES(k,     8)
//   key_i[63:0]            = K1 = LOADBYTES(k + 8, 8)
//   nonce_i[127:64]        = N0 = LOADBYTES(n,     8)
//   nonce_i[63:0]          = N1 = LOADBYTES(n + 8, 8)
//   ad_block_i             = {A0, A1}
//   ciphertext_block_i     = {C0, C1}
//   plaintext_block_o      = {M0, M1}
//   tag_i                  = {T0, T1}
//
// Stream contract:
//   ad_bytes_i declares total associated-data length. The core requests
//   ceil(ad_bytes_i / 16) AD blocks on ad_*.
//   msg_bytes_i declares total ciphertext/plaintext length. The core requests
//   ceil(msg_bytes_i / 16) ciphertext blocks on ciphertext_*.
//   plaintext_bytes_o reports the valid byte count for each plaintext block.

module ascon_aead128_dec_ad #(
  parameter integer ROUNDS_PER_CYCLE = 1
) (
  input  wire         clk,
  input  wire         rst_n,

  input  wire         start_i,
  input  wire [127:0] key_i,
  input  wire [127:0] nonce_i,
  input  wire [31:0]  ad_bytes_i,
  input  wire [31:0]  msg_bytes_i,
  input  wire [127:0] tag_i,

  output wire         busy_o,
  output reg          done_o,

  output wire         ad_ready_o,
  input  wire         ad_valid_i,
  input  wire [127:0] ad_block_i,

  output wire         ciphertext_ready_o,
  input  wire         ciphertext_valid_i,
  input  wire [127:0] ciphertext_block_i,

  output reg          plaintext_valid_o,
  input  wire         plaintext_ready_i,
  output reg  [127:0] plaintext_block_o,
  output reg  [4:0]   plaintext_bytes_o,

  output reg          auth_valid_o,
  input  wire         auth_ready_i,
  output reg          auth_ok_o
);

  localparam [63:0] ASCON_128A_IV = 64'h00001000808c0001;
  localparam [63:0] ASCON_PAD0    = 64'h0000000000000001;
  localparam [63:0] ASCON_DSEP    = 64'h8000000000000000;

  localparam [3:0] ST_IDLE              = 4'd0;
  localparam [3:0] ST_INIT_WAIT         = 4'd1;
  localparam [3:0] ST_AD_WAIT_FULL      = 4'd2;
  localparam [3:0] ST_AD_FULL_WAIT      = 4'd3;
  localparam [3:0] ST_AD_WAIT_PARTIAL   = 4'd4;
  localparam [3:0] ST_AD_PARTIAL_WAIT   = 4'd5;
  localparam [3:0] ST_AD_EMPTY_WAIT     = 4'd6;
  localparam [3:0] ST_MSG_WAIT_FULL     = 4'd7;
  localparam [3:0] ST_MSG_FULL_WAIT     = 4'd8;
  localparam [3:0] ST_MSG_WAIT_PARTIAL  = 4'd9;
  localparam [3:0] ST_DRAIN_PT          = 4'd10;
  localparam [3:0] ST_FINAL_WAIT        = 4'd11;
  localparam [3:0] ST_AUTH_WAIT         = 4'd12;

  reg [3:0]   state_q;
  reg [319:0] ascon_state_q;
  reg [127:0] key_q;
  reg [127:0] tag_q;
  reg [31:0]  ad_full_blocks_left_q;
  reg [4:0]   ad_final_bytes_q;
  reg         ad_present_q;
  reg [31:0]  msg_full_blocks_left_q;
  reg [4:0]   msg_final_bytes_q;

  reg         perm_start_q;
  reg [3:0]   perm_rounds_q;
  reg [319:0] perm_state_i_q;
  wire        perm_busy_w;
  wire        perm_done_w;
  wire [319:0] perm_state_o_w;

  wire [63:0] k0_w = key_q[127:64];
  wire [63:0] k1_w = key_q[63:0];

  wire [63:0] s0_w = ascon_state_q[319:256];
  wire [63:0] s1_w = ascon_state_q[255:192];
  wire [63:0] s2_w = ascon_state_q[191:128];
  wire [63:0] s3_w = ascon_state_q[127:64];
  wire [63:0] s4_w = ascon_state_q[63:0];

  wire [63:0] a0_w = ad_block_i[127:64];
  wire [63:0] a1_w = ad_block_i[63:0];
  wire [63:0] c0_w = ciphertext_block_i[127:64];
  wire [63:0] c1_w = ciphertext_block_i[63:0];

  wire [4:0] ad_part0_bytes_w = (ad_final_bytes_q > 5'd8) ? 5'd8 : ad_final_bytes_q;
  wire [4:0] ad_part1_bytes_w = (ad_final_bytes_q > 5'd8) ? (ad_final_bytes_q - 5'd8) : 5'd0;
  wire [63:0] ad_part0_mask_w = byte_mask64(ad_part0_bytes_w);
  wire [63:0] ad_part1_mask_w = byte_mask64(ad_part1_bytes_w);
  wire [63:0] ad_part_a0_w    = a0_w & ad_part0_mask_w;
  wire [63:0] ad_part_a1_w    = a1_w & ad_part1_mask_w;
  wire [63:0] ad_part_s0_w    = (ad_final_bytes_q < 5'd8) ?
                                (s0_w ^ ad_part_a0_w ^ pad64(ad_final_bytes_q)) :
                                (s0_w ^ ad_part_a0_w);
  wire [63:0] ad_part_s1_w    = (ad_final_bytes_q < 5'd8) ?
                                s1_w :
                                ((ad_final_bytes_q == 5'd8) ?
                                 (s1_w ^ ASCON_PAD0) :
                                 (s1_w ^ ad_part_a1_w ^ pad64(ad_part1_bytes_w)));

  wire [63:0] full_m0_w = s0_w ^ c0_w;
  wire [63:0] full_m1_w = s1_w ^ c1_w;

  wire [4:0] msg_part0_bytes_w = (msg_final_bytes_q > 5'd8) ? 5'd8 : msg_final_bytes_q;
  wire [4:0] msg_part1_bytes_w = (msg_final_bytes_q > 5'd8) ? (msg_final_bytes_q - 5'd8) : 5'd0;
  wire [63:0] msg_part0_mask_w = byte_mask64(msg_part0_bytes_w);
  wire [63:0] msg_part1_mask_w = byte_mask64(msg_part1_bytes_w);
  wire [63:0] msg_part_c0_w    = c0_w & msg_part0_mask_w;
  wire [63:0] msg_part_c1_w    = c1_w & msg_part1_mask_w;
  wire [63:0] msg_part_m0_w    = (s0_w ^ msg_part_c0_w) & msg_part0_mask_w;
  wire [63:0] msg_part_m1_w    = (s1_w ^ msg_part_c1_w) & msg_part1_mask_w;
  wire [63:0] msg_part_s0_w    = (msg_final_bytes_q < 5'd8) ?
                                 ((s0_w & ~msg_part0_mask_w) ^ msg_part_c0_w ^ pad64(msg_final_bytes_q)) :
                                 msg_part_c0_w;
  wire [63:0] msg_part_s1_w    = (msg_final_bytes_q < 5'd8) ?
                                 s1_w :
                                 ((msg_final_bytes_q == 5'd8) ?
                                  (s1_w ^ ASCON_PAD0) :
                                  ((s1_w & ~msg_part1_mask_w) ^ msg_part_c1_w ^ pad64(msg_part1_bytes_w)));

  wire [127:0] calc_tag_w = {perm_state_o_w[127:64] ^ k0_w,
                             perm_state_o_w[63:0] ^ k1_w};

  assign busy_o = (state_q != ST_IDLE) | perm_busy_w;
  assign ad_ready_o = ((state_q == ST_AD_WAIT_FULL) ||
                       (state_q == ST_AD_WAIT_PARTIAL));
  assign ciphertext_ready_o =
    ((state_q == ST_MSG_WAIT_FULL) || (state_q == ST_MSG_WAIT_PARTIAL)) &&
    !plaintext_valid_o;

  ascon_perm_unrolled #(
    .ROUNDS_PER_CYCLE(ROUNDS_PER_CYCLE)
  ) u_perm (
    .clk     (clk),
    .rst_n   (rst_n),
    .start_i (perm_start_q),
    .rounds_i(perm_rounds_q),
    .state_i (perm_state_i_q),
    .busy_o  (perm_busy_w),
    .done_o  (perm_done_w),
    .state_o (perm_state_o_w)
  );

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

  task start_perm;
    input [3:0] rounds;
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
      if (msg_full_blocks_left_q != 32'd0) begin
        state_q <= ST_MSG_WAIT_FULL;
      end else if (msg_final_bytes_q != 5'd0) begin
        state_q <= ST_MSG_WAIT_PARTIAL;
      end else begin
        state_q <= ST_DRAIN_PT;
      end
    end
  endtask

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q                 <= ST_IDLE;
      ascon_state_q           <= 320'd0;
      key_q                   <= 128'd0;
      tag_q                   <= 128'd0;
      ad_full_blocks_left_q   <= 32'd0;
      ad_final_bytes_q        <= 5'd0;
      ad_present_q            <= 1'b0;
      msg_full_blocks_left_q  <= 32'd0;
      msg_final_bytes_q       <= 5'd0;
      perm_start_q            <= 1'b0;
      perm_rounds_q           <= 4'd0;
      perm_state_i_q          <= 320'd0;
      done_o                  <= 1'b0;
      plaintext_valid_o       <= 1'b0;
      plaintext_block_o       <= 128'd0;
      plaintext_bytes_o       <= 5'd0;
      auth_valid_o            <= 1'b0;
      auth_ok_o               <= 1'b0;
    end else begin
      perm_start_q <= 1'b0;
      done_o       <= 1'b0;

      if (plaintext_valid_o && plaintext_ready_i) begin
        plaintext_valid_o <= 1'b0;
      end

      case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            key_q                  <= key_i;
            tag_q                  <= tag_i;
            ad_full_blocks_left_q  <= {4'd0, ad_bytes_i[31:4]};
            ad_final_bytes_q       <= {1'b0, ad_bytes_i[3:0]};
            ad_present_q           <= (ad_bytes_i != 32'd0);
            msg_full_blocks_left_q <= {4'd0, msg_bytes_i[31:4]};
            msg_final_bytes_q      <= {1'b0, msg_bytes_i[3:0]};
            ascon_state_q          <= {ASCON_128A_IV, key_i[127:64], key_i[63:0],
                                       nonce_i[127:64], nonce_i[63:0]};
            auth_ok_o              <= 1'b0;
            start_perm(4'd12, {ASCON_128A_IV, key_i[127:64], key_i[63:0],
                               nonce_i[127:64], nonce_i[63:0]});
            state_q <= ST_INIT_WAIT;
          end
        end

        ST_INIT_WAIT: begin
          if (perm_done_w) begin
            ascon_state_q <= {perm_state_o_w[319:128],
                              perm_state_o_w[127:64] ^ k0_w,
                              perm_state_o_w[63:0] ^ k1_w};

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

        ST_AD_WAIT_FULL: begin
          if (ad_valid_i && ad_ready_o) begin
            ad_full_blocks_left_q <= ad_full_blocks_left_q - 32'd1;
            ascon_state_q         <= {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w};
            start_perm(4'd8, {s0_w ^ a0_w, s1_w ^ a1_w, s2_w, s3_w, s4_w});
            state_q <= ST_AD_FULL_WAIT;
          end
        end

        ST_AD_FULL_WAIT: begin
          if (perm_done_w) begin
            ascon_state_q <= perm_state_o_w;
            if (ad_full_blocks_left_q != 32'd0) begin
              state_q <= ST_AD_WAIT_FULL;
            end else if (ad_final_bytes_q != 5'd0) begin
              state_q <= ST_AD_WAIT_PARTIAL;
            end else if (ad_present_q) begin
              start_perm(4'd8, {perm_state_o_w[319:256] ^ ASCON_PAD0,
                                perm_state_o_w[255:0]});
              state_q <= ST_AD_EMPTY_WAIT;
            end else begin
              enter_message_phase({perm_state_o_w[319:64],
                                   perm_state_o_w[63:0] ^ ASCON_DSEP});
            end
          end
        end

        ST_AD_WAIT_PARTIAL: begin
          if (ad_valid_i && ad_ready_o) begin
            ascon_state_q <= {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w};
            start_perm(4'd8, {ad_part_s0_w, ad_part_s1_w, s2_w, s3_w, s4_w});
            state_q <= ST_AD_PARTIAL_WAIT;
          end
        end

        ST_AD_PARTIAL_WAIT: begin
          if (perm_done_w) begin
            enter_message_phase({perm_state_o_w[319:64],
                                 perm_state_o_w[63:0] ^ ASCON_DSEP});
          end
        end

        ST_AD_EMPTY_WAIT: begin
          if (perm_done_w) begin
            enter_message_phase({perm_state_o_w[319:64],
                                 perm_state_o_w[63:0] ^ ASCON_DSEP});
          end
        end

        ST_MSG_WAIT_FULL: begin
          if (ciphertext_valid_i && ciphertext_ready_o) begin
            plaintext_block_o      <= {full_m0_w, full_m1_w};
            plaintext_bytes_o      <= 5'd16;
            plaintext_valid_o      <= 1'b1;
            ascon_state_q          <= {c0_w, c1_w, s2_w, s3_w, s4_w};
            msg_full_blocks_left_q <= msg_full_blocks_left_q - 32'd1;
            start_perm(4'd8, {c0_w, c1_w, s2_w, s3_w, s4_w});
            state_q <= ST_MSG_FULL_WAIT;
          end
        end

        ST_MSG_FULL_WAIT: begin
          if (perm_done_w) begin
            ascon_state_q <= perm_state_o_w;
            if (msg_full_blocks_left_q != 32'd0) begin
              state_q <= ST_MSG_WAIT_FULL;
            end else if (msg_final_bytes_q != 5'd0) begin
              state_q <= ST_MSG_WAIT_PARTIAL;
            end else begin
              state_q <= ST_DRAIN_PT;
            end
          end
        end

        ST_MSG_WAIT_PARTIAL: begin
          if (ciphertext_valid_i && ciphertext_ready_o) begin
            plaintext_block_o   <= {msg_part_m0_w, msg_part_m1_w};
            plaintext_bytes_o   <= msg_final_bytes_q;
            plaintext_valid_o   <= 1'b1;
            ascon_state_q       <= {msg_part_s0_w, msg_part_s1_w, s2_w, s3_w, s4_w};
            state_q             <= ST_DRAIN_PT;
          end
        end

        ST_DRAIN_PT: begin
          if (!plaintext_valid_o) begin
            if (msg_final_bytes_q == 5'd0) begin
              start_perm(4'd12, {s0_w ^ ASCON_PAD0,
                                 s1_w,
                                 s2_w ^ k0_w,
                                 s3_w ^ k1_w,
                                 s4_w});
            end else begin
              start_perm(4'd12, {s0_w,
                                 s1_w,
                                 s2_w ^ k0_w,
                                 s3_w ^ k1_w,
                                 s4_w});
            end
            state_q <= ST_FINAL_WAIT;
          end
        end

        ST_FINAL_WAIT: begin
          if (perm_done_w) begin
            auth_ok_o    <= (calc_tag_w == tag_q);
            auth_valid_o <= 1'b1;
            state_q      <= ST_AUTH_WAIT;
          end
        end

        ST_AUTH_WAIT: begin
          if (auth_valid_o && auth_ready_i) begin
            auth_valid_o <= 1'b0;
            done_o       <= 1'b1;
            state_q      <= ST_IDLE;
          end
        end

        default: begin
          state_q <= ST_IDLE;
        end
      endcase
    end
  end

endmodule
