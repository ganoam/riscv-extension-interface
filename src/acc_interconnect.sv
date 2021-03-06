// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Noam Gallmann <gnoam@live.com>
//
// Implements one hierarchy level of the accelerator interconnnect.

`include "acc_interface/assign.svh"

module acc_interconnect #(
    // Hierarchy level
    parameter int unsigned HierLevel     = 0,
    // The number of requesters.
    parameter int          NumReq        = 0,
    // The number of rsponders.
    parameter int          NumRsp        = 0,
    // Insert Pipeline register into request path
    parameter bit          RegisterReq   = 0,
    // Insert Pipeline register into response path
    parameter bit          RegisterRsp   = 0
) (
    input clk_i,
    input rst_ni,

    // From / To accelerator adapter
    input  acc_pkg::acc_c_req_t    [NumReq-1:0] acc_c_slv_req_i,
    output acc_pkg::acc_c_rsp_t    [NumReq-1:0] acc_c_slv_rsp_o,
    output acc_pkg::acc_cmem_req_t [NumReq-1:0] acc_cmem_mst_req_o,
    input  acc_pkg::acc_cmem_rsp_t [NumReq-1:0] acc_cmem_mst_rsp_i,

    // From / To next interconnect level
    output acc_pkg::acc_c_req_t    [NumReq-1:0] acc_c_mst_next_req_o,
    input  acc_pkg::acc_c_rsp_t    [NumReq-1:0] acc_c_mst_next_rsp_i,
    input  acc_pkg::acc_cmem_req_t [NumReq-1:0] acc_cmem_slv_next_req_i,
    output acc_pkg::acc_cmem_rsp_t [NumReq-1:0] acc_cmem_slv_next_rsp_o,

    // From / To accelerator unit
    output acc_pkg::acc_c_req_t    [NumRsp-1:0] acc_c_mst_req_o,
    input  acc_pkg::acc_c_rsp_t    [NumRsp-1:0] acc_c_mst_rsp_i,
    input  acc_pkg::acc_cmem_req_t [NumRsp-1:0] acc_cmem_slv_req_i,
    output acc_pkg::acc_cmem_rsp_t [NumRsp-1:0] acc_cmem_slv_rsp_o
);

  import acc_pkg::*;

  // TODO: clearer signal naming
  // Request cross-bar index width
  localparam int unsigned IdxWidth = cf_math_pkg::idx_width(NumReq);

  // Response cross-bar index width
  localparam int unsigned OfflAddrWidth = cf_math_pkg::idx_width(NumRsp);

  // Bypass demux comparator signal width
  localparam LogNumHier = NumHier > 1 ? $clog2(NumHier) : 1;

  typedef logic [AddrWidth-1:0] addr_t;

  // Master C request: cross-bar in
  acc_c_req_chan_t [NumReq-1:0]         c_mst_req_q_chan;
  // Accelerator address
  logic [NumReq-1:0][OfflAddrWidth-1:0] c_mst_req_q_addr;
  // Hierarchy level address
  logic [NumReq-1:0][HierAddrWidth-1:0] c_mst_req_q_level;
  logic [NumReq-1:0]                    c_mst_req_q_valid;
  logic [NumReq-1:0]                    c_mst_req_p_ready;

  // Slave C request: cross-bar out
  acc_c_req_chan_t [NumRsp-1:0] c_slv_req_q_chan;
  logic [NumRsp-1:0]            c_slv_req_q_valid;
  logic [NumRsp-1:0]            c_slv_req_p_ready;

  // Slave C response: cross-bar in
  acc_c_rsp_chan_t [NumRsp-1:0] c_slv_rsp_p_chan;
  logic [NumRsp-1:0]            c_slv_rsp_p_valid;
  logic [NumRsp-1:0]            c_slv_rsp_q_ready;

  // Master C response: cross-bar out
  acc_c_rsp_chan_t [NumReq-1:0] c_mst_rsp_p_chan;
  logic [NumReq-1:0]            c_mst_rsp_p_valid;
  logic [NumReq-1:0]            c_mst_rsp_q_ready;

  // Cross-bar routing signal
  logic [NumRsp-1:0][IdxWidth-1:0] c_rsp_idx;

  // Master Cmem request: cross-bar in
  acc_cmem_req_chan_t  [NumRsp-1:0] cmem_mst_req_q_chan;
  logic [NumRsp-1:0]                cmem_mst_req_q_valid;
  logic [NumRsp-1:0]                cmem_mst_req_p_ready;

  // Slave CMem request: cross-bar out
  acc_cmem_req_chan_t [NumReq-1:0] cmem_slv_req_q_chan;
  logic [NumReq-1:0]               cmem_slv_req_q_valid;
  logic [NumReq-1:0]               cmem_slv_req_p_ready;

  // Slave Cmem response: cross-bar in
  acc_cmem_rsp_chan_t [NumReq-1:0] cmem_slv_rsp_p_chan;
  // Accelerator address
  logic [NumReq-1:0][OfflAddrWidth-1:0] cmem_slv_rsp_p_addr;
  // Hierarchy level address
  logic [NumReq-1:0][HierAddrWidth-1:0] cmem_slv_rsp_p_level;
  logic [NumReq-1:0]                    cmem_slv_rsp_p_valid;
  logic [NumReq-1:0]                    cmem_slv_rsp_q_ready;

  // Master Cmem response: cross-bar out
  acc_cmem_rsp_chan_t [NumRsp-1:0] cmem_mst_rsp_p_chan;
  logic [NumRsp-1:0]                    cmem_mst_rsp_p_valid;
  logic [NumRsp-1:0]                    cmem_mst_rsp_q_ready;

  // Cross-bar routing signal
  logic [NumRsp-1:0][IdxWidth-1:0] cmem_req_idx;

  /////////////////////////////////
  // C Req / Rsp Routing signals //
  /////////////////////////////////

  // Generate request routing signals
  // X-bar in
  for (genvar i=0; i<NumReq; i++) begin : gen_c_mst_req_assignment
    assign c_mst_req_q_chan[i]  = acc_c_slv_req_i[i].q;
    // Xbar Address
    assign c_mst_req_q_addr[i]  = acc_c_slv_req_i[i].q.addr[OfflAddrWidth-1:0];
    // Hierarchy level address
    assign c_mst_req_q_level[i] = acc_c_slv_req_i[i].q.addr[AddrWidth-1:AccAddrWidth];
  end

  // X-bar out
  for (genvar i=0; i<NumRsp; i++) begin : gen_c_slv_req_assignment
    assign acc_c_mst_req_o[i].q = c_slv_req_q_chan[i];
    assign acc_c_mst_req_o[i].q_valid = c_slv_req_q_valid[i];
    assign acc_c_mst_req_o[i].p_ready = c_slv_req_p_ready[i];
  end

  // Generate response routing signal
  // hart_id -> xbar id
  for (genvar i=0; i<NumRsp; i++) begin : gen_c_mst_rsp_assignment
    assign c_slv_rsp_p_chan[i] = acc_c_mst_rsp_i[i].p;
    // Hart_id signals are generally hard wired at synthesis time. This
    // logic reduces to a simple lookup table.
    always_comb begin
      c_rsp_idx[i] = '0;
      for (int j=0; j<NumReq; j++) begin
        c_rsp_idx[i] |= (acc_c_mst_rsp_i[i].p.hart_id == acc_c_slv_req_i[j].q.hart_id) ?
          IdxWidth'(unsigned'(j)) : '0;
      end
    end
    assign c_slv_rsp_p_valid[i] = acc_c_mst_rsp_i[i].p_valid;
    assign c_slv_rsp_q_ready[i] = acc_c_mst_rsp_i[i].q_ready;
  end

  ////////////////////
  // C Interconnect //
  ////////////////////

  // Bypass this hierarchy level
  for (genvar i=0; i<NumReq; i++) begin : gen_c_bypass_path
    // C Request Path
    assign acc_c_mst_next_req_o[i].q = acc_c_slv_req_i[i].q;
    stream_demux #(
        .N_OUP ( 2 )
    ) c_req_bypass_demux_i (
        .inp_valid_i ( acc_c_slv_req_i[i].q_valid                                              ),
        .inp_ready_o ( acc_c_slv_rsp_o[i].q_ready                                              ),
        .oup_sel_i   ( c_mst_req_q_level[i] != LogNumHier'(HierLevel)                          ),
        .oup_valid_o ( {acc_c_mst_next_req_o[i].q_valid, c_mst_req_q_valid[i]}                 ),
        .oup_ready_i ( {acc_c_mst_next_rsp_i[i].q_ready, c_mst_rsp_q_ready[i]}                 )
    );

    // C Response Path
    stream_arbiter #(
        .DATA_T  ( acc_c_rsp_chan_t ),
        .N_INP   ( 2                ),
        .ARBITER ( "rr"             )
    ) c_rsp_bypass_arbiter_i (
        .clk_i       ( clk_i                                                   ),
        .rst_ni      ( rst_ni                                                  ),
        .inp_data_i  ( {acc_c_mst_next_rsp_i[i].p, c_mst_rsp_p_chan[i]}        ),
        .inp_valid_i ( {acc_c_mst_next_rsp_i[i].p_valid, c_mst_rsp_p_valid[i]} ),
        .inp_ready_o ( {acc_c_mst_next_req_o[i].p_ready, c_mst_req_p_ready[i]} ),
        .oup_data_o  ( acc_c_slv_rsp_o[i].p                                    ),
        .oup_valid_o ( acc_c_slv_rsp_o[i].p_valid                              ),
        .oup_ready_i ( acc_c_slv_req_i[i].p_ready                              )
    );
  end

  // C Request X-bar
  stream_xbar #(
      .NumInp      ( NumReq           ),
      .NumOut      ( NumRsp           ),
      .DataWidth   ( DataWidth        ),
      .payload_t   ( acc_c_req_chan_t ),
      .OutSpillReg ( RegisterReq      )
  ) c_req_xbar_i (
      .clk_i   ( clk_i             ),
      .rst_ni  ( rst_ni            ),
      .flush_i ( 1'b0              ),
      .rr_i    ( '0                ),
      .data_i  ( c_mst_req_q_chan  ),
      .sel_i   ( c_mst_req_q_addr  ),
      .valid_i ( c_mst_req_q_valid ),
      .ready_o ( c_mst_rsp_q_ready ),
      .data_o  ( c_slv_req_q_chan  ),
      .idx_o   ( /* unused */      ),
      .valid_o ( c_slv_req_q_valid ),
      .ready_i ( c_slv_rsp_q_ready )
  );

  // C Response X-bar
  stream_xbar #(
      .NumInp      ( NumRsp           ),
      .NumOut      ( NumReq           ),
      .DataWidth   ( DataWidth        ),
      .payload_t   ( acc_c_rsp_chan_t ),
      .OutSpillReg ( RegisterRsp      )
  ) c_rsp_xbar_i (
      .clk_i   ( clk_i             ),
      .rst_ni  ( rst_ni            ),
      .flush_i ( 1'b0              ),
      .rr_i    ( '0                ),
      .data_i  ( c_slv_rsp_p_chan  ),
      .sel_i   ( c_rsp_idx         ),
      .valid_i ( c_slv_rsp_p_valid ),
      .ready_o ( c_slv_req_p_ready ),
      .data_o  ( c_mst_rsp_p_chan  ),
      .idx_o   ( /* unused */      ),
      .valid_o ( c_mst_rsp_p_valid ),
      .ready_i ( c_mst_req_p_ready )
  );

  ////////////////////////////////////
  // CMem Req / Rsp Routing signals //
  ////////////////////////////////////

  // Generate response routing signal
  for (genvar i=0; i<NumReq; i++) begin : gen_cmem_mst_rsp_assignment
    assign cmem_slv_rsp_p_chan[i]  = acc_cmem_mst_rsp_i[i].p;
    // Xbar Address
    assign cmem_slv_rsp_p_addr[i]  = acc_cmem_mst_rsp_i[i].p.addr[OfflAddrWidth-1:0];
    // Hierarchy level address
    assign cmem_slv_rsp_p_level[i] = acc_cmem_mst_rsp_i[i].p.addr[AddrWidth-1:AccAddrWidth];
  end


  // X-bar out
  for (genvar i=0; i<NumRsp; i++) begin : gen_cmem_slv_req_assignment
    assign acc_cmem_slv_rsp_o[i].p       = cmem_mst_rsp_p_chan[i];
    assign acc_cmem_slv_rsp_o[i].p_valid = cmem_mst_rsp_p_valid[i];
    assign acc_cmem_slv_rsp_o[i].q_ready = cmem_mst_rsp_q_ready[i];
  end

  for (genvar i=0; i<NumRsp; i++) begin : gen_cmem_mst_req_assignment
    assign cmem_mst_req_q_chan[i]  = acc_cmem_slv_req_i[i].q;
    // hart_id -> xbar id
    always_comb begin
      cmem_req_idx[i] = '0;
      for (int j=0; j<NumReq; j++) begin
        cmem_req_idx[i] |= (acc_cmem_slv_req_i[i].q.hart_id == acc_c_slv_req_i[j].q.hart_id) ?
          IdxWidth'(unsigned'(j)) : '0;
      end
    end
    assign cmem_mst_req_q_valid[i] = acc_cmem_slv_req_i[i].q_valid;
    assign cmem_mst_req_p_ready[i] = acc_cmem_slv_req_i[i].p_ready;
  end

  ///////////////////////
  // CMem Interconnect //
  ///////////////////////

  // Bypass this hierarchy level
  for (genvar i=0; i<NumReq; i++) begin : gen_cmem_bypass_path
    // Cmem Response Path
    assign acc_cmem_slv_next_rsp_o[i].p = acc_cmem_mst_rsp_i[i].p;
    stream_demux #(
        .N_OUP ( 2 )
    ) cmem_rsp_bypass_demux_i (
        .inp_valid_i ( acc_cmem_mst_rsp_i[i].p_valid                                 ),
        .inp_ready_o ( acc_cmem_mst_req_o[i].p_ready                                 ),
        .oup_sel_i   ( cmem_slv_rsp_p_level[i] != LogNumHier'(HierLevel)             ),
        .oup_valid_o ( {acc_cmem_slv_next_rsp_o[i].p_valid, cmem_slv_rsp_p_valid[i]} ),
        .oup_ready_i ( {acc_cmem_slv_next_req_i[i].p_ready, cmem_slv_req_p_ready[i]} )
    );

    // Cmem Request Path
    stream_arbiter #(
        .DATA_T  ( acc_cmem_req_chan_t ),
        .N_INP   ( 2                   ),
        .ARBITER ( "rr"                )
    ) cmem_req_bypass_arbiter_i (
        .clk_i       ( clk_i                                                         ),
        .rst_ni      ( rst_ni                                                        ),
        .inp_data_i  ( {acc_cmem_slv_next_req_i[i].q, cmem_slv_req_q_chan[i]}        ),
        .inp_valid_i ( {acc_cmem_slv_next_req_i[i].q_valid, cmem_slv_req_q_valid[i]} ),
        .inp_ready_o ( {acc_cmem_slv_next_rsp_o[i].q_ready, cmem_slv_rsp_q_ready[i]} ),
        .oup_data_o  ( acc_cmem_mst_req_o[i].q                                       ),
        .oup_valid_o ( acc_cmem_mst_req_o[i].q_valid                                 ),
        .oup_ready_i ( acc_cmem_mst_rsp_i[i].q_ready                                 )
    );
  end

  // Cmem Response X-bar
  stream_xbar #(
      .NumInp      ( NumReq              ),
      .NumOut      ( NumRsp              ),
      .DataWidth   ( DataWidth           ),
      .payload_t   ( acc_cmem_rsp_chan_t ),
      .OutSpillReg ( RegisterReq         )
  ) cmem_rsp_xbar_i (
      .clk_i   ( clk_i                ),
      .rst_ni  ( rst_ni               ),
      .flush_i ( 1'b0                 ),
      .rr_i    ( '0                   ),
      .data_i  ( cmem_slv_rsp_p_chan  ),
      .sel_i   ( cmem_slv_rsp_p_addr  ),
      .valid_i ( cmem_slv_rsp_p_valid ),
      .ready_o ( cmem_slv_req_p_ready ),
      .data_o  ( cmem_mst_rsp_p_chan  ),
      .idx_o   ( /* unused */         ),
      .valid_o ( cmem_mst_rsp_p_valid ),
      .ready_i ( cmem_mst_req_p_ready )
  );

  // Cmem Request X-bar
  stream_xbar #(
      .NumInp      ( NumRsp              ),
      .NumOut      ( NumReq              ),
      .DataWidth   ( DataWidth           ),
      .payload_t   ( acc_cmem_req_chan_t ),
      .OutSpillReg ( RegisterRsp         )
  ) cmem_req_xbar_i (
      .clk_i   ( clk_i                ),
      .rst_ni  ( rst_ni               ),
      .flush_i ( 1'b0                 ),
      .rr_i    ( '0                   ),
      .data_i  ( cmem_mst_req_q_chan  ),
      .sel_i   ( cmem_req_idx         ),
      .valid_i ( cmem_mst_req_q_valid ),
      .ready_o ( cmem_mst_rsp_q_ready ),
      .data_o  ( cmem_slv_req_q_chan  ),
      .idx_o   ( /* unused */         ),
      .valid_o ( cmem_slv_req_q_valid ),
      .ready_i ( cmem_slv_rsp_q_ready )
  );

  // Sanity Checks
  // pragma translate_off
`ifndef VERILATOR
  for (genvar i=0; i<NumReq; i++) begin : gen_creq_fwd_asserts
    assert property (@(posedge clk_i)
        (acc_c_mst_next_req_o[i].q_valid)
            |-> acc_c_mst_next_req_o[i].q.addr[AddrWidth-1:AccAddrWidth] != HierLevel)
    else
      $error("Accelerator C request to level %0d bypassed interconnect level %0d.",
             acc_c_mst_next_req_o[i].q.addr[AddrWidth-1:AccAddrWidth], HierLevel);
  end

  for (genvar i=0; i<NumRsp; i++) begin : gen_creq_asserts
    assert property (@(posedge clk_i)
        (acc_c_mst_req_o[i].q_valid)
            |-> acc_c_mst_req_o[i].q.addr[AddrWidth-1:AccAddrWidth] == HierLevel)
    else
      $error("Accelerator C request to level %0d routed to interconnect level %0d.",
             acc_c_mst_req_o[i].q.addr[AddrWidth-1:AccAddrWidth], HierLevel);
  end
`endif
  // pragma translate_on

endmodule

`include "acc_interface/typedef.svh"
`include "acc_interface/assign.svh"

