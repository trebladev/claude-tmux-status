# claude-tmux-status

在 tmux 的 window 标签旁显示 Claude Code 状态圆点。它使用 Claude Code 官方 lifecycle hooks，不解析终端画面，也不保存 prompt、回复或工具参数。

## 状态

| 圆点 | 状态 | 触发时机 |
|---|---|---|
| 🟢 绿色 | 正在运行 | 提交 prompt 后，以及 Claude 调用工具时 |
| 🟡 黄色 | 等待输入 | 启动完成、回答结束、等待权限或用户输入时 |
| 🔴 红色 | 错误 | 当前 turn 因 API、认证、限流等错误结束时 |
| ⚪ 灰色 | 已停止 | Claude 正常退出，或记录的 Claude 进程已消失；默认隐藏 |

一个 window 有多个 pane 时只显示一个圆点，优先级是：`错误 > 等待 > 运行 > 停止`。从未启动过 Claude，或 Claude 已经退出的 window 默认不显示圆点。

## 安装

### TPM

把插件加入 `~/.tmux.conf`（把仓库名替换成你的实际 GitHub 地址）：

```tmux
set -g @plugin 'your-name/claude-tmux-status'
```

然后按 `prefix + I` 安装，或重新加载 tmux 配置。插件加载时会安全地把自己的 hooks 合并进 `~/.claude/settings.json`，不会覆盖已有配置。

### 本地目录

```tmux
run-shell '/absolute/path/to/claude-tmux-status/claude-tmux-status.tmux'
```

重新加载配置：

```bash
tmux source-file ~/.tmux.conf
```

已经运行的 Claude Code 不会动态加载新 hooks，需要退出并重新启动一次。之后每次状态改变都会立即刷新 tmux 状态栏。

插件为每次状态变化生成唯一的 tmux job generation，避免很快完成的请求因为 `#()` 缓存而短暂保留上一次的颜色。

## 配置

以下选项要放在 TPM 插件声明或 `run-shell` 之前：

```tmux
set -g @claude-status-icon '●'
set -g @claude-status-working-colour 'colour40'
set -g @claude-status-waiting-colour '#ffff00'
set -g @claude-status-error-colour 'colour196'
set -g @claude-status-stopped-colour 'colour244'
set -g @claude-status-show-stopped 'off' # 设为 on 可显示停止后的灰点
```

插件会在现有的 `window-status-format` 和 `window-status-current-format` 末尾追加 `#{E:@claude-tmux-status}`，不会替换你的 window 样式。

## 卸载

```bash
/absolute/path/to/claude-tmux-status/scripts/uninstall.sh
```

卸载脚本只删除带有 `claude-tmux-status-v1` 标记的 hooks 和本插件的 tmux 格式片段，其他 Claude hooks 与 tmux 样式保持不变。首次修改已有 `settings.json` 时，安装器还会保留 `settings.json.claude-tmux-status.bak` 备份。

## 原理与限制

- `SessionStart` / `Stop` / `PermissionRequest` 将状态设为等待。
- `UserPromptSubmit` / `PreToolUse` 将状态设为运行。
- `StopFailure` 将状态设为错误。
- `SessionEnd` 将状态设为停止。
- 状态文件位于 `/tmp/claude-tmux-status-<uid>/`，只包含状态、更新时间和进程 ID，权限受当前用户的 `umask 077` 保护。
- `claude --bare` 会跳过 hooks，因此不会显示实时状态。
- `kill -9` 不会触发 `SessionEnd`，渲染器会通过 PID 存活检查自动降级为灰色。

运行测试：

```bash
./tests/run.sh
```
