# cmux Session Restore

Автоматическое восстановление Claude Code сессий в cmux после перезапуска.

## Проблема

cmux не восстанавливает запущенные процессы — после рестарта все вкладки с Claude Code пустые. Приходится вручную делать `claude --resume` в каждой.

## Решение

Скрипт сохраняет привязку «вкладка cmux → Claude session ID» и при следующем запуске cmux автоматически восстанавливает в каждой `claude --resume`.

cmux восстанавливает только сами вкладки — внутри них пустой shell. Скрипт допускает три случая для каждой сохранённой сессии:

| Состояние вкладки | Действие |
|---|---|
| Имя совпадает + в TTY уже жив `claude` | пропуск (не вмешиваемся) |
| Имя совпадает + в TTY пустой shell | `cmux send "claude --resume X\n"` |
| Имени нет совсем | `cmux new-workspace --name X --focus true`, затем `cmux send` |

`cmux send`-ы идут одной быстрой пачкой (см. ниже про Broken pipe). Stagger между запусками `claude` достигается через сам shell — каждой сессии приходит `sleep N && claude --resume X`, где N = индекс × 30. 14 сессий стартуют за ~7 минут друг за другом. Это:
- не плодит сразу N процессов claude (память и CPU не лопаются)
- не триггерит rate-limit Anthropic API
- даёт `statusline.sh` шанс закешировать `ccusage`/limits до того, как все сессии попросят их одновременно

Весь цикл выполняется в фоне (`&`) — shell не блокируется.

## Быстрая установка

Отдай ссылку на этот репо своему Claude Code и скажи: **"Установи cmux session restore"**

Клод прочитает `CLAUDE.md` и установит всё автоматически.

## Ручная установка

```bash
# 1. Скопировать скрипт восстановления
cp cmux-auto-resume.zsh ~/.claude/scripts/cmux-auto-resume.zsh

# 2. Добавить в ~/.zshrc (в конец файла)
echo '[[ -f ~/.claude/scripts/cmux-auto-resume.zsh ]] && source ~/.claude/scripts/cmux-auto-resume.zsh' >> ~/.zshrc

# 3. Добавить Stop hook в ~/.claude/settings.json (вмержить в существующий)
# "hooks": { "Stop": [{ "hooks": [{ "type": "command", "command": "/usr/bin/python3 ~/.claude/scripts/cc-sessions.py save 2>/dev/null || true", "timeout": 10 }] }] }

# 4. Убедиться что cc-sessions.py установлен
ls ~/.claude/scripts/cc-sessions.py
```

## Как работает

```
Сохранение (при каждом завершении Claude сессии):
  Claude Stop hook -> cc-sessions.py save -> cmux-restore.json

Восстановление (при открытии cmux):
  cmux start -> zsh -> .zshrc -> cmux-auto-resume.zsh
    -> находит cmux-restore.json
    -> создает вкладки / отправляет resume в существующие
    -> закрывает пустую вкладку "~"
```

## Диагностика

```bash
# Лог восстановления
cat ~/.claude/logs/cmux-resume-zsh.log

# Что сохранено
cat ~/.claude/cmux-restore.json | python3 -m json.tool

# Принудительный save
python3 ~/.claude/scripts/cc-sessions.py save

# Сбросить lock (повторить restore)
rm ~/.claude/cmux-restore.lock
```

## Подводные камни, которые мы обошли

- **`cmux send` в живой claude → user input.** Если в workspace уже бежит claude, отправленная через `cmux send` строка попадёт ему **внутрь чата как сообщение от пользователя**, а не выполнится в shell. Поэтому скрипт перед каждым `cmux send` проверяет `ps -eo tty,command` — есть ли в TTY процесс `/opt/homebrew/bin/claude` (или другой `*/claude` бинарь). Если есть — пропуск.
- **`--settings` JSON содержит `claude-hook`.** Простая подстрока `"claude-hook" not in cmd` отсекает все живые claude (потому что hook-конфиг зашит в `--settings`). Сравнение идёт **только по имени бинаря** — первый whitespace-токен в `command`.
- **Дубликаты имён workspace.** При сохранении (`cc-sessions.py save`) дедуп по `sessionId` (приоритет — последний `savedAt`). При восстановлении: каждая вкладка с одинаковым именем используется максимум одной записью (через `consumed`-флаг).
- **Race на стартапе.** Lock через inode сокета `cmux.sock` (`stat -f%i`) — уникален в рамках одной cmux-сессии. Гарантирует один restore-проход за жизнь cmux.
- **Thundering herd на ccusage.** При параллельном старте 14 сессий каждая `statusline.sh` рожала свой `ccusage daily` (~100% CPU × 14 = коллапс). Решено в [`claude-statusline`](../claude-statusline/) через `mkdir`-lock; staggered restore — дополнительная защита.

## Регрессии cmux 0.64.3 и обходные пути

В апреле 2026 cmux 0.64.x изменил поведение нескольких CLI-команд. Скрипт обходит четыре регрессии:

| Регрессия | Симптом | Workaround |
|---|---|---|
| `new-workspace --command "X"` | Команда тихо игнорируется. Workspace создаётся с пустым shell. | Не использовать `--command`. Создавать через `new-workspace --focus true`, потом `cmux send`. |
| Долгая пауза между `cmux send` | Сокет к pty закрывается → следующий send возвращает `Failed to write to socket (Broken pipe, errno 32)`. Воспроизводится на ~30s паузе. | Все `send`-ы в одну пачку без пауз (`time.sleep(0.5)` между ними максимум). Ступенчатый запуск claude — через сам shell: `sleep N && claude --resume X`. |
| Lazy pty | Без явного `--focus true` cmux создаёт workspace, но pty инициализируется только при первом фокусе. `cmux send` возвращает OK, но команда буферизуется и может не дойти. | Создавать с `--focus true`. Цена: лёгкое мерцание UI при создании каждой вкладки. |
| Stale `tree` IDs | `cmux tree` показывает `surface:N`/`tty=ttysNN` от предыдущего процесса cmux. `cmux send --surface surface:2` ругается «Surface is not a terminal», хотя в `tree` он `[terminal]`. | Никогда не передавать `--surface` из `tree` напрямую. Матчинг и адресация — только по имени workspace и `workspace:N` ref. |
| Browser-split panes | Если в workspace есть pane с браузером и он `[focused]`, дефолтная цель send — браузерная surface, и cmux отвергает с «Surface is not a terminal». | Текущий скрипт пропускает такие — отметить и оставить юзеру вручную. |

## Ограничения

- cmux hooks (`set-hook`) не сохраняются между рестартами — поэтому используется zshrc
- Сессии без контента (пустые) не сохраняются Claude Code — только сессии с историей
- При закрытии воркспейсов могут оставаться MCP-процессы (`bun server.ts`) — `pkill -f "bun server.ts"`
- cmux v0.63.2; в будущих версиях будет встроенный restore (коммит 7102fdf)

## Платформа

- **macOS**: работает из коробки
- **Linux**: нужна адаптация путей (`stat -f%i` -> `stat -c %i`, путь к cmux)
