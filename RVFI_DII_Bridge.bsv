/*-
 * Copyright (c) 2018 Jonathan Woodruff
 * Copyright (c) 2018 Alexandre Joannou
 * Copyright (c) 2018-2019 Peter Rugg
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory (Department of Computer Science and
 * Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
 * DARPA SSITH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

import Vector :: *;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import FIFOLevel :: *;
import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import RVFI_DII_Types :: *;
import Socket :: *;
import Clocks :: *;

typedef 2048 MaxDepth;

interface RVFI_DII_Client#(numeric type xlen, numeric type seq_len);
    method ActionValue#(Bit#(32)) getInst(UInt#(seq_len) seqReq);
    interface Put#(RVFI_DII_Execution#(xlen)) report;
endinterface

interface RVFI_DII_Server#(numeric type xlen, numeric type seq_len);
    interface Get#(RVFI_DII_Execution#(xlen)) report;
endinterface

interface RVFI_DII_Bridge #(numeric type xlen, numeric type seq_len);
  interface Reset new_rst;
  interface RVFI_DII_Client #(xlen, seq_len) client;
endinterface

Bit#(0) dontCare = ?;
module mkRVFI_DII_Bridge#(String name, Integer dflt_port) (RVFI_DII_Bridge #(xlen, seq_len))
  provisos (Add#(a__, TDiv#(xlen,8), 8), Add#(b__, xlen, 64));
  // handle buffers with different Reset
  let    clk <- exposeCurrentClock;
  let    rst <- exposeCurrentReset;
  let newRst <- mkReset(0, True, clk);
  let  reqff <- mkSyncFIFO(valueOf(MaxDepth), clk, rst, clk);
  let  rspff <- mkSyncFIFO(8, clk, newRst.new_rst, clk);
  // local state
  let     traceBuf <- mkSizedFIFO(valueOf(MaxDepth));
  SyncFIFOCountIfc#(Bit#(0), 8) haltBuf <- mkSyncFIFOCount(clk, rst, clk);
  let  tracesQueue <- mkSizedFIFO(8);
  Reg#(Bit#(TLog#(MaxDepth)))  countInstIn <- mkReg(0);
  Reg#(Bit#(TLog#(MaxDepth))) countInstOut <- mkReg(0);
  let       socket <- mkSocket(name, dflt_port);
  let   seqNumBuff <- mkRegU;
  //Array of recently inserted instructions to replay in event of mispredict/trap
  Vector#(TExp#(seq_len), Reg#(Bit#(32))) recentIns <- replicateM(mkRegU);

  // receive an RVFI_DII command from a socket and dispatch it
  rule receiveCmd(!haltBuf.dNotEmpty);
    let mBytes <- socket.get;
    if (mBytes matches tagged Valid .bytes) begin
      RVFI_DII_Instruction_ByteStream cmd = unpack(pack(bytes));
      Bool halt = (cmd.rvfi_cmd == 0);
      if (!halt) begin
        reqff.enq(byteStream2rvfiInst(cmd).rvfi_insn);
        countInstIn <= countInstIn + 1;
      end else haltBuf.enq(dontCare);
    end
  endrule

  // handle the different kinds of execution traces
  rule handleITrace(!(haltBuf.dNotEmpty && countInstIn == countInstOut));
    traceBuf.enq(rspff.first);
    rspff.deq;
    countInstOut <= countInstOut + 1;
  endrule
  (* fire_when_enabled *)
  rule handleReset(haltBuf.dNotEmpty && countInstIn == countInstOut);
    newRst.assertReset;
    haltBuf.deq;
    countInstIn  <= 0;
    countInstOut <= 0;
    seqNumBuff <= 0;
    traceBuf.enq(RVFI_DII_Execution{
      rvfi_order: ?,
      rvfi_trap:  ?,
      rvfi_halt:  True,
      rvfi_intr:  ?,
      rvfi_insn:  ?,
      rvfi_rs1_addr:  ?,
      rvfi_rs2_addr:  ?,
      rvfi_rs1_data:  ?,
      rvfi_rs2_data:  ?,
      rvfi_pc_rdata:  ?,
      rvfi_pc_wdata:  ?,
      rvfi_mem_wdata: ?,
      rvfi_rd_addr:   ?,
      rvfi_rd_wdata:  ?,
      rvfi_mem_addr:  ?,
      rvfi_mem_rmask: ?,
      rvfi_mem_wmask: ?,
      rvfi_mem_rdata: ?
    });
    tracesQueue.enq(dontCare);
  endrule

  // send execution traces back through the socket
  rule drainTrace;
    Vector#(88, Bit#(8)) traceBytes = unpack(pack(rvfi2byteStream(traceBuf.first)));
    Bool sent <- socket.put(traceBytes);
    if (sent) begin
      traceBuf.deq;
      if (traceBuf.first.rvfi_halt) tracesQueue.deq;
    end
  endrule

  // wire up interfaces
  interface new_rst = newRst.new_rst;
  interface RVFI_DII_Client client;
      method ActionValue#(Bit#(32)) getInst (UInt#(seq_len) seqReq) if (haltBuf.dNotEmpty);
          if (seqReq == seqNumBuff) begin
              reqff.deq;
              seqNumBuff <= seqNumBuff + 1;
              recentIns[seqNumBuff] <= reqff.first;
              return reqff.first;
          end else begin
              return recentIns[seqReq];
          end
      endmethod
      interface Put report = toPut(rspff);
  endinterface

endmodule
