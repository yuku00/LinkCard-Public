from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
b=(r/'BridgeSnapshot.inc').read_text()
production=b[b.index('static void FPBridgeAfterAlert('):b.index('static void FPOfferBridgeCapture(')]
fixture=(r/'tests/bridge-host.m').read_text()
Path(sys.argv[1]).write_text(fixture.replace('/* PRODUCTION */',production))
