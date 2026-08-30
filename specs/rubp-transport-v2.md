# RUBP Transport v2

Status: frozen transport contract.

RUBP v2 adds accidental-corruption detection for physical links between a
network adapter and vintage client while preserving fixed 64-byte frames.

## Header delta from v1

| Offset | Size | v2 field |
|---:|---:|---|
| 4 | 1 | transport version `0x02` |
| 12 | 2 | low timestamp bits, big-endian; zero is valid |
| 14 | 2 | CRC-16/CCITT-FALSE, big-endian |

Bytes 0-11 and the 48-byte payload at 16-63 are unchanged.

## CRC

- Width: 16
- Polynomial: `0x1021`
- Initial value: `0xFFFF`
- Input/output reflection: false
- Final xor: `0x0000`
- Check vector: ASCII `123456789` → `0x29B1`
- Coverage: all 64 bytes with bytes 14 and 15 zeroed

Receivers must validate CRC before dispatch. A failed frame has no trustworthy
type, sequence, identity, state hash, or payload and is discarded in full.

## Negotiation and compatibility

The HELLO header selects the transport version for that connection. Hosts
reply in the selected version. Payload `specVersion` remains the RachelSpec
rules version and is not transport negotiation.

Version 1 remains valid and unchanged. Mixed-version lobbies are supported by
encoding shared messages separately at each connection boundary.

## Recovery

CRC is detection, not acknowledgement. After identity assignment, clients use
the existing `SYNC_REQUEST` flow to recover authoritative public/private state.
Physical transports that cannot accept consecutive 64-byte frames require an
inter-frame idle interval or a pull/flow-control adapter mode.
