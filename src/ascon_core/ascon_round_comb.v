`timescale 1ns/1ps
// SPDX-License-Identifier: Apache-2.0
//
// ASCON one-round combinational primitive.
//
// Scope:
//   - Pure permutation round only.
//   - No AEAD mode logic.
//   - No byte-string endian conversion.
//   - No bus/protocol assumptions.
//
// Internal state packing convention:
//   state_i[319:256] = S0
//   state_i[255:192] = S1
//   state_i[191:128] = S2
//   state_i[127:64]  = S3
//   state_i[63:0]    = S4
//
// The round constant is XORed into the low byte of S2, matching the
// word-level ASCON permutation used by ascon-c.

module ascon_round_comb (
  input  wire [319:0] state_i,
  input  wire [7:0]   rc_i,
  output wire [319:0] state_o
);

  function [63:0] ror64;
    input [63:0] x;
    input integer n;
    begin
      ror64 = (x >> n) | (x << (64 - n));
    end
  endfunction

  wire [63:0] x0 = state_i[319:256];
  wire [63:0] x1 = state_i[255:192];
  wire [63:0] x2 = state_i[191:128];
  wire [63:0] x3 = state_i[127:64];
  wire [63:0] x4 = state_i[63:0];

  // Constant addition + S-box pre-mix.
  wire [63:0] a0 = x0 ^ x4;
  wire [63:0] a1 = x1;
  wire [63:0] a2 = x2 ^ x1 ^ {56'b0, rc_i};
  wire [63:0] a3 = x3;
  wire [63:0] a4 = x4 ^ x3;

  // 64 parallel 5-bit S-boxes in bit-sliced form.
  wire [63:0] t0 = a0 ^ ((~a1) & a2);
  wire [63:0] t1 = a1 ^ ((~a2) & a3);
  wire [63:0] t2 = a2 ^ ((~a3) & a4);
  wire [63:0] t3 = a3 ^ ((~a4) & a0);
  wire [63:0] t4 = a4 ^ ((~a0) & a1);

  wire [63:0] s0 = t0 ^ t4;
  wire [63:0] s1 = t1 ^ t0;
  wire [63:0] s2 = t2;
  wire [63:0] s3 = t3 ^ t2;
  wire [63:0] s4 = t4;

  // Linear diffusion layer.
  wire [63:0] y0 =  s0 ^ ror64(s0, 19) ^ ror64(s0, 28);
  wire [63:0] y1 =  s1 ^ ror64(s1, 61) ^ ror64(s1, 39);
  wire [63:0] y2 = ~(s2 ^ ror64(s2,  1) ^ ror64(s2,  6));
  wire [63:0] y3 =  s3 ^ ror64(s3, 10) ^ ror64(s3, 17);
  wire [63:0] y4 =  s4 ^ ror64(s4,  7) ^ ror64(s4, 41);

  assign state_o = {y0, y1, y2, y3, y4};

endmodule
