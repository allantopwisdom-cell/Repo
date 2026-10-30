#!/usr/bin/env python3
"""Compile the actual Logos constructor in a host-only fault-injection harness."""
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
assert source.count('%ctor {') == 1, 'expected one production constructor'
preamble = source.split('%group ', 1)[0]
body = source.split('%ctor {', 1)[1]
for old, new in (('%init(PCRCommonHooks)', 'TestInitCommon()'), ('%init(PCRGPHooks)', 'TestInitGP()')):
    assert body.count(old) == 1, 'unexpected production hook initialization'
    body = body.replace(old, new)
assert not re.search(r'%(?:ctor|init|orig|hook|group|end)\b', body), 'unhandled Logos in constructor'
Path(sys.argv[2]).write_text(preamble + '\nstatic void PCRTestInitialize(void) {' + body)
