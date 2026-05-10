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

  task send_byte;
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
      while (!uio_out[1] && timeout < 20) begin
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

  initial begin
    errors = 0;
    reset_dut();

    if (uio_oe !== 8'b0011_1111) begin
      $display("FAIL: uio_oe got=%02x", uio_oe);
      errors = errors + 1;
    end

    send_byte(8'h01); // SET_MODE
    send_byte(8'h01); // decrypt
    expect_response(8'h4b);

    send_byte(8'h21); // STATUS
    // Status bit layout: {00,error,auth_ok,done,busy,mode,1}
    expect_response(8'h03);

    send_byte(8'h40); // CLEAR
    expect_response(8'hc1);

    send_byte(8'hff); // invalid
    expect_response(8'hee);

    if (errors == 0) begin
      $display("ALL ASCON TT SCAFFOLD TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT SCAFFOLD TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
