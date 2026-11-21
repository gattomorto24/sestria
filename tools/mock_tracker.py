#!/usr/bin/env python3
"""Tracker WebTorrent minimale per i collaudi locali di Sestria online.

Riproduce solo ciò che serve alla segnalazione WebRTC: annunci con offerte inoltrate a peer casuali dello sciame,
risposte instradate con to_peer_id e rimozione del peer alla chiusura del socket. Solo libreria standard.
Uso: python3 tools/mock_tracker.py [porta]   (default 32650, ascolta solo su 127.0.0.1)
"""
import asyncio, base64, hashlib, json, random, struct, sys

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
swarms = {}  # info_hash -> {peer_id: writer}


async def send_text(writer, text):
    data = text.encode()
    n = len(data)
    head = b"\x81" + (bytes([n]) if n < 126 else b"\x7e" + struct.pack(">H", n) if n < 65536 else b"\x7f" + struct.pack(">Q", n))
    writer.write(head + data)
    await writer.drain()


async def read_frame(reader):
    head = await reader.readexactly(2)
    opcode, masked, n = head[0] & 15, head[1] & 128, head[1] & 127
    if n == 126:
        n = struct.unpack(">H", await reader.readexactly(2))[0]
    elif n == 127:
        n = struct.unpack(">Q", await reader.readexactly(8))[0]
    if n > 1 << 20:
        raise ConnectionError("frame troppo grande")
    mask = await reader.readexactly(4) if masked else b"\0\0\0\0"
    payload = bytearray(await reader.readexactly(n))
    for i in range(n):
        payload[i] ^= mask[i % 4]
    return opcode, bytes(payload)


async def handle(reader, writer):
    mine = set()
    try:
        request = (await reader.readuntil(b"\r\n\r\n")).decode("latin1")
        key = next(line.split(":", 1)[1].strip() for line in request.split("\r\n") if line.lower().startswith("sec-websocket-key"))
        accept = base64.b64encode(hashlib.sha1(key.encode() + GUID).digest()).decode()
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % accept).encode())
        await writer.drain()
        while True:
            opcode, payload = await read_frame(reader)
            if opcode == 8:
                break
            if opcode == 9:
                writer.write(b"\x8a" + bytes([len(payload)]) + payload)
                continue
            if opcode != 1:
                continue
            try:
                m = json.loads(payload.decode())
            except ValueError:
                continue
            if m.get("action") != "announce":
                continue
            ih, pid = m.get("info_hash", ""), m.get("peer_id", "")
            swarm = swarms.setdefault(ih, {})
            swarm[pid] = writer
            mine.add((ih, pid))
            if "answer" in m and m.get("to_peer_id") in swarm:
                await send_text(swarm[m["to_peer_id"]], json.dumps({"action": "announce", "info_hash": ih, "offer_id": m.get("offer_id"), "peer_id": pid, "answer": m["answer"]}))
            offers = m.get("offers") or []
            others = [p for p in swarm if p != pid]
            random.shuffle(others)
            for i, offer in enumerate(offers):
                if others:
                    target = others[i % len(others)]
                    await send_text(swarm[target], json.dumps({"action": "announce", "info_hash": ih, "offer_id": offer.get("offer_id"), "peer_id": pid, "offer": offer.get("offer")}))
            await send_text(writer, json.dumps({"action": "announce", "interval": 120, "info_hash": ih, "complete": len(swarm), "incomplete": 0}))
    except (asyncio.IncompleteReadError, ConnectionError, StopIteration):
        pass
    finally:
        for ih, pid in mine:
            if swarms.get(ih, {}).get(pid) is writer:
                del swarms[ih][pid]
        writer.close()


async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 32650
    server = await asyncio.start_server(handle, "127.0.0.1", port)
    print("tracker di prova su ws://127.0.0.1:%d" % port, flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
