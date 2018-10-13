/*-
 * Copyright (c) 2018 Jonathan Woodruff
 * Copyright (c) 2018 Alexandre Joannou
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
import GetPut :: *;
import ClientServer :: *;
import RVFI_DII :: *;
import Socket::*;
import Clocks :: *;

typedef Client#(Bit#(32), RVFI_DII_Execution#(32, 4)) RVFI_DII_Client;
typedef Server#(Bit#(32), RVFI_DII_Execution#(32, 4)) RVFI_DII_Server;
interface RVFI_DII_Bridge;
  interface Reset new_rst;
  interface RVFI_DII_Client inst;
endinterface

module mkRVFI_DII_Bridge#(String name, Integer dflt_port) (RVFI_DII_Bridge);
  // handle different Reset
  Clock clk      <- exposeCurrentClock;
  Reset rst      <- exposeCurrentReset;
  MakeResetIfc r <- mkReset(0, True, clk);
  let reqff      <- mkSyncFIFO(2048, clk, rst, clk);
  let rspff      <- mkSyncFIFO(10, clk, r.new_rst, clk);
  // local state
  FIFO#(RVFI_DII_Execution#(32, 4)) traceBuf <- mkSizedFIFO(2048);
  FIFOF#(Bit#(0))                    haltBuf <- mkSizedFIFOF(10);
  FIFO#(Bit#(0))                 tracesQueue <- mkSizedFIFO(10);
  Reg#(Bit#(10))                 countInstIn <- mkReg(0);
  Reg#(Bit#(10))                countInstOut <- mkReg(0);
  Socket#(8, 88)                    socket   <- mkSocket(name, dflt_port);

  rule receiveCmd(!haltBuf.notEmpty);
    Maybe#(Vector#(8, Bit#(8))) mBytes <- socket.get;
    if (mBytes matches tagged Valid .bytes) begin
      RVFI_DII_Instruction_ByteStream cmd = unpack(pack(bytes));
      Bool halt = (cmd.rvfi_cmd == 0);
      if (!halt) begin
        reqff.enq(byteStream2rvfiInst(cmd).rvfi_insn);
        countInstIn <= countInstIn + 1;
      end else haltBuf.enq(?);
    end
  endrule

  (* descending_urgency = "handleITrace, handleReset"*)
  rule handleITrace;
    traceBuf.enq(rspff.first);
    rspff.deq;
    countInstOut <= countInstOut + 1;
  endrule
  rule handleReset(haltBuf.notEmpty && countInstIn == countInstOut);
    r.assertReset;
    haltBuf.deq;
    countInstIn  <= 0;
    countInstOut <= 0;
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
    tracesQueue.enq(?);
  endrule

  rule drainTrace;
    Vector#(88, Bit#(8)) traceBytes = unpack(pack(rvfi2byteStream(traceBuf.first)));
    Bool sent <- socket.put(traceBytes);
    if (sent) begin
      traceBuf.deq;
      if (traceBuf.first.rvfi_halt) tracesQueue.deq;
    end
  endrule

  interface new_rst = r.new_rst;
  interface Client inst;
    interface Get request;
      method get = actionvalue reqff.deq; return reqff.first; endactionvalue;
    endinterface
    interface Put response;
      method put(trace) = action rspff.enq(trace); endaction;
    endinterface
  endinterface
endmodule
