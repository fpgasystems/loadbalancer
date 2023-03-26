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
      //{},
      {name: 'm_hdr_data (in)', wave: 'xx34.x....x7x.', data: ['hdr1', 'hdr2', 'hdr5']},
      {name: 'm_hdr_vld (in)',  wave: '0.1..0.....10.'},
      {name: 'm_hdr_rdy (out)', wave: '0.1010.....1..'},
      //{},
      {name: 'm_bdy_data (in)', wave: 'xxx3.x.5x.7..x', data: ['bdy1', 'bdy3', 'bdy5']},
      {name: 'm_bdy_vld (in)',  wave: '0..1.0.10.1..0'},
      {name: 'm_bdy_rdy (out)', wave: '0...1....0..1.'},
      {},
      // Proxy 0: *Cold start* -> Been fwded and PR-ed oid1 -> Running -> Been fwded and PR-ed another oid1.
      {name: 'stat_proxy_0 (in)', wave: 'xx3x4x5xx6xx7x', data: ['ox,l0', 'o9,l1', 'o9,l1', 'o9,l0', 'o9,l1'],
       node: '....k.......q..'},
      // Proxy 1: Executing oid3 (load=5 jobs) -> Finished previous oid3 and started another oid3 
      // 			-> Finished the previous oid3 and PR-ed to oid1 until it's finished -> Started another oid1.
      {name: 'stat_proxy_1 (in)', wave: 'xx3x4x5xx6xx7x', data: ['o3,l5', 'o3,l4', 'o1,l3', 'o1,l3', 'o1,l2'],
       node: '...............'},
      // Proxy 2: Executing oid6 (load=1 job) -> Idle -> PR-ed to oid5 and started executing -> Got another oid5 (load=2).
      {name: 'stat_proxy_2 (in)', wave: 'xx3x4x5xx6xx7x', data: ['o6,l1', 'o6,l0', 'o5,l1', 'o5,l2', 'o5,l2'],
       node: '......*..:.....'},
      // Proxy 3: Finished one oid7 every time the status is pulled.
      {name: 'stat_proxy_3 (in)', wave: 'xx3x4x5xx6xx7x', data: ['o7,l4', 'o7,l3', 'o7,l2', 'o7,l1', 'o7,l0'],
       node: '.............m.'},
      {},
      {name: 'leat_loaded_lb (out)',   wave: 'x.3x4x5x.6x.7x', data: ['vfid:0', 'vfid:2', 'vfid:2', 'vfid:0', 'vfid:3'],
       node: '...l.n.p..r..s..'},
      {name: 'pr_ctrl (out)', wave: 'xx3x4xxxxxxx7x', data: ['v0,o9', 'v2,o5', 'v3,o9']},
  
    ],
      edge: [
          'i-~>j the 4th request delayed by one cycle (due to queuing)',
          'l-~>k *cold start* on region 0',
          'n-~>* *cold start* on region 2',
          'p-~>: load increased to 2',
          'r-~>q *warm start* on region 0 (previously idle)',
          's-~>m least-loaded region, cold start',
    ],
   head:{
    text:'Figure: Waveform of the load balancer.',
     tick:0,
     every:1
   },
   foot:{
     text:'h0/1,b0/1: header/body=present/absent; o3,l5: oid=3,load=5; pr: partial reconfiguration; lb: load balancing                                  ',
     tick: 0,
     // tock:0
   },
  }
  