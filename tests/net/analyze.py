"""Анализ логов сетевого стенда (tests/net/net_harness.gd).

Использование:  python tests/net/analyze.py <папка_с_логами>

Истина о позиции игрока — лог его владельца (local=1). Для каждого наблюдателя
(хост/другие клиенты) сравниваем, где он видит этого игрока в тот же момент времени.
Все процессы работают на одной машине и пишут системное время (unix, мс), поэтому моменты сравнимы.
Время в отчёте — относительно начала сценария у хоста.
"""
import csv
import glob
import math
import os
import sys
from bisect import bisect_left

JUMP_PX = 40.0        # скачок за один кадр больше этого — «телепорт» (рывок даёт ~13 px/кадр)
SNAP_ERROR_PX = 64.0  # ошибка позиции больше этого — видимый рассинхрон


def pct(values, p):
    if not values:
        return float("nan")
    s = sorted(values)
    return s[min(len(s) - 1, int(len(s) * p))]


def load_rows(path):
    if not os.path.exists(path):
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def scenario_start(events_path):
    for row in load_rows(events_path):
        if row["event"].startswith("scenario=") and row["event"].endswith("start"):
            return int(row["t_ms"])
    return 0


def interp(track, t):
    """track: отсортированный список (t, x, y). Линейная интерполяция."""
    ts = [p[0] for p in track]
    i = bisect_left(ts, t)
    if i <= 0:
        return track[0][1], track[0][2]
    if i >= len(track):
        return track[-1][1], track[-1][2]
    t0, x0, y0 = track[i - 1]
    t1, x1, y1 = track[i]
    k = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
    return x0 + (x1 - x0) * k, y0 + (y1 - y0) * k


def collect(folder):
    """Структурированные метрики прогона: owner_jumps, pairs, stats, netstats."""
    procs = {}
    for path in glob.glob(os.path.join(folder, "*.csv")):
        base = os.path.basename(path)
        if base.endswith("_stats.csv") or base.endswith("_events.csv"):
            continue
        procs[base[:-4]] = {"rows": load_rows(path)}
    start = scenario_start(os.path.join(folder, "host_events.csv"))

    truth = {}
    for p in procs.values():
        for r in p["rows"]:
            if r["local"] == "1":
                truth.setdefault(r["peer"], []).append((int(r["t_ms"]) - start, float(r["x"]), float(r["y"])))
    for v in truth.values():
        v.sort()

    result = {"owner_jumps": {}, "pairs": [], "stats": {}, "netstats": {}}
    for tag, p in procs.items():
        prev, jumps = None, []
        for r in p["rows"]:
            if r["local"] != "1":
                continue
            cur = (int(r["t_ms"]) - start, float(r["x"]), float(r["y"]))
            if prev and math.dist(prev[1:], cur[1:]) > JUMP_PX:
                jumps.append((cur[0], math.dist(prev[1:], cur[1:])))
            prev = cur
        result["owner_jumps"][tag] = jumps

        by_peer = {}
        for r in p["rows"]:
            if r["local"] == "0":
                by_peer.setdefault(r["peer"], []).append(r)
        for peer, rows in by_peer.items():
            if peer not in truth:
                continue
            errs, shake, jumps_n, fake = [], [], 0, 0
            prev = None
            for r in rows:
                t = int(r["t_ms"]) - start
                x, y = float(r["x"]), float(r["y"])
                tx, ty = interp(truth[peer], t)
                if r["alive"] == "1" and t >= 0:
                    errs.append(math.dist((x, y), (tx, ty)))
                if prev:
                    d = math.dist(prev[1:], (x, y))
                    ox0, oy0 = interp(truth[peer], prev[0])
                    owner_d = math.dist((ox0, oy0), (tx, ty))
                    if d > JUMP_PX:
                        jumps_n += 1
                        if owner_d < d * 0.5:  # у владельца за тот же интервал так не прыгал
                            fake += 1
                    elif t >= 0:
                        shake.append(abs(d - owner_d))
                prev = (t, x, y)
            result["pairs"].append({"observer": tag, "peer": peer, "err_p50": pct(errs, .5), "err_p95": pct(errs, .95),
                                    "err_max": max(errs or [0]), "over64": sum(e > SNAP_ERROR_PX for e in errs),
                                    "jumps": jumps_n, "fake": fake, "shake_p95": pct(shake, .95)})

    for path in sorted(glob.glob(os.path.join(folder, "*_stats.csv"))):
        tag = os.path.basename(path)[:-10]
        rows = load_rows(path)[1:]  # первая секунда — прогрев
        if not rows:
            continue
        col = lambda k: [float(r[k]) for r in rows]
        rtt = [v for v in col("rtt_ms") if v >= 0]
        loss = [v for v in col("loss") if v >= 0]
        result["stats"][tag] = {"rtt": pct(rtt, .5) if rtt else float("nan"),
                                "loss": pct(loss, .5) * 100 if loss else float("nan"),
                                "sent_kb": pct(col("sent_bytes"), .5) / 1024, "recv_kb": pct(col("recv_bytes"), .5) / 1024,
                                "pkts_out": pct(col("sent_pkts"), .5), "frame_p99": pct(col("frame_p99"), .5),
                                "frame_max": max(col("frame_max"))}
    for path in glob.glob(os.path.join(folder, "*_events.csv")):
        for row in load_rows(path):
            if row["event"].startswith("NETSTATS "):
                result["netstats"][os.path.basename(path)[:-11]] = row["event"][9:]
    return result


def main(folder):
    res = collect(folder)
    print(f"== {folder}")
    print("\n-- Скачки у владельца (телепорт/коррекция своего персонажа)")
    for tag, jumps in res["owner_jumps"].items():
        desc = ", ".join(f"{t/1000:.1f}с:{d:.0f}px" for t, d in jumps[:8])
        print(f"  {tag:8s} скачков={len(jumps):3d}  {desc}")

    print("\n-- Как видят чужих игроков (ошибка = расстояние до позиции у владельца в тот же момент)")
    print("  дрожание = |смещение за кадр у наблюдателя − смещение владельца за тот же интервал| (p95, px)")
    print(f"  {'наблюдатель':12s} {'игрок':12s} {'p50':>6s} {'p95':>6s} {'max':>6s} {'>64px':>6s} {'скачки':>7s} {'ложн.скачки':>11s} {'дрожание':>9s}")
    for p in res["pairs"]:
        print(f"  {p['observer']:12s} {p['peer']:12s} {p['err_p50']:6.1f} {p['err_p95']:6.1f} {p['err_max']:6.0f} "
              f"{p['over64']:6d} {p['jumps']:7d} {p['fake']:11d} {p['shake_p95']:9.2f}")

    print("\n-- Сеть и кадр (медианы по секундам)")
    print(f"  {'процесс':10s} {'RTT мс':>7s} {'потери':>7s} {'отпр КБ/с':>10s} {'приём КБ/с':>10s} {'пак/с out':>9s} {'кадр p99':>9s} {'кадр max':>9s}")
    for tag, s in res["stats"].items():
        print(f"  {tag:10s} {s['rtt']:7.1f} {s['loss']:6.1f}% {s['sent_kb']:10.1f} {s['recv_kb']:10.1f} "
              f"{s['pkts_out']:9.0f} {s['frame_p99']:9.1f} {s['frame_max']:9.1f}")
    for tag, ns in res["netstats"].items():
        print(f"  NETSTATS {tag}: {ns}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
