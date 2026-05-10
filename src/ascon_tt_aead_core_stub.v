`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// Placeholder for the future full AEAD engine.
//
// The final implementation should use a shared runtime encrypt/decrypt FSM and
// one RPC=1 Ascon permutation engine.  This stub is intentionally not used yet;
// it reserves the filename in info.yaml so the project structure is stable.

module ascon_tt_aead_core_stub (
  input  wire clk,
  input  wire rst_n,
  input  wire start_i,
  output reg  done_o
);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_o <= 1'b0;
    end else begin
      done_o <= start_i;
    end
  end

endmodule

`default_nettype wire
