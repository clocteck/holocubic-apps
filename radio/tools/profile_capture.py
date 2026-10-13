"""Read-only COM capture. DTR/RTS remain deasserted; no reset or serial writes."""
import argparse
from pathlib import Path
import time
import serial
p=argparse.ArgumentParser();p.add_argument('--port',default='COM35');p.add_argument('--output',required=True);p.add_argument('--seconds',type=int,default=600);a=p.parse_args()
s=serial.Serial(port=None,baudrate=115200,timeout=.25);s.dtr=False;s.rts=False;s.port=a.port
s.open();output=Path(a.output);output.parent.mkdir(parents=True,exist_ok=True)
print('CAPTURE_READY '+a.port,flush=True)
pending=b'';deadline=time.monotonic()+a.seconds
try:
    with output.open('xb') as f:
        while time.monotonic()<deadline:
            data=s.read(s.in_waiting or 1)
            if not data:continue
            f.write(data);f.flush();pending+=data
            while b'\n' in pending:
                line,pending=pending.split(b'\n',1)
                if b'[RADIO_PROFILE]' in line:print(line.decode('utf-8',errors='replace').strip(),flush=True)
finally:s.close();print('CAPTURE_CLOSED',flush=True)
