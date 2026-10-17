import { hapTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { execFileSync } from 'child_process';
import { existsSync } from 'fs';
import path from 'path';

// runtime 跟应用走。生成 rawfile 是 entry 模块打包图里的任务，
// 排在 ProcessResource 之前，使用正在执行 hvigor 的 Node，不依赖额外安装的 Node。
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
      const runtimeDir = path.resolve(node.getNodePath(), '..', 'plugins', 'runtime');
      hap.targets((target) => {
        const targetName = target.getTargetName();
        node.registerTask({
          name: `${targetName}@GeneratePluginRuntime`,
          dependencies: [`${targetName}@PreBuild`],
          postDependencies: [`${targetName}@ProcessResource`],
          run() {
            ensureRuntimeDeps(runtimeDir);
            execFileSync(nodeBin(), ['build.mjs', '--rawfile'], {
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

function ensureRuntimeDeps(runtimeDir: string): void {
  if (existsSync(path.join(runtimeDir, 'node_modules', 'esbuild'))) {
    return;
  }
  const node = nodeBin();
  const dir = path.dirname(node);
  const npmCmd = path.join(dir, process.platform === 'win32' ? 'npm.cmd' : 'npm');
  const npmCli = path.join(dir, 'node_modules', 'npm', 'bin', 'npm-cli.js');
  if (existsSync(npmCmd)) {
    execFileSync(npmCmd, ['ci'], { cwd: runtimeDir, stdio: 'inherit' });
    return;
  }
  if (existsSync(npmCli)) {
    execFileSync(node, [npmCli, 'ci'], { cwd: runtimeDir, stdio: 'inherit' });
    return;
  }
  const npmOnPath = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  execFileSync(npmOnPath, ['ci'], {
    cwd: runtimeDir,
    stdio: 'inherit',
    shell: process.platform === 'win32',
  });
}

export default {
  system: hapTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: [generatePluginRuntime()],
};
