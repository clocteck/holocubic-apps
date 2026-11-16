/* Appended to production functions by test_dsp.py; codec/file IO alone is mocked. */
static const int16_t *test_input;
static int test_length,test_pos,test_chunk,test_toggle;
static int audio_decode_next(audio_instance_t *inst,size_t *bytes,int postprocess)
{
    *bytes=0;
    if(test_pos==test_length)return 0;
    if(test_pos==test_toggle){
        audio_dsp_lock(inst);
        inst->effects.vbass_enabled=!inst->effects.vbass_enabled;
        audio_rebuild_filters(inst);
        audio_dsp_unlock(inst);
    }
    int n=test_length-test_pos;if(n>test_chunk)n=test_chunk;
    if(test_pos<test_toggle && test_pos+n>test_toggle)n=test_toggle-test_pos;
    *bytes=n*inst->source_channels*2;
    memcpy(inst->out_buf,test_input+test_pos*inst->source_channels,*bytes);
    test_pos+=n;
    if(postprocess)audio_postprocess_pcm(inst,inst->out_buf,bytes);
    return 1;
}
API int process(const int16_t *input,float *output,int length,int rate,int channels,
                int volume_q15,int loudness_q15,int bass,int toggle,int chunk,
                int flat,int threshold,uint32_t *stats)
{
    audio_instance_t inst={0};
    float dry[256]={0},wet[256]={0};uint8_t decoded[8192],read[8192];
    audio_default_effects(&inst.effects);
    inst.sample_rate=rate;inst.source_channels=channels;inst.output_channels=1;
    inst.bits_per_sample=16;inst.opened=1;inst.out_buf=decoded;
    inst.dsp_buf=dry;inst.vbass_buf=wet;inst.dsp_cap=inst.vbass_cap=256;
    inst.effects.volume_q15=volume_q15;inst.loudness_gain_q15=loudness_q15;
    inst.effects.vbass_enabled=bass;inst.effects.limiter_threshold=threshold;
    if(bass==2)inst.effects.vbass_even=inst.effects.vbass_odd=0; /* Dry-state probe. */
    if(flat){inst.effects.eq_enabled=inst.effects.hpf_enabled=0;}
    audio_rebuild_filters(&inst);
    test_input=input;test_length=length;test_pos=0;test_chunk=chunk;test_toggle=toggle;
    int total=0;
    for(;;){
        size_t got=0;
        if(audio_read_pcm(&inst,read,sizeof(read),&got))return -1;
        if(!got)break;
        if(total+(int)got/2>length+AUDIO_PEAK_OUTPUT_DELAY)return -2;
        for(size_t i=0;i<got/2;i++)output[total++]=((int16_t*)read)[i]/32767.0f;
    }
    stats[0]=inst.peak.clipped;stats[1]=inst.peak.limited;stats[2]=inst.peak.bass_limited;
    return total;
}
API void defaults(float *v)
{
    audio_effect_settings s;audio_default_effects(&s);
    for(int i=0;i<7;i++){v[i]=s.eq_freq[i];v[i+7]=s.eq_gain[i];v[i+14]=s.eq_q[i];}
    v[21]=s.hpf_freq;v[22]=s.vbass_mix;v[23]=s.vbass_drive;
    v[24]=s.vbass_low_hpf;v[25]=s.vbass_low_lpf;v[26]=s.vbass_out_hpf;v[27]=s.vbass_out_lpf;
}
API void protect(const float *dry,const float *bass,float *out,int length,int rate,float gain,float ceiling,uint32_t *stats)
{
    audio_peak p;audio_peak_init(&p,rate);
    for(int i=0;i<length+AUDIO_PEAK_OUTPUT_DELAY;i++){
        int16_t v=audio_peak_sample(&p,i<length?dry[i]:0,i<length?bass[i]:0,gain,ceiling);
        if(i>=AUDIO_PEAK_OUTPUT_DELAY)out[i-AUDIO_PEAK_OUTPUT_DELAY]=v/32767.0f;
    }
    stats[0]=p.clipped;stats[1]=p.limited;stats[2]=p.bass_limited;
}
static int removed;
static void fake_delay(uint32_t ms){(void)ms;}
static void fake_remove(void *task){if(task)removed++;}
API int stop_check(void)
{
    audio_instance_t inst={0};removed=0;
    inst.host.task.delay=fake_delay;inst.host.task.remove=fake_remove;
    inst.producer_task=(void*)1;inst.producer_task_running=1;inst.dsp_busy=1;
    audio_play_task_stop_internal(&inst,2);
    return removed==1 && !inst.dsp_busy && !inst.producer_task_running && !inst.producer_task;
}
