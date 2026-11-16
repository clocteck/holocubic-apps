-- User preset 2026-11-16. Five matching bands; the two extra Music bands bypass.
return {
  volume=0.4,hpf_freq=150,limiter_peak=31000,
  vbass=true,vbass_mix=0.20,vbass_drive=3,
  vbass_low_hpf=75,vbass_low_lpf=200,vbass_out_hpf=150,vbass_out_lpf=495,
  vbass_even=1.6,vbass_odd=0.8,vbass_solo=false,
  eq={6,0,4.2,-3.5,0,-2.5,-0.8},
  eq_freqs={180,250,420,1000,1250,2500,4300},
  eq_q={1,1,1,1,1,1,1},
}
