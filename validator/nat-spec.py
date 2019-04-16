EXP_TIME = 10
EXT_IP_ADDR = ext_ip
EXT_PORT = 1

if a_packet_received and EXP_TIME <= now:
    flow_emap = emap_expire_all(flow_emap, now - EXP_TIME)

h3 = pop_header(tcpudp, on_mismatch=([],[]))
h2 = pop_header(ipv4, on_mismatch=([],[]))
h1 = pop_header(ether, on_mismatch=([],[]))
assert a_packet_received
assert ((h1.type & 0x10) == 0x10) # 0x10 -> IPv4
assert h2.npid == 6 or h2.npid == 17 # 6/17 -> TCP/UDP
if received_on_port == EXT_PORT:
    flow_indx = h3.dst_port - start_port
    if emap_has_idx(flow_emap, flow_indx): # Flow is present in the table
        internal_flow = emap_get_key(flow_emap, flow_indx)
        flow_emap = emap_refresh_idx(flow_emap, flow_indx, now)
        if (internal_flow.dip != h2.saddr or
            internal_flow.dp != h3.src_port or
            internal_flow.prot != h2.npid):
            return ([],[])
        else:
            return ([internal_flow.idev],
                    [ether(h1, saddr=..., daddr=...),
                     ipv4(h2, cksum=..., saddr=internal_flow.dip, daddr=internal_flow.sip),
                     tcpudp(src_port=internal_flow.dp, dst_port=internal_flow.sp)])
    else:
        return ([],[])
else: # packet from the internal network
    internal_flow_id = FlowIdc(h3.src_port, h3.dst_port, h2.saddr, h2.daddr, received_on_port, h2.npid)
    if emap_has(flow_emap, internal_flow_id): # flow present in the table
        idx = emap_get(flow_emap, internal_flow_id)
        flow_emap = emap_refresh_idx(flow_emap, idx, now)
        return ([EXT_PORT],
                [ether(h1, saddr=..., daddr=...),
                 ipv4(h2, cksum=..., saddr=EXT_IP_ADDR),
                 tcpudp(h3, src_port=idx + start_port)])
    else: # No flow in the table
        if emap_full(flow_emap): # flowtable overflow
            return ([],[])
        else:
            idx = the_index_allocated
            flow_emap = emap_add(flow_emap, internal_flow_id, idx, now)
            return ([EXT_PORT],
                    [ether(h1, saddr=..., daddr=...),
                     ipv4(h2, cksum=..., saddr=EXT_IP_ADDR),
                     tcpudp(h3, src_port=idx + start_port)])