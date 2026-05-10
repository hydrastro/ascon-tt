`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// Tiny Tapeout permutation execution core.
//
// This is the TT-3 bridge between the byte serial frontend and the verified
// ascon-rtl permutation engine. The final full-AEAD FSM will call this same
// execution layer repeatedly.

module ascon_tt_perm_core (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       clear_i,

  input  wire       load_valid_i,
  input  wire [5:0] load_index_i,
  input  wire [7:0] load_byte_i,

  input  wire [5:0] read_index_i,
  output wire [7:0] read_byte_o,
  output wire [7:0] state_xor_o,

  input  wire [3:0] rounds_i,
  input  wire       start_i,
  output wire       busy_o,
  output wire       done_o
);

  reg [319:0] state_q;
  reg [319:0] state_next;

  wire [319:0] perm_state_o;
  wire         perm_busy_w;
  wire         perm_done_w;

  assign busy_o = perm_busy_w;
  assign done_o = perm_done_w;

  function [7:0] extract_byte320;
    input [319:0] value;
    input [5:0]   index;
    begin
      case (index)
        6'd0:  extract_byte320 = value[319:312];
        6'd1:  extract_byte320 = value[311:304];
        6'd2:  extract_byte320 = value[303:296];
        6'd3:  extract_byte320 = value[295:288];
        6'd4:  extract_byte320 = value[287:280];
        6'd5:  extract_byte320 = value[279:272];
        6'd6:  extract_byte320 = value[271:264];
        6'd7:  extract_byte320 = value[263:256];
        6'd8:  extract_byte320 = value[255:248];
        6'd9:  extract_byte320 = value[247:240];
        6'd10: extract_byte320 = value[239:232];
        6'd11: extract_byte320 = value[231:224];
        6'd12: extract_byte320 = value[223:216];
        6'd13: extract_byte320 = value[215:208];
        6'd14: extract_byte320 = value[207:200];
        6'd15: extract_byte320 = value[199:192];
        6'd16: extract_byte320 = value[191:184];
        6'd17: extract_byte320 = value[183:176];
        6'd18: extract_byte320 = value[175:168];
        6'd19: extract_byte320 = value[167:160];
        6'd20: extract_byte320 = value[159:152];
        6'd21: extract_byte320 = value[151:144];
        6'd22: extract_byte320 = value[143:136];
        6'd23: extract_byte320 = value[135:128];
        6'd24: extract_byte320 = value[127:120];
        6'd25: extract_byte320 = value[119:112];
        6'd26: extract_byte320 = value[111:104];
        6'd27: extract_byte320 = value[103:96];
        6'd28: extract_byte320 = value[95:88];
        6'd29: extract_byte320 = value[87:80];
        6'd30: extract_byte320 = value[79:72];
        6'd31: extract_byte320 = value[71:64];
        6'd32: extract_byte320 = value[63:56];
        6'd33: extract_byte320 = value[55:48];
        6'd34: extract_byte320 = value[47:40];
        6'd35: extract_byte320 = value[39:32];
        6'd36: extract_byte320 = value[31:24];
        6'd37: extract_byte320 = value[23:16];
        6'd38: extract_byte320 = value[15:8];
        6'd39: extract_byte320 = value[7:0];
        default: extract_byte320 = 8'd0;
      endcase
    end
  endfunction

  function [319:0] insert_byte320;
    input [319:0] value;
    input [5:0]   index;
    input [7:0]   byte_v;
    begin
      insert_byte320 = value;
      case (index)
        6'd0:  insert_byte320[319:312] = byte_v;
        6'd1:  insert_byte320[311:304] = byte_v;
        6'd2:  insert_byte320[303:296] = byte_v;
        6'd3:  insert_byte320[295:288] = byte_v;
        6'd4:  insert_byte320[287:280] = byte_v;
        6'd5:  insert_byte320[279:272] = byte_v;
        6'd6:  insert_byte320[271:264] = byte_v;
        6'd7:  insert_byte320[263:256] = byte_v;
        6'd8:  insert_byte320[255:248] = byte_v;
        6'd9:  insert_byte320[247:240] = byte_v;
        6'd10: insert_byte320[239:232] = byte_v;
        6'd11: insert_byte320[231:224] = byte_v;
        6'd12: insert_byte320[223:216] = byte_v;
        6'd13: insert_byte320[215:208] = byte_v;
        6'd14: insert_byte320[207:200] = byte_v;
        6'd15: insert_byte320[199:192] = byte_v;
        6'd16: insert_byte320[191:184] = byte_v;
        6'd17: insert_byte320[183:176] = byte_v;
        6'd18: insert_byte320[175:168] = byte_v;
        6'd19: insert_byte320[167:160] = byte_v;
        6'd20: insert_byte320[159:152] = byte_v;
        6'd21: insert_byte320[151:144] = byte_v;
        6'd22: insert_byte320[143:136] = byte_v;
        6'd23: insert_byte320[135:128] = byte_v;
        6'd24: insert_byte320[127:120] = byte_v;
        6'd25: insert_byte320[119:112] = byte_v;
        6'd26: insert_byte320[111:104] = byte_v;
        6'd27: insert_byte320[103:96] = byte_v;
        6'd28: insert_byte320[95:88] = byte_v;
        6'd29: insert_byte320[87:80] = byte_v;
        6'd30: insert_byte320[79:72] = byte_v;
        6'd31: insert_byte320[71:64] = byte_v;
        6'd32: insert_byte320[63:56] = byte_v;
        6'd33: insert_byte320[55:48] = byte_v;
        6'd34: insert_byte320[47:40] = byte_v;
        6'd35: insert_byte320[39:32] = byte_v;
        6'd36: insert_byte320[31:24] = byte_v;
        6'd37: insert_byte320[23:16] = byte_v;
        6'd38: insert_byte320[15:8] = byte_v;
        6'd39: insert_byte320[7:0] = byte_v;
        default: begin
        end
      endcase
    end
  endfunction

  function [7:0] xor_state320;
    input [319:0] value;
    integer i;
    begin
      xor_state320 = 8'd0;
      for (i = 0; i < 40; i = i + 1) begin
        xor_state320 = xor_state320 ^ extract_byte320(value, i[5:0]);
      end
    end
  endfunction

  assign read_byte_o = extract_byte320(state_q, read_index_i);
  assign state_xor_o = xor_state320(state_q);

  always @* begin
    state_next = state_q;
    if (load_valid_i) begin
      state_next = insert_byte320(state_q, load_index_i, load_byte_i);
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= 320'd0;
    end else if (clear_i) begin
      state_q <= 320'd0;
    end else if (perm_done_w) begin
      state_q <= perm_state_o;
    end else begin
      state_q <= state_next;
    end
  end

  ascon_perm_unrolled #(
    .ROUNDS_PER_CYCLE(1)
  ) u_perm (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (start_i),
    .rounds_i (rounds_i),
    .state_i  (state_q),
    .state_o  (perm_state_o),
    .busy_o   (perm_busy_w),
    .done_o   (perm_done_w)
  );

endmodule

`default_nettype wire
