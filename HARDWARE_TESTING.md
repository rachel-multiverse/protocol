# Rachel vintage hardware validation

Rachel distinguishes five levels of evidence for each machine and transport:

| Level | Meaning |
|---|---|
| Source | A client exists, but its transport may still be a stub or proposal. |
| Build | The release image and transport-specific regression checks pass in CI. |
| Emulator | The image boots and completes the smoke test in an emulator. |
| Community hardware | A named adapter completes the smoke test on a real machine. |
| Maintainer hardware | The same test is reproducible on hardware held by a maintainer. |

Only the last two levels justify saying a physical configuration is supported.

## Five-minute smoke test

1. Record the computer model and board revision, RAM expansion, video standard,
   network adapter revision, adapter firmware and client image commit.
2. Start `rachel-server` on raw TCP port 6502 with one human and one AI.
3. Boot the CI-built client image and connect to the server's IPv4 address.
4. Confirm WELCOME, GAME_START and the initial hand are displayed.
5. Complete one legal play or draw and confirm the next turn begins.
6. Continue until either the game completes or ten turns have passed.
7. Reboot and repeat once to expose initialization and stale-buffer faults.

## Evidence to attach

- a photograph or short video showing the machine, adapter and game screen;
- the exact CI artifact or commit hash;
- server logs covering connection through the last successful action;
- a serial trace when the adapter or emulator can provide one;
- whether failure is repeatable after a cold boot.

Remove Wi-Fi credentials, public addresses and reconnect tokens before sharing
logs. A failure is useful evidence and does not need to be polished into a bug
diagnosis by the tester.

## Result template

```text
Machine / revision:
Region / video standard:
RAM or required expansions:
Network adapter / revision:
Adapter firmware:
Rachel client commit:
Rachel server commit:
Passed: boot / connect / initial hand / action / next turn / game completion
Repeatable after cold boot: yes / no
Emulator or physical hardware:
Evidence links:
Notes:
```

## Transport contract

Vintage raw TCP clients connect to port **6502**. Modern TLS clients use port
**443**. Serial adapters use either ESP-AT framing or Hayes-compatible
transparent mode as documented in [CLIENT_GUIDE.md](CLIENT_GUIDE.md).
