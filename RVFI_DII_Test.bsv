/*-
 * Copyright (c) 2018 Jonathan Woodruff
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

import FIFO::*;
import GetPut::*;
import ClientServer::*;
import RVFI_DII::*;
import RVFI_DII_bridge::*;

module mkRVFI_DII_Test(Empty);
  Client#(Bit#(32), RVFI_DII_Execution#(32, 4)) bridge <- mkRVFI_DII_bridge();
  FIFO#(RVFI_DII_Execution#(32, 4)) tracebuf <- mkFIFO;
  Reg#(Bit#(64)) count <- mkReg(0);

  rule doInst;
    Bit#(32) insn <- bridge.request.get();
   $display("%x", insn);
    tracebuf.enq(RVFI_DII_Execution{
      rvfi_insn: insn,
      rvfi_order: count
    });
    count <= count + 1;
  endrule

  rule deliverTrace;
    bridge.response.put(tracebuf.first);
    tracebuf.deq;
  endrule
endmodule
