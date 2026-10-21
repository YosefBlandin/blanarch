// Drives the tracked forbidden-word hooks in throwaway repos. Each repo gets its own private list holding a
// made-up token; the real list is never read.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const installer = fileURLToPath(new URL('./install-hooks.mjs', import.meta.url));
const TOKEN = 'zorblatt-qx7';

const scratch = mkdtempSync(join(tmpdir(), 'hooks-test-'));
const emptyConfig = join(scratch, 'empty-gitconfig');
writeFileSync(emptyConfig, '');

// Isolate from the developer's git config and from any git hook environment the tests run inside.
const baseEnv = Object.fromEntries(
  Object.entries(process.env).filter(([k]) => !k.startsWith('GIT_') && k !== 'SKIP_FORBIDDEN_CHECK'),
);
Object.assign(baseEnv, {
  GIT_CONFIG_GLOBAL: emptyConfig,
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_AUTHOR_NAME: 'Test',
  GIT_AUTHOR_EMAIL: 'test@example.com',
  GIT_COMMITTER_NAME: 'Test',
  GIT_COMMITTER_EMAIL: 'test@example.com',
});

function run(cmd, args, cwd, extraEnv = {}) {
  const r = spawnSync(cmd, args, { cwd, env: { ...baseEnv, ...extraEnv }, encoding: 'utf8' });
  return { code: r.status, out: `${r.stdout}${r.stderr}` };
}

const git = (cwd, args, env) => run('git', args, cwd, env);

let counter = 0;
function newRepo({ list = `# made-up test list\n\n${TOKEN}\n`, install = true } = {}) {
  const repo = join(scratch, `repo-${++counter}`);
  mkdirSync(repo);
  git(repo, ['init', '-q', '-b', 'main']);
  writeFileSync(join(repo, '.gitignore'), 'private/\n');
  if (list !== null) {
    mkdirSync(join(repo, 'private'));
    writeFileSync(join(repo, 'private', 'company-strings.txt'), list);
  }
  if (install) {
    const r = run('node', [installer], repo);
    assert.equal(r.code, 0, r.out);
  }
  return repo;
}

function commitFile(repo, name, content, message = 'add file', env) {
  writeFileSync(join(repo, name), content);
  git(repo, ['add', name]);
  return git(repo, ['commit', '-q', '-m', message], env);
}

const hasToken = (s) => s.toLowerCase().includes(TOKEN);

test.after(() => rmSync(scratch, { recursive: true, force: true }));

test('T-HOOK-1: a staged line with a listed string is blocked and only a count is printed', () => {
  const repo = newRepo();
  const clean = commitFile(repo, 'ok.txt', 'nothing to see\n');
  assert.equal(clean.code, 0, clean.out);

  const r = commitFile(repo, 'leak.txt', `line one\nhello ${TOKEN.toUpperCase()} world\n`);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
  assert.ok(!hasToken(r.out), 'output must not contain the listed string');
  assert.equal(git(repo, ['rev-list', '--count', 'HEAD']).out.trim(), '1');
});

test('T-HOOK-1: a staged file name with a listed string is blocked', () => {
  const repo = newRepo();
  const r = commitFile(repo, `${TOKEN}.txt`, 'harmless\n');
  assert.notEqual(r.code, 0);
  assert.ok(!hasToken(r.out));
});

test('T-HOOK-2: a commit message with a listed string is blocked by commit-msg', () => {
  const repo = newRepo();
  const r = commitFile(repo, 'ok.txt', 'fine\n', `Fix the ${TOKEN} thing`);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /commit-msg: 1 /);
  assert.ok(!hasToken(r.out));
  assert.notEqual(git(repo, ['rev-parse', '-q', '--verify', 'HEAD']).code, 0, 'no commit was made');
});

test('T-HOOK-2: a listed string on a message line starting with # is blocked', () => {
  const repo = newRepo();
  writeFileSync(join(repo, 'ok.txt'), 'fine\n');
  git(repo, ['add', 'ok.txt']);
  const r = git(repo, ['commit', '-q', '-m', 'Title', '-m', `## Notes: ${TOKEN}`]);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /commit-msg: 1 /);
  assert.notEqual(git(repo, ['rev-parse', '-q', '--verify', 'HEAD']).code, 0, 'no commit was made');
});

test('T-HOOK-1: a listed string inside a file git treats as binary is blocked', () => {
  const repo = newRepo();
  const r = commitFile(repo, 'blob.bin', `\0\0header ${TOKEN}\n`);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
});

test('T-HOOK-1: a symlink replaced by a file with a listed string is blocked', () => {
  const repo = newRepo();
  symlinkSync('ok.txt', join(repo, 'link'));
  writeFileSync(join(repo, 'ok.txt'), 'fine\n');
  git(repo, ['add', 'ok.txt', 'link']);
  assert.equal(git(repo, ['commit', '-q', '-m', 'add link']).code, 0);
  rmSync(join(repo, 'link'));
  const r = commitFile(repo, 'link', `${TOKEN}\n`, 'replace link');
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
});

test('T-HOOK-1: list lines with trailing spaces or CR still match', () => {
  const repo = newRepo({ list: `${TOKEN}  \r\n` });
  const r = commitFile(repo, 'leak.txt', `${TOKEN}\n`);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
});

test('T-HOOK-3: a missing list blocks with the expected path; SKIP_FORBIDDEN_CHECK=1 proceeds with a warning', () => {
  const repo = newRepo({ list: null });
  const expected = join(git(repo, ['rev-parse', '--show-toplevel']).out.trim(), 'private', 'company-strings.txt');

  const blocked = commitFile(repo, 'ok.txt', 'fine\n');
  assert.notEqual(blocked.code, 0);
  assert.ok(blocked.out.includes(expected), blocked.out);
  assert.match(blocked.out, /SKIP_FORBIDDEN_CHECK=1/);

  const skipped = git(repo, ['commit', '-q', '-m', 'add file'], { SKIP_FORBIDDEN_CHECK: '1' });
  assert.equal(skipped.code, 0, skipped.out);
  assert.match(skipped.out, /warning/i);
});

test('T-HOOK-3: a list with only comments and blank lines counts as missing', () => {
  const repo = newRepo({ list: '# nothing here\n\n   \n' });
  const r = commitFile(repo, 'ok.txt', 'fine\n');
  assert.notEqual(r.code, 0);
  assert.match(r.out, /SKIP_FORBIDDEN_CHECK=1/);
});

test('T-HOOK-4: with the list present, SKIP_FORBIDDEN_CHECK=1 still blocks a hit', () => {
  const repo = newRepo();
  const r = commitFile(repo, 'leak.txt', `${TOKEN}\n`, 'add file', { SKIP_FORBIDDEN_CHECK: '1' });
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
  assert.ok(!hasToken(r.out));
  assert.notEqual(git(repo, ['rev-parse', '-q', '--verify', 'HEAD']).code, 0, 'no commit was made');
});

test('T-HOOK-5: a linked worktree on a branch without .githooks is blocked using the main checkout list', () => {
  const repo = newRepo();
  assert.equal(commitFile(repo, 'ok.txt', 'fine\n').code, 0);
  assert.ok(!existsSync(join(repo, '.githooks')));
  const wt = join(scratch, `wt-${counter}`);
  const add = git(repo, ['worktree', 'add', '-q', '-b', 'side', wt]);
  assert.equal(add.code, 0, add.out);
  assert.ok(!existsSync(join(wt, 'private')), 'the worktree has no list of its own');

  const r = commitFile(wt, 'leak.txt', `x ${TOKEN} y\n`);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /pre-commit: 1 /);
  assert.ok(!hasToken(r.out));

  git(wt, ['rm', '-q', '--cached', 'leak.txt']);
  const ok = commitFile(wt, 'fine.txt', 'fine\n');
  assert.equal(ok.code, 0, ok.out);
});

test('T-HOOK-5: the installer marks the hooks executable in the shared hooks folder', () => {
  const repo = newRepo();
  for (const name of ['pre-commit', 'commit-msg', 'forbidden-scan.sh']) {
    const mode = statSync(join(repo, '.git', 'hooks', name)).mode & 0o777;
    assert.equal(mode, 0o755, name);
  }
});

test('T-HOOK-5: the installer refuses when core.hooksPath is set', () => {
  const repo = newRepo({ install: false });
  git(repo, ['config', 'core.hooksPath', '.myhooks']);
  const r = run('node', [installer], repo);
  assert.notEqual(r.code, 0);
  assert.match(r.out, /core\.hooksPath/);
  assert.ok(!existsSync(join(repo, '.git', 'hooks', 'pre-commit')));
  assert.ok(!existsSync(join(repo, '.myhooks')));
});

test('T-HOOK-5: the installer does nothing outside a git checkout', () => {
  const dir = join(scratch, 'not-a-repo');
  mkdirSync(dir);
  const r = run('node', [installer], dir, { GIT_CEILING_DIRECTORIES: scratch });
  assert.equal(r.code, 0, r.out);
  assert.ok(!existsSync(join(dir, '.git')));
});
