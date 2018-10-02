/*-
 * Copyright (c) 2018 Matthew Naylor
 * Copyright (c) 2018 Alexandre Joannou
 * All rights reserved.
 * 
 * This software was partly developed by the University of Cambridge
 * Computer Laboratory as part of the Partially-Ordered Event-Triggered
 * Systems (POETS) project, funded by EPSRC grant EP/N031768/1.
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

package Socket;

// Access named sockets on the file system in simulation.

import Vector :: *;

`ifdef SIMULATE

// Imports from C
// --------------
import "BDPI" function ActionValue#(Bit#(64)) serv_socket_create(String name);
import "BDPI" function Action serv_socket_init(Bit#(64) ptr);
import "BDPI" function ActionValue#(Bit#(32))
  serv_socket_get8(Bit#(64) ptr);
import "BDPI" function ActionValue#(Bool)
  serv_socket_put8(Bit#(64) ptr, Bit#(8) b);
import "BDPI" function ActionValue#(Bit#(n))
  serv_socket_getN(Bit#(64) ptr, Bit#(32) nbytes);
import "BDPI" function ActionValue#(Bool)
  serv_socket_putN(Bit#(64) ptr, Bit#(32) nbytes, Bit#(n) b);

// Wrappers
// --------

interface Socket#(numeric type n, numeric type m);
  method ActionValue#(Maybe#(Vector#(n, Bit#(8)))) get;
  method ActionValue#(Bool) put(Vector#(m, Bit#(8)) data);
endinterface

module mkSocket#(String name) (Socket#(n,m));
  Reg#(Bool)      is_initialized <- mkReg(False);
  Reg#(Bit#(64)) serv_socket_ptr <- mkRegU;

  rule do_init (!is_initialized);
    let tmp <- serv_socket_create(name);
    serv_socket_init(tmp);
    serv_socket_ptr <= tmp;
    is_initialized  <= True;
  endrule

  method get if (is_initialized) = actionvalue
    Bit#(TMul#(TAdd#(n, 1), 8)) tmp
      <- serv_socket_getN(serv_socket_ptr, fromInteger(valueOf(n)));
    Vector#(TAdd#(n, 1), Bit#(8)) res = unpack(tmp);
    if (res[valueOf(n)] == 0) return Valid(init(res));
    else return Invalid;
  endactionvalue;
    
  method put(data) if (is_initialized) =
    serv_socket_putN(serv_socket_ptr, fromInteger(valueOf(m)), pack(data));
endmodule

`endif
endpackage
