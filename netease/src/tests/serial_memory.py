"""Read memory-only diagnostics; never capture credentials or playback URLs."""
import argparse
import json
import re
import time
from pathlib import Path
import serial

p=argparse.ArgumentParser()
p.add_argument('--port',default='COM35')
p.add_argument('--seconds',type=int,default=1200)
args=p.parse_args()
dest=Path(__file__).resolve().parents[1]/'build/serial-memory.jsonl'
dest.parent.mkdir(exist_ok=True)
port=serial.Serial(port=None,baudrate=115200,timeout=0.5)
port.dtr=False;port.rts=False;port.port=args.port
port.open()
print('Memory-only serial capture started on '+args.port,flush=True)
try:
    with dest.open('a',encoding='utf-8') as log:
        deadline=time.monotonic()+args.seconds
        while time.monotonic()<deadline:
            line=port.readline().decode('utf-8',errors='replace')
            usage=re.search(r'\[usage\] CPU0: (\d+), CPU1: (\d+) \| RAM (\d+)/(\d+) \(\d+%\) \| PSRAM (\d+)/(\d+) \(\d+%\)',line)
            module=re.search(r'\[dynmod\] (dlopen|dlclose) (before|after) target=(/sd/[\w/.-]+) psram_free=(\d+) psram_largest=(\d+)',line)
            entry=None
            if usage:
                cpu0,cpu1,ram,total,psram,pstotal=map(int,usage.groups())
                entry=dict(cpu0=cpu0,cpu1=cpu1,ram_used=ram,psram_used=psram,psram_free=pstotal-psram)
            elif module:
                op,phase,target,free,largest=module.groups()
                entry=dict(op=op,phase=phase,target=target,psram_free=int(free),largest=int(largest))
            if entry:
                entry['time']=time.strftime('%H:%M:%S')
                out=json.dumps(entry)
                print(out,flush=True);log.write(out+'\n');log.flush()
except KeyboardInterrupt:
    pass
finally:
    port.close()
