# Figma Landings

Конвертер макетов из Figma в готовые лендинги. Claude Code + Figma MCP = лендинг за один сеанс.

## Что это

Даёшь Claude Code ссылку на фрейм в Figma — он вытаскивает структуру, тексты, картинки и собирает HTML/CSS лендинг. Без ручного экспорта, без пиксель-хантинга.

**Пример:** `sites/altairika-land/` — лендинг «Виртуальная Энциклопедия», собранный из [этого макета](https://www.figma.com/design/IFZH08q7QaYrz8QnrMr7xv/Altairika-%E2%80%A2-Virtual-Encyclopedia?node-id=20610-6136).

## Быстрый старт

### 1. Установи Figma MCP сервер

Создай токен в Figma: **Settings > Security > Personal access tokens** (scope: File content, Read).

```bash
# Добавь MCP сервер в Claude Code
claude mcp add -s project figma-dev -- npx figma-developer-mcp --figma-api-key ТВОЙ_ТОКЕН --stdio
```

Перезапусти Claude Code.

### 2. Скорми Claude ссылку на Figma

Открой Claude Code в этом репозитории и напиши:

```
Вот ссылка на макет в Figma: https://www.figma.com/design/XXXXX/Name?node-id=123-456
Собери из него лендинг в sites/my-landing/
```

Claude:
1. Вызовет `get_figma_data` — получит структуру и тексты
2. Вызовет `download_figma_images` — скачает картинки
3. Сгенерирует `index.html` с инлайн-стилями

### 3. Проверь локально

```bash
cd sites/my-landing && python3 -m http.server 8888
# Открой http://localhost:8888
```

## Структура

```
sites/              — готовые лендинги
  altairika-land/   — пример: лендинг Виртуальной Энциклопедии
    index.html
    images/
    Dockerfile
skills/figma/       — справочник по Figma MCP (для Claude)
docs/               — подробная документация
```

## Что под капотом

- **Figma MCP** — [figma-developer-mcp](https://github.com/GLips/Figma-Context-MCP) (Framelink), 2 инструмента: `get_figma_data` + `download_figma_images`
- **Claude Code** — сборка HTML/CSS по данным из Figma
- Подробная инструкция для разработчиков: [`docs/README.md`](docs/README.md)
- Справочник MCP-инструментов для Claude: [`skills/figma/SKILL.md`](skills/figma/SKILL.md)
