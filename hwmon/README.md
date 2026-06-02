# HW Monitor

Simple 320x240 hardware monitor app for Cubic Lua/LVGL.

Host server:

```text
GET http://192.168.0.80:8888/api/state
```

Host setup:

```bash
pip install psutil GPUtil
python host_monitor.py --host 0.0.0.0 --port 8888
```

Notes:

- `psutil` provides CPU and memory data.
- CPU model is read from Windows CIM first, then `platform.processor()`.
- GPU model is read from `GPUtil`, with Windows video controller data as fallback.
- CPU temperature is best effort. The script tries `psutil`, LibreHardwareMonitor/OpenHardwareMonitor WMI, then Windows ACPI thermal-zone data.
- CPU/GPU voltage and CPU power require LibreHardwareMonitor/OpenHardwareMonitor WMI on most Windows machines.
- NVIDIA GPU power is read from `nvidia-smi` when available.
