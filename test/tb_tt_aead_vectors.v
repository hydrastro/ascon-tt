`timescale 1ns/1ps
`default_nettype none

module tb_tt_aead_vectors;
`include "ascon_aead128_ad_vectors.vh"
  reg [7:0] ui_in;
  wire [7:0] uo_out;
  reg [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg ena;
  reg clk;
  reg rst_n;

  integer errors;
  integer i;
  integer timeout;
  reg [7:0] response;

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

  function [7:0] byte_from_u128;
    input [127:0] value;
    input integer idx;
    begin
      case (idx)
        0:  byte_from_u128 = value[71:64];
        1:  byte_from_u128 = value[79:72];
        2:  byte_from_u128 = value[87:80];
        3:  byte_from_u128 = value[95:88];
        4:  byte_from_u128 = value[103:96];
        5:  byte_from_u128 = value[111:104];
        6:  byte_from_u128 = value[119:112];
        7:  byte_from_u128 = value[127:120];
        8:  byte_from_u128 = value[7:0];
        9:  byte_from_u128 = value[15:8];
        10: byte_from_u128 = value[23:16];
        11: byte_from_u128 = value[31:24];
        12: byte_from_u128 = value[39:32];
        13: byte_from_u128 = value[47:40];
        14: byte_from_u128 = value[55:48];
        default: byte_from_u128 = value[63:56];
      endcase
    end
  endfunction

  function [7:0] byte_from_two_blocks;
    input [127:0] block0;
    input [127:0] block1;
    input integer idx;
    begin
      if (idx < 16) begin
        byte_from_two_blocks = byte_from_u128(block0, idx);
      end else begin
        byte_from_two_blocks = byte_from_u128(block1, idx - 16);
      end
    end
  endfunction

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

  task send_byte_no_resp;
    input [7:0] value;
    begin
      @(negedge clk);
      ui_in = value;
      uio_in[0] = 1'b1;
      uio_in[1] = 1'b1;
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

  task get_response;
    output [7:0] value;
    integer t;
    begin
      t = 0;
      uio_in[1] = 1'b1;
      while (!uio_out[1] && t < 100) begin
        @(posedge clk);
        t = t + 1;
      end
      #1;
      if (!uio_out[1]) begin
        $display("FAIL: timeout waiting for response");
        errors = errors + 1;
        value = 8'hxx;
      end else begin
        value = uo_out;
      end
      @(posedge clk);
      @(negedge clk);
      uio_in[1] = 1'b0;
    end
  endtask

  task expect_response;
    input [7:0] expected;
    reg [7:0] value;
    begin
      get_response(value);
      if (value !== expected) begin
        $display("FAIL: response got=%02x expected=%02x", value, expected);
        errors = errors + 1;
      end
    end
  endtask

  task send_cmd_expect;
    input [7:0] cmd;
    input [7:0] expected;
    begin
      send_byte_no_resp(cmd);
      expect_response(expected);
    end
  endtask

  task set_len_le;
    input [7:0] cmd;
    input [31:0] len;
    input [7:0] expected;
    begin
      send_byte_no_resp(cmd);
      send_byte_no_resp(len[7:0]);
      send_byte_no_resp(len[15:8]);
      send_byte_no_resp(len[23:16]);
      send_byte_no_resp(len[31:24]);
      expect_response(expected);
    end
  endtask

  task send_u128;
    input [7:0] cmd;
    input [127:0] value;
    input [7:0] expected;
    begin
      send_byte_no_resp(cmd);
      for (i = 0; i < 16; i = i + 1) send_byte_no_resp(byte_from_u128(value, i));
      expect_response(expected);
    end
  endtask

  task send_bytes_from_blocks;
    input [7:0] cmd;
    input integer nbytes;
    input [127:0] block0;
    input [127:0] block1;
    input [7:0] expected;
    begin
      send_byte_no_resp(cmd);
      for (i = 0; i < nbytes; i = i + 1) send_byte_no_resp(byte_from_two_blocks(block0, block1, i));
      expect_response(expected);
    end
  endtask

  task read_indexed;
    input [7:0] cmd;
    input [7:0] index;
    output [7:0] value;
    begin
      send_byte_no_resp(cmd);
      send_byte_no_resp(index);
      get_response(value);
    end
  endtask

  task wait_done;
    reg [7:0] status;
    begin
      timeout = 0;
      status = 8'h00;
      while (!status[3] && timeout < 500) begin
        repeat (2) @(posedge clk);
        send_byte_no_resp(8'h21);
        get_response(status);
        timeout = timeout + 1;
      end
      if (!status[3]) begin
        $display("FAIL: timeout waiting for AEAD done status=%02x", status);
        errors = errors + 1;
      end
    end
  endtask

  task run_case7_encrypt;
    reg [7:0] got;
    reg [7:0] exp;
    begin
      send_cmd_expect(8'h40, 8'hc1);
      send_byte_no_resp(8'h01); send_byte_no_resp(8'h00); expect_response(8'ha0);

      set_len_le(8'h02, VEC_AEAD_AD_C7_AD_BYTES, 8'ha2);
      set_len_le(8'h03, VEC_AEAD_AD_C7_MSG_BYTES, 8'ha3);

      send_u128(8'h10, VEC_AEAD_AD_KEY, 8'hb0);
      send_u128(8'h11, VEC_AEAD_AD_NONCE, 8'hb1);
      send_bytes_from_blocks(8'h12, VEC_AEAD_AD_C7_AD_BYTES, VEC_AEAD_AD_C7_AD0, VEC_AEAD_AD_C7_AD1, 8'hb2);
      send_bytes_from_blocks(8'h13, VEC_AEAD_AD_C7_MSG_BYTES, VEC_AEAD_AD_C7_PT0, VEC_AEAD_AD_C7_PT1, 8'hb3);

      send_cmd_expect(8'h20, 8'hd0);
      wait_done();

      for (i = 0; i < VEC_AEAD_AD_C7_MSG_BYTES; i = i + 1) begin
        read_indexed(8'h30, i[7:0], got);
        exp = byte_from_two_blocks(VEC_AEAD_AD_C7_CT0, VEC_AEAD_AD_C7_CT1, i);
        if (got !== exp) begin
          $display("FAIL ENC out byte %0d got=%02x exp=%02x", i, got, exp);
          errors = errors + 1;
        end
      end

      for (i = 0; i < 16; i = i + 1) begin
        read_indexed(8'h31, i[7:0], got);
        exp = byte_from_u128(VEC_AEAD_AD_C7_TAG, i);
        if (got !== exp) begin
          $display("FAIL ENC tag byte %0d got=%02x exp=%02x", i, got, exp);
          errors = errors + 1;
        end
      end
    end
  endtask

  task run_case7_decrypt;
    reg [7:0] got;
    reg [7:0] exp;
    reg [7:0] status;
    begin
      send_cmd_expect(8'h40, 8'hc1);
      send_byte_no_resp(8'h01); send_byte_no_resp(8'h01); expect_response(8'ha1);

      set_len_le(8'h02, VEC_AEAD_AD_C7_AD_BYTES, 8'ha2);
      set_len_le(8'h03, VEC_AEAD_AD_C7_MSG_BYTES, 8'ha3);

      send_u128(8'h10, VEC_AEAD_AD_KEY, 8'hb0);
      send_u128(8'h11, VEC_AEAD_AD_NONCE, 8'hb1);
      send_bytes_from_blocks(8'h12, VEC_AEAD_AD_C7_AD_BYTES, VEC_AEAD_AD_C7_AD0, VEC_AEAD_AD_C7_AD1, 8'hb2);
      send_bytes_from_blocks(8'h13, VEC_AEAD_AD_C7_MSG_BYTES, VEC_AEAD_AD_C7_CT0, VEC_AEAD_AD_C7_CT1, 8'hb3);
      send_u128(8'h14, VEC_AEAD_AD_C7_TAG, 8'hb4);

      send_cmd_expect(8'h20, 8'hd0);
      wait_done();

      send_byte_no_resp(8'h21);
      get_response(status);
      if (!status[4]) begin
        $display("FAIL DEC auth_ok low status=%02x", status);
        errors = errors + 1;
      end

      for (i = 0; i < VEC_AEAD_AD_C7_MSG_BYTES; i = i + 1) begin
        read_indexed(8'h30, i[7:0], got);
        exp = byte_from_two_blocks(VEC_AEAD_AD_C7_PT0, VEC_AEAD_AD_C7_PT1, i);
        if (got !== exp) begin
          $display("FAIL DEC out byte %0d got=%02x exp=%02x", i, got, exp);
          errors = errors + 1;
        end
      end
    end
  endtask

  initial begin
    errors = 0;
    reset_dut();

    if (uio_oe !== 8'b0011_1111) begin
      $display("FAIL: uio_oe got=%02x", uio_oe);
      errors = errors + 1;
    end

    run_case7_encrypt();
    run_case7_decrypt();

    if (errors == 0) begin
      $display("ALL ASCON TT FULL AEAD VECTOR TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT FULL AEAD VECTOR TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
