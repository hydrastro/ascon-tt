`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// TT-1 serial frontend skeleton.
//
// This module intentionally implements only a tiny command/status shell.  The
// full AEAD byte-store and shared AEAD FSM will be added incrementally.

module ascon_tt_serial_frontend (
  input  wire       clk,
  input  wire       rst_n,
  input  wire       ena_i,

  input  wire [7:0] cmd_data_i,
  output reg  [7:0] resp_o,

  input  wire       in_valid_i,
  output wire       in_ready_o,

  input  wire       out_ready_i,
  output reg        out_valid_o,

  output wire       busy_o,
  output reg        done_o,
  output reg        auth_ok_o,
  output reg        error_o
);

  localparam [7:0] CMD_NOP       = 8'h00;
  localparam [7:0] CMD_SET_MODE  = 8'h01;
  localparam [7:0] CMD_STATUS    = 8'h21;
  localparam [7:0] CMD_CLEAR     = 8'h40;

  localparam [2:0] ST_IDLE       = 3'd0;
  localparam [2:0] ST_WAIT_MODE  = 3'd1;
  localparam [2:0] ST_RESP       = 3'd2;

  reg [2:0] state_q;
  reg       mode_decrypt_q;

  wire in_fire_w  = in_valid_i && in_ready_o;
  wire out_fire_w = out_valid_o && out_ready_i;

  assign in_ready_o = ena_i && !out_valid_o;
  assign busy_o = (state_q != ST_IDLE);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q <= ST_IDLE;
      mode_decrypt_q <= 1'b0;
      resp_o <= 8'h00;
      out_valid_o <= 1'b0;
      done_o <= 1'b0;
      auth_ok_o <= 1'b0;
      error_o <= 1'b0;
    end else begin
      done_o <= 1'b0;

      if (out_fire_w) begin
        out_valid_o <= 1'b0;
        if (state_q == ST_RESP) begin
          state_q <= ST_IDLE;
        end
      end

      if (in_fire_w) begin
        case (state_q)
          ST_IDLE: begin
            case (cmd_data_i)
              CMD_NOP: begin
              end

              CMD_CLEAR: begin
                mode_decrypt_q <= 1'b0;
                resp_o <= 8'hc1;
                out_valid_o <= 1'b1;
                done_o <= 1'b0;
                auth_ok_o <= 1'b0;
                error_o <= 1'b0;
                state_q <= ST_RESP;
              end

              CMD_SET_MODE: begin
                state_q <= ST_WAIT_MODE;
              end

              CMD_STATUS: begin
                resp_o <= {2'b00, error_o, auth_ok_o, done_o, busy_o, mode_decrypt_q, 1'b1};
                out_valid_o <= 1'b1;
                state_q <= ST_RESP;
              end

              default: begin
                error_o <= 1'b1;
                resp_o <= 8'hee;
                out_valid_o <= 1'b1;
                state_q <= ST_RESP;
              end
            endcase
          end

          ST_WAIT_MODE: begin
            mode_decrypt_q <= cmd_data_i[0];
            resp_o <= {7'h25, cmd_data_i[0]};
            out_valid_o <= 1'b1;
            state_q <= ST_RESP;
          end

          default: begin
            state_q <= ST_IDLE;
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
