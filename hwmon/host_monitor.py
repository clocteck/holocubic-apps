#!/usr/bin/env python3
import argparse
import json
import platform
import re
import shutil
import socket
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


DEFAULT_HOST = "0.0.0.0"
DEFAULT_PORT = 8888
DEFAULT_TEMP_CACHE_SECONDS = 5.0
_WINDOWS_ROOT_NAMESPACES = None


def clamp_pct(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if n < 0:
        return 0.0
    if n > 100:
        return 100.0
    return round(n, 1)


def valid_temperature(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if n < -20 or n > 130:
        return None
    return round(n, 1)


def parse_number(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text or text.upper() in ("N/A", "[N/A]", "NULL", "NONE"):
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", text)
    if not match:
        return None
    try:
        return float(match.group(0))
    except ValueError:
        return None


def round_sensor(value, digits=2):
    value = parse_number(value)
    if value is None:
        return None
    return round(value, digits)


def compact_name(value):
    text = " ".join(str(value or "").split())
    return text or None


def first_json_value(value):
    if isinstance(value, list):
        return value[0] if value else None
    return value


def windows_cpu_name():
    if platform.system().lower() != "windows":
        return None
    script = (
        "Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | "
        "Select-Object -First 1 -ExpandProperty Name | "
        "ConvertTo-Json -Compress"
    )
    return compact_name(first_json_value(run_powershell_json(script)))


def windows_root_namespaces():
    global _WINDOWS_ROOT_NAMESPACES
    if _WINDOWS_ROOT_NAMESPACES is not None:
        return _WINDOWS_ROOT_NAMESPACES
    if platform.system().lower() != "windows":
        _WINDOWS_ROOT_NAMESPACES = set()
        return _WINDOWS_ROOT_NAMESPACES
    script = (
        "Get-CimInstance -Namespace root -ClassName __Namespace "
        "-ErrorAction SilentlyContinue | "
        "Select-Object -ExpandProperty Name | ConvertTo-Json -Compress"
    )
    raw = run_powershell_json(script)
    values = raw if isinstance(raw, list) else [raw]
    _WINDOWS_ROOT_NAMESPACES = {str(value).lower() for value in values if value}
    return _WINDOWS_ROOT_NAMESPACES


def cpu_model_name():
    name = windows_cpu_name()
    if name:
        return name
    name = compact_name(platform.processor())
    if name:
        return name
    return compact_name(platform.machine()) or "CPU"


def first_cpu_temperature(psutil_mod):
    sensors = getattr(psutil_mod, "sensors_temperatures", None)
    if not sensors:
        return None
    try:
        data = sensors(fahrenheit=False)
    except Exception:
        return None
    if not data:
        return None

    preferred = ("coretemp", "k10temp", "cpu_thermal", "acpitz")
    groups = []
    for name in preferred:
        if name in data:
            groups.append(data[name])
    for name, values in data.items():
        if name not in preferred:
            groups.append(values)

    best = None
    for values in groups:
        for item in values or []:
            current = getattr(item, "current", None)
            if current is None:
                continue
            try:
                current = float(current)
            except (TypeError, ValueError):
                continue
            if best is None or current > best:
                best = current
    return valid_temperature(best)


def run_powershell_json(script):
    for exe in ("powershell.exe", "pwsh.exe"):
        path = shutil.which(exe)
        if not path:
            continue
        try:
            proc = subprocess.run(
                [path, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=3.0,
                check=False,
            )
        except Exception:
            continue
        raw = (proc.stdout or "").strip()
        if proc.returncode != 0 or not raw:
            continue
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw
    return None


def windows_acpi_temperature():
    if platform.system().lower() != "windows":
        return None
    script = (
        "Get-CimInstance -Namespace root/wmi "
        "-ClassName MSAcpi_ThermalZoneTemperature "
        "-ErrorAction SilentlyContinue | "
        "Select-Object -ExpandProperty CurrentTemperature | "
        "ConvertTo-Json -Compress"
    )
    raw = run_powershell_json(script)
    if raw is None:
        return None
    values = raw if isinstance(raw, list) else [raw]
    temps = []
    for value in values:
        try:
            celsius = (float(value) / 10.0) - 273.15
        except (TypeError, ValueError):
            continue
        temp = valid_temperature(celsius)
        if temp is not None:
            temps.append(temp)
    if not temps:
        return None
    return max(temps)


def hardware_monitor_cpu_temperature(namespace):
    script = (
        f"Get-CimInstance -Namespace {namespace} "
        "-ClassName Sensor -ErrorAction SilentlyContinue | "
        "Where-Object { $_.SensorType -eq 'Temperature' } | "
        "Select-Object Name,Value,Identifier,Parent | "
        "ConvertTo-Json -Compress"
    )
    raw = run_powershell_json(script)
    if raw is None:
        return None
    items = raw if isinstance(raw, list) else [raw]
    temps = []
    for item in items:
        if not isinstance(item, dict):
            continue
        text = " ".join(str(item.get(key, "")) for key in ("Name", "Identifier", "Parent")).lower()
        if not any(token in text for token in ("cpu", "package", "core", "tctl", "tdie", "ccd")):
            continue
        if any(token in text for token in ("gpu", "nvme", "ssd", "memory", "ram")):
            continue
        temp = valid_temperature(item.get("Value"))
        if temp is not None:
            temps.append(temp)
    if not temps:
        return None
    return max(temps)


def hardware_monitor_sensors(namespace, sensor_type):
    script = (
        f"Get-CimInstance -Namespace {namespace} "
        "-ClassName Sensor -ErrorAction SilentlyContinue | "
        f"Where-Object {{ $_.SensorType -eq '{sensor_type}' }} | "
        "Select-Object SensorType,Name,Value,Identifier,Parent | "
        "ConvertTo-Json -Compress"
    )
    raw = run_powershell_json(script)
    if raw is None:
        return []
    items = raw if isinstance(raw, list) else [raw]
    return [item for item in items if isinstance(item, dict)]


def hardware_monitor_sensor_value(namespace, sensor_type, include_any, exclude_any=(), prefer_any=()):
    candidates = []
    include_any = tuple(token.lower() for token in include_any)
    exclude_any = tuple(token.lower() for token in exclude_any)
    prefer_any = tuple(token.lower() for token in prefer_any)

    for item in hardware_monitor_sensors(namespace, sensor_type):
        text = " ".join(str(item.get(key, "")) for key in ("Name", "Identifier", "Parent")).lower()
        if include_any and not any(token in text for token in include_any):
            continue
        if exclude_any and any(token in text for token in exclude_any):
            continue
        value = round_sensor(item.get("Value"), 2)
        if value is None:
            continue
        score = 0
        for i, token in enumerate(prefer_any):
            if token in text:
                score += 100 - i
        candidates.append((score, value))

    if not candidates:
        return None
    candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return candidates[0][1]


def hardware_monitor_extra_metrics():
    metrics = {
        "cpu_power_w": None,
        "cpu_voltage_v": None,
        "gpu_power_w": None,
        "gpu_voltage_v": None,
    }
    root_names = windows_root_namespaces()
    namespaces = []
    if "librehardwaremonitor" in root_names:
        namespaces.append("root\\LibreHardwareMonitor")
    if "openhardwaremonitor" in root_names:
        namespaces.append("root\\OpenHardwareMonitor")

    for namespace in namespaces:
        if metrics["cpu_power_w"] is None:
            metrics["cpu_power_w"] = hardware_monitor_sensor_value(
                namespace,
                "Power",
                ("cpu", "package", "cores", "ppt"),
                ("gpu", "nvme", "ssd", "drive", "memory", "ram"),
                ("cpu package", "package", "ppt", "cores"),
            )
        if metrics["cpu_voltage_v"] is None:
            metrics["cpu_voltage_v"] = hardware_monitor_sensor_value(
                namespace,
                "Voltage",
                ("vcore", "cpu core", "cpu", "soc"),
                ("gpu", "nvme", "ssd", "drive", "memory", "ram", "battery"),
                ("vcore", "cpu core", "core", "soc"),
            )
        if metrics["gpu_power_w"] is None:
            metrics["gpu_power_w"] = hardware_monitor_sensor_value(
                namespace,
                "Power",
                ("gpu", "nvidia", "radeon", "graphics"),
                ("cpu", "nvme", "ssd", "drive", "memory", "ram"),
                ("gpu package", "package", "gpu core", "power"),
            )
        if metrics["gpu_voltage_v"] is None:
            metrics["gpu_voltage_v"] = hardware_monitor_sensor_value(
                namespace,
                "Voltage",
                ("gpu", "nvidia", "radeon", "graphics"),
                ("cpu", "nvme", "ssd", "drive", "memory", "ram", "battery"),
                ("gpu core", "core", "voltage"),
            )

    return metrics


def nvidia_smi_power():
    if not shutil.which("nvidia-smi"):
        return {}
    try:
        proc = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=power.draw,power.limit",
                "--format=csv,noheader,nounits",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=2.0,
            check=False,
        )
    except Exception:
        return {}
    if proc.returncode != 0:
        return {}
    line = (proc.stdout or "").splitlines()[0:1]
    if not line:
        return {}
    parts = [part.strip() for part in line[0].split(",")]
    return {
        "gpu_power_w": round_sensor(parts[0], 2) if len(parts) >= 1 else None,
        "gpu_power_limit_w": round_sensor(parts[1], 2) if len(parts) >= 2 else None,
    }


def read_extra_metrics():
    metrics = hardware_monitor_extra_metrics()
    smi = nvidia_smi_power()
    if smi.get("gpu_power_w") is not None:
        metrics["gpu_power_w"] = smi["gpu_power_w"]
    metrics["gpu_power_limit_w"] = smi.get("gpu_power_limit_w")
    return metrics


def read_cpu_temperature(psutil_mod):
    temp = first_cpu_temperature(psutil_mod)
    if temp is not None:
        return temp, "psutil"

    root_names = windows_root_namespaces()
    if "librehardwaremonitor" in root_names:
        temp = hardware_monitor_cpu_temperature("root\\LibreHardwareMonitor")
        if temp is not None:
            return temp, "librehardwaremonitor"
    if "openhardwaremonitor" in root_names:
        temp = hardware_monitor_cpu_temperature("root\\OpenHardwareMonitor")
        if temp is not None:
            return temp, "openhardwaremonitor"

    temp = windows_acpi_temperature()
    if temp is not None:
        return temp, "windows_acpi"

    return None, None


def collect_gpu_gputil():
    try:
        import GPUtil
    except Exception:
        return None
    try:
        gpus = GPUtil.getGPUs()
    except Exception:
        return None
    if not gpus:
        return None
    gpu = gpus[0]
    return {
        "name": getattr(gpu, "name", "GPU") or "GPU",
        "usage": clamp_pct((getattr(gpu, "load", 0.0) or 0.0) * 100.0),
        "temp": getattr(gpu, "temperature", None),
        "memory_used_mb": getattr(gpu, "memoryUsed", None),
        "memory_total_mb": getattr(gpu, "memoryTotal", None),
    }


def collect_gpu_windows():
    if platform.system().lower() != "windows":
        return None
    script = (
        "Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | "
        "Select-Object Name | ConvertTo-Json -Compress"
    )
    raw = run_powershell_json(script)
    if raw is None:
        return None
    items = raw if isinstance(raw, list) else [raw]
    for item in items:
        name = compact_name(item.get("Name") if isinstance(item, dict) else item)
        if not name:
            continue
        low = name.lower()
        if "microsoft basic" in low or "remote" in low:
            continue
        return {
            "name": name,
            "usage": None,
            "temp": None,
        }
    return None


def collect_gpu():
    return collect_gpu_gputil() or collect_gpu_windows()


def collect_snapshot(psutil_mod, sample_window, cpu_temp=None, cpu_temp_source=None, cpu_name=None, extra_metrics=None):
    cpu_usage = psutil_mod.cpu_percent(interval=sample_window)
    if cpu_temp is None and cpu_temp_source is None:
        cpu_temp, cpu_temp_source = read_cpu_temperature(psutil_mod)
    if not cpu_name:
        cpu_name = cpu_model_name()
    if extra_metrics is None:
        extra_metrics = read_extra_metrics()
    mem = psutil_mod.virtual_memory()
    gpu = collect_gpu()

    result = {
        "host": socket.gethostname(),
        "platform": platform.platform(),
        "timestamp": int(time.time()),
        "cpu": {
            "name": cpu_name,
            "usage": clamp_pct(cpu_usage),
            "temp": cpu_temp,
            "temp_source": cpu_temp_source,
            "power_w": extra_metrics.get("cpu_power_w"),
            "voltage_v": extra_metrics.get("cpu_voltage_v"),
        },
        "gpu": gpu or {
            "name": "GPU",
            "usage": None,
            "temp": None,
        },
        "memory": {
            "usage": clamp_pct(mem.percent),
            "used_gb": round((mem.total - mem.available) / (1024 ** 3), 1),
            "total_gb": round(mem.total / (1024 ** 3), 1),
        },
    }
    result["gpu"]["power_w"] = extra_metrics.get("gpu_power_w")
    result["gpu"]["power_limit_w"] = extra_metrics.get("gpu_power_limit_w")
    result["gpu"]["voltage_v"] = extra_metrics.get("gpu_voltage_v")
    return result


class MonitorState:
    def __init__(self, psutil_mod, sample_window, temp_cache_seconds):
        self.psutil = psutil_mod
        self.sample_window = sample_window
        self.temp_cache_seconds = max(1.0, float(temp_cache_seconds))
        self.cpu_temp = None
        self.cpu_temp_source = None
        self.next_temp_read = 0.0
        self.cpu_name = cpu_model_name()
        self.extra_metrics = {}
        self.next_extra_read = 0.0
        self.seq = 0

    def cached_cpu_temperature(self):
        now = time.monotonic()
        if now >= self.next_temp_read:
            self.cpu_temp, self.cpu_temp_source = read_cpu_temperature(self.psutil)
            self.next_temp_read = now + self.temp_cache_seconds
        return self.cpu_temp, self.cpu_temp_source

    def cached_extra_metrics(self):
        now = time.monotonic()
        if now >= self.next_extra_read:
            self.extra_metrics = read_extra_metrics()
            self.next_extra_read = now + 2.0
        return self.extra_metrics

    def snapshot(self):
        self.seq += 1
        cpu_temp, cpu_temp_source = self.cached_cpu_temperature()
        extra_metrics = self.cached_extra_metrics()
        data = collect_snapshot(self.psutil, self.sample_window, cpu_temp, cpu_temp_source, self.cpu_name, extra_metrics)
        data["seq"] = self.seq
        data["ok"] = True
        return data


class MonitorHandler(BaseHTTPRequestHandler):
    server_version = "HWMonitor/1.0"

    def log_message(self, fmt, *args):
        if not getattr(self.server, "quiet", False):
            super().log_message(fmt, *args)

    def send_json(self, status, value):
        raw = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("access-control-allow-origin", "*")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def send_text(self, status, text):
        raw = text.encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "text/plain; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/health"):
            self.send_text(200, "ok\nGET /api/state\n")
            return
        if path == "/api/state":
            try:
                self.send_json(200, self.server.monitor_state.snapshot())
            except Exception as exc:
                self.send_json(500, {"ok": False, "error": str(exc)})
            return
        self.send_json(404, {"ok": False, "error": "not found"})


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Serve desktop hardware metrics for the Cubic HW Monitor app.")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"listen host, default: {DEFAULT_HOST}")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"listen port, default: {DEFAULT_PORT}")
    parser.add_argument("--sample-window", type=float, default=0.2, help="CPU sampling window in seconds")
    parser.add_argument("--temp-cache-seconds", type=float, default=DEFAULT_TEMP_CACHE_SECONDS, help="seconds between temperature sensor reads")
    parser.add_argument("--once", action="store_true", help="print one snapshot and exit")
    parser.add_argument("--quiet", action="store_true", help="only print errors")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv or sys.argv[1:])
    try:
        import psutil
    except Exception as exc:
        print("psutil is required: pip install psutil GPUtil", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 2

    psutil.cpu_percent(interval=None)
    if args.once:
        print(json.dumps(collect_snapshot(psutil, args.sample_window), ensure_ascii=False, indent=2))
        return 0

    state = MonitorState(psutil, args.sample_window, args.temp_cache_seconds)
    state.cached_cpu_temperature()
    state.cached_extra_metrics()
    server = ThreadingHTTPServer((args.host, args.port), MonitorHandler)
    server.monitor_state = state
    server.quiet = args.quiet
    print(f"HW Monitor server listening on http://{args.host}:{args.port}")
    print("Device URL: http://192.168.0.80:8888/api/state")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
