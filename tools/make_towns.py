"""產生 App 內建的鄉鎮市區邊界（見 docs/specs/weather.md 的「地點」「結構」）。

資料：內政部國土測繪中心「鄉鎮市區界線(TWD97經緯度)」https://data.gov.tw/dataset/7441
授權：政府資料開放授權條款第 1 版 https://data.gov.tw/license

用法：python3 tools/make_towns.py <下載的 zip> voice_todo/Infrastructure/Weather/towns.json

邊界簡化到約 100 公尺（0.001 度）、座標取到小數 4 位：定位送出的座標本來就只到約 1 公里，
隨機抽樣的判斷結果和原始邊界 99.6% 相同，檔案從 18 MB 變成約 0.5 MB。只用標準函式庫。
"""

import json
import struct
import sys
import zipfile

TOLERANCE = 0.001


def read_dbf(data):
    """每一筆的 COUNTYNAME + TOWNNAME，例如「臺北市信義區」。"""
    count = struct.unpack("<I", data[4:8])[0]
    header, record = struct.unpack("<HH", data[8:12])
    fields, pos = [], 32
    while data[pos] != 0x0D:
        fields.append((data[pos:pos + 11].split(b"\0")[0].decode(), data[pos + 16]))
        pos += 32
    names = []
    for i in range(count):
        row, offset, values = data[header + i * record + 1:header + (i + 1) * record], 0, {}
        for name, length in fields:
            values[name] = row[offset:offset + length].decode("utf-8").strip()
            offset += length
        names.append(values["COUNTYNAME"] + values["TOWNNAME"])
    return names


def read_shp(data):
    """每一筆的多個區塊（ring），點是 (經度, 緯度)。"""
    shapes, pos = [], 100
    while pos < len(data):
        length = struct.unpack(">I", data[pos + 4:pos + 8])[0] * 2
        content, pos = data[pos + 8:pos + 8 + length], pos + 8 + length
        part_count, point_count = struct.unpack("<II", content[36:44])
        parts = list(struct.unpack(f"<{part_count}I", content[44:44 + 4 * part_count])) + [point_count]
        start = 44 + 4 * part_count
        flat = struct.unpack(f"<{2 * point_count}d", content[start:start + 16 * point_count])
        points = list(zip(flat[0::2], flat[1::2]))
        shapes.append([points[parts[k]:parts[k + 1]] for k in range(part_count)])
    return shapes


def simplify(points, tolerance):
    """Douglas-Peucker，保留頭尾。"""
    keep, stack = {0, len(points) - 1}, [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = points[a], points[b]
        dx, dy = x2 - x1, y2 - y1
        length = (dx * dx + dy * dy) ** 0.5
        best, index = 0, None
        for i in range(a + 1, b):
            x, y = points[i]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / length if length else ((x - x1) ** 2 + (y - y1) ** 2) ** 0.5
            if d > best:
                best, index = d, i
        if index is not None and best > tolerance:
            keep.add(index)
            stack += [(a, index), (index, b)]
    return [points[i] for i in sorted(keep)]


def main(source, output):
    archive = zipfile.ZipFile(source)
    member = next(n for n in archive.namelist() if n.startswith("TOWN_MOI_") and n.endswith(".shp"))
    names = read_dbf(archive.read(member[:-4] + ".dbf"))
    shapes = read_shp(archive.read(member))
    towns = []
    for name, rings in zip(names, shapes):
        simplified = [simplify(ring, TOLERANCE) for ring in rings]
        flat = [[round(c, 4) for point in ring for c in point] for ring in simplified if len(ring) >= 4]
        towns.append({"name": name, "rings": flat})
    with open(output, "w", encoding="utf-8") as file:
        json.dump(towns, file, ensure_ascii=False, separators=(",", ":"))
    print(f"{len(towns)} 個鄉鎮市區，{sum(len(r) // 2 for t in towns for r in t['rings'])} 個點")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
