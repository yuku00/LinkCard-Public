# NFCPRO identification milestone — 0.9.0 (26)

Independent implementation, based on NXP PN532 User Manual UM0701-02 Rev.02:
https://www.nxp.com/docs/en/user-guide/141520.pdf
Sections 6.2 (frames/ACK/NAK/abort), 7.2.10 (Normal SAM mode), 7.2.11 (HSU wake),
7.3.1 (RF runtime parameters), 7.3.5 (ISO14443A discovery and target layout).
No proprietary implementation, private package, captured UID or user image is included.
All test identifiers are synthetic.

## Exact command scope
Only a foreground user click on **识别卡片** starts this sequence. Connection, trust,
auto-discovery and standard 180A reads do not send it. Routing requires the unchanged
built-in profile, exact PCR-NFCPRO/PCR-NFCPRO(BLE) advertisement, actual FF00/FF02/FF01,
and no conflicting 180A model (TD5322A if provided). Names are hints, not authentication.

1. HSU dummy wake bytes `55 55 00 00 00 00 00`; wait 250 ms after writes drain.
2. Host ACK `00 00 FF 00 FF 00` aborts a pending prior command; wait 250 ms and
   quarantine notifications. This also handles reader state surviving a BLE reconnect.
3. SAMConfiguration `14 01 14 01`: Normal mode, no SAM access. The timeout field
   only applies to Virtual Card mode, not the Normal mode used here.
4. RFConfiguration `32 05 00 00 01`: finite activation retries, never infinite FF.
5. InListPassiveTarget `4A 01 00`: one ISO14443A target, 106 kbit/s.
6. RFConfiguration `32 01 00`: field off after a valid card/no-card reply; keep BLE.

All command bodies are wrapped with the standard PN532 preamble/LEN/LCS/D4/DCS/postamble.
These modify PN532 operating state, not card memory or persistent reader configuration.
There is no EEPROM/flash command, register-write API, vendor extension, arbitrary
transceive, sector authentication, protected read, UID write, key recovery, cloud or DFU.
ISO14443A activation can include the chip's normal selection/RATS; it is not a sector read.
No claim of cloneability or UID-writability is made from SAK.

## Bounds and transport
One command in flight, no application resend. Startup writes have 2-second deadlines;
SAM/retry/field-off each 2 seconds, poll 4 seconds. Finite stage progression bounds the
whole attempt to about 14 seconds at worst, normally much less. Only NbTg=0 means
"no card"; a timeout means no valid response, not proof that no card is present.
Writes are at most min(20, CoreBluetooth maximumWriteValueLength), serialized by
with-response callbacks or canSendWriteWithoutResponse flow control. Early replies wait
for the last write callback before progression. Notifications may split at any byte.

The strict bounded parser validates ACK/NAK, LCS, DCS, TFI D5, response command and
postamble. Duplicate ACK, response-before-ACK, unsolicited/multiple responses,
extended frames (not needed here), extra/truncated data, bad UID/ATS lengths and
PN532 error frames fail closed. UID lengths 4/7/10 are supported. ATQA is displayed
MSB-first exactly as documented. ATS is validated but not exposed as stored card content.

Cancellation immediately clears timers/queues/results and disconnects, suppressing
automatic reconnect for this attempt. It does not pretend to retract bytes already sent
or synchronously power down the peripheral. Polling is already finite; the next explicit
reconnected attempt wakes and aborts old reader state before SAM. Idle/closing callbacks
are ignored. Background uses the existing stop/disconnect policy. No infinite retry.

## Privacy and UI
Existing four blur channels, workbench, dithering default, image picker and send-confirmation
preference remain unchanged. The stable device page gains a small identification panel.
UID lives only in memory, masked by default, explicitly revealable/copyable. Explicit copy
uses local-only pasteboard with 60-second expiry. Nothing is uploaded or logged. Disconnect
clears the result. This milestone does not implement reading sectors or writing cards.

## Verification boundaries
Reference source contracts, production coordinator linked only to host test doubles,
native XCTest parser/model tests and the existing four fullApp UI tests are required.
The real device-page button is physically tapped in UI tests while disconnected; it must
show its production guard and never fake a radio connection or scan success. The original
4 pass / 0 fail / 0 skip requirement, unit gates and default quiescence remain mandatory.
Public build diagnostics remain limited to 12 items and 640 characters per message;
raw logs, screenshots, accessibility dumps and user images are never uploaded.
Simulator/model tests do not establish real PCR-NFCPRO RF compatibility. First hardware
acceptance: connect the owned TD5322A, put one owned ISO14443A card on its antenna,
click once; compare locally, then test no-card and cancellation/reconnect. Do not publish UID.
