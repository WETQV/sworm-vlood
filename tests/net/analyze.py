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


def clock_offsets(folder):
    """Сдвиг часов каждого процесса к часам хоста (CLOCK_OFFSET из стенда; на одной машине ~0)."""
    off = {}
    for path in glob.glob(os.path.join(folder, "*_events.csv")):
        tag = os.path.basename(path)[:-11]
        for row in load_rows(path):
            if row["event"].startswith("CLOCK_OFFSET "):
                off[tag] = int(row["event"].split(" ")[1])
    return off


def load_shifted(path, tag, offsets):
    """Строки лога с временем, переведённым на часы хоста."""
    rows = load_rows(path)
    d = offsets.get(tag, 0)
    if d:
        for r in rows:
            r["t_ms"] = str(int(r["t_ms"]) + d)
    return rows


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
        procs[base[:-4]] = {"rows": load_shifted(path, base[:-4], clock_offsets(folder))}
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


def collect_events(folder):
    """События стенда: (время, процесс, слова события)."""
    events = []
    offsets = clock_offsets(folder)
    for path in glob.glob(os.path.join(folder, "*_events.csv")):
        tag = os.path.basename(path)[:-11]
        for row in load_shifted(path, tag, offsets):
            events.append((int(row["t_ms"]), tag, row["event"].split(" ")))
    return sorted(events, key=lambda e: e[0])


def actions_report(folder):
    """Сетевые действия игроков и ИИ: задержки доставки и согласованность времени показа."""
    ev = collect_events(folder)
    sent = {}          # (kind, peer, seq) -> t
    host_lat, obs_lat, relay_lat, offsets, ai_offsets = [], [], [], [], []
    host_played = {}   # (kind, peer, seq) -> момент, когда хост принял/выполнил
    for t, tag, w in ev:
        if w[0] == "SENT":
            sent[(w[1], w[2], w[3])] = t
        elif w[0] == "PLAYED" and tag == "host":
            host_played[(w[1], w[2], w[3])] = t
    for (kind, peer, seq), t in sent.items():
        if peer == "1":  # действия самого хоста: "принял" = отправил
            host_played.setdefault((kind, peer, seq), t)
    for t, tag, w in ev:
        if w[0] == "PLAYED":
            key = (w[1], w[2], w[3])
            if key not in sent:
                continue
            if tag == "host":
                host_lat.append(t - sent[key])
            else:
                recv = t - float(w[5])  # момент приёма = показ − задержка выравнивания
                obs_lat.append(recv - sent[key])
                if key in host_played:
                    relay_lat.append(recv - host_played[key])
                if w[1] == "attack":
                    offsets.append(float(w[4]))
        elif w[0] == "AIEV" and tag != "host":
            if w[1] in ("3", "4"):  # SlimeAI.State: 3 = WINDUP (замах), 4 = LUNGE (удар)
                ai_offsets.append(float(w[2]))
    # Согласованность по телу: где было тело владельца в момент атаки (его лог) и где тело
    # показано у наблюдателя в момент проигрывания атаки (лог наблюдателя). Не зависит от анимации оружия.
    body_offsets = []
    tracks = {}  # (процесс, peer) -> [(t, x, y)]
    for path in glob.glob(os.path.join(folder, "*.csv")):
        base = os.path.basename(path)
        if base.endswith("_stats.csv") or base.endswith("_events.csv"):
            continue
        for r in load_shifted(path, base[:-4], clock_offsets(folder)):
            tracks.setdefault((base[:-4], r["peer"]), []).append((int(r["t_ms"]), float(r["x"]), float(r["y"])))
    owner_of = {}
    for (proc, peer), tr in tracks.items():
        tr.sort()
    for path in glob.glob(os.path.join(folder, "*.csv")):
        base = os.path.basename(path)
        if base.endswith("_stats.csv") or base.endswith("_events.csv"):
            continue
        for r in load_rows(path)[:200]:
            if r["local"] == "1":
                owner_of[r["peer"]] = base[:-4]
                break
    for t, tag, w in ev:
        if w[0] == "PLAYED" and w[1] == "attack" and tag != "host":
            key = (w[1], w[2], w[3])
            owner_proc = owner_of.get(w[2])
            if key in sent and owner_proc and (owner_proc, w[2]) in tracks and (tag, w[2]) in tracks:
                ox, oy = interp(tracks[(owner_proc, w[2])], sent[key])
                vx, vy = interp(tracks[(tag, w[2])], t)
                body_offsets.append(math.dist((ox, oy), (vx, vy)))
    return {"host_lat": host_lat, "obs_lat": obs_lat, "relay_lat": relay_lat, "offsets": offsets,
            "ai_offsets": ai_offsets, "body_offsets": body_offsets}


def integrity_report(folder):
    """Сценарий integrity: отправлено / принято хостом / попаданий / смертей."""
    ev = collect_events(folder)
    rep = {}
    host_peer = None
    for t, tag, w in ev:
        if w[0] == "INTEGRITY_SENT":
            rep.setdefault(w[1], {})["sent"] = int(w[3])
            rep[w[1]]["class"] = int(w[2])
            if tag == "host":
                host_peer = w[1]
        elif w[0] == "PLAYED" and tag == "host" and w[1] == "attack":
            rep.setdefault(w[2], {}).setdefault("accepted", 0)
            rep[w[2]]["accepted"] += 1
        elif w[0] == "HIT":
            rep.setdefault(w[1], {}).setdefault("hits", 0)
            rep[w[1]]["hits"] += 1
            rep[w[1]]["dmg"] = rep[w[1]].get("dmg", 0) + int(w[2])
        elif w[0] == "SPAM_SENT":
            rep.setdefault(w[1], {})["spam"] = 21
    deaths = {tag: int(w[1]) for t, tag, w in ev if w[0] == "DIED_COUNT"}
    if host_peer and host_peer in rep:  # свои атаки хост не валидирует — принято = отправлено
        rep[host_peer]["accepted"] = rep[host_peer].get("sent", 0)
    return rep, deaths


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

    act = actions_report(folder)
    if act["host_lat"] or act["ai_offsets"]:
        print("\n-- Сетевые действия (мс / px)")
        f = lambda v: f"p50={pct(v,.5):.0f} p95={pct(v,.95):.0f} max={max(v or [float('nan')]):.0f} n={len(v)}"
        print(f"  владелец → хост (приём запроса):          {f(act['host_lat'])}")
        print(f"  хост → наблюдатель (подтверждение):       {f(act['relay_lat'])}")
        print(f"  владелец → наблюдатель (всего):             {f(act['obs_lat'])}")
        print(f"  атака игрока: оружие ↔ точка удара у наблюдателя, px: {f(act['offsets'])}")
        print(f"  атака игрока: тело у наблюдателя ↔ тело владельца в момент удара, px: {f(act['body_offsets'])}")
        print(f"  атака врага: тело ↔ точка события у клиента, px:  {f(act['ai_offsets'])}")

    rep, deaths = integrity_report(folder)
    if any("sent" in r for r in rep.values()):
        print("\n-- Целостность (манекен): каждое принятое хостом действие = ровно одно попадание")
        print(f"  {'игрок':12s} {'класс':>5s} {'отправлено':>10s} {'спам+повтор':>11s} {'принято':>8s} {'попаданий':>9s} {'урон':>6s}")
        for peer, r in rep.items():
            if "sent" not in r and "hits" not in r:
                continue
            print(f"  {peer:12s} {r.get('class', -1):5d} {r.get('sent', 0):10d} {r.get('spam', 0):11d} "
                  f"{r.get('accepted', 0):8d} {r.get('hits', 0):9d} {r.get('dmg', 0):6d}")
        print(f"  смертей манекена по процессам: {deaths}")

    ev = collect_events(folder)
    life = [(t, tag, " ".join(w)) for t, tag, w in ev
            if w[0] in ("LEAVING", "SESSION_END", "FLOOR", "FLOOR_STUCK", "TIMEOUT", "RESTART", "HOST_LEAVING")]
    if life:
        t0 = life[0][0]
        print("\n-- Жизненный цикл")
        for t, tag, text in life:
            print(f"  {(t - t0)/1000:6.1f}с {tag:6s} {text}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
