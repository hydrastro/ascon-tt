`timescale 1ns/1ps
`default_nettype none

module tb_tt_job_buffers;
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
  reg [7:0] response;
  reg [7:0] expected;

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

  function [7:0] xor_transformed_range;
    input [7:0] base;
    input integer nbytes;
    input [7:0] mask;
    integer j;
    begin
      xor_transformed_range = 8'd0;
      for (j = 0; j < nbytes; j = j + 1) begin
        xor_transformed_range = xor_transformed_range ^ ((base + j[7:0]) ^ mask);
      end
    end
  endfunction

  function [7:0] stub_tag_byte;
    input [3:0] idx;
    begin
      stub_tag_byte = xor_range(8'h10, 16) ^
                      xor_range(8'h30, 16) ^
                      xor_range(8'hc0, 16) ^
                      xor_range(8'h80, 17) ^
                      xor_range(8'ha0, 31) ^
                      {4'd0, idx};
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
      while (!uio_out[1] && t < 80) begin
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
    input [7:0] expected_value;
    reg [7:0] value;
    begin
      get_response(value);
      if (value !== expected_value) begin
        $display("FAIL: response got=%02x expected=%02x", value, expected_value);
        errors = errors + 1;
      end
    end
  endtask

  task send_cmd_expect;
    input [7:0] cmd;
    input [7:0] expected_value;
    begin
      send_byte_no_resp(cmd);
      expect_response(expected_value);
    end
  endtask

  task set_len_le;
    input [7:0] cmd;
    input [31:0] len;
    input [7:0] expected_value;
    begin
      send_byte_no_resp(cmd);
      send_byte_no_resp(len[7:0]);
      send_byte_no_resp(len[15:8]);
      send_byte_no_resp(len[23:16]);
      send_byte_no_resp(len[31:24]);
      expect_response(expected_value);
    end
  endtask

  task send_payload;
    input [7:0] cmd;
    input integer nbytes;
    input [7:0] base;
    input [7:0] expected_value;
    integer j;
    begin
      send_byte_no_resp(cmd);
      for (j = 0; j < nbytes; j = j + 1) begin
        send_byte_no_resp(base + j[7:0]);
      end
      expect_response(expected_value);
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

  initial begin
    errors = 0;
    reset_dut();

    send_cmd_expect(8'h40, 8'hc1);

    send_byte_no_resp(8'h01);
    send_byte_no_resp(8'h01);
    expect_response(8'ha1);

    set_len_le(8'h02, 32'd17, 8'ha2);
    set_len_le(8'h03, 32'd31, 8'ha3);

    send_payload(8'h10, 16, 8'h10, 8'hb0);
    send_payload(8'h11, 16, 8'h30, 8'hb1);
    send_payload(8'h12, 17, 8'h80, 8'hb2);
    send_payload(8'h13, 31, 8'ha0, 8'hb3);
    send_payload(8'h14, 16, 8'hc0, 8'hb4);

    send_cmd_expect(8'h51, 8'd17);
    send_cmd_expect(8'h52, 8'd31);
    send_cmd_expect(8'h56, xor_range(8'h80, 17));
    send_cmd_expect(8'h57, xor_range(8'ha0, 31));

    send_cmd_expect(8'h20, 8'hd0);
    send_cmd_expect(8'h21, 8'hdb);

    for (i = 0; i < 31; i = i + 1) begin
      read_indexed(8'h30, i[7:0], response);
      expected = (8'ha0 + i[7:0]) ^ 8'h5a;
      if (response !== expected) begin
        $display("FAIL: out byte %0d got=%02x expected=%02x", i, response, expected);
        errors = errors + 1;
      end
    end

    for (i = 0; i < 16; i = i + 1) begin
      read_indexed(8'h31, i[7:0], response);
      expected = stub_tag_byte(i[3:0]);
      if (response !== expected) begin
        $display("FAIL: result tag byte %0d got=%02x expected=%02x", i, response, expected);
        errors = errors + 1;
      end
    end

    send_cmd_expect(8'h58, xor_transformed_range(8'ha0, 31, 8'h5a));
    send_cmd_expect(8'h59, 8'h00);

    send_cmd_expect(8'h40, 8'hc1);
    set_len_le(8'h02, 32'd33, 8'ha2);
    send_cmd_expect(8'h12, 8'he2);

    if (errors == 0) begin
      $display("ALL ASCON TT JOB BUFFER TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT JOB BUFFER TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
