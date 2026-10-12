#!/usr/bin/env python3
"""Supply authorized application credentials to Envied without logging them."""
import os
from pathlib import Path
import re
import tempfile


def configure(path: Path) -> None:
    values = {
        'deezerClientId': os.environ.get('DEEZER_CLIENT_ID', ''),
        'deezerClientSecret': os.environ.get('DEEZER_CLIENT_SECRET', ''),
    }
    if not any(values.values()):
        return  # Preserve an existing local configuration.
    if not all(values.values()):
        raise ValueError('Both Deezer application credentials must be configured')
    # Reject dotenv syntax and control characters rather than changing a key.
    if any(not re.fullmatch(r'[A-Za-z0-9_.-]+', value) for value in values.values()):
        raise ValueError('Invalid Deezer application credential encoding')
    lines = path.read_text().splitlines()
    lines = [line for line in lines
             if not re.match(r'^\s*(deezerClientId|deezerClientSecret)\s*=', line)]
    lines.extend(f'{key}={value}' for key, value in values.items())
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent,
                                         prefix='.env-', delete=False) as output:
            temporary = Path(output.name)
            output.write('\n'.join(lines) + '\n')
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    try:
        configure(Path(__file__).resolve().parent.parent / 'lib/.env')
    except (OSError, ValueError):
        raise SystemExit('Cannot configure Deezer application credentials; no values were logged')
