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

import Assert::*;
import Vector :: *;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import FIFOLevel :: *;
import RegFile :: * ;
import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;
import RVFI_DII_Types :: *;
import Socket :: *;
import Clocks :: *;
import ConfigReg :: *;

interface RVFI_DII_Client#(numeric type xlen, numeric type memwidth, numeric type reqWidth);
    method ActionValue#(Vector#(reqWidth, Maybe#(Bit#(32)))) getInst(Vector#(reqWidth, Maybe#(Dii_Id)) seqReq);
    interface Put#(Vector#(reqWidth, Maybe#(RVFI_DII_Execution#(xlen,memwidth)))) report;
endinterface

interface RVFI_DII_Client_Scalar#(numeric type xlen, numeric type memwidth);
    method ActionValue#(Maybe#(Bit#(32))) getInst(Dii_Id seqReq);
    interface Put#(RVFI_DII_Execution#(xlen,memwidth)) report;
endinterface

interface RVFI_DII_Server#(numeric type xlen, numeric type memwidth);
    interface Get#(RVFI_DII_Execution#(xlen,memwidth)) report;
endinterface

interface RVFI_DII_Bridge #(numeric type xlen, numeric type memwidth, numeric type reqWidth);
  interface Reset new_rst;
  interface RVFI_DII_Client #(xlen,memwidth,reqWidth) client;
  method Bool done;
endinterface

interface RVFI_DII_Bridge_Scalar #(numeric type xlen, numeric type memwidth);
  interface Reset new_rst;
  interface RVFI_DII_Client_Scalar #(xlen,memwidth) client;
  method Bool done;
endinterface

module mkRVFI_DII_Bridge#(String name, Integer dflt_port) (RVFI_DII_Bridge #(xlen, memwidth,reqWidth))
  provisos (Add#(a__, TDiv#(xlen,8), 8), Add#(b__, xlen, 64), Add#(c__, TDiv#(memwidth,8), 8), Add#(d__, memwidth, 64));

  // handle buffers with different Reset
  let    clk <- exposeCurrentClock;
  let newRst <- mkReset(0, True, clk);
  Reg#(Bool) doReset <- mkSyncRegToCC(False, clk, newRst.new_rst);
  Socket#(8, 88) socket <- mkSocket(name, dflt_port);
  RVFI_DII_Bridge#(xlen, memwidth, reqWidth) bridge <- mkRVFI_DII_Bridge_Core(name, dflt_port, socket, reset_by newRst.new_rst);

  rule readDone;
    doReset <= bridge.done;
  endrule

  rule doResetRule(doReset);
    $display("Performing reset in RVFI_DII Bridge");
    newRst.assertReset;
  endrule

  interface done = bridge.done;
  interface new_rst = newRst.new_rst;
  interface RVFI_DII_Client client = bridge.client;
endmodule

module mkRVFI_DII_Bridge_Scalar#(String name, Integer dflt_port) (RVFI_DII_Bridge_Scalar #(xlen, memwidth))
  provisos (Add#(a__, TDiv#(xlen,8), 8), Add#(b__, xlen, 64), Add#(c__, TDiv#(memwidth,8), 8), Add#(d__, memwidth, 64));
  RVFI_DII_Bridge#(xlen, memwidth, 1) bridge <- mkRVFI_DII_Bridge(name, dflt_port);
  return interface RVFI_DII_Bridge_Scalar
    interface new_rst = bridge.new_rst;
    interface RVFI_DII_Client_Scalar client;
      method ActionValue#(Maybe#(Bit#(32))) getInst (Dii_Id seqReq);
        let inst <- bridge.client.getInst(replicate(Valid(seqReq)));
        return inst[0];
      endmethod
      interface Put report;
        method Action put (RVFI_DII_Execution#(xlen, memwidth) rep);
          bridge.client.report.put(replicate(Valid(rep)));
        endmethod
      endinterface
    endinterface
    method Bool done = bridge.done;
  endinterface;
endmodule

module mkRVFI_DII_Bridge_Core#(String name, Integer dflt_port, Socket#(8, 88) socket) (RVFI_DII_Bridge #(xlen, memwidth, reqWidth))
  provisos (Add#(a__, TDiv#(xlen,8), 8), Add#(b__, xlen, 64), Add#(c__, TDiv#(memwidth,8), 8), Add#(d__, memwidth, 64));
  Reg#(Bool) allBuffered <- mkConfigReg(False);
  Reg#(Dii_Id) countInstIn <- mkConfigReg(0);
  Reg#(Dii_Id) countInstOut <- mkConfigReg(0);
  Reg#(Bool) doneReg <- mkConfigReg(False);
  //Array of instructions
  RegFile#(Dii_Id, Bit#(32)) insts <- mkRegFileFull;

  rule queTraces(!allBuffered);
    let mBytes <- socket.get;
    if (mBytes matches tagged Valid .bytes) begin
      RVFI_DII_Instruction_ByteStream cmd = unpack(pack(bytes));
      Bool halt = (cmd.rvfi_cmd == 0);
      if (!halt) begin
        //$display("Received instruction RVFI_DII Bridge: ", fshow(cmd));
        insts.upd(countInstIn, byteStream2rvfiInst(cmd).rvfi_insn);
        countInstIn <= countInstIn + 1;
      end else begin
        // Return the default "nop" in this case.
        allBuffered <= True;
        $display("Halt received in RVFI_DII Bridge");
      end
    end
  endrule

  function Action sendRvfiTrace(RVFI_DII_Execution#(xlen,memwidth) rvfiTrace) =
    action
      Vector#(88, Bit#(8)) traceBytes = unpack(pack(rvfi2byteStream(rvfiTrace)));
      //$display("Sent RVFI-DII trace: ", fshow(rvfiTrace));
      Bool sent <- socket.put(traceBytes);
      dynamicAssert(sent, "RVFI trace failed to send!");
    endaction;

  Bool readyToHalt = (allBuffered && countInstOut == countInstIn);
  rule report_halt(readyToHalt && !doneReg);
    sendRvfiTrace(RVFI_DII_Execution{
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
    $display("Sent Halt trace in RVFI_DII Bridge");
    doneReg <= True;
  endrule

  // wire up interfaces
  interface Reset new_rst = error("mkRVFI_DII_Bridge_Core does not provide a reset interface. Did you mean to use mkRVFI_DII_Bridge that wraps this module?");
  interface RVFI_DII_Client client;
    method ActionValue#(Vector#(reqWidth, Maybe#(Bit#(32)))) getInst (Vector#(reqWidth, Maybe#(Dii_Id)) seqReqs) if (allBuffered);
      Vector#(reqWidth, Maybe#(Bit#(32))) nextInsts = replicate(tagged Invalid);
      for (Integer i = 0; i < valueOf(reqWidth); i = i + 1) begin
        if (seqReqs[i] matches tagged Valid .seqReq) begin
          if (seqReq < countInstIn) nextInsts[i] = tagged Valid insts.sub(seqReq);
        end
      end
      //$display("Called getInst in RVFI_DII Bridge ", fshow(seqReqs), fshow(nextInsts));
      return nextInsts;
    endmethod
    interface Put report;
      method Action put(Vector#(reqWidth, Maybe#(RVFI_DII_Execution#(xlen,memwidth))) rvfiTrace) if (!readyToHalt && !doneReg);
        Dii_Id newCount = countInstOut;
        for (Integer i = 0; i < valueOf(reqWidth); i = i + 1) begin
          if (rvfiTrace[i] matches tagged Valid .trace) begin
            sendRvfiTrace(trace);
            newCount = newCount + 1;
          end
        end
        countInstOut <= newCount;
      endmethod
    endinterface
  endinterface
  method Bool done = doneReg;
endmodule
