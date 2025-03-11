/*-
 * Copyright (c) 2023 Peter Rugg
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

#ifndef rvfi_dii_utils_h_include
#define rvfi_dii_utils_h_include

#include <stdint.h>

#define for_all_dii_fields \
  dii_field(dii_insn, uint32_t)\
  dii_field(dii_time, uint16_t)\
  dii_field(dii_cmd, uint8_t)\
  dii_field(dii_pad, uint8_t)

typedef struct {
#define dii_field(name, type) type name;
for_all_dii_fields
#undef dii_field
} dii_pkt_t;

#define for_all_rvfi_fields \
  rvfi_field(rvfi_order, uint64_t)\
  rvfi_field(rvfi_pc_rdata, uint64_t)\
  rvfi_field(rvfi_pc_wdata, uint64_t)\
  rvfi_field(rvfi_insn, uint64_t)\
  rvfi_field(rvfi_rs1_data, uint64_t)\
  rvfi_field(rvfi_rs2_data, uint64_t)\
  rvfi_field(rvfi_rd_wdata, uint64_t)\
  rvfi_field(rvfi_mem_addr, uint64_t)\
  rvfi_field(rvfi_mem_rdata, uint64_t)\
  rvfi_field(rvfi_mem_wdata, uint64_t)\
  rvfi_field(rvfi_mem_rmask, uint8_t )\
  rvfi_field(rvfi_mem_wmask, uint8_t )\
  rvfi_field(rvfi_rs1_addr, uint8_t )\
  rvfi_field(rvfi_rs2_addr, uint8_t )\
  rvfi_field(rvfi_rd_addr, uint8_t )\
  rvfi_field(rvfi_trap, uint8_t )\
  rvfi_field(rvfi_halt, uint8_t )\
  rvfi_field(rvfi_intr, uint8_t )

typedef struct {
#define rvfi_field(name, type) type name;
for_all_rvfi_fields
#undef rvfi_field
} rvfi_pkt_t;

#ifdef __cplusplus
extern "C" {
#endif
extern void rvfi_dii_bridge_rst (int log_buff_size);
#ifndef exclude_dii_getters
#define dii_field(name, type) extern type get_##name (int idx);
for_all_dii_fields
#undef dii_field
#endif
#ifndef exclude_rvfi_setters
extern void put_rvfi_pkt (
  int idx
#define rvfi_field(name, type) , type name
for_all_rvfi_fields
#undef rvfi_field
);
extern void put_rvfi_pkt_wrap(int idx, const rvfi_pkt_t *pkt);
#endif
extern void print_dii_pkt(const dii_pkt_t *pkt);
extern void print_rvfi_pkt(const rvfi_pkt_t *pkt);
#ifdef __cplusplus
}
#endif

#endif
