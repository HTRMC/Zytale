# Zytale - Hytale Server Rewrite in Zig

## Overview

Start with a **proxy** to intercept and validate packet parsing against real Hytale traffic, then incrementally replace server functionality.

## Revised Approach: Proxy-First

```
[Hytale Client] <---> [Zytale Proxy] <---> [Real Hytale Server]
                           |
                      Log & Analyze
                        Packets
```

**Why proxy first:**

1. Validate packet parsing against real traffic
2. Understand protocol without reverse-engineering alone
3. Incrementally replace server responses
4. Debug mismatches immediately

## Project Structure

```
C:\Users\HTRMC\Dev\Projects\Zytale\
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig                 # Entry point (proxy mode)
│   ├── proxy/
│   │   ├── proxy.zig            # Main proxy logic
│   │   ├── client_conn.zig      # Client connection handler
│   │   ├── server_conn.zig      # Upstream server connection
│   │   └── logger.zig           # Packet logging/analysis
│   ├── net/
│   │   ├── packet/
│   │   │   ├── frame.zig        # Packet framing
│   │   │   ├── codec.zig        # Serialization
│   │   │   ├── varint.zig       # VarInt encoding
│   │   │   ├── registry.zig     # Packet ID registry
│   │   │   └── compression.zig  # Zstd wrapper
│   │   └── transport/
│   │       ├── tcp.zig          # TCP transport
│   │       └── quic.zig         # QUIC transport
│   └── protocol/
│       ├── packets/
│       │   ├── connection/      # Connect, Disconnect, Ping, Pong
│       │   ├── auth/            # Auth packets
│       │   ├── world/           # Chunk, block updates
│       │   └── entity/          # Entity updates
│       └── types.zig            # Common types (UUID, Vec3, etc.)
└── tools/
    └── packet_dump.zig          # Packet analysis tool
```

## Implementation Phases

### Phase 1: Basic Proxy Infrastructure

- [ ] Create project skeleton at `C:\Users\HTRMC\Dev\Projects\Zytale`
- [ ] TCP listener for client connections
- [ ] TCP client for upstream server connection
- [ ] Raw byte forwarding (passthrough mode)
- [ ] Basic logging of connection events

### Phase 2: Packet Framing

- [ ] Implement packet frame parsing: `[u32 LE len][u32 LE id][payload]`
- [ ] VarInt encoding/decoding (LEB128)
- [ ] Frame validation (size limits, valid IDs)
- [ ] Log packet IDs and sizes without parsing payload

### Phase 3: Compression

- [ ] Zstd decompression for reading packets
- [ ] Zstd compression for forwarding
- [ ] Flag packets as compressed/uncompressed based on registry

### Phase 4: Packet Parsing

- [ ] Define packet structures based on Java source
- [ ] Parse connection packets (Connect, Disconnect, Ping, Pong)
- [ ] Parse auth packets
- [ ] Log parsed packet contents
- [ ] Verify against Java packet definitions

### Phase 5: Packet Modification

- [ ] Intercept and modify specific packets
- [ ] Inject custom packets
- [ ] Block/filter packets
- [ ] Test client/server responses

### Phase 6: Server Replacement

- [ ] Handle connection packets directly (no upstream)
- [ ] Implement auth flow
- [ ] Implement world data sending
- [ ] Full server mode

## Key Java Files to Reference

| Java File                                  | Purpose             | For Proxy             |
| ------------------------------------------ | ------------------- | --------------------- |
| `protocol/io/PacketIO.java`                | Serialization utils | Frame parsing         |
| `protocol/io/VarInt.java`                  | VarInt codec        | LEB128 impl           |
| `protocol/PacketRegistry.java`             | Packet metadata     | ID mapping            |
| `protocol/packets/connection/Connect.java` | Connect packet      | First packet to parse |
| `protocol/packets/connection/Ping.java`    | Ping packet         | Keep-alive            |
| `server/core/io/netty/PacketEncoder.java`  | Encoding            | Compression logic     |
| `server/core/io/netty/PacketDecoder.java`  | Decoding            | Frame extraction      |

## Protocol Details (from Java analysis)

### Packet Frame Format

```
[4 bytes] Length (u32 LE) - payload size
[4 bytes] Packet ID (u32 LE)
[N bytes] Payload (possibly Zstd compressed)
```

### VarInt Encoding (LEB128)

- 7 bits of data per byte
- MSB = 1 means more bytes follow
- Max 5 bytes for 32-bit values

### Key Packets to Implement First

1. `Connect` (ID varies) - Initial handshake with protocol hash
2. `Ping`/`Pong` - Keep-alive mechanism
3. `Disconnect` - Clean disconnection
4. `AuthGrant`/`AuthToken` - Authentication flow

### Compression

- Zstd compression
- Level configured via `hytale.protocol.compressionLevel`
- Per-packet compression flag in registry

## Verification

1. **Passthrough test**: Client connects through proxy to real server, plays normally
2. **Logging test**: All packets logged with IDs and sizes
3. **Parse test**: Connection packets parsed correctly, fields match expected
4. **Modify test**: Inject a ping packet, verify server responds with pong
5. **Replace test**: Handle ping/pong locally without forwarding

## First Steps

1. `zig init` in `C:\Users\HTRMC\Dev\Projects\Zytale`
2. Create `src/main.zig` with CLI args (listen port, upstream host:port)
3. Implement TCP listener accepting single connection
4. Implement TCP client connecting to upstream
5. Forward bytes bidirectionally (raw passthrough)
6. Add hex dump logging for all traffic
7. Implement frame parsing to extract packet ID and size
