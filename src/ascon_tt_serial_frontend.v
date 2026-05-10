`timescale 1ns/1ps
`default_nettype none
// SPDX-License-Identifier: Apache-2.0

// TT-3 serial byte frontend.
//
// Implements the byte command protocol, the TT-2 job-loading storage layer,
// and TT-3 permutation-engine integration.  Full AEAD execution is still stubbed
// behind CMD_START; the new permutation commands validate the shared permutation
// datapath that full AEAD will reuse.

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

  localparam [7:0] CMD_NOP              = 8'h00;
  localparam [7:0] CMD_SET_MODE         = 8'h01;
  localparam [7:0] CMD_SET_AD_BYTES     = 8'h02;
  localparam [7:0] CMD_SET_MSG_BYTES    = 8'h03;

  localparam [7:0] CMD_LOAD_KEY         = 8'h10;
  localparam [7:0] CMD_LOAD_NONCE       = 8'h11;
  localparam [7:0] CMD_LOAD_AD          = 8'h12;
  localparam [7:0] CMD_LOAD_DATA        = 8'h13;
  localparam [7:0] CMD_LOAD_TAG         = 8'h14;

  localparam [7:0] CMD_START            = 8'h20;
  localparam [7:0] CMD_STATUS           = 8'h21;

  localparam [7:0] CMD_CLEAR            = 8'h40;

  localparam [7:0] CMD_READ_MODE        = 8'h50;
  localparam [7:0] CMD_READ_AD_COUNT    = 8'h51;
  localparam [7:0] CMD_READ_DATA_COUNT  = 8'h52;
  localparam [7:0] CMD_READ_KEY_XOR     = 8'h53;
  localparam [7:0] CMD_READ_NONCE_XOR   = 8'h54;
  localparam [7:0] CMD_READ_TAG_XOR     = 8'h55;
  localparam [7:0] CMD_READ_AD_XOR      = 8'h56;
  localparam [7:0] CMD_READ_DATA_XOR    = 8'h57;

  localparam [7:0] CMD_LOAD_STATE       = 8'h60;
  localparam [7:0] CMD_SET_ROUNDS       = 8'h61;
  localparam [7:0] CMD_START_PERM       = 8'h62;
  localparam [7:0] CMD_READ_STATE_XOR   = 8'h63;
  localparam [7:0] CMD_READ_STATE_BYTE  = 8'h64;

  localparam [2:0] ST_IDLE              = 3'd0;
  localparam [2:0] ST_RECV              = 3'd1;
  localparam [2:0] ST_RESP              = 3'd2;

  reg [2:0] state_q;
  reg [7:0] active_cmd_q;
  reg [31:0] remaining_q;
  reg [7:0] byte_idx_q;
  reg [31:0] temp_len_q;

  reg       mode_decrypt_q;
  reg [31:0] ad_bytes_q;
  reg [31:0] msg_bytes_q;

  reg [127:0] key_q;
  reg [127:0] nonce_q;
  reg [127:0] tag_q;

  reg key_loaded_q;
  reg nonce_loaded_q;
  reg tag_loaded_q;

  reg [31:0] ad_count_q;
  reg [31:0] data_count_q;

  reg [7:0] key_xor_q;
  reg [7:0] nonce_xor_q;
  reg [7:0] tag_xor_q;
  reg [7:0] ad_xor_q;
  reg [7:0] data_xor_q;

  reg [3:0] perm_rounds_q;
  reg       perm_start_q;
  reg       perm_clear_q;
  reg       perm_load_valid_q;
  reg [5:0] perm_load_index_q;
  reg [7:0] perm_load_byte_q;
  reg [5:0] perm_read_index_q;
  reg       perm_done_seen_q;

  wire in_fire_w  = in_valid_i && in_ready_o;
  wire out_fire_w = out_valid_o && out_ready_i;

  wire [5:0] perm_read_index_w =
    (in_fire_w && (state_q == ST_RECV) && (active_cmd_q == CMD_READ_STATE_BYTE)) ?
    cmd_data_i[5:0] : perm_read_index_q;

  wire [7:0] perm_read_byte_w;
  wire [7:0] perm_state_xor_w;
  wire       perm_busy_w;
  wire       perm_done_w;

  assign in_ready_o = ena_i && !out_valid_o && !perm_start_q;
  assign busy_o = (state_q != ST_IDLE) || perm_busy_w;

  function [31:0] insert_byte32;
    input [31:0] old_v;
    input [1:0]  index;
    input [7:0]  byte_v;
    begin
      insert_byte32 = old_v;
      case (index)
        2'd0: insert_byte32[7:0]   = byte_v;
        2'd1: insert_byte32[15:8]  = byte_v;
        2'd2: insert_byte32[23:16] = byte_v;
        default: insert_byte32[31:24] = byte_v;
      endcase
    end
  endfunction

  function [127:0] insert_byte128;
    input [127:0] old_v;
    input [3:0]   index;
    input [7:0]   byte_v;
    begin
      insert_byte128 = old_v;
      case (index)
        4'd0:  insert_byte128[7:0]     = byte_v;
        4'd1:  insert_byte128[15:8]    = byte_v;
        4'd2:  insert_byte128[23:16]   = byte_v;
        4'd3:  insert_byte128[31:24]   = byte_v;
        4'd4:  insert_byte128[39:32]   = byte_v;
        4'd5:  insert_byte128[47:40]   = byte_v;
        4'd6:  insert_byte128[55:48]   = byte_v;
        4'd7:  insert_byte128[63:56]   = byte_v;
        4'd8:  insert_byte128[71:64]   = byte_v;
        4'd9:  insert_byte128[79:72]   = byte_v;
        4'd10: insert_byte128[87:80]   = byte_v;
        4'd11: insert_byte128[95:88]   = byte_v;
        4'd12: insert_byte128[103:96]  = byte_v;
        4'd13: insert_byte128[111:104] = byte_v;
        4'd14: insert_byte128[119:112] = byte_v;
        default: insert_byte128[127:120] = byte_v;
      endcase
    end
  endfunction

  function [7:0] status_byte;
    begin
      status_byte[0] = 1'b1;             // alive
      status_byte[1] = mode_decrypt_q;
      status_byte[2] = busy_o;
      status_byte[3] = done_o;
      status_byte[4] = auth_ok_o;
      status_byte[5] = error_o;
      status_byte[6] = key_loaded_q;
      status_byte[7] = nonce_loaded_q;
    end
  endfunction

  task clear_all;
    begin
      state_q <= ST_IDLE;
      active_cmd_q <= CMD_NOP;
      remaining_q <= 32'd0;
      byte_idx_q <= 8'd0;
      temp_len_q <= 32'd0;

      mode_decrypt_q <= 1'b0;
      ad_bytes_q <= 32'd0;
      msg_bytes_q <= 32'd0;
      key_q <= 128'd0;
      nonce_q <= 128'd0;
      tag_q <= 128'd0;

      key_loaded_q <= 1'b0;
      nonce_loaded_q <= 1'b0;
      tag_loaded_q <= 1'b0;

      ad_count_q <= 32'd0;
      data_count_q <= 32'd0;

      key_xor_q <= 8'd0;
      nonce_xor_q <= 8'd0;
      tag_xor_q <= 8'd0;
      ad_xor_q <= 8'd0;
      data_xor_q <= 8'd0;

      perm_rounds_q <= 4'd12;
      perm_start_q <= 1'b0;
      perm_clear_q <= 1'b1;
      perm_load_valid_q <= 1'b0;
      perm_load_index_q <= 6'd0;
      perm_load_byte_q <= 8'd0;
      perm_read_index_q <= 6'd0;
      perm_done_seen_q <= 1'b0;

      resp_o <= 8'h00;
      out_valid_o <= 1'b0;
      done_o <= 1'b0;
      auth_ok_o <= 1'b0;
      error_o <= 1'b0;
    end
  endtask

  task issue_response;
    input [7:0] value;
    begin
      resp_o <= value;
      out_valid_o <= 1'b1;
      state_q <= ST_RESP;
    end
  endtask

  /* verilator lint_off UNUSED */
  wire _unused_storage_reduce = ^{key_q, nonce_q, tag_q, tag_loaded_q, ad_bytes_q[31:8], msg_bytes_q[31:8], ad_count_q[31:8], data_count_q[31:8], perm_done_seen_q};
  /* verilator lint_on UNUSED */

  ascon_tt_perm_core u_perm_core (
    .clk          (clk),
    .rst_n        (rst_n),
    .clear_i      (perm_clear_q),
    .load_valid_i (perm_load_valid_q),
    .load_index_i (perm_load_index_q),
    .load_byte_i  (perm_load_byte_q),
    .read_index_i (perm_read_index_w),
    .read_byte_o  (perm_read_byte_w),
    .state_xor_o  (perm_state_xor_w),
    .rounds_i     (perm_rounds_q),
    .start_i      (perm_start_q),
    .busy_o       (perm_busy_w),
    .done_o       (perm_done_w)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      clear_all();
    end else begin
      perm_start_q <= 1'b0;
      perm_clear_q <= 1'b0;
      perm_load_valid_q <= 1'b0;

      if (perm_done_w) begin
        done_o <= 1'b1;
        perm_done_seen_q <= 1'b1;
      end

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
                clear_all();
                issue_response(8'hc1);
              end

              CMD_SET_MODE: begin
                active_cmd_q <= CMD_SET_MODE;
                remaining_q <= 32'd1;
                byte_idx_q <= 8'd0;
                state_q <= ST_RECV;
              end

              CMD_SET_AD_BYTES: begin
                active_cmd_q <= CMD_SET_AD_BYTES;
                remaining_q <= 32'd4;
                byte_idx_q <= 8'd0;
                temp_len_q <= 32'd0;
                ad_count_q <= 32'd0;
                ad_xor_q <= 8'd0;
                state_q <= ST_RECV;
              end

              CMD_SET_MSG_BYTES: begin
                active_cmd_q <= CMD_SET_MSG_BYTES;
                remaining_q <= 32'd4;
                byte_idx_q <= 8'd0;
                temp_len_q <= 32'd0;
                data_count_q <= 32'd0;
                data_xor_q <= 8'd0;
                state_q <= ST_RECV;
              end

              CMD_LOAD_KEY: begin
                active_cmd_q <= CMD_LOAD_KEY;
                remaining_q <= 32'd16;
                byte_idx_q <= 8'd0;
                key_q <= 128'd0;
                key_xor_q <= 8'd0;
                key_loaded_q <= 1'b0;
                state_q <= ST_RECV;
              end

              CMD_LOAD_NONCE: begin
                active_cmd_q <= CMD_LOAD_NONCE;
                remaining_q <= 32'd16;
                byte_idx_q <= 8'd0;
                nonce_q <= 128'd0;
                nonce_xor_q <= 8'd0;
                nonce_loaded_q <= 1'b0;
                state_q <= ST_RECV;
              end

              CMD_LOAD_AD: begin
                if (ad_bytes_q == 32'd0) begin
                  issue_response(8'hb2);
                end else begin
                  active_cmd_q <= CMD_LOAD_AD;
                  remaining_q <= ad_bytes_q;
                  byte_idx_q <= 8'd0;
                  ad_count_q <= 32'd0;
                  ad_xor_q <= 8'd0;
                  state_q <= ST_RECV;
                end
              end

              CMD_LOAD_DATA: begin
                if (msg_bytes_q == 32'd0) begin
                  issue_response(8'hb3);
                end else begin
                  active_cmd_q <= CMD_LOAD_DATA;
                  remaining_q <= msg_bytes_q;
                  byte_idx_q <= 8'd0;
                  data_count_q <= 32'd0;
                  data_xor_q <= 8'd0;
                  state_q <= ST_RECV;
                end
              end

              CMD_LOAD_TAG: begin
                active_cmd_q <= CMD_LOAD_TAG;
                remaining_q <= 32'd16;
                byte_idx_q <= 8'd0;
                tag_q <= 128'd0;
                tag_xor_q <= 8'd0;
                tag_loaded_q <= 1'b0;
                state_q <= ST_RECV;
              end

              CMD_START: begin
                // Full AEAD still stubbed until TT-4.
                if (key_loaded_q && nonce_loaded_q && ((mode_decrypt_q == 1'b0) || tag_loaded_q)) begin
                  done_o <= 1'b1;
                  auth_ok_o <= 1'b1;
                  error_o <= 1'b0;
                  issue_response(8'hd0);
                end else begin
                  done_o <= 1'b0;
                  auth_ok_o <= 1'b0;
                  error_o <= 1'b1;
                  issue_response(8'he1);
                end
              end

              CMD_STATUS: begin
                issue_response(status_byte());
              end

              CMD_READ_MODE:       issue_response({7'd0, mode_decrypt_q});
              CMD_READ_AD_COUNT:   issue_response(ad_count_q[7:0]);
              CMD_READ_DATA_COUNT: issue_response(data_count_q[7:0]);
              CMD_READ_KEY_XOR:    issue_response(key_xor_q);
              CMD_READ_NONCE_XOR:  issue_response(nonce_xor_q);
              CMD_READ_TAG_XOR:    issue_response(tag_xor_q);
              CMD_READ_AD_XOR:     issue_response(ad_xor_q);
              CMD_READ_DATA_XOR:   issue_response(data_xor_q);

              CMD_LOAD_STATE: begin
                active_cmd_q <= CMD_LOAD_STATE;
                remaining_q <= 32'd40;
                byte_idx_q <= 8'd0;
                perm_clear_q <= 1'b1;
                perm_done_seen_q <= 1'b0;
                done_o <= 1'b0;
                state_q <= ST_RECV;
              end

              CMD_SET_ROUNDS: begin
                active_cmd_q <= CMD_SET_ROUNDS;
                remaining_q <= 32'd1;
                byte_idx_q <= 8'd0;
                state_q <= ST_RECV;
              end

              CMD_START_PERM: begin
                if (perm_busy_w) begin
                  error_o <= 1'b1;
                  issue_response(8'he6);
                end else begin
                  done_o <= 1'b0;
                  auth_ok_o <= 1'b0;
                  error_o <= 1'b0;
                  perm_done_seen_q <= 1'b0;
                  perm_start_q <= 1'b1;
                  issue_response(8'hd6);
                end
              end

              CMD_READ_STATE_XOR: begin
                issue_response(perm_state_xor_w);
              end

              CMD_READ_STATE_BYTE: begin
                active_cmd_q <= CMD_READ_STATE_BYTE;
                remaining_q <= 32'd1;
                byte_idx_q <= 8'd0;
                state_q <= ST_RECV;
              end

              default: begin
                error_o <= 1'b1;
                issue_response(8'hee);
              end
            endcase
          end

          ST_RECV: begin
            case (active_cmd_q)
              CMD_SET_MODE: begin
                mode_decrypt_q <= cmd_data_i[0];
                issue_response(8'ha0 | {7'd0, cmd_data_i[0]});
              end

              CMD_SET_AD_BYTES: begin
                temp_len_q <= insert_byte32(temp_len_q, byte_idx_q[1:0], cmd_data_i);
                if (remaining_q == 32'd1) begin
                  ad_bytes_q <= insert_byte32(temp_len_q, byte_idx_q[1:0], cmd_data_i);
                  issue_response(8'ha2);
                end
              end

              CMD_SET_MSG_BYTES: begin
                temp_len_q <= insert_byte32(temp_len_q, byte_idx_q[1:0], cmd_data_i);
                if (remaining_q == 32'd1) begin
                  msg_bytes_q <= insert_byte32(temp_len_q, byte_idx_q[1:0], cmd_data_i);
                  issue_response(8'ha3);
                end
              end

              CMD_LOAD_KEY: begin
                key_q <= insert_byte128(key_q, byte_idx_q[3:0], cmd_data_i);
                key_xor_q <= key_xor_q ^ cmd_data_i;
                if (remaining_q == 32'd1) begin
                  key_loaded_q <= 1'b1;
                  issue_response(8'hb0);
                end
              end

              CMD_LOAD_NONCE: begin
                nonce_q <= insert_byte128(nonce_q, byte_idx_q[3:0], cmd_data_i);
                nonce_xor_q <= nonce_xor_q ^ cmd_data_i;
                if (remaining_q == 32'd1) begin
                  nonce_loaded_q <= 1'b1;
                  issue_response(8'hb1);
                end
              end

              CMD_LOAD_AD: begin
                ad_count_q <= ad_count_q + 32'd1;
                ad_xor_q <= ad_xor_q ^ cmd_data_i;
                if (remaining_q == 32'd1) begin
                  issue_response(8'hb2);
                end
              end

              CMD_LOAD_DATA: begin
                data_count_q <= data_count_q + 32'd1;
                data_xor_q <= data_xor_q ^ cmd_data_i;
                if (remaining_q == 32'd1) begin
                  issue_response(8'hb3);
                end
              end

              CMD_LOAD_TAG: begin
                tag_q <= insert_byte128(tag_q, byte_idx_q[3:0], cmd_data_i);
                tag_xor_q <= tag_xor_q ^ cmd_data_i;
                if (remaining_q == 32'd1) begin
                  tag_loaded_q <= 1'b1;
                  issue_response(8'hb4);
                end
              end

              CMD_LOAD_STATE: begin
                perm_load_valid_q <= 1'b1;
                perm_load_index_q <= byte_idx_q[5:0];
                perm_load_byte_q <= cmd_data_i;
                if (remaining_q == 32'd1) begin
                  issue_response(8'hc6);
                end
              end

              CMD_SET_ROUNDS: begin
                if ((cmd_data_i == 8'd6) || (cmd_data_i == 8'd8) || (cmd_data_i == 8'd12)) begin
                  perm_rounds_q <= cmd_data_i[3:0];
                  issue_response(8'ha6);
                end else begin
                  error_o <= 1'b1;
                  issue_response(8'hea);
                end
              end

              CMD_READ_STATE_BYTE: begin
                perm_read_index_q <= cmd_data_i[5:0];
                issue_response(perm_read_byte_w);
              end

              default: begin
                error_o <= 1'b1;
                issue_response(8'hef);
              end
            endcase

            if (state_q == ST_RECV) begin
              byte_idx_q <= byte_idx_q + 8'd1;
              if (remaining_q != 32'd0) begin
                remaining_q <= remaining_q - 32'd1;
              end
            end
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
