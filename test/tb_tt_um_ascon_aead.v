`timescale 1ns/1ps
`default_nettype none

module tb_tt_um_ascon_aead;
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
  reg [7:0] expected_xor;

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
      uio_in[0] = 1'b1; // in_valid
      uio_in[1] = 1'b1; // out_ready
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

  task expect_response;
    input [7:0] expected;
    integer timeout;
    begin
      timeout = 0;
      uio_in[1] = 1'b1; // out_ready
      while (!uio_out[1] && timeout < 30) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      #1;
      if (!uio_out[1]) begin
        $display("FAIL: timeout waiting for response %02x", expected);
        errors = errors + 1;
      end else if (uo_out !== expected) begin
        $display("FAIL: response got=%02x expected=%02x", uo_out, expected);
        errors = errors + 1;
      end
      @(posedge clk);
      @(negedge clk);
      uio_in[1] = 1'b0;
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

  task send_cmd_payload_expect;
    input [7:0] cmd;
    input integer nbytes;
    input [7:0] base;
    input [7:0] expected;
    integer j;
    begin
      send_byte_no_resp(cmd);
      for (j = 0; j < nbytes; j = j + 1) begin
        send_byte_no_resp(base + j[7:0]);
      end
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

  function [7:0] xor_range;
    input [7:0] base;
    input integer nbytes;
    integer j;
    begin
      xor_range = 8'd0;
      for (j = 0; j < nbytes; j = j + 1) begin
        xor_range = xor_range ^ (base + j[7:0]);
      end
    end
  endfunction

  initial begin
    errors = 0;
    reset_dut();

    if (uio_oe !== 8'b0011_1111) begin
      $display("FAIL: uio_oe got=%02x", uio_oe);
      errors = errors + 1;
    end

    send_cmd_expect(8'h40, 8'hc1); // CLEAR

    // SET_MODE decrypt
    send_byte_no_resp(8'h01);
    send_byte_no_resp(8'h01);
    expect_response(8'ha1);

    send_cmd_expect(8'h50, 8'h01); // READ_MODE

    set_len_le(8'h02, 32'd17, 8'ha2); // SET_AD_BYTES
    set_len_le(8'h03, 32'd31, 8'ha3); // SET_MSG_BYTES

    send_cmd_payload_expect(8'h10, 16, 8'h10, 8'hb0); // LOAD_KEY
    expected_xor = xor_range(8'h10, 16);
    send_cmd_expect(8'h53, expected_xor);

    send_cmd_payload_expect(8'h11, 16, 8'h30, 8'hb1); // LOAD_NONCE
    expected_xor = xor_range(8'h30, 16);
    send_cmd_expect(8'h54, expected_xor);

    send_cmd_payload_expect(8'h12, 17, 8'h80, 8'hb2); // LOAD_AD
    send_cmd_expect(8'h51, 8'd17);
    expected_xor = xor_range(8'h80, 17);
    send_cmd_expect(8'h56, expected_xor);

    send_cmd_payload_expect(8'h13, 31, 8'ha0, 8'hb3); // LOAD_DATA
    send_cmd_expect(8'h52, 8'd31);
    expected_xor = xor_range(8'ha0, 31);
    send_cmd_expect(8'h57, expected_xor);

    send_cmd_payload_expect(8'h14, 16, 8'hc0, 8'hb4); // LOAD_TAG
    expected_xor = xor_range(8'hc0, 16);
    send_cmd_expect(8'h55, expected_xor);

    // START stub should accept because key, nonce, and decrypt tag are loaded.
    send_cmd_expect(8'h20, 8'hd0);

    // Status: alive=1, mode=1, done=1, auth_ok=1, key_loaded=1, nonce_loaded=1.
    // busy should be 0 once response is consumed; error should be 0.
    send_cmd_expect(8'h21, 8'hdb);

    send_cmd_expect(8'hff, 8'hee);

    if (errors == 0) begin
      $display("ALL ASCON TT BYTE FRONTEND TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT BYTE FRONTEND TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
