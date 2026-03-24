#!/usr/bin/env python3
"""Remove outer white ring from Clarion logo via edge flood-fill (transparent)."""
from collections import deque

from PIL import Image


def process_logo(path: str) -> None:
    im = Image.open(path).convert("RGBA")
    arr = im.load()
    w, h = im.size

    def is_light(px):
        r, g, b, a = px
        return r > 235 and g > 235 and b > 235 and a > 200

    visited = [[False] * w for _ in range(h)]
    q = deque()
    for x in range(w):
        q.append((0, x))
        q.append((h - 1, x))
    for y in range(h):
        q.append((y, 0))
        q.append((y, w - 1))

    while q:
        y, x = q.popleft()
        if y < 0 or y >= h or x < 0 or x >= w:
            continue
        if visited[y][x]:
            continue
        visited[y][x] = True
        px = arr[x, y]  # PIL load uses (x,y)
        if not is_light(px):
            continue
        arr[x, y] = (0, 0, 0, 0)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            q.append((y + dy, x + dx))

    im.save(path)


if __name__ == "__main__":
    process_logo("/home/clearmined/code/prod/cc_mobile/assets/clarionchain_logo.png")
