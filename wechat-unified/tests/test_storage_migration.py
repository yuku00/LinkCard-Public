"""Synthetic directories only; compiles and executes the production migration core."""
import hashlib
import errno
from pathlib import Path
import os
import pathlib
import pwd
import sys
import shutil
import struct
import subprocess
import tempfile
import time
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

def receipt_bytes(*fields):
    # Match production's uint64_t casts even if Darwin dev_t is signed.
    return struct.pack('=QQQQQ', *(value & ((1 << 64) - 1) for value in fields))

class Migration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.cli = pathlib.Path(cls.build.name) / 'migrate'
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT/'Sources'), str(ROOT/'tests/storage_migration_cli.c'), '-o', str(cls.cli)], check=True)
    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = pathlib.Path(self.tmp.name)
        self.old = self.base/'support'; self.old.mkdir()
        self.docs = self.base/'Documents'; self.docs.mkdir()
        self.source = self.old/'WeChatUnified'
        self.target = self.docs/'WeChatUnifiedStorage'
        self.stage = self.docs/'.WUStorage-migration'
    def fixture(self):
        self.source.mkdir()
        for name, data in {'config.json': b'{"schema":1}', 'backup.json': b'broken backup\0', 'VoicePacks/6162/index.plist': b'voice', 'Repository/6364.plist': b'message refs', 'Themes/8F82A3B2-B87B-4E68-B1DA-273DB0156A63/气泡.png': b'image'}.items():
            path = self.source/name; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    def unsupported_commit(self, result):
        return result.returncode == 1 and 'ish' in os.uname().release and b'errno=22:' in result.stderr and '系统不支持无覆盖原子提交'.encode() in result.stderr
    def run_migration(self, ok):
        result = subprocess.run([self.cli, self.old, self.docs], capture_output=True)
        if ok and self.unsupported_commit(result):
            self.assertFalse(self.target.exists())
            self.assertTrue((self.stage/'.wu-storage-v1').is_file())
            self.assertEqual(self.snapshot(self.source), self.snapshot(self.stage/'WeChatUnified'))
            self.skipTest('iSH rejects renameat2(RENAME_NOREPLACE); verified staged bytes, NOT atomic commit')
        self.assertEqual(result.returncode, 0 if ok else 1, result.stderr.decode())
        return result
    def committed_fixture(self):
        # Pre-existing committed state fixture, NOT a substitute production commit.
        self.fixture(); self.target.mkdir()
        shutil.copytree(self.source, self.target/'WeChatUnified')
        stat = self.source.stat()
        (self.target/'.wu-storage-v1').write_bytes(receipt_bytes(1, stat.st_dev, stat.st_ino, 0, 0))
    def test_restart_receipt_keeps_current_data_and_legacy_unchanged(self):
        self.committed_fixture(); before = self.snapshot(self.source)
        (self.target/'WeChatUnified/config.json').write_bytes(b'new data')
        self.run_migration(True); self.run_migration(True)
        self.assertEqual((self.target/'WeChatUnified/config.json').read_bytes(), b'new data')
        self.assertEqual(self.snapshot(self.source), before)
        self.assertFalse(self.stage.exists())
    def snapshot(self, root):
        return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
    def test_copy_all_bytes_and_restart_uses_current_target(self):
        self.fixture(); extra = self.old/'WeChatUnifiedEmoticons'; extra.mkdir(); (extra/'index').write_bytes(b'emoticons')
        before = self.snapshot(self.old)
        self.run_migration(True)
        self.assertEqual(self.snapshot(self.source), self.snapshot(self.target/'WeChatUnified'))
        self.assertEqual((self.target/'WeChatUnifiedEmoticons/index').read_bytes(), b'emoticons')
        (self.target/'WeChatUnified/config.json').write_bytes(b'{"schema":1,"enabled":true}')
        self.run_migration(True)
        self.assertEqual((self.target/'WeChatUnified/config.json').read_bytes(), b'{"schema":1,"enabled":true}')
        self.assertEqual(self.snapshot(self.old), before)
        self.assertFalse(self.stage.exists())
    def fresh_attempt(self):
        result = subprocess.run([self.cli, self.old, self.docs], capture_output=True)
        if self.unsupported_commit(result):
            self.assertFalse(self.target.exists())
            location = self.stage
        else:
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            location = self.target
        self.assertEqual((location/'WeChatUnified/config.json').read_bytes(), b'{"schema":1,"enabled":false,"words":""}')
        self.assertEqual((location/'.wu-storage-v1').read_bytes(), struct.pack('=QQQQQ', 2, 0, 0, 0, 0))
        return result
    def test_fresh_install_prepares_defaults_without_creating_legacy_data(self):
        self.fresh_attempt()
        self.assertEqual(list(self.old.iterdir()), [])
    def test_fresh_install_with_missing_support_parent(self):
        self.old.rmdir(); self.fresh_attempt(); self.assertFalse(self.old.exists())
    def test_fresh_install_atomic_commit_and_restart(self):
        result = self.fresh_attempt()
        if self.unsupported_commit(result):
            self.skipTest('iSH rejects atomic no-replace; staged fresh defaults checked, NOT committed')
        before = self.snapshot(self.target)
        self.run_migration(True); self.assertEqual(self.snapshot(self.target), before)
    def test_fresh_committed_fixture_restarts_before_first_save(self):
        # Explicit already-committed fixture; does NOT replace an unsupported commit.
        (self.target/'WeChatUnified').mkdir(parents=True)
        (self.target/'WeChatUnified/config.json').write_bytes(b'{"schema":1,"enabled":false,"words":""}')
        (self.target/'.wu-storage-v1').write_bytes(struct.pack('=QQQQQ', 2, 0, 0, 0, 0))
        self.old.rmdir(); before = self.snapshot(self.target)
        self.run_migration(True); self.run_migration(True)
        self.assertEqual(self.snapshot(self.target), before)
        (self.target/'WeChatUnified/config.json').unlink()
        self.run_migration(False); self.assertFalse((self.target/'WeChatUnified/config.json').exists())
    def test_partial_source_with_any_file_never_initializes(self):
        self.source.mkdir(); (self.source/'orphan-resource').write_bytes(b'keep')
        self.run_migration(False); self.assertEqual(list(self.docs.iterdir()), [])
        self.assertEqual((self.source/'orphan-resource').read_bytes(), b'keep')
    def test_directory_only_remnants_restart_disabled_without_fake_resources(self):
        (self.source/'Themes/synthetic-empty/nested').mkdir(parents=True)
        (self.source/'VoicePacks/synthetic-account').mkdir(parents=True)
        before = {str(p.relative_to(self.source)): p.stat().st_ino for p in self.source.rglob('*')}
        result = subprocess.run([self.cli, self.old, self.docs], capture_output=True)
        location = self.stage if self.unsupported_commit(result) else self.target
        if location == self.target: self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual((location/'WeChatUnified/config.json').read_bytes(), b'{"schema":1,"enabled":false,"words":""}')
        self.assertEqual(struct.unpack('=QQQQQ', (location/'.wu-storage-v1').read_bytes())[0], 3)
        self.assertFalse((location/'WeChatUnified/Themes').exists())
        self.assertFalse((location/'WeChatUnified/VoicePacks').exists())
        self.assertEqual(before, {str(p.relative_to(self.source)): p.stat().st_ino for p in self.source.rglob('*')})
        self.assertEqual(self.snapshot(self.source), {})
        if location == self.stage: self.skipTest('iSH cannot atomic commit; verified empty-remnant stage only')
        (self.target/'WeChatUnified/config.json').write_bytes(b'current')
        self.run_migration(True)
        self.assertEqual((self.target/'WeChatUnified/config.json').read_bytes(), b'current')
    def test_empty_remnants_with_symlink_fifo_or_extra_file_are_rejected(self):
        self.source.mkdir()
        leaf=self.source/'leaf'
        for kind in ['link', 'fifo', 'file']:
            with self.subTest(kind=kind):
                if kind=='link': leaf.symlink_to(self.base/'absent')
                elif kind=='fifo': os.mkfifo(leaf)
                else: leaf.write_bytes(b'')
                self.run_migration(False); self.assertFalse(self.stage.exists()); leaf.unlink()
        extra=self.old/'WeChatUnifiedEmoticons'; extra.mkdir(); (extra/'data').write_bytes(b'keep')
        self.run_migration(False); self.assertFalse(self.stage.exists())
    def test_orphan_legacy_emoticons_are_not_a_fresh_install(self):
        extra=self.old/'WeChatUnifiedEmoticons'; extra.mkdir(); (extra/'keep').write_bytes(b'history')
        self.run_migration(False); self.assertEqual(list(self.docs.iterdir()), [])
        self.assertEqual((extra/'keep').read_bytes(), b'history')
    def test_fresh_install_preserves_interrupted_stage(self):
        self.stage.mkdir(); (self.stage/'keep').write_bytes(b'partial')
        self.run_migration(False); self.assertFalse(self.target.exists())
        self.assertEqual((self.stage/'keep').read_bytes(), b'partial')
    def test_source_parent_symlink_and_non_directory_are_not_absence(self):
        self.old.rmdir(); self.old.symlink_to(self.base/'missing')
        self.run_migration(False); self.assertEqual(list(self.docs.iterdir()), [])
        self.old.unlink(); self.old.write_bytes(b'history')
        self.run_migration(False); self.assertEqual(self.old.read_bytes(), b'history')
        self.assertEqual(list(self.docs.iterdir()), [])
    def test_source_root_dangling_symlink_is_not_absence(self):
        self.source.symlink_to(self.base/'missing')
        self.run_migration(False); self.assertEqual(list(self.docs.iterdir()), [])
        self.assertTrue(self.source.is_symlink())
    def test_valid_target_survives_source_removal_replacement_and_missing_parent(self):
        self.committed_fixture(); (self.target/'WeChatUnified/config.json').write_bytes(b'current')
        before=self.snapshot(self.target)
        shutil.rmtree(self.source); self.run_migration(True)
        self.source.mkdir(); (self.source/'config.json').write_bytes(b'obsolete replacement')
        self.run_migration(True); self.assertEqual((self.source/'config.json').read_bytes(), b'obsolete replacement')
        shutil.rmtree(self.old); self.run_migration(True)
        self.old.write_bytes(b'not a directory'); self.run_migration(True)
        self.assertEqual(self.snapshot(self.target), before); self.assertFalse(self.stage.exists())
    def test_migrated_emoticons_require_target_not_legacy_extra(self):
        self.committed_fixture()
        main=self.source.stat(); extra=self.old/'WeChatUnifiedEmoticons'; extra.mkdir(); old_extra=extra.stat()
        (self.target/'.wu-storage-v1').write_bytes(receipt_bytes(1, main.st_dev, main.st_ino, old_extra.st_dev, old_extra.st_ino))
        (self.target/'WeChatUnifiedEmoticons').mkdir(); (self.target/'WeChatUnifiedEmoticons/keep').write_bytes(b'emoticons')
        shutil.rmtree(self.old); self.run_migration(True)
        shutil.rmtree(self.target/'WeChatUnifiedEmoticons'); self.run_migration(False)
        self.assertFalse((self.target/'WeChatUnifiedEmoticons').exists())
    def test_invalid_receipt_fields_are_rejected_without_old_source(self):
        self.committed_fixture(); shutil.rmtree(self.old)
        for fields in [(0,0,0,0,0), (1,0,0,0,0), (1,1,2,3,0), (2,1,0,0,0), (3,0,0,0,0)]:
            with self.subTest(fields=fields):
                (self.target/'.wu-storage-v1').write_bytes(struct.pack('=QQQQQ', *fields))
                before=self.snapshot(self.target); self.run_migration(False)
                self.assertEqual(self.snapshot(self.target), before)
    def test_permission_denial_is_not_absence_but_valid_target_is_independent(self):
        self.committed_fixture()
        self.base.chmod(0o755); pathlib.Path(self.build.name).chmod(0o755)
        self.docs.chmod(0o777); self.old.chmod(0)
        self.addCleanup(self.old.chmod, 0o700)
        def demote():
            nobody = pwd.getpwnam('nobody')
            os.setgroups([])
            os.setgid(nobody.pw_gid); os.setuid(nobody.pw_uid)
        kwargs={'preexec_fn': demote} if os.geteuid()==0 else {}
        result=subprocess.run([self.cli, self.old, self.docs], capture_output=True, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        shutil.rmtree(self.target)
        result=subprocess.run([self.cli, self.old, self.docs], capture_output=True, **kwargs)
        self.assertEqual(result.returncode, 1, result.stderr.decode())
        self.assertEqual(list(self.docs.iterdir()), [])
    def test_corrupt_config_is_preserved_not_repaired_or_emptied(self):
        self.fixture(); (self.source/'config.json').write_bytes(b'\0broken json')
        result = subprocess.run([self.cli, self.old, self.docs], capture_output=True)
        if self.unsupported_commit(result):
            self.assertFalse(self.target.exists()); location = self.stage
            self.assertTrue((location/'.wu-storage-v1').is_file())
        else:
            self.assertEqual(result.returncode, 0, result.stderr.decode()); location = self.target
        self.assertEqual((location/'WeChatUnified/config.json').read_bytes(), b'\0broken json')
        self.assertEqual((self.source/'config.json').read_bytes(), b'\0broken json')
    def test_existing_target_even_empty_is_not_overwritten(self):
        self.fixture(); self.target.mkdir(); self.run_migration(False)
        self.assertEqual(list(self.target.iterdir()), [])
        (self.target/'sentinel').write_bytes(b'keep'); self.run_migration(False)
        self.assertEqual((self.target/'sentinel').read_bytes(), b'keep'); self.assertFalse(self.stage.exists())
    def test_incomplete_stage_is_preserved_and_blocks_retry(self):
        self.fixture(); self.stage.mkdir(); (self.stage/'partial').write_bytes(b'keep')
        self.run_migration(False); self.assertEqual((self.stage/'partial').read_bytes(), b'keep')
        self.assertFalse(self.target.exists())
    def test_symlink_in_source_is_rejected(self):
        self.fixture(); (self.source/'link').symlink_to(self.base/'private')
        (self.base/'private').write_bytes(b'private')
        self.run_migration(False); self.assertFalse(self.target.exists())
        self.assertEqual((self.base/'private').read_bytes(), b'private')
        self.assertTrue((self.source/'link').is_symlink())
    def test_target_root_missing_after_commit_does_not_reinitialize(self):
        self.committed_fixture()
        (self.target/'WeChatUnified').rename(self.target/'saved')
        self.run_migration(False); self.assertFalse((self.target/'WeChatUnified').exists())
    def test_receipt_corruption_blocks_existing_target(self):
        self.committed_fixture()
        (self.target/'.wu-storage-v1').write_bytes(b'broken')
        before = self.snapshot(self.target)
        self.run_migration(False); self.assertEqual(self.snapshot(self.target), before)
    def test_receipt_fifo_does_not_block_startup(self):
        self.committed_fixture()
        marker=self.target/'.wu-storage-v1'; marker.unlink(); os.mkfifo(marker)
        result=subprocess.run([self.cli, self.old, self.docs], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(self.stage.exists())
    def test_target_symlink_is_not_a_fresh_install(self):
        self.target.symlink_to(self.base/'missing')
        self.run_migration(False)
        self.assertTrue(self.target.is_symlink()); self.assertFalse(self.stage.exists())
    @unittest.skipUnless(sys.platform == 'darwin', 'Apple metadata requires real Darwin fcopyfile')
    def test_apple_metadata_files_and_directories_are_preserved(self):
        self.fixture()
        items = [self.source, self.source/'config.json', self.source/'VoicePacks']
        stamp = 1600000000123456789
        attribute = 'com.wechatunified.synthetic-migration-test'
        for item in items:
            item.chmod(0o750 if item.is_dir() else 0o640)
            # CPython exposes os.setxattr only on Linux; use Darwin's real xattr tool.
            subprocess.run(['xattr', '-wx', attribute, b'synthetic metadata\x00unchanged'.hex(), str(item)], check=True)
            subprocess.run(['chmod', '+a', 'everyone allow read,readattr,readextattr,readsecurity', str(item)], check=True)
            os.utime(item, ns=(stamp, stamp))
        def metadata(item):
            stat = item.stat()
            acl = subprocess.check_output(['ls', '-lde', str(item)], text=True).splitlines()[1:]
            return (stat.st_mode & 0o7777, stat.st_uid, stat.st_gid, stat.st_mtime_ns,
                    bytes.fromhex(subprocess.check_output(['xattr', '-px', attribute, str(item)], text=True)), acl)
        before = [metadata(item) for item in items]
        self.run_migration(True)
        for item, expected in zip(items, before):
            target = self.target/'WeChatUnified'/item.relative_to(self.source)
            self.assertEqual(metadata(target), expected)
            self.assertEqual(metadata(item), expected)
        self.assertFalse(self.stage.exists())

    def test_final_commit_conflict_even_empty_target_is_not_replaced(self):
        self.stage.mkdir(); (self.stage/'copy').write_bytes(b'new')
        self.target.mkdir()
        identity = self.target.stat().st_ino
        result = subprocess.run([self.cli, '--commit', self.docs], capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.target.stat().st_ino, identity)
        self.assertEqual(list(self.target.iterdir()), [])
        self.assertEqual((self.stage/'copy').read_bytes(), b'new')

    def test_final_commit_conflict_never_replaces_target(self):
        self.stage.mkdir(); (self.stage/'copy').write_bytes(b'new')
        self.target.mkdir(); (self.target/'sentinel').write_bytes(b'keep')
        result = subprocess.run([self.cli, '--commit', self.docs], capture_output=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual((self.target/'sentinel').read_bytes(), b'keep')
        self.assertEqual((self.stage/'copy').read_bytes(), b'new')
    def test_byte_verifier_rejects_corruption_extra_file_and_link(self):
        self.fixture(); shutil.copytree(self.source, self.stage)
        def verify(expected):
            result = subprocess.run([self.cli, '--verify', self.source, self.stage], capture_output=True)
            self.assertEqual(result.returncode, 0 if expected else 1)
        verify(True)
        file = self.stage/'config.json'; original = file.read_bytes()
        file.write_bytes(b'x'*len(original)); verify(False)
        file.write_bytes(original); extra = self.stage/'extra'; extra.write_bytes(b'x'); verify(False)
        extra.unlink(); file.unlink(); file.symlink_to(self.source/'config.json'); verify(False)
    def test_killed_copy_leaves_source_intact_and_restart_protected(self):
        self.fixture()
        large = self.source/'large'; large.write_bytes(b'original')
        with large.open('r+b') as f: f.truncate(128*1024*1024)
        before = self.snapshot(self.source)
        process = subprocess.Popen([self.cli, self.old, self.docs], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            partial = self.stage/'WeChatUnified/large'; deadline = time.monotonic()+15
            while process.poll() is None and time.monotonic()<deadline:
                if partial.exists() and partial.stat().st_size>0: break
                time.sleep(.001)
            self.assertIsNone(process.poll(), 'copy completed before interruption could be injected')
            self.assertTrue(partial.exists(), 'copy never reached data stage')
            process.kill(); process.wait(timeout=10)
        finally:
            if process.poll() is None: process.kill(); process.wait()
        self.assertFalse(self.target.exists()); self.assertTrue(self.stage.exists())
        self.run_migration(False); self.assertEqual(self.snapshot(self.source), before)

class Wiring(unittest.TestCase):
    def test_all_production_storage_paths_are_centralized(self):
        for file in (ROOT/'Sources').glob('*.m'):
            if file.name == 'WUStorage.m': continue
            self.assertNotIn('NSApplicationSupportDirectory', file.read_text(), file.name)
        core=(ROOT/'Sources/Core.m').read_text()
        self.assertIn('BOOL ready=WUStorageInitialize()', core)
        self.assertIn('if(!ready || configDir<0)', core)
        self.assertIn('StorageNotice();', core)
        storage=(ROOT/'Sources/WUStorage.m').read_text()
        self.assertIn('wu_storage_prepare(support.fileSystemRepresentation,dest,&reason)', storage)
        self.assertNotIn('old>=0 && dest>=0', storage)
        self.assertNotIn('if(!support || !documents)', storage)
        backup=(ROOT/'Sources/WUBackup.m').read_text()
        self.assertIn('NSURL *support=WUStorageEnvelope();', backup)

class Diagnostic(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.cli = Path(cls.build.name) / 'diagnostic'
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-I',str(ROOT/'Sources'),str(ROOT/'tests/storage_migration_cli.c'),'-o',str(cls.cli)],check=True)
        cls.commit_cli=Path(cls.build.name)/'diagnostic-commit-fault'
        subprocess.run(['clang','-std=c11','-Wall','-Wextra','-Werror','-DWU_TEST_COMMIT_FAILURE','-I',str(ROOT/'Sources'),str(ROOT/'tests/storage_migration_cli.c'),'-o',str(cls.commit_cli)],check=True)
    @classmethod
    def tearDownClass(cls): cls.build.cleanup()
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='private-synthetic-')
        self.addCleanup(self.tmp.cleanup)
        self.base=Path(self.tmp.name); self.old=self.base/'old-private-name'; self.old.mkdir()
        self.docs=self.base/'docs-private-name'; self.docs.mkdir()
        self.main=self.old/'WeChatUnified'; self.target=self.docs/'WeChatUnifiedStorage'; self.stage=self.docs/'.WUStorage-migration'
    def run_core(self, expected, old=None, **kwargs):
        p=subprocess.run([str(self.cli),'--diagnostic',str(self.old if old is None else old),str(self.docs)],capture_output=True,text=True,**kwargs)
        self.assertEqual(p.returncode,1,p.stderr)
        self.assertEqual(p.stdout.strip(),expected)
        self.assertNotIn('private',p.stdout+p.stderr)
        return p
    def test_null_support_url(self):
        self.run_core('support_url unavailable 0',old='--null')
        self.assertEqual(list(self.docs.iterdir()),[])
    def test_source_parent_not_directory(self):
        self.old.rmdir(); self.old.write_bytes(b'preserve')
        self.run_core('support_open errno %d'%errno.ENOTDIR)
        self.assertEqual(self.old.read_bytes(),b'preserve'); self.assertEqual(list(self.docs.iterdir()),[])
    def test_orphan_extra_reports_main_missing_not_empty(self):
        extra=self.old/'WeChatUnifiedEmoticons'; extra.mkdir(); (extra/'secret').write_bytes(b'preserve')
        for _ in range(2): self.run_core('legacy_main_stat errno %d'%errno.ENOENT)
        self.assertEqual((extra/'secret').read_bytes(),b'preserve'); self.assertEqual(list(self.docs.iterdir()),[])
    def test_main_and_extra_non_directory(self):
        self.main.write_bytes(b'preserve')
        self.run_core('legacy_main_stat not_directory 0')
        self.assertEqual(self.main.read_bytes(),b'preserve'); self.main.unlink(); self.main.mkdir()
        extra=self.old/'WeChatUnifiedEmoticons'; extra.write_bytes(b'preserve extra')
        self.run_core('legacy_extra_stat not_directory 0')
        self.assertEqual(extra.read_bytes(),b'preserve extra'); self.assertEqual(list(self.docs.iterdir()),[])
    def test_target_bad_receipt_does_not_touch_source(self):
        self.main.mkdir(); (self.main/'private').write_bytes(b'preserve')
        self.target.mkdir()
        for _ in range(2): self.run_core('target_receipt_open errno %d'%errno.ENOENT)
        self.assertEqual((self.main/'private').read_bytes(),b'preserve'); self.assertEqual(list(self.target.iterdir()),[])
    def test_target_receipt_invalid_type(self):
        self.target.mkdir(); (self.target/'.wu-storage-v1').write_bytes(b'bad')
        self.run_core('target_receipt_validate invalid_type_or_size 0')
        self.assertEqual((self.target/'.wu-storage-v1').read_bytes(),b'bad')
    def test_target_main_open_error_after_valid_receipt(self):
        self.target.mkdir(); (self.target/'.wu-storage-v1').write_bytes(receipt_bytes(2,0,0,0,0))
        self.run_core('target_main_open errno %d'%errno.ENOENT)
        self.assertEqual((self.target/'.wu-storage-v1').read_bytes(),receipt_bytes(2,0,0,0,0))
        self.assertFalse(self.stage.exists())
    def test_first_failure_order_is_actual_extra_open(self):
        (self.target/'WeChatUnified').mkdir(parents=True)
        (self.target/'.wu-storage-v1').write_bytes(receipt_bytes(1,1,2,3,4))
        self.run_core('target_extra_open errno %d'%errno.ENOENT)
        self.assertFalse(self.stage.exists())
    def test_target_receipt_invalid_fields(self):
        self.target.mkdir(); (self.target/'.wu-storage-v1').write_bytes(receipt_bytes(0,0,0,0,0))
        self.run_core('target_receipt_validate invalid_fields 0')
        self.assertFalse(self.stage.exists())
    def test_conflicting_stage_remains(self):
        self.stage.mkdir(); (self.stage/'private').write_bytes(b'partial')
        for _ in range(2): self.run_core('stage_create errno %d'%errno.EEXIST)
        self.assertEqual((self.stage/'private').read_bytes(),b'partial'); self.assertFalse(self.target.exists())
    def test_nonempty_remnants_not_treated_as_empty(self):
        self.main.mkdir(); (self.main/'private').write_bytes(b'preserve')
        self.run_core('legacy_main_scan not_directory_only_or_unreadable 0')
        self.assertEqual((self.main/'private').read_bytes(),b'preserve'); self.assertEqual(list(self.docs.iterdir()),[])
    def test_copy_detects_link_and_reports_semantic_failure(self):
        self.main.mkdir(); (self.main/'config.json').write_bytes(b'preserve'); (self.main/'link').symlink_to('not-present')
        self.run_core('main_copy io_or_validation_failed 0')
        self.assertEqual((self.main/'config.json').read_bytes(),b'preserve'); self.assertTrue((self.main/'link').is_symlink()); self.assertFalse(self.target.exists()); self.assertTrue(self.stage.is_dir())
        self.run_core('stage_create errno %d'%errno.EEXIST)
    def test_injected_commit_conflict_keeps_source_and_stage(self):
        self.main.mkdir(); (self.main/'config.json').write_bytes(b'preserve')
        p=subprocess.run([str(self.commit_cli),'--diagnostic',str(self.old),str(self.docs)],capture_output=True,text=True)
        self.assertEqual(p.returncode,1,p.stderr)
        self.assertEqual(p.stdout.strip(),'commit errno %d'%errno.EEXIST)
        self.assertNotIn('private',p.stdout+p.stderr)
        self.assertEqual((self.main/'config.json').read_bytes(),b'preserve')
        self.assertEqual((self.stage/'WeChatUnified/config.json').read_bytes(),b'preserve')
        self.assertFalse(self.target.exists())
        self.run_core('stage_create errno %d'%errno.EEXIST)
    def test_access_denial_never_interpreted_as_absence(self):
        self.base.chmod(0o755); Path(self.build.name).chmod(0o755); self.docs.chmod(0o777); self.old.chmod(0)
        self.addCleanup(self.old.chmod,0o700)
        kwargs={}
        if os.geteuid()==0:
            def demote():
                nobody=pwd.getpwnam('nobody'); os.setgroups([]); os.setgid(nobody.pw_gid); os.setuid(nobody.pw_uid)
            kwargs['preexec_fn']=demote
        self.run_core('support_open errno %d'%errno.EACCES,**kwargs)
        self.assertEqual(list(self.docs.iterdir()),[])


if __name__ == '__main__': unittest.main()
