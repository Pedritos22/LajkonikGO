import math


def meters(a, b):
    """Coordinates are [latitude, longitude] throughout the internal API."""
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    value = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(value)))


def segment_distance(point, a, b):
    scale = math.cos(math.radians(point[0]))
    ax, ay = (a[1] - point[1]) * scale * 111195, (a[0] - point[0]) * 111195
    bx, by = (b[1] - point[1]) * scale * 111195, (b[0] - point[0]) * 111195
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy))) if dx or dy else 0
    return math.hypot(ax + t * dx, ay + t * dy)


def near_path(point, path, radius=30):
    return any(segment_distance(point, a, b) <= radius for a, b in zip(path, path[1:]))


def samples(path, spacing=25):
    result = []
    for a, b in zip(path, path[1:]):
        length = meters(a, b)
        count = max(1, math.ceil(length / spacing))
        for i in range(count):
            t = (i + .5) / count
            result.append(([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], length / count))
    return result


def decode_polyline(encoded, precision=6):
    result, lat, lon, index = [], 0, 0, 0
    while index < len(encoded):
        values = []
        for _ in range(2):
            value, shift = 0, 0
            while True:
                byte = ord(encoded[index]) - 63
                index += 1
                value |= (byte & 31) << shift
                shift += 5
                if byte < 32:
                    break
            values.append(~(value >> 1) if value & 1 else value >> 1)
        lat += values[0]
        lon += values[1]
        result.append([lat / 10 ** precision, lon / 10 ** precision])
    return result
