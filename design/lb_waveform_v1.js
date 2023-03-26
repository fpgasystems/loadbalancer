{
    signal: [
      {name: 'aclk', wave: 'pPp.P..p....Pp'},
      {name: 'request', wave: 'x3xx456x..x.7x', data: ['oid=9', 'oid=5', 'oid=5', 'oid=9', 'oid=9'],
        node: '......i........'},
      {},
      {name: 'm_meta_data (in)', wave: 'x3.x45.6..x.7x', data: ['h1,b1', 'h1,b0', 'h0,b1', 'h0,b0', 'h1,b1'],
        node: '.......j.......'},
      {name: 'm_meta_vld (in)',  wave: '01.01.....0.10'},
      {name: 'm_meta_rdy (out)', wave: '0.1..010.1...0'},
      {},
      {name: 'm_hdr_data (in)', wave: 'x3.x4x....x.7x', data: ['hdr1', 'hdr2', 'hdr5']},
      {name: 'm_hdr_vld (in)',  wave: '01.010......10'},
      {name: 'm_hdr_rdy (out)', wave: '0.1010......1.'},
      {},
      {name: 'm_bdy_data (in)', wave: 'x3.x.5.x..x.7x', data: ['bdy1', 'bdy3', 'bdy5']},
      {name: 'm_bdy_vld (in)',  wave: '01.0.1.0....10'},
      {name: 'm_bdy_rdy (out)',  wave: '0.1.0.1.......'},
      {},
      {name: 'lb_ctrl (out)',   wave: 'x.3x4x5x.6x.7x', data: ['vfid:0', 'vfid:2', 'vfid:2', 'vfid:0', 'vfid:0']},
      {name: 'stat_table_in (out)', wave: 'x.3x4x5x.6x.7x', data: ['<0,9>', '<2,5>', '<2,5>', '<0,9>', '<0,9>']},
      {name: 'stat_table_out (in)', wave: 'x.0x0x1x.1x.1x'},
      {name: 'pr_ctrl (out)',   wave: 'x.3x4x........', data: ['<0,9>', '<2,5>']},
      {},
      {name: 'q_in_hdr_0 (out)', wave: 'x.3x.....x..7x', data: ['hdr1', 'hdr3']},
      {name: 'q_hdr_rd_rdy_0 (in)', wave: '1....0..1.....'},
      {name: 'q_in_hdr_2 (out)', wave: 'x...4.......x.', data: ['hdr2']},
      {name: 'q_hdr_rd_rdy_2 (in)', wave: '10.........1..'},
      {name: 'q_bdy_in_0 (out)', wave: 'xx3..x......7.', data: ['bdy1', 'bdy5']},
      {name: 'q_bdy_rd_rdy_0 (in)', wave: '0...1....0...1'},
      {name: 'q_bdy_in_2 (out)', wave: 'x.....5x......', data: ['bdy3']},
      {name: 'q_bdy_rd_rdy_2 (in)', wave: '0.1...........'},
    ],
      edge: [
          'i-~>j the 4th request delayed by one cycle (due to queuing)'
    ],
   head:{
    text:'Figure: Waveform of the load balancer.',
     tick:0,
     every:1
   },
   foot:{
    text:'h0/1,b0/1: header or body present/absent; pr: partial reconfiguration; lb: load balancing decision; q: queue                                    ',
     tick: 0,
     // tock:0
   },
  }
  