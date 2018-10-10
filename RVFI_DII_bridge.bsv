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
import GetPut :: *;
import ClientServer :: *;
import RVFI_DII :: *;
import Socket::*;

module mkRVFI_DII_bridge#(String name, Integer dflt_port)
  (Client#(Bit#(32), RVFI_DII_Execution#(32, 4)));
  FIFO#(RVFI_DII_Instruction)       instbuf <- mkSizedFIFO(2048);
  FIFO#(Bool)                       haltbuf <- mkSizedFIFO(2048);
  FIFO#(RVFI_DII_Execution#(32, 4)) tracbuf <- mkSizedFIFO(2048);
  Reg#(Bit#(10))                    count   <- mkReg(0);
  Socket#(8, 88)                   socket   <- mkSocket(name, dflt_port);

  rule receiveInst;
    Maybe#(Vector#(8, Bit#(8))) mBytes <- socket.get;
    if (mBytes matches tagged Valid .bytes) begin
      RVFI_DII_Instruction_ByteStream inst = unpack(pack(bytes));
      Bool halt = (inst.rvfi_cmd == 0);
      if (!halt) instbuf.enq(byteStream2rvfiInst(inst));
      haltbuf.enq(halt);
    end
  endrule

  rule pushReport(!haltbuf.first);
    Vector#(88, Bit#(8)) traceBytes = unpack(pack(rvfi2byteStream(tracbuf.first)));
    Bool sent <- socket.put(traceBytes);
    if (sent) begin
      tracbuf.deq;
      haltbuf.deq;
    end
  endrule

  rule pushHalt(haltbuf.first);
    Vector#(88, Bit#(8)) traceBytes = unpack(pack(RVFI_DII_Execution_ByteStream{
      rvfi_order: ?,
      rvfi_trap:  ?,
      rvfi_halt:  1,
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
    }));
    Bool sent <- socket.put(traceBytes);
    if (sent) begin
      haltbuf.deq;
    end
  endrule

  interface Get request;
    method ActionValue#(Bit#(32)) get;// if (count == instbuf.first.rvfi_time && !instbuf.first.rvfi_cmd);
      instbuf.deq;
      return instbuf.first.rvfi_insn;
    endmethod
  endinterface
  interface Put response;
    method Action put(RVFI_DII_Execution#(32, 4) trace);
      tracbuf.enq(trace);
    endmethod
  endinterface
endmodule
