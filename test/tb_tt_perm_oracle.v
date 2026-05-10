`timescale 1ns/1ps
`default_nettype none

// TT-3.1 integration-hardening test.
//
// This test verifies the Tiny Tapeout byte protocol and byte ordering against
// a direct oracle instance of the verified ascon_perm_unrolled core.

module tb_tt_perm_oracle;
  reg [7:0] ui_in;
  wire [7:0] uo_out;
  reg [7:0] uio_in;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  reg ena;
  reg clk;
  reg rst_n;

  reg oracle_start;
  reg [3:0] oracle_rounds;
  reg [319:0] oracle_state_i;
  wire [319:0] oracle_state_o;
  wire oracle_busy;
  wire oracle_done;

  integer errors;
  integer i;
  integer timeout;
  reg [7:0] response;
  reg [7:0] expected_byte;
  reg [319:0] input_state;

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

  ascon_perm_unrolled #(
    .ROUNDS_PER_CYCLE(1)
  ) oracle (
    .clk(clk),
    .rst_n(rst_n),
    .start_i(oracle_start),
    .rounds_i(oracle_rounds),
    .state_i(oracle_state_i),
    .state_o(oracle_state_o),
    .busy_o(oracle_busy),
    .done_o(oracle_done)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  function [7:0] state_byte;
    input [319:0] state;
    input integer index;
    begin
      case (index)
        0:  state_byte = state[319:312];
        1:  state_byte = state[311:304];
        2:  state_byte = state[303:296];
        3:  state_byte = state[295:288];
        4:  state_byte = state[287:280];
        5:  state_byte = state[279:272];
        6:  state_byte = state[271:264];
        7:  state_byte = state[263:256];
        8:  state_byte = state[255:248];
        9:  state_byte = state[247:240];
        10: state_byte = state[239:232];
        11: state_byte = state[231:224];
        12: state_byte = state[223:216];
        13: state_byte = state[215:208];
        14: state_byte = state[207:200];
        15: state_byte = state[199:192];
        16: state_byte = state[191:184];
        17: state_byte = state[183:176];
        18: state_byte = state[175:168];
        19: state_byte = state[167:160];
        20: state_byte = state[159:152];
        21: state_byte = state[151:144];
        22: state_byte = state[143:136];
        23: state_byte = state[135:128];
        24: state_byte = state[127:120];
        25: state_byte = state[119:112];
        26: state_byte = state[111:104];
        27: state_byte = state[103:96];
        28: state_byte = state[95:88];
        29: state_byte = state[87:80];
        30: state_byte = state[79:72];
        31: state_byte = state[71:64];
        32: state_byte = state[63:56];
        33: state_byte = state[55:48];
        34: state_byte = state[47:40];
        35: state_byte = state[39:32];
        36: state_byte = state[31:24];
        37: state_byte = state[23:16];
        38: state_byte = state[15:8];
        39: state_byte = state[7:0];
        default: state_byte = 8'h00;
      endcase
    end
  endfunction

  function [319:0] make_state;
    integer j;
    reg [319:0] tmp;
    begin
      tmp = 320'd0;
      for (j = 0; j < 40; j = j + 1) begin
        tmp[((39 - j) * 8) +: 8] = (8'h80 ^ j[7:0] ^ (j[7:0] << 1));
      end
      make_state = tmp;
    end
  endfunction

  task reset_dut;
    begin
      ui_in <= 8'h00;
      uio_in <= 8'h00;
      ena <= 1'b1;
      oracle_start <= 1'b0;
      oracle_rounds <= 4'd12;
      oracle_state_i <= 320'd0;
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

  task read_state_byte;
    input [7:0] index;
    output [7:0] value;
    begin
      send_byte_no_resp(8'h64);
      send_byte_no_resp(index);
      get_response(value);
    end
  endtask

  task run_oracle;
    begin
      @(negedge clk);
      oracle_state_i = input_state;
      oracle_rounds = 4'd12;
      oracle_start = 1'b1;
      @(posedge clk);
      @(negedge clk);
      oracle_start = 1'b0;

      timeout = 0;
      while (!oracle_done && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end

      if (!oracle_done) begin
        $display("FAIL: oracle timeout");
        errors = errors + 1;
      end
    end
  endtask

  task run_tt_perm;
    reg [7:0] status;
    begin
      send_cmd_expect(8'h40, 8'hc1);

      send_byte_no_resp(8'h60);
      for (i = 0; i < 40; i = i + 1) begin
        send_byte_no_resp(state_byte(input_state, i));
      end
      expect_response(8'hc6);

      send_byte_no_resp(8'h61);
      send_byte_no_resp(8'd12);
      expect_response(8'ha6);

      send_cmd_expect(8'h62, 8'hd6);

      timeout = 0;
      status = 8'h00;
      while (!status[3] && timeout < 100) begin
        repeat (2) @(posedge clk);
        send_byte_no_resp(8'h21);
        get_response(status);
        timeout = timeout + 1;
      end

      if (!status[3]) begin
        $display("FAIL: TT permutation timeout, status=%02x", status);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    input_state = make_state();

    reset_dut();

    if (uio_oe !== 8'b0011_1111) begin
      $display("FAIL: uio_oe got=%02x", uio_oe);
      errors = errors + 1;
    end

    run_oracle();
    run_tt_perm();

    for (i = 0; i < 40; i = i + 1) begin
      read_state_byte(i[7:0], response);
      expected_byte = state_byte(oracle_state_o, i);
      if (response !== expected_byte) begin
        $display("FAIL: state byte %0d got=%02x expected=%02x", i, response, expected_byte);
        errors = errors + 1;
      end
    end

    if (errors == 0) begin
      $display("ALL ASCON TT PERM ORACLE TESTS PASSED");
      $finish;
    end else begin
      $display("ASCON TT PERM ORACLE TESTS FAILED errors=%0d", errors);
      $fatal;
    end
  end

endmodule

`default_nettype wire
