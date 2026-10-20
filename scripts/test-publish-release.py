"""Exercise publish ordering and failure guards without building or uploading."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(__file__).with_name('publish-release.sh').read_text()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / 'scripts').mkdir()
    (root / 'Resources').mkdir()
    (root / 'Resources/ReleaseNotes.md').write_text('Release notes')
    (root / 'dist').mkdir()
    binaries = root / 'bin'
    binaries.mkdir()
    mock = binaries / 'mock'
    mock.write_text('#!' + sys.executable + '''
import os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
case = os.environ['CASE']
with open('calls', 'a') as log:
    log.write(name + ' ' + ' '.join(args) + '\\n')
if name == 'plist':
    print('https://github.com/owner/repo/releases/latest/download/appcast.xml' if 'SUFeedURL' in args[1] else '1')
elif name == 'gh':
    if args[:2] == ['auth', 'status'] and case == 'auth': sys.exit(1)
    if args[:2] == ['repo', 'view']: print('false')
    if args[0] == 'api':
        if case == 'api': sys.exit(1)
        if case == 'duplicate': print('v1')
elif name == 'git':
    if args[0] == 'status':
        if case == 'dirty' or (case == 'changed' and Path('built').exists()): print(' M source')
    elif args[0] == 'rev-parse': print('commit')
    elif args[0] == 'ls-remote': print('other' if case == 'unpushed' else 'commit')
elif name == 'bash' and args == ['scripts/release-macos.sh']:
    Path('built').touch()
''')
    mock.chmod(0o755)
    for name in ['plist', 'gh', 'git', 'bash', 'shasum', 'python3']:
        (binaries / name).symlink_to(mock)
    script = root / 'scripts/publish-release.sh'
    script.write_text(source.replace('/usr/libexec/PlistBuddy', str(binaries / 'plist')))
    for case in ['ok', 'auth', 'api', 'duplicate', 'dirty', 'unpushed', 'changed']:
        (root / 'calls').unlink(missing_ok=True)
        (root / 'built').unlink(missing_ok=True)
        result = subprocess.run(['/bin/bash', str(script)], cwd=root,
            env={**os.environ, 'PATH': f'{binaries}:/usr/bin:/bin', 'CASE': case},
            capture_output=True, text=True)
        calls = (root / 'calls').read_text()
        published = 'gh release create' in calls
        built = (root / 'built').exists()
        assert (result.returncode == 0) == (case == 'ok'), (case, result.stderr)
        assert published == (case == 'ok'), (case, calls)
        assert built == (case in ['ok', 'changed']), (case, calls)
        if published:
            assert '--target commit' in calls
            assert calls.index('gh api') < calls.index('bash scripts/release-macos.sh') < calls.index('gh release create')
        print(f'PASS: {case}')
