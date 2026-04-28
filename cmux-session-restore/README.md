# cmux Session Restore

Автоматическое восстановление Claude Code сессий в cmux после перезапуска.

## Проблема

cmux не восстанавливает запущенные процессы — после рестарта все вкладки с Claude Code пустые. Приходится вручную делать `claude --resume` в каждой.

## Решение

Скрипт сохраняет привязку "вкладка cmux -> Claude session ID" и при следующем запуске cmux автоматически создает вкладки и запускает `claude --resume` в каждой.

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

## Ограничения

- cmux hooks (`set-hook`) не сохраняются между рестартами — поэтому используется zshrc
- Сессии без контента (пустые) не сохраняются Claude Code — только сессии с историей
- При закрытии воркспейсов могут оставаться MCP-процессы (`bun server.ts`) — `pkill -f "bun server.ts"`
- cmux v0.63.2; в будущих версиях будет встроенный restore (коммит 7102fdf)

## Платформа

- **macOS**: работает из коробки
- **Linux**: нужна адаптация путей (`stat -f%i` -> `stat -c %i`, путь к cmux)
