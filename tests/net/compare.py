"""Сравнение двух серий прогонов стенда (до/после) по конфигурациям.

Использование:
  python tests/net/compare.py "<glob папок ДО>" "<glob папок ПОСЛЕ>"
Папки сопоставляются по конфигурации из имени: sworm_net_<сценарий>_<N>p_<RTT>ms_<время>.
Если в серии несколько прогонов одной конфигурации, берётся последний.
"""
import glob
import math
import os
import re
import sys

from analyze import collect

NAME = re.compile(r"sworm_net_(\w+?)_(\d+)p_(\d+)ms_\d+$")


def series(pattern):
    runs = {}
    for folder in sorted(glob.glob(pattern)):
        m = NAME.search(os.path.basename(folder))
        if m:
            runs[(m.group(1), int(m.group(2)), int(m.group(3)))] = folder
    return runs


def summarize(folder):
    r = collect(folder)
    pairs = r["pairs"]
    med = lambda k: sorted(p[k] for p in pairs)[len(pairs) // 2] if pairs else float("nan")
    worst = lambda k: max((p[k] for p in pairs), default=float("nan"))
    clients = [s for t, s in r["stats"].items() if t.startswith("c")]
    host = r["stats"].get("host", {})
    return {
        "err_p50": med("err_p50"), "err_p95": worst("err_p95"),
        "over64": sum(p["over64"] for p in pairs), "fake": sum(p["fake"] for p in pairs),
        "shake": worst("shake_p95"),
        "client_kb": sum(c["sent_kb"] for c in clients) / len(clients) if clients else float("nan"),
        "host_kb": host.get("sent_kb", float("nan")),
    }


def fmt(v, digits=1):
    return "—" if isinstance(v, float) and math.isnan(v) else f"{v:.{digits}f}" if isinstance(v, float) else str(v)


def main(before_glob, after_glob):
    before, after = series(before_glob), series(after_glob)
    print("| Конфигурация | Ошибка p50, px | Ошибка p95 (худш.), px | Кадров >64 px | Ложных скачков | Дрожание p95 (худш.), px | Клиент отпр., КБ/с | Хост отпр., КБ/с |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for key in sorted(set(before) & set(after), key=lambda k: (k[1], k[0], k[2])):
        b, a = summarize(before[key]), summarize(after[key])
        cells = []
        for k, d in [("err_p50", 1), ("err_p95", 1), ("over64", 0), ("fake", 0), ("shake", 2), ("client_kb", 1), ("host_kb", 1)]:
            cells.append(f"{fmt(b[k], d)} → **{fmt(a[k], d)}**")
        print(f"| {key[1]} игр., {key[0]}, RTT+{key[2]} мс | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
