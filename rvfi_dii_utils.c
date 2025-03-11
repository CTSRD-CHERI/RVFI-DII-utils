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

#include "rvfi_dii_utils.h"
#include "SocketPacketUtils/socket_packet_utils.h"

#include <stdlib.h>
#include <stdio.h>

unsigned long long my_sock = 0;
dii_pkt_t *dii_buff = 0;
rvfi_pkt_t *rvfi_buff = 0;
bool *rvfi_buff_fresh = 0;
int buff_size;
int enq_head;
int deq_head;

// Reset and configure with a conservative estimate for the number of
// packets that can live in the pipeline at a time
void rvfi_dii_bridge_rst(int log_buff_size) {
  my_sock = serv_socket_create("RVFI_DII", 8000);
  serv_socket_init(my_sock);
  if (dii_buff) free(dii_buff);
  if (rvfi_buff) free(rvfi_buff);
  if (rvfi_buff_fresh) free(rvfi_buff_fresh);
  buff_size = 1 << log_buff_size;
  dii_buff = (dii_pkt_t *) malloc(buff_size * sizeof dii_buff[0]);
  rvfi_buff = (rvfi_pkt_t *) malloc(buff_size * sizeof rvfi_buff[0]);
  rvfi_buff_fresh = (bool *) calloc(buff_size, sizeof rvfi_buff_fresh[0]);
  enq_head = 0;
  deq_head = 0;
}

// Get the relevant whole packet, receiving from the network if required
dii_pkt_t* dii_get(int idx) {
  printf("dii_get! %i\n", idx);
  if (idx == enq_head) {
    int recv_cnt = 0;
    while (recv_cnt < sizeof dii_buff[0]) {
      int recv = serv_socket_get8(my_sock);
      if (recv != -1) {
        ((char *)(dii_buff + idx))[recv_cnt++] = (char)recv;
      }
    }
    enq_head = (enq_head + 1) % buff_size;
  }
  return dii_buff + idx;
}

// Individual getters for fields to avoid propagating struct layout into Verilog.
// Repeated calls with same ID expected and will not cause redundant network traffic.
#define dii_field(name, type) type get_##name (int idx) { return dii_get(idx) -> name; }
for_all_dii_fields
#undef dii_field

// Send an RVFI packet
void rvfi_send(rvfi_pkt_t *pkt) {
  int send_cnt = 0;
  while (send_cnt < sizeof *pkt) {
    if (serv_socket_put8_blocking(my_sock, ((char *)pkt)[send_cnt]))
      ++ send_cnt;
  }
}

// Supports out of order retire: call in any order with IDs matching DII IDs
// Will send RVFI packets until next pending packet
void put_rvfi_pkt(
  int idx
#define rvfi_field(name, type) , type name
for_all_rvfi_fields
#undef rvfi_field
) {
  #define rvfi_field(name, type) rvfi_buff[idx].name = name;
  for_all_rvfi_fields
  #undef rvfi_field
  rvfi_buff_fresh[idx] = true;
  while (rvfi_buff_fresh[deq_head]) {
    rvfi_send(rvfi_buff + deq_head);
    rvfi_buff_fresh[deq_head] = false;
    deq_head = (deq_head + 1) % buff_size;
  }
}

extern void put_rvfi_pkt_wrap(int idx, const rvfi_pkt_t *pkt) {
  put_rvfi_pkt(
      idx
#define rvfi_field(name, type) , pkt->name
for_all_rvfi_fields
#undef rvfi_field
  );
}

void print_dii_pkt(const dii_pkt_t *pkt) {
  printf("Begin DII Packet =========\n");
  #define dii_field(name, type) printf("%s: %x\n", #name, pkt->name);
  for_all_dii_fields
  #undef dii_field
  printf("End DII Packet ===========\n");
}

void print_rvfi_pkt(const rvfi_pkt_t *pkt) {
  printf("Begin RVFI Packet ========\n");
  #define rvfi_field(name, type) printf("%s: %lx\n", #name, (unsigned long int) pkt->name);
  for_all_rvfi_fields
  #undef rvfi_field
  printf("End RVFI Packet ==========\n");
}
