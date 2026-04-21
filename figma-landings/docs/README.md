# Figma Landings

## Обзор

Проект для создания лендингов на основе дизайнов из Figma. Claude Code с помощью Figma MCP сервера считывает макеты и конвертирует их в готовый HTML/CSS код.

Домен: `land.altget.ru` (деплой через Coolify при пуше в main).

## Как подключить Figma MCP сервер

### 1. Создать Personal Access Token в Figma

1. Открой [figma.com](https://figma.com) и войди в аккаунт
2. Перейди в **Settings** (иконка профиля в левом верхнем углу)
3. Раздел **Security** -> **Personal access tokens**
4. Нажми **Generate new token**
5. Scope: **File content** — Read only
6. Скопируй токен (он показывается только один раз)

### 2. Сохранить токен в macOS Keychain

```bash
security add-generic-password -a "figma" -s "figma-api-token" -w "YOUR_TOKEN"
```

Проверить, что сохранился:

```bash
security find-generic-password -a "figma" -s "figma-api-token" -w
```

### 3. Добавить переменную окружения

Добавь в `~/.zshrc`:

```bash
export FIGMA_PERSONAL_ACCESS_TOKEN=$(security find-generic-password -a "figma" -s "figma-api-token" -w)
```

Затем перезагрузи шелл:

```bash
source ~/.zshrc
```

### 4. Добавить MCP сервер в Claude Code

```bash
claude mcp add -s project figma-dev -- npx figma-developer-mcp --figma-api-key YOUR_TOKEN --stdio
```

Замени `YOUR_TOKEN` на свой токен из Figma (или используй переменную `$FIGMA_PERSONAL_ACCESS_TOKEN`).

### 5. Перезапустить Claude Code

Закрой и открой Claude Code заново, чтобы MCP сервер подключился.

## Как работает процесс

```
Figma URL -> get_figma_data -> YAML с layout/content -> HTML/CSS
                            -> download_figma_images -> SVG/PNG assets
```

1. Дизайнер кидает ссылку на Figma-фрейм (или называет файл)
2. Claude извлекает `fileKey` и `nodeId` из URL
3. Вызывает `get_figma_data` — получает структуру, тексты, цвета, размеры в YAML
4. Вызывает `download_figma_images` — скачивает иконки, фоны, иллюстрации
5. Генерирует HTML/CSS код в `sites/<название-лендинга>/`
6. После пуша в main Coolify деплоит на `land.altget.ru`

## Доступные файлы Figma

### Altairika Team

| Файл | fileKey | Описание |
|------|---------|----------|
| Altairika - Virtual Encyclopedia | `IFZH08q7QaYrz8QnrMr7xv` | Все дизайн-концепции и исследования |
| Шаблон анонса | `TODO` | Шаблоны анонсов |
| Шаблон поста | `TODO` | Шаблоны постов |
| Брендбук | `TODO` | Брендбук: цвета, шрифты, логотипы |

### FranchCamp Team

| Файл | fileKey | Описание |
|------|---------|----------|
| Общий файл | `TODO` | Общие дизайны FranchCamp |
| Шаблон поста | `TODO` | Шаблоны постов FranchCamp |

### Design Team

| Файл | fileKey | Описание |
|------|---------|----------|
| Altairium | `TODO` | Проект Altairium |
| Архив | `TODO` | Архив дизайнов |

> Файлы с `TODO` в fileKey ещё не подключены. По мере необходимости добавляй fileKey из URL Figma.

## Структура проекта

```
figma-landings/
├── CLAUDE.md              # Инструкции для Claude Code
├── .gitignore
├── docs/
│   └── README.md          # Этот файл
├── sites/                 # Лендинги (каждый в своей папке)
│   └── <name>/
│       ├── index.html
│       ├── styles.css
│       └── images/
└── skills/
    └── figma/
        └── SKILL.md       # Справочник по Figma MCP инструментам
```

## Требования к лендингам

- Семантический HTML5
- Современный CSS (flexbox, grid)
- Mobile-first, адаптивный дизайн
- Минимум JavaScript (только для интерактива)
- Оптимизированные изображения (WebP где возможно)
- Pixel-perfect соответствие макету в Figma

## Статус и последние обновления

- **2026-04-21**: Первый лендинг — altairika-land (Виртуальная Энциклопедия), 63 изображения из Figma, 14 секций
- **2026-04-21**: Инициализация проекта, настройка структуры и документации
