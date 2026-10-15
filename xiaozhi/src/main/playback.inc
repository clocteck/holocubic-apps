/* TX-only playback. One worker owns decoder, PCM ring and I2S.
 * Capture is stopped before this worker exists; no microphone/reference DSP. */
#define PB_QUEUE 64u
#define PB_PCM 8192u
#define PB_BLOCK 128u
#define PB_DMA_COUNT 4u
#define PB_MAX_DECODE 1920u
struct playback_state {
    xz_instance_t *owner;
    void *stream, *task;
    volatile int running, stop, finished, drained;
    volatile uint32_t head, tail;
    uint16_t lens[PB_QUEUE];
    uint8_t packets[PB_QUEUE][XZ_MAX_OPUS_BYTES];
    int16_t pcm[PB_PCM], decoded[PB_MAX_DECODE];
    int32_t tx[PB_BLOCK];
    uint32_t read_pos, write_pos;
    uint32_t packets_decoded, samples_written, underruns;
    char error[128];
};
static void pb_fail(playback_state *p,const char *message)
{
    if(p->error[0])return;
    size_t n=strlen(message);if(n>=sizeof(p->error))n=sizeof(p->error)-1;
    memcpy(p->error,message,n);p->error[n]=0;
    xz_set_error(p->owner,message);
}
static int pb_write(playback_state *p)
{
    const module_host_api_v2 *h=p->owner->host;
    size_t offset=0;
    while(offset<sizeof(p->tx) && !__atomic_load_n(&p->stop,__ATOMIC_ACQUIRE)){
        size_t written=0;
        int err=h->i2s.write(p->stream,(uint8_t*)p->tx+offset,sizeof(p->tx)-offset,&written,100);
        if(err!=MODULE_OK || !written || written>sizeof(p->tx)-offset){
            pb_fail(p,"audio: playback I2S write failed");return 0;
        }
        offset+=written;
    }
    return offset==sizeof(p->tx);
}
static void playback_task(void *arg)
{
    playback_state *p=arg;
    xz_instance_t *inst=p->owner;
    const module_host_api_v2 *h=inst->host;
    int primed=0, starvation=0;
    const uint32_t prebuffer=(uint32_t)inst->rate*120u/1000u;
    while(!__atomic_load_n(&p->stop,__ATOMIC_ACQUIRE)){
        if(h->diag.heartbeat)h->diag.heartbeat();
        uint32_t ready=p->write_pos-p->read_pos;
        /* Decode just enough ahead; all buffers reused, no per-packet allocation. */
        while(ready<prebuffer && PB_PCM-ready>=PB_MAX_DECODE){
            uint32_t tail=p->tail;
            if(tail==__atomic_load_n(&p->head,__ATOMIC_ACQUIRE))break;
            int count=opus_decode(inst->decoder,p->packets[tail],p->lens[tail],
                                  p->decoded,PB_MAX_DECODE,0);
            if(count<=0){pb_fail(p,"audio: Opus decode failed");goto done;}
            for(int i=0;i<count;i++)p->pcm[(p->write_pos++)&(PB_PCM-1)]=p->decoded[i];
            inst->decode_count++;inst->opus_bytes_in+=p->lens[tail];
            inst->pcm_bytes_out+=(uint32_t)count*2u;p->packets_decoded++;
            __atomic_store_n(&p->tail,(tail+1u)%PB_QUEUE,__ATOMIC_RELEASE);
            ready=p->write_pos-p->read_pos;
        }
        int ended=__atomic_load_n(&p->finished,__ATOMIC_ACQUIRE) &&
                  p->tail==__atomic_load_n(&p->head,__ATOMIC_ACQUIRE);
        if(!primed && (ready>=prebuffer || ended))primed=1;
        if(!primed){h->task.delay(10);continue;}
        if(ready>=PB_BLOCK || (ended && ready)){
            int volume=__atomic_load_n(&inst->playback_volume,__ATOMIC_RELAXED);
            for(uint32_t i=0;i<PB_BLOCK;i++){
                int32_t v=i<ready?p->pcm[(p->read_pos++)&(PB_PCM-1)]:0;
                p->tx[i]=(v*volume/100)*65536;
            }
            if(!pb_write(p))break;
            p->samples_written+=ready<PB_BLOCK?ready:PB_BLOCK;
            starvation=0;
        }else if(ended){
            /* Firmware has no DMA completion counter. Push a full DMA ring of
             * silence, then wait its duration so the last accepted sample has
             * left the peripheral before advertising drained. */
            memset(p->tx,0,sizeof(p->tx));
            for(uint32_t i=0;i<PB_DMA_COUNT;i++)if(!pb_write(p))goto done;
            h->task.delay((PB_DMA_COUNT*PB_BLOCK*1000u+(uint32_t)inst->rate-1)/(uint32_t)inst->rate);
            __atomic_store_n(&p->drained,1,__ATOMIC_RELEASE);
            break;
        }else{
            if(!starvation){p->underruns++;starvation=1;}
            /* Keep sub-block PCM across packets; only genuine network gaps get
             * silence. Never pad each decoded Opus packet separately. */
            memset(p->tx,0,sizeof(p->tx));if(!pb_write(p))break;
        }
    }
done:
    __atomic_store_n(&p->running,0,__ATOMIC_RELEASE); /* last access before return */
}
static void stop_playback(xz_instance_t *inst)
{
    playback_state *p=inst?inst->playback:NULL;
    if(!p)return;
    const module_host_api_v2 *h=inst->host;
    __atomic_store_n(&p->stop,1,__ATOMIC_RELEASE);
    uint32_t waited=0;
    while(__atomic_load_n(&p->running,__ATOMIC_ACQUIRE)){
        h->task.delay(10);waited+=10;
        if(waited>=1500){
            pb_fail(p,"audio: playback worker stop timeout");
            if(p->task)h->task.remove(p->task);
            break;
        }
    }
    if(p->stream && h->i2s.end(p->stream)!=MODULE_OK)
        pb_fail(p,"audio: playback I2S release failed");
    inst->playback=NULL;h->heap.free(p);
}
static int l_playback_start(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);
    const module_host_api_v2 *h=inst?inst->host:s_host;
    if(!inst || !h)return 0;
    if(!inst->started || !inst->decoder || inst->rate!=16000 || inst->channels!=1)
        return push_error(L,h,"audio: playback requires 16kHz mono codec");
    if(!h->i2s.begin || !h->i2s.write || !h->i2s.end || !h->task.create_ex || !h->task.delay)
        return push_error(L,h,"audio: host playback API missing");
    stop_playback(inst);stop_capture(inst);close_audio(inst);
    opus_decoder_ctl(inst->decoder,OPUS_RESET_STATE);
    playback_state *p=h->heap.calloc(1,sizeof(*p),MODULE_HEAP_PSRAM|MODULE_HEAP_8BIT);
    if(!p)return push_error(L,h,"audio: playback PSRAM allocation failed");
    p->owner=inst;inst->playback=p;
    module_i2s_config_t cfg;
    memset(&cfg,0,sizeof(cfg));cfg.size=sizeof(cfg);
    cfg.mode=MODULE_I2S_MODE_TX;cfg.sample_rate=inst->rate;cfg.bits=32;cfg.channels=1;
    cfg.format=MODULE_I2S_FORMAT_I2S;cfg.channel_mode=MODULE_I2S_CHANNEL_MONO_LEFT;
    cfg.bclk_pin=41;cfg.ws_pin=45;cfg.dout_pin=48;cfg.din_pin=-1;cfg.mclk_pin=-1;
    cfg.dma_buf_count=PB_DMA_COUNT;cfg.dma_buf_len=PB_BLOCK;
    cfg.flags=MODULE_I2S_FLAG_AUTO_CLEAR_TX;
    if(h->i2s.begin(&cfg,&p->stream)!=MODULE_OK || !p->stream){
        stop_playback(inst);return push_error(L,h,"audio: playback I2S unavailable");
    }
    p->running=1;
    if(h->task.create_ex("xz-play",playback_task,p,32768,2,0,
                        MODULE_HEAP_PSRAM|MODULE_HEAP_8BIT,&p->task)!=MODULE_OK || !p->task){
        p->running=0;stop_playback(inst);return push_error(L,h,"audio: playback task create failed");
    }
    xz_set_error(inst,"");h->lua.pushboolean(L,1);return 1;
}
static int l_playback_write(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);const module_host_api_v2 *h=inst->host;
    playback_state *p=inst->playback;size_t len=0;const char *data=h->lua.checklstring(L,1,&len);
    if(!p)return push_error(L,h,"audio: playback is not started");
    if(!__atomic_load_n(&p->running,__ATOMIC_ACQUIRE))
        return push_error(L,h,p->error[0]?p->error:"audio: playback worker stopped");
    if(__atomic_load_n(&p->finished,__ATOMIC_ACQUIRE))
        return push_error(L,h,"audio: packet after playback finish");
    if(!len || len>XZ_MAX_OPUS_BYTES)return push_error(L,h,"audio: invalid Opus packet size");
    uint32_t head=p->head,next=(head+1u)%PB_QUEUE;
    if(next==__atomic_load_n(&p->tail,__ATOMIC_ACQUIRE))return push_error(L,h,"would_block");
    memcpy(p->packets[head],data,len);p->lens[head]=(uint16_t)len;
    __atomic_store_n(&p->head,next,__ATOMIC_RELEASE);h->lua.pushboolean(L,1);return 1;
}
static int l_playback_finish(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);
    if(inst->playback)__atomic_store_n(&inst->playback->finished,1,__ATOMIC_RELEASE);
    inst->host->lua.pushboolean(L,1);return 1;
}
static int l_playback_stop(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);stop_playback(inst);
    inst->host->lua.pushboolean(L,1);return 1;
}
static int l_playback_status(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);const module_host_api_v2 *h=inst->host;
    playback_state *p=inst->playback;h->lua.createtable(L,0,9);
    set_boolean_field(L,h,"running",p && __atomic_load_n(&p->running,__ATOMIC_ACQUIRE));
    set_boolean_field(L,h,"drained",p && __atomic_load_n(&p->drained,__ATOMIC_ACQUIRE));
    set_string_field(L,h,"error",p?p->error:inst->last_error);
    set_integer_field(L,h,"packets_decoded",p?p->packets_decoded:0);
    set_integer_field(L,h,"samples_written",p?p->samples_written:0);
    set_integer_field(L,h,"underruns",p?p->underruns:0);
    set_integer_field(L,h,"pcm_capacity_bytes",PB_PCM*2);
    set_integer_field(L,h,"queued_packets",p?(p->head+PB_QUEUE-p->tail)%PB_QUEUE:0);
    return 1;
}
static int l_set_volume(lua_State *L)
{
    xz_instance_t *inst=instance_from_lua(L);
    int value=(int)inst->host->lua.tointeger(L,1);
    if(value<0)value=0;if(value>100)value=100;
    __atomic_store_n(&inst->playback_volume,value,__ATOMIC_RELAXED);
    inst->host->lua.pushboolean(L,1);return 1;
}
