`timescale 1ns/1ps

module tb_tt16_core_cycles;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg clear_i = 1'b0;
  reg start_i = 1'b0;
  reg decrypt_i = 1'b0;

  reg [127:0] key_i;
  reg [127:0] nonce_i;
  reg [31:0]  ad_bytes_i;
  reg [31:0]  msg_bytes_i;
  reg [127:0] tag_i;
  reg [127:0] ad_block0_i;
  reg [127:0] ad_block1_i;
  reg [127:0] data_block0_i;
  reg [127:0] data_block1_i;

  wire busy_o;
  wire done_o;
  wire auth_ok_o;
  wire [127:0] result_tag_o;
  wire [127:0] out_block0_o;
  wire [127:0] out_block1_o;

  integer cycle_ctr;
  integer start_cycle;
  integer timeout_ctr;

  always #5 clk = ~clk;

  ascon_tt_aead_bridge #(
    .ROUNDS_PER_CYCLE(1),
    .USE_SHARED_AEAD(1)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .clear_i(clear_i),
    .start_i(start_i),
    .decrypt_i(decrypt_i),
    .key_i(key_i),
    .nonce_i(nonce_i),
    .ad_bytes_i(ad_bytes_i),
    .msg_bytes_i(msg_bytes_i),
    .tag_i(tag_i),
    .ad_block0_i(ad_block0_i),
    .ad_block1_i(ad_block1_i),
    .data_block0_i(data_block0_i),
    .data_block1_i(data_block1_i),
    .busy_o(busy_o),
    .done_o(done_o),
    .auth_ok_o(auth_ok_o),
    .result_tag_o(result_tag_o),
    .out_block0_o(out_block0_o),
    .out_block1_o(out_block1_o)
  );

  always @(posedge clk) begin
    if (!rst_n) cycle_ctr <= 0;
    else cycle_ctr <= cycle_ctr + 1;
  end

  task run_case;
    input integer dec;
    input integer ad_len;
    input integer msg_len;
    begin
      @(posedge clk);
      decrypt_i <= dec[0];
      ad_bytes_i <= ad_len[31:0];
      msg_bytes_i <= msg_len[31:0];
      key_i <= 128'h000102030405060708090a0b0c0d0e0f;
      nonce_i <= 128'h101112131415161718191a1b1c1d1e1f;
      tag_i <= 128'h202122232425262728292a2b2c2d2e2f;
      ad_block0_i <= 128'h303132333435363738393a3b3c3d3e3f;
      ad_block1_i <= 128'h404142434445464748494a4b4c4d4e4f;
      data_block0_i <= 128'h505152535455565758595a5b5c5d5e5f;
      data_block1_i <= 128'h606162636465666768696a6b6c6d6e6f;

      start_i <= 1'b1;
      start_cycle = cycle_ctr;
      @(posedge clk);
      start_i <= 1'b0;

      timeout_ctr = 0;
      while (!done_o && timeout_ctr < 10000) begin
        timeout_ctr = timeout_ctr + 1;
        @(posedge clk);
      end

      if (!done_o) begin
        $display("PERF_TIMEOUT decrypt=%0d ad=%0d msg=%0d", dec, ad_len, msg_len);
      end else begin
        $display("PERF decrypt=%0d ad=%0d msg=%0d cycles=%0d", dec, ad_len, msg_len, cycle_ctr - start_cycle);
      end

      clear_i <= 1'b1;
      @(posedge clk);
      clear_i <= 1'b0;
      repeat (4) @(posedge clk);
    end
  endtask

  initial begin
    key_i = 0;
    nonce_i = 0;
    ad_bytes_i = 0;
    msg_bytes_i = 0;
    tag_i = 0;
    ad_block0_i = 0;
    ad_block1_i = 0;
    data_block0_i = 0;
    data_block1_i = 0;

    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    run_case(0,  0,  0);
    run_case(0,  0,  1);
    run_case(0,  0,  8);
    run_case(0,  0, 16);
    run_case(0,  0, 32);
    run_case(0,  8,  8);
    run_case(0, 16, 16);
    run_case(0, 32, 32);

    run_case(1,  0, 16);
    run_case(1, 16, 16);
    run_case(1, 32, 32);

    $finish;
  end
endmodule
