// Copies the tracked hooks in .githooks/ into git's shared hooks folder, so every worktree runs them on any
// branch. Run by the root `prepare` script. Never sets core.hooksPath, and refuses to install when it is set,
// because git would then ignore the shared folder.
import { execFileSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HOOKS = ['forbidden-scan.sh', 'pre-commit', 'commit-msg'];
const source = fileURLToPath(new URL('../.githooks/', import.meta.url));

function git(...args) {
  try {
    return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

const common = git('rev-parse', '--path-format=absolute', '--git-common-dir');
if (common === null) {
  console.log('install-hooks: not a git checkout, nothing to install.');
  process.exit(0);
}

const hooksPath = git('config', '--get', 'core.hooksPath');
if (hooksPath) {
  console.error(
    `install-hooks: core.hooksPath is set to "${hooksPath}", so git would skip the forbidden word hooks.\n` +
      'Unset it with `git config --unset core.hooksPath` (check --global too), then run `npm run prepare`.',
  );
  process.exit(1);
}

const target = join(common, 'hooks');
mkdirSync(target, { recursive: true });
for (const name of HOOKS) {
  copyFileSync(join(source, name), join(target, name));
  chmodSync(join(target, name), 0o755);
}
console.log(`install-hooks: installed ${HOOKS.join(', ')} into ${target}`);
