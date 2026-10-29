import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import { createRequire } from 'module';
import path from 'path';

// 运行时源码在 @honyomi/plugin-runtime（extension-sdk）。生成 rawfile 仍是 entry
// 打包图里的任务，排在 ProcessResource 之前，使用正在执行 hvigor 的 Node。
function generatePluginRuntime() {
  return {
    pluginId: 'generatePluginRuntime',
    apply(node: {
      getNodePath: () => string;
      getContext: (id: string) => OhosHapContext;
      registerTask: (task: object) => void;
    }) {
      const hap = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN);
      if (hap === undefined) {
        return;
      }
      const entryDir = node.getNodePath();
      hap.targets((target) => {
        const targetName = target.getTargetName();
        node.registerTask({
          name: `${targetName}@GeneratePluginRuntime`,
          dependencies: [`${targetName}@PreBuild`],
          postDependencies: [`${targetName}@ProcessResource`],
          run() {
            const runtimeDir = resolveRuntimeDir(entryDir);
            ensureRuntimeDeps(runtimeDir);
            const rawfile = path.join(entryDir, 'src', 'main', 'resources', 'rawfile', 'plugin_runtime_jsvm.js');
            execFileSync(nodeBin(), ['build.mjs', '--rawfile', rawfile], {
              cwd: runtimeDir,
              stdio: 'inherit',
            });
          },
        });
      });
    },
  };
}

function nodeBin(): string {
  return process.env.HONYOMI_NODE || process.execPath;
}

function resolveRuntimeDir(entryDir: string): string {
  const fromEnv = process.env.HONYOMI_RUNTIME_DIR;
  if (fromEnv !== undefined && existsSync(path.join(fromEnv, 'build.mjs'))) {
    return fromEnv;
  }
  const appRoot = path.resolve(entryDir, '..');
  for (const dir of [path.join(appRoot, 'plugins', 'catalog'), path.join(appRoot, 'plugins'), appRoot]) {
    const pkg = path.join(dir, 'package.json');
    if (!existsSync(pkg)) {
      continue;
    }
    try {
      const resolved = createRequire(pkg).resolve('@honyomi/plugin-runtime/package.json');
      return path.dirname(resolved);
    } catch {
      // 这个目录还没装上工具链，继续找。
    }
  }
  const sibling = path.resolve(appRoot, '..', 'extension-sdk', 'packages', 'runtime');
  if (existsSync(path.join(sibling, 'build.mjs'))) {
    return sibling;
  }
  throw new Error('找不到 @honyomi/plugin-runtime。请在 plugins/catalog 安装 @honyomi/plugin-tools，或设置 HONYOMI_RUNTIME_DIR');
}

function canResolve(runtimeDir: string, name: string): boolean {
  try {
    createRequire(path.join(runtimeDir, 'package.json')).resolve(name);
    return true;
  } catch {
    return false;
  }
}

function workspaceRoot(start: string): string | null {
  let current = start;
  for (let i = 0; i < 6; i++) {
    const pkgPath = path.join(current, 'package.json');
    if (existsSync(pkgPath)) {
      try {
        const parsed = JSON.parse(readFileSync(pkgPath, 'utf8')) as { workspaces?: unknown };
        if (Array.isArray(parsed.workspaces)) {
          return current;
        }
      } catch {
        // 继续向上找 workspace 根。
      }
    }
    const parent = path.dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }
  return null;
}

function ensureRuntimeDeps(runtimeDir: string): void {
  if (canResolve(runtimeDir, 'esbuild')) {
    return;
  }
  const installDir = workspaceRoot(runtimeDir) ?? runtimeDir;
  const useCi = existsSync(path.join(installDir, 'package-lock.json'));
  const args = useCi ? ['ci'] : ['install'];
  const node = nodeBin();
  const binDir = path.dirname(node);
  const npmCli = path.join(binDir, 'node_modules', 'npm', 'bin', 'npm-cli.js');
  if (existsSync(npmCli)) {
    execFileSync(node, [npmCli, ...args], { cwd: installDir, stdio: 'inherit' });
    return;
  }
  const npmCmd = path.join(binDir, process.platform === 'win32' ? 'npm.cmd' : 'npm');
  const command = existsSync(npmCmd) ? npmCmd : (process.platform === 'win32' ? 'npm.cmd' : 'npm');
  execFileSync(command, args, {
    cwd: installDir,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [generatePluginRuntime()],
};
