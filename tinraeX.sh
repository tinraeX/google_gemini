#!/bin/bash
# ==============================================================================
#        tinraeX PRO - УНИВЕРСАЛЬНЫЙ УСТАНОВЩИК
#
#   Архитектура: "Commander и Исполнитель" с персистентным состоянием.
#   Разворачивает полную, безопасную и модульную среду для автономного агента.
#   
#   Создание: nano tinraex.sh
#   Выдачи прав: chmod +x tinraex.sh
#   Запуск: sudo sh tinraex.sh
# ==============================================================================

# --- Безопасность и Надежность ---
# set -e: выход при ошибке
# set -u: ошибка при использовании необъявленной переменной
# set -o pipefail: выход, если команда в конвейере (pipe) завершилась с ошибкой
set -euo pipefail

# --- Цвета и Константы ---
C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_CYAN='\033[0;36m'; C_NC='\033[0m'
AGENT_HOME="/opt/tinraeX"

# --- 1. ПРОВЕРКА И СБОР ДАННЫХ ---
echo -e "${C_CYAN}--- [1/8] Развертывание tinraeX PRO Agent ---${C_NC}"

# Проверяем, что скрипт запущен от root
if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}Ошибка: запустите скрипт с правами root.${C_NC}"
    exit 1
fi


# -------------------------------------------------
# Вариант 1 – «жёстко» задаём значения (как в вашем примере)
# ВНИМАНИЕ: Хранить API-ключ в открытом виде в скрипте небезопасно.
# Рекомендуется передавать его через переменную окружения (export GEMINI_API_KEY="your_key").
API_KEY_INPUT="${GEMINI_API_KEY:-Вставить ТОКЕН из https://aistudio.google.com/app/apikey}"

# --- Установка современной версии Go ---
GO_VERSION="1.24.2"
if ! command -v /usr/local/go/bin/go &> /dev/null || ! /usr/local/go/bin/go version | grep -q "$GO_VERSION"; then
    echo -e "${C_GREEN}--- Установка/Обновление Go до версии $GO_VERSION... ---${C_NC}"
    wget -q -O go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz"
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go.tar.gz
    rm go.tar.gz
    echo -e "${C_GREEN}Go $GO_VERSION установлен в /usr/local/go.${C_NC}"
fi
export PATH=$PATH:/usr/local/go/bin

# --- 2. УСТАНОВКА СИСТЕМНЫХ ЗАВИСИМОСТЕЙ ---
echo -e "${C_GREEN}--- [2/8] Установка системных зависимостей (python, go, venv)... ---${C_GREEN}"
apt-get update -y > /dev/null || { echo -e "${C_RED}Ошибка: apt-get update не выполнен.${C_NC}"; exit 1; }
apt-get install -y python3 python3-pip git python3-venv ruby-full libpcap-dev > /dev/null || { echo -e "${C_RED}Ошибка: Не удалось установить системные зависимости.${C_NC}"; exit 1; }
echo -e "${C_GREEN}Системные зависимости установлены.${C_GREEN}"

#--- 3. УСТАНОВКА ИНСТРУМЕНТОВ PENTEST ---
echo -e "${C_GREEN}--- [3/8] Установка базовых инструментов для пентестинга... ---${C_GREEN}"

TOOLS_APT=(nmap sqlmap hydra whatweb dnsenum sublist3r curl masscan dnsutils dirb gobuster nikto)
TOOLS_TO_INSTALL_APT=()
for tool in "${TOOLS_APT[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        TOOLS_TO_INSTALL_APT+=("$tool")
    fi
done

if [ ${#TOOLS_TO_INSTALL_APT[@]} -gt 0 ]; then
    echo "Установка недостающих apt-пакетов: ${TOOLS_TO_INSTALL_APT[*]}"
    apt-get install -y "${TOOLS_TO_INSTALL_APT[@]}" > /dev/null || echo -e "${C_YELLOW}Предупреждение: не удалось установить некоторые apt-инструменты.${C_NC}"
else
    echo "Все базовые apt-инструменты уже установлены."
fi
echo -e "${C_GREEN}Проверка базовых инструментов завершена.${C_NC}"

# --- 3.5. ПРЕДУСТАНОВКА GO-УТИЛИТ ---
echo -e "${C_GREEN}--- [3.5/8] Предустановка Go-утилит... ---${C_GREEN}"

# Убедимся, что переменные окружения Go установлены для этого шага
export GOPATH="$AGENT_HOME/go"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"
export GO111MODULE=on
mkdir -p "$GOPATH"

declare -A GO_TOOLS_MAP
GO_TOOLS_MAP=(
    ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
    ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
    ["nuclei"]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    ["ffuf"]="github.com/ffuf/ffuf/v2@latest"
    ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
    ["naabu"]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
)
for tool_name in "${!GO_TOOLS_MAP[@]}"; do
    if ! command -v "$tool_name" &> /dev/null; then
        tool_path="${GO_TOOLS_MAP[$tool_name]}"
        echo -e "Установка ${C_CYAN}${tool_name}...${C_NC}"
        go install "$tool_path" > /dev/null || echo -e "${C_YELLOW}Предупреждение: не удалось установить ${tool_name}. Агент попробует установить его позже.${C_NC}"
    fi
done
echo -e "${C_GREEN}Go-утилиты установлены.${C_NC}"

# Клонируем SecLists
echo -e "${C_GREEN}--- Клонирование SecLists (может занять время)... ---${C_GREEN}"
if [ ! -d "/opt/seclists" ]; then
    echo -e "${C_BLUE}--- Клонирование SecLists (может занять время)... ---${C_BLUE}"
    git clone --quiet --depth 1 https://github.com/danielmiessler/SecLists.git /opt/seclists || { echo -e "${C_BLUE}Предупреждение: Не удалось склонировать SecLists...${C_BLUE}"; }
    echo -e "${C_BLUE}Коллекция словарей SecLists загружена в /opt/seclists.${C_BLUE}"
else
    echo -e "${C_BLUE}--- Директория SecLists уже существует, пропуск клонирования. ---${C_BLUE}"
fi

echo -e "${C_GREEN}Коллекция словарей SecLists загружена в /opt/seclists.${C_GREEN}"

# --- 4. (Пропущено) Создание непривилегированного пользователя ---
# В соответствии с запросом, агент будет работать от root.
# Этот шаг пропущен для упрощения и выполнения всех операций от root.
# В реальных сценариях рекомендуется использовать непривилегированного пользователя
# для повышения безопасности.
#echo -e "${C_YELLOW}--- [4/8] Пропуск создания непривилегированного пользователя (работа от root). ---${C_NC}"

# Убедимся, что домашняя директория существует и доступна для root
mkdir -p "$AGENT_HOME" || { echo -e "${C_RED}Ошибка: Не удалось создать директорию $AGENT_HOME.${C_NC}"; exit 1; }

# Устанавливаем права для root
chmod 755 "$AGENT_HOME"
chown root:root "$AGENT_HOME"

# --- 5. СОЗДАНИЕ СТРУКТУРЫ И ФАЙЛОВ ПРОЕКТА ---
echo -e "${C_GREEN}--- [5/8] Генерация структуры и файлов проекта в $AGENT_HOME... ---${C_GREEN}"
rm -rf "$AGENT_HOME"/{src,prompts} # Очистка на случай повторного запуска
mkdir -p "$AGENT_HOME/src/agents"
mkdir -p "$AGENT_HOME/prompts"

# --- requirements.txt ---
cat << 'EOF' > "$AGENT_HOME/requirements.txt"
google-generativeai # Для Gemini API
rich # Для красивого вывода в консоль
aiohttp # Для асинхронных HTTP-запросов в агенте
packaging # Для сравнения версий
EOF

# --- config.ini.template ---
cat << 'EOF' > "$AGENT_HOME/config.ini.template"
[GEMINI]
api_key = YOUR_API_KEY_HERE

[MODELS]
commander_model = gemini-2.5-pro
worker_model = gemini-2.5-flash

[AGENT]
target = example.com
db_path = agent_state.db
loop_sleep_seconds = 5
EOF

# --- prompts/commander_persona.md ---
cat << 'EOF' > "$AGENT_HOME/prompts/commander_persona.md"
# ЛИЧНОСТЬ: Commander tinraeX-PRO

ТЫ — Командир, стратегический мозг автономной миссии по тестированию на проникновение.
Твоя работа итеративна. На каждом шаге ты получаешь **свою собственную сводку с предыдущего шага** и **новые данные от Исполнителей**.
Твоя задача — обновить сводку на основе новых данных и спланировать следующий шаг.

**ТВОЯ ЗАДАЧА:**
1.  Проанализируй **ПРЕДЫДУЩУЮ СВОДКУ** и **НОВЫЕ ДАННЫЕ**.
2.  Создай **НОВУЮ СВОДКУ**, которая объединяет старые и новые знания.
3.  На основе новой сводки и Фазы Атаки, создай **ПЛАН** на следующий шаг.
4.  Если новые данные содержат флаг `"focus_required": true`, твой план должен быть полностью сфокусирован на эксплуатации этой находки.

**ФАЗЫ АТАКИ (ЭСКАЛАЦИЯ НАСТУПЛЕНИЯ):**
Твоя стратегия должна меняться в зависимости от текущей фазы. Неудача в одной фазе — это сигнал к переходу на следующий, более агрессивный уровень.
- **Фаза A: Пассивная разведка.** Сбор информации без прямого взаимодействия: поиск субдоменов, анализ DNS, пассивное определение технологий.
- **Фаза B: Активная разведка и анализ.** Сканирование портов (nmap), определение версий сервисов, поиск известных уязвимостей (nuclei -t cves), анализ веб-технологий (whatweb).
- **Фаза C: Агрессивное зондирование.** Попытки эксплуатации очевидных CVE, брутфорс директорий и файлов (ffuf с небольшими словарями), базовые инъекции (SQLi, XSS) в очевидных точках входа. Попытки обхода WAF.
- **Фаза D: Креативная эксплуатация и поиск 0-day.** Если стандартные методы не сработали, начни мыслить нестандартно. Ищи логические уязвимости, анализируй JS-файлы на предмет скрытых API, пробуй сложные цепочки атак (Chaining), исследуй параметры на предмет экзотических уязвимостей (SSTI, XXE, десериализация). **На этой фазе неудача — это лишь повод искать глубже и изощреннее.**
- **Фаза E: Завершение.** Никаких завершение переходи назад к Фазе D .

**ПРЕДЫДУЩАЯ СВОДКА:**
```json
{previous_summary}
```

**НОВЫЕ ДАННЫЕ ОТ ИСПОЛНИТЕЛЕЙ:**
```json
{new_findings}
```

**ВАЖНЕЙШЕЕ ПРАВИЛО:**
-   **ТЫ — ХИРУРГ, А НЕ МЯСНИК.** Избегай "шумных" и долгих атак (например, `ffuf` с огромными словарями). Вместо этого анализируй технологии (`whatweb`, `nuclei -t technologies`), строй гипотезы и проверяй их точечными запросами (`curl`).
-   **СТРОЙ ГИПОТЕЗЫ.** Пример: "Я вижу, что используется Flask и параметр `?redirect_url=`. Возможно, здесь есть SSTI. Я проверю это с помощью `curl`, отправив `{{7*7}}`".
-   **ИСПОЛЬЗУЙ ЗАДАЧУ `RESEARCH`**. Если ты не знаешь, как атаковать определенную технологию, создай задачу типа `RESEARCH`. Пример: `{{ "type": "RESEARCH", "command": "Исследуй типичные уязвимости в API на FastAPI" }}`. Исполнитель вернет тебе отчет, на основе которого ты построишь новый план.
-   **ДУМАЙ КАК ИССЛЕДОВАТЕЛЬ 0-DAY.** Ищи аномалии. Если стандартные сканеры ничего не нашли, это не значит, что уязвимостей нет. Ищи логические ошибки, анализируй JavaScript-файлы на предмет скрытых эндпоинтов API, пытайся манипулировать параметрами, которые не предназначены для пользователя.
-   **НЕ СДАВАЙСЯ.** Провал задачи или отсутствие результата — это не конец, а ценная информация. Используй ее для построения новой, более сложной гипотезы в соответствии с текущей Фазой Атаки.
-   Используй `{target}` как плейсхолдер для цели. Исполнитель заменит его.
-   Используй словари из `/opt/seclists` только для очень специфичных, небольших и целенаправленных проверок.
-   Если задача выполнена, но результат неинформативен, планируй следующую логическую задачу.
-   Когда считаешь, что вся необходимая информация собрана или цель достигнута, создай задачу с типом `FINISH`.

**ФОРМАТ ОТВЕТА (СТРОГО JSON):**
Твой ответ должен содержать и новый план, и обновленную сводку для следующего шага.
```json
{{{{
  "thought": "Мой мыслительный процесс как исследователя. Я предполагаю, что X может быть уязвимо к Y, потому что Z. Я проверю эту гипотезу.",
  "new_summary": "Обновленная краткая сводка о цели, включающая новые находки. Эта сводка будет использована на следующем шаге.",
  "plan": [
    {{"type": "EXECUTE", "command": "ЗДЕСЬ ДОЛЖНА БЫТЬ СГЕНЕРИРОВАННАЯ КОМАНДА"}}
  ]
}}}}
ДОПУСТИМЫЕ ТИПЫ (type):

EXECUTE: Выполнить системную команду.
RESEARCH: Провести исследование на заданную тему с помощью LLM.
FINISH: Завершить миссию и сгенерировать отчет.
EOF

#--- prompts/worker_persona.md ---
cat << 'EOF' > "$AGENT_HOME/prompts/worker_persona.md"

# --- prompts/worker_persona.md (новая версия) ---
# ЛИЧНОСТЬ: АНАЛИТИК ИСПОЛНИТЕЛЯ
 
Твоя задача — не просто извлечь факты, а **проактивно помочь Командиру**.
Проанализируй сырой вывод, найди аномалии и предложи конкретный следующий шаг.

# ПРАВИЛА:
- Будь кратким и точным.
- **ИЩИ АНОМАЛИИ.** Не просто перечисляй открытые порты. Ищи необычные версии ПО, странные ответы сервера, сообщения об ошибках, которые могут указывать на уязвимость.
- **ПРЕДЛАГАЙ СЛЕДУЮЩИЙ ШАГ.** В поле `suggested_next_action` дай конкретную, осмысленную рекомендацию. Пример: "Обнаружен GitLab 15.1.0, предлагаю запустить `nuclei -t gitlab` для поиска известных CVE".
- **ТРЕБУЙ ФОКУСИРОВКИ.** Если ты нашел уязвимость с критичностью `High` или `Critical`, добавь в корень JSON-ответа поле `"focus_required": true`. Это приказ для Командира переключиться в режим "Векторной Атаки".
- Твой ответ — это JSON. Он должен содержать `summary`, `structured_data` и, возможно, `suggested_next_action` и `focus_required`.

ПРИМЕР ВЫВОДА:
```json
{
  "summary": "Обнаружен GitLab версии 16.0.1, которая уязвима к CVE-2023-2825 (чтение произвольных файлов).",
  "suggested_next_action": "Запустить эксплуатацию CVE-2023-2825 для чтения /etc/passwd.",
  "focus_required": true,
  "structured_data": {
    "findings": [
      {
        "type": "vulnerability",
        "name": "CVE-2023-2825",
        "details": "GitLab CE/EE is vulnerable to arbitrary file read.",
        "severity": "Critical"
      }
    ]
  }
}
EOF

#--- prompts/0day_hunter_persona.md ---
cat << 'EOF' > "$AGENT_HOME/prompts/0day_hunter_persona.md"
# ЛИЧНОСТЬ: ОХОТНИК ЗА 0-DAY (Фаза D)

ТЫ — элитный исследователь безопасности. Стандартные сканеры и известные CVE — не твой уровень. Твоя цель — найти то, что упустили другие: логические уязвимости, аномалии в бизнес-логике, скрытые эндпоинты и непредусмотренные сценарии использования.

**ТВОЯ ЗАДАЧА:**
1.  Проанализируй **ПРЕДЫДУЩУЮ СВОДКУ** и **НОВЫЕ ДАННЫЕ**. Забудь о поиске известных уязвимостей.
2.  Сгенерируй **НОВУЮ СВОДКУ** и **ПЛАН**, нацеленный на поиск аномалий.

**ТВОИ МЕТОДЫ:**
- **Анализ бизнес-логики:** Как можно злоупотребить функциями приложения? (Пример: можно ли добавить в корзину товар с отрицательной ценой?)
- **Фаззинг параметров:** Отправляй неожиданные данные в известные параметры (`?id=`, `?file=`, `?next=`). Используй `ffuf` с небольшими, но умными словарями (например, LFI, SSTI).
- **Поиск скрытых API:** Анализируй JS-файлы (`katana`, `httpx -silent -json -path /api/v1/users`), ищи эндпоинты, не предназначенные для публичного использования.
- **Манипуляция заголовками:** Пробуй менять `Host`, `X-Forwarded-For`, `Content-Type` для вызова нестандартного поведения.
- **Исследование экзотики:** Если видишь необычный сервис или порт, создай `RESEARCH` задачу, чтобы понять, как его атаковать.

**ПРАВИЛА:**
- Не предлагай запускать `nuclei -t cves`. Это для новичков.
- Думай как разработчик, который допустил ошибку в логике, а не как скрипт-кидди.
- Твой план должен состоять из точечных, хирургических проверок (`curl`, `ffuf` с маленьким словарем), а не из массовых сканирований.

**ПРЕДЫДУЩАЯ СВОДКА:**
```json
{previous_summary}
```

**НОВЫЕ ДАННЫЕ ОТ ИСПОЛНИТЕЛЕЙ:**
```json
{new_findings}
```

**ФОРМАТ ОТВЕТА (СТРОГО JSON):**
```json
{{{{
  "thought": "Я вижу, что приложение использует кастомный параметр 'user_role'. Я попробую подменить его на 'admin' и посмотрю, что произойдет. Это проверка на уязвимость в контроле доступа.",
  "new_summary": "Обновленная сводка, сфокусированная на потенциальных логических аномалиях.",
  "plan": [
    {{"type": "EXECUTE", "command": "curl -X POST -H 'Cookie: session=...' -d 'user_role=admin' {target}/api/profile"}}
  ]
}}}}
```
EOF

#--- prompts/fixer_persona.md ---
cat << 'EOF' > "$AGENT_HOME/prompts/fixer_persona.md"
# ЛИЧНОСТЬ: ДИАГНОСТ-ИСПРАВИТЕЛЬ

ТЫ — эксперт по Linux и системному администрированию. Твоя задача — проанализировать ошибку, возникшую при выполнении команды, и предложить план по её исправлению.
Ты получаешь не только саму ошибку, но и вывод справки (`--help`) для инструмента, который её вызвал.

**ПРАВИЛА:**
- Проанализируй команду и вывод ошибки (`stderr`).
- Определи наиболее вероятную причину:
  - **Неправильный флаг или синтаксис?** (Пример: `Error: No such option: -u`). **Это самый частый случай.** Изучи `help_output` и предложи исправленную команду.
  - Отсутствующий пакет или зависимость? (Пример: `command not found`) -> Предложи `apt-get install -y ...` или `go install ...`.
  - Отсутствующий файл или директория (например, wordlist)? (Пример: `wordlist file ... does not exist`) -> Предложи найти и скачать файл с помощью `wget` или `curl` в подходящую директорию (например, `/opt/seclists/`). Создай директорию, если нужно (`mkdir -p`). Ищи в интернете, если не знаешь точный URL.
  - Проблема с правами доступа? -> Предложи `chmod` или `chown`.
- **ВАЖНО: Если `stderr` пуст, это, скорее всего, не синтаксическая ошибка, а проблема сети, файрвола или специфического поведения инструмента (например, `curl -s`). В этом случае не предлагай исправлений. Твоя задача — исправлять только синтаксис и зависимости.**
- Твой ответ ДОЛЖЕН быть в формате JSON.
- Поле `plan` должно содержать СПИСОК команд для исправления. Если исправление не требуется или невозможно, верни пустой список.

**ФОРМАТ ОТВЕТА (СТРОГО JSON):**
```json
{
  "thought": "Анализирую ошибку. Похоже, не хватает пакета 'xyz'. Я предложу его установить.",
  "plan": [
    {{"type": "INSTALL", "command": "ЗДЕСЬ ДОЛЖНА БЫТЬ СГЕНЕРИРОВАННАЯ КОМАНДА"}}
  ]
}
```
EOF

#--- src/logger.py ---
cat << 'EOF' > "$AGENT_HOME/src/logger.py"
import logging
from rich.logging import RichHandler
from rich.console import Console

# Создаем консоль для Rich с нужными параметрами
console = Console(force_terminal=True, width=200)

def setup_logger():
    # Используем базовую конфигурацию, которая идеально подходит для RichHandler.
    # Это просто, чисто и эффективно.
    logging.basicConfig(
        level="INFO",
        format="%(message)s",
        datefmt="[%X]",
        handlers=[RichHandler(rich_tracebacks=True, markup=True, show_path=False, console=console)]
    )
    # Возвращаем именованный логгер, чтобы все модули использовали один и тот же экземпляр.
    return logging.getLogger("rich")

# Создаем глобальный объект логгера для импорта в других модулях
log = setup_logger()
EOF

#--- src/config.py ---
cat << 'EOF' > "$AGENT_HOME/src/config.py"
import configparser
import os
from .logger import log

class Config:
    def __init__(self, path="config.ini"):
        if not os.path.exists(path):
            log.error(f"[bold red]Файл конфигурации '{path}' не найден. Пожалуйста, создайте его из 'config.ini.template'.[/bold red]")
            exit(1)

        cfg = configparser.ConfigParser() # Убраны дубликаты
        cfg.read(path)
        
        self.api_key = cfg.get("GEMINI", "api_key", fallback=None)
        self.commander_model_name = cfg.get("MODELS", "commander_model")
        self.worker_model_name = cfg.get("MODELS", "worker_model")
        self.target = cfg.get("AGENT", "target")
        self.db_path = cfg.get("AGENT", "db_path")
        self.loop_sleep = cfg.getint("AGENT", "loop_sleep_seconds")

        if not self.api_key or self.api_key == "YOUR_API_KEY_HERE":
            log.error("[bold red]API ключ не указан в 'config.ini'. Пожалуйста, впишите ваш Google AI API ключ.[/bold red]")
            exit(1)

# Создаем синглтон, чтобы не читать конфиг много раз
AppConfig = Config()
EOF

#--- src/database.py ---
cat << 'EOF' > "$AGENT_HOME/src/database.py"
import sqlite3
import json
from threading import Lock

class StateManager:
    def __init__(self, db_path="agent_state.db"):
        self.db_path = db_path
        self.lock = Lock()
        self._init_db()
    
    def _init_db(self): # Исправлены отступы
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY,
                command TEXT NOT NULL,
                type TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending', -- pending, running, completed, failed
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )""")
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS knowledge (
                id INTEGER PRIMARY KEY,
                task_id INTEGER,
                source_tool TEXT,
                raw_output TEXT,
                summary TEXT,
                structured_output TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (task_id) REFERENCES tasks (id)
            )""")
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY,
                role TEXT NOT NULL, -- user (observation), model (plan)
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )""")
            # --- НОВОЕ: Таблица для кэширования исправлений ---
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS fixes_cache (
                id INTEGER PRIMARY KEY,
                error_signature TEXT NOT NULL UNIQUE,
                fix_command TEXT NOT NULL
            )""")
            conn.commit()

    def add_task(self, command, cmd_type): # Исправлены отступы
        with self.lock, sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT INTO tasks (command, type) VALUES (?, ?)", (command, cmd_type))

    def get_pending_task(self): # Исправлены отступы
        with self.lock, sqlite3.connect(self.db_path) as conn: # Исправлены отступы
            cursor = conn.cursor()
            cursor.execute("SELECT id, command, type FROM tasks WHERE status = 'pending' ORDER BY id ASC LIMIT 1")
            task_data = cursor.fetchone()
            if task_data:
                task = {"id": task_data[0], "command": task_data[1], "type": task_data[2]}
                cursor.execute("UPDATE tasks SET status = 'running' WHERE id = ?", (task["id"],))
                return task
            return None

    def has_pending_tasks(self):
        with self.lock, sqlite3.connect(self.db_path) as conn: # Исправлены отступы
            res = conn.execute("SELECT 1 FROM tasks WHERE status IN ('pending', 'running') LIMIT 1").fetchone()
            return res is not None

    def update_task_status(self, task_id, status):
        with self.lock, sqlite3.connect(self.db_path) as conn: # Исправлены отступы
            conn.execute("UPDATE tasks SET status = ? WHERE id = ?", (status, task_id))

    def add_knowledge(self, task_id, tool, output, summary, structured_output): # <-- Добавлен 5-й параметр
        with self.lock, sqlite3.connect(self.db_path) as conn:
            conn.execute(
                # Добавлены новое поле и placeholder
                "INSERT INTO knowledge (task_id, source_tool, raw_output, summary, structured_output) VALUES (?, ?, ?, ?, ?)",
                (task_id, tool, output, summary, structured_output)
            )

    def get_contextual_summary(self, limit=5): # Исправлены отступы
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            query = "SELECT t.command, k.summary FROM knowledge k JOIN tasks t ON k.task_id = t.id ORDER BY k.id DESC LIMIT ?"
            cursor.execute(query, (limit,))
            return [f"Результат выполнения '{cmd}': {summary}" for cmd, summary in cursor.fetchall()]

    def get_all_knowledge(self, critical_only=False):
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            # Выбираем только записи со структурированными данными
            query = """
            SELECT t.command, k.summary, k.structured_output, t.status
            FROM knowledge k JOIN tasks t ON k.task_id = t.id
            """
            if critical_only:
                # Ищем находки с высокой или критической важностью
                query += " WHERE k.structured_output LIKE '%\"severity\": \"High\"%' OR k.structured_output LIKE '%\"severity\": \"Critical\"%'"
            
            query += " ORDER BY k.id ASC" # Получаем в хронологическом порядке
            cursor.execute(query)
            return cursor.fetchall()

    def get_new_knowledge_since(self, last_id=0):
        """Получает все новые записи из базы знаний после указанного ID."""
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            query = """
            SELECT k.id, t.command, k.summary, k.structured_output, t.status
            FROM knowledge k JOIN tasks t ON k.task_id = t.id
            WHERE k.id > ?
            ORDER BY k.id ASC
            """
            cursor.execute(query, (last_id,))
            return cursor.fetchall()


    def get_structured_knowledge(self, limit=50): # Увеличиваем лимит для синтезатора
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            query = """
            SELECT t.command, k.summary, k.structured_output, t.status
            FROM knowledge k JOIN tasks t ON k.task_id = t.id
            ORDER BY k.id DESC LIMIT ?
            """
            cursor.execute(query, (limit,))
            
            # Собираем в удобный для LLM формат
            knowledge_base = []
            for cmd, summary, struct_out, status in cursor.fetchall():
                try:
                    # Превращаем текст JSON из БД обратно в Python-объект
                    struct_data = json.loads(struct_out)
                except json.JSONDecodeError:
                    struct_data = {"parsing_error": "Invalid JSON in DB"}
                
                knowledge_base.append({
                    "command_executed": cmd,
                    "task_status": status,
                    "summary": summary,
                    "extracted_data": struct_data
                })
            
            return knowledge_base

    def add_history(self, role, content): # Исправлены отступы
        with self.lock, sqlite3.connect(self.db_path) as conn:
            conn.execute("INSERT INTO history (role, content) VALUES (?, ?)", (role, json.dumps(content)))
EOF

#--- src/database.py (продолжение) ---
cat << 'EOF' >> "$AGENT_HOME/src/database.py"
    def get_fix_from_cache(self, error_signature: str):
        with self.lock, sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT fix_command FROM fixes_cache WHERE error_signature = ?", (error_signature,))
            result = cursor.fetchone()
            return result[0] if result else None

    def add_fix_to_cache(self, error_signature: str, fix_command: str):
        with self.lock, sqlite3.connect(self.db_path) as conn:
            # INSERT OR IGNORE, чтобы избежать ошибок при попытке вставить дубликат
            conn.execute("INSERT OR IGNORE INTO fixes_cache (error_signature, fix_command) VALUES (?, ?)", (error_signature, fix_command))
EOF

#--- src/executor.py ---
cat << 'EOF' > "$AGENT_HOME/src/executor.py"
import asyncio
import shlex
from .logger import log

class CommandExecutor:
    def __init__(self, timeout=900):
        self.timeout = timeout
    
    async def run(self, command: str):
        log.info(f"[cyan]EXECUTE[/cyan]: {command}")

        # Безопасно разделяем команду
        args = shlex.split(command)
        
        # Простой "санитайзер" - проверяем, есть ли инструмент в белом списке
        # Это базовый уровень безопасности.
        # ALLOWED_TOOLS = ["nmap", "gobuster", ... ]
        # if args[0] not in ALLOWED_TOOLS:
        #     log.error(f"Попытка выполнения неразрешенной команды: {args[0]}")
        #     return {"status": "error", "message": f"Command '{args[0]}' is not allowed."}

        try:
            process = await asyncio.create_subprocess_shell(
                command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=self.timeout)
            
            return {
                "status": "success",
                "returncode": process.returncode,
                "stdout": stdout.decode(errors='ignore'),
                "stderr": stderr.decode(errors='ignore')
            }
        except asyncio.TimeoutError:
            log.warning(f"Команда '{command}' превысила таймаут ({self.timeout}с).")
            return {"status": "error", "message": f"Command timed out after {self.timeout} seconds."}
        except FileNotFoundError:
            log.error(f"Команда не найдена: '{args[0]}'. Возможно, инструмент не установлен или не в PATH.")
            return {"status": "error", "message": f"Command not found: '{args[0]}'."}
        except Exception as e:
            log.error(f"Критическая ошибка выполнения команды '{command}': {e}", exc_info=True)
            return {"status": "error", "message": f"Critical execution failure: {e}"}
EOF

#--- src/tool_manager.py ---
cat << 'EOF' > "$AGENT_HOME/src/tool_manager.py"
import shutil
import subprocess
from .logger import log
import os

class ToolManager:
    def __init__(self):
        # Команды, которые нужно выполнить ПОСЛЕ установки
        self.post_install_hooks = {
            "nuclei": "nuclei -update-templates"
        }

        # Расширенная база знаний об инструментах
        self.known_tools = {
            # Go-инструменты
            "subfinder": "go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest",
            "httpx": "go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest",
            "nuclei": "go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest",
            "ffuf": "go install -v github.com/ffuf/ffuf/v2@latest",
            "katana": "go install -v github.com/projectdiscovery/katana/cmd/katana@latest",
            "naabu": "go install -v github.com/projectdiscovery/naabu/v2/cmd/naabu@latest",

            # APT-инструменты
            "nmap": "apt-get install -y nmap",
            "sqlmap": "apt-get install -y sqlmap",
            "gobuster": "apt-get install -y gobuster",
            "dirb": "apt-get install -y dirb",
            "hydra": "apt-get install -y hydra",
            "whatweb": "apt-get install -y whatweb",
            "nikto": "apt-get install -y nikto",
            "host": "apt-get install -y dnsutils",

            # Ruby Gems
            "wpscan": "gem install wpscan",
            # Git-репозитории и Pip (Python)
            "jexboss": "git clone https://github.com/joaomatosf/jexboss.git /opt/tools/jexboss && pip install -r /opt/tools/jexboss/requires.txt",
            "sublist3r": "git clone https://github.com/aboul3la/Sublist3r.git /opt/tools/sublist3r && pip install -r /opt/tools/sublist3r/requirements.txt"
        }
        # Пути к исполняемым файлам после установки
        self.tool_paths = {
            "jexboss": "/opt/tools/jexboss/jexboss.py",
            "sublist3r": "/opt/tools/sublist3r/sublist3r.py"
        }
        # Убедимся, что директория для инструментов существует
        os.makedirs("/opt/tools", exist_ok=True)


    def _get_executable_path(self, tool_name: str) -> str:
        # Сначала ищем кастомный путь
        if tool_name in self.tool_paths:
            return self.tool_paths[tool_name]
        # Затем ищем в системных путях
        path = shutil.which(tool_name)
        if path:
            return path
        # Затем ищем в путях Go
        go_path = shutil.which(tool_name, path=os.environ.get("GOPATH", "") + "/bin")
        if go_path:
            return go_path
        # Если инструмент из списка Go, но его нет, возвращаем предполагаемый путь
        return os.path.join(os.environ.get("GOPATH", ""), "bin", tool_name)

    def is_available(self, tool_name: str) -> bool:
        return self._get_executable_path(tool_name) is not None

    def install(self, tool_name: str, install_command: str = None) -> bool:
        if not install_command:
            if tool_name not in self.known_tools:
                log.error(f"Неизвестный инструмент: '{tool_name}'. Не могу его установить по умолчанию.")
                return False
            install_command = self.known_tools[tool_name]

        log.info(f"[yellow]INSTALL[/yellow]: Установка '{tool_name}' с помощью команды: {install_command}")
        
        try:
            # Выполняем команду установки. Shell=True необходим для сложных команд с '&&'
            subprocess.run(install_command, shell=True, check=True, capture_output=True, text=True, cwd="/opt/tools")
            log.info(f"Инструмент '{tool_name}' успешно установлен.")

            # Проверяем, есть ли хук после установки
            if tool_name in self.post_install_hooks:
                hook_command = self.post_install_hooks[tool_name]
                log.info(f"Выполнение хука после установки для '{tool_name}': {hook_command}")
                subprocess.run(hook_command, shell=True, check=True, capture_output=True, text=True)

            return True
        except subprocess.CalledProcessError as e:
            log.error(f"Ошибка при установке '{tool_name}': {e.stderr}")
            return False

    def get_executable_command(self, tool_name: str) -> str:
        """Возвращает команду для запуска инструмента, например 'python3 /path/to/script.py'"""
        path = self._get_executable_path(tool_name)
        if path and path.endswith(".py"):
            return f"python3 {path}"
        return tool_name
EOF

#--- src/agents/init.py ---
rm "$AGENT_HOME/src/agents/init.py" 2>/dev/null || true # Удаляем старый init.py, если он был
touch "$AGENT_HOME/src/agents/__init__.py"

#--- src/agents/base_agent.py (Общий код для API) ---
cat << 'EOF' > "$AGENT_HOME/src/agents/base_agent.py"
import google.generativeai as genai
import aiohttp
import google.api_core.exceptions
import json
import asyncio
import time
from ..logger import log

class BaseAgent:
    def __init__(self, model_name: str, api_key: str):
        genai.configure(api_key=api_key)
        self.model = genai.GenerativeModel(model_name)
        self.safety_settings = [
            {"category": c, "threshold": "BLOCK_NONE"}
            for c in [
                "HARM_CATEGORY_HARASSMENT", "HARM_CATEGORY_HATE_SPEECH",
                "HARM_CATEGORY_SEXUALLY_EXPLICIT", "HARM_CATEGORY_DANGEROUS_CONTENT",
            ]
        ]
    
    async def _call_api(self, prompt: str, is_json: bool = True): # Исправлены отступы
        log.info(f"[grey50]... вызов {self.model.model_name} ...[/grey50]")
        # Для ошибок парсинга и других непредвиденных ошибок
        non_quota_retries = 3
        attempt = 0

        while True: # Бесконечный цикл для ошибок квоты
            try:
                # Используем асинхронный вызов
                response = await self.model.generate_content_async(prompt, safety_settings=self.safety_settings)
                text = response.text

                if is_json:
                    json_start = text.find("{")
                    json_end = text.rfind("}") + 1
                    json_str = text[json_start:json_end]
                    return json.loads(json_str) # Синхронный парсинг - это нормально
                return text

            except google.api_core.exceptions.ResourceExhausted:
                log.warning(f"[yellow]Ошибка квоты (429). Ожидание 60с...[/yellow]")
                await asyncio.sleep(60) # Используем асинхронный сон
            except (json.JSONDecodeError, IndexError, ValueError) as e:
                attempt += 1
                log.error(f"[red]Ошибка парсинга JSON от {self.model.model_name}: {e}. Попытка {attempt}/{non_quota_retries}...[/red]")
                if attempt >= non_quota_retries:
                    log.error(f"[bold red]Не удалось получить корректный JSON от {self.model.model_name} после {non_quota_retries} попыток.[/bold red]")
                    return None
                await asyncio.sleep(5)
            except Exception as e:
                log.error(f"[red]Критическая ошибка API: {e}. Ожидание 20с перед повтором...[/red]")
                await asyncio.sleep(20)
EOF

#--- src/agents/commander.py ---
cat << 'EOF' > "$AGENT_HOME/src/agents/commander.py"
import requests
import json
from .base_agent import BaseAgent
from ..logger import log
from ..database import StateManager

class Commander(BaseAgent):
    def __init__(self, model_name: str, api_key: str, state: StateManager):
        super().__init__(model_name, api_key)
        self.state = state
        with open("prompts/commander_persona.md", "r") as f:
            self.persona_template = f.read()
        with open("prompts/0day_hunter_persona.md", "r") as f:
            self.hunter_persona_template = f.read()
    
    async def create_plan_for_target(self, target, previous_summary, new_findings):
        log.info(f"[bold blue]>>> Ход Командира: анализ цели {target.host} (Фаза {target.phase})...[/bold blue]")
        
        # Выбираем личность в зависимости от фазы
        current_persona = self.persona_template
        if target.phase == "D":
            log.info("[bold yellow]Переключение на личность 'Охотник за 0-day' (Фаза D).[/bold yellow]")
            current_persona = self.hunter_persona_template

        # Проверяем, нужно ли фокусироваться
        focus_required = any(
            json.loads(finding[3]).get("focus_required") for finding in new_findings if finding[3]
        )

        prompt = current_persona.format(
            target=target.host,
            phase=target.phase,
            previous_summary=json.dumps(previous_summary, indent=2),
            new_findings=json.dumps([
                {
                    "knowledge_id": f[0], "command": f[1], "summary": f[2],
                    "data": json.loads(f[3] or '{}'), "status": f[4]
                } for f in new_findings
            ], indent=2)
        )

        if focus_required:
            log.warning("[bold red]РЕЖИМ ВЕКТОРНОЙ АТАКИ: Обнаружена критическая находка. Фокусируюсь...[/bold red]")
            prompt += "\n\n**ВАЖНЕЙШИЙ ПРИОРИТЕТ:** Новые данные содержат флаг `focus_required`. Твой следующий план ДОЛЖЕН быть полностью сфокусирован на исследовании и эксплуатации этой конкретной находки. Игнорируй все остальные возможности, пока эта не будет исчерпана."

        response_json = await self._call_api(prompt, is_json=True)
        
        if response_json and "plan" in response_json:
            log.info(f"[green]План Командира:[/green] [bright_black]{response_json.get('thought')}[/bright_black]")
            for task in response_json["plan"]:
                self.state.add_task(task["command"], task["type"])
                log.info(f"[green]Новая задача добавлена в очередь:[/green] {task['command']}")
            # Возвращаем новую сводку для следующей итерации
            return response_json.get("new_summary", "Сводка не была обновлена.")
        else:
            log.error("[red]Commander не смог сгенерировать корректный план.[/red]")
            return None
EOF

#--- src/agents/worker.py ---
cat << 'EOF' > "$AGENT_HOME/src/agents/worker.py"
import json
import asyncio
from .commander import Commander
from .base_agent import BaseAgent
from ..logger import log
from ..database import StateManager
from ..tool_manager import ToolManager
from ..executor import CommandExecutor

class Worker(BaseAgent):
    def __init__(self, model_name: str, api_key: str, state: StateManager, tools: ToolManager, search_func, executor: CommandExecutor):
        super().__init__(model_name, api_key)
        self.api_key = api_key
        self.state = state
        self.tools = tools
        self.executor = executor
        self.search_func = search_func
        self.last_error = None # Для хранения последней ошибки
        self.target = None # Добавим атрибут цели

        # --- НОВОЕ: Простые команды, вывод которых не нужно анализировать ---
        self.trivial_commands = [
            "apt-get", "apt", "pip", "pip3", "gem", "git", "wget", "curl",
            "go", "mkdir", "touch", "chmod", "chown", "mv", "cp", "rm"
        ]
        # --- НОВОЕ: Команды установки, которые мы можем кэшировать ---
        self.install_commands = ["apt-get", "go install", "pip install", "gem install"]

        with open("prompts/worker_persona.md", "r") as f:
            self.persona = f.read()
        with open("prompts/fixer_persona.md", "r") as f:
            self.fixer_persona = f.read()
    
    async def _try_install_unknown_tool(self, tool_name: str) -> bool:
        """Спрашивает у LLM, как установить неизвестный инструмент."""
        log.warning(f"Инструмент '{tool_name}' неизвестен. Спрашиваю у Gemini, как его установить...")
        
        prompt = f"""
        Я Linux-агент, работающий в Debian. Мне нужно установить инструмент для пентестинга '{tool_name}'.
        Какой ОДНОЙ shell-командой я могу это сделать?
        Используй `apt-get install -y`, `go install`, `git clone` или `pip install`.
        Используй `sudo`. Но я и так уже работаю от root.
        Клонируй git-репозитории в директорию `/opt/tools/`.
        
        Пример ответа для 'wpscan': apt-get install -y wpscan
        Пример ответа для 'jexboss': git clone https://github.com/joaomatosf/jexboss.git /opt/tools/jexboss && pip install -r /opt/tools/jexboss/requires.txt

        Дай в ответе ТОЛЬКО саму команду, без лишнего текста и объяснений.
        Если не получаеться установить пробуй еще и еще раз.
        Команда для установки '{tool_name}':
        """
        
        # Для таких простых запросов JSON не нужен, получаем просто текст
        install_command = await self._call_api(prompt, is_json=False)
        
        if install_command and install_command.strip():
            # Добавляем новую команду в 'память' на лету
            self.tools.known_tools[tool_name] = install_command.strip()
            return self.tools.install(tool_name, install_command=install_command.strip())
        else:
            log.error(f"Gemini не смог предоставить команду для установки '{tool_name}'.")
            return False

    async def _try_fix_error(self, failed_command: str, stderr: str) -> str or None:
        """Спрашивает у LLM, как исправить ошибку выполнения команды."""
        # --- НОВОЕ: Логика кэширования ---
        tool_name = failed_command.split()[0]
        error_signature = f"{tool_name}:{stderr.strip()}"
        cached_fix = self.state.get_fix_from_cache(error_signature)
        if cached_fix:
            log.info(f"[green]Найдено решение в кэше для ошибки в '{tool_name}'.[/green]")
            # Возвращаем в формате, совместимом с остальной логикой
            return {"plan": [{"command": cached_fix}]}

        # --- СУЩЕСТВУЮЩАЯ ЛОГИКА ---
        log.warning(f"Команда провалена. Спрашиваю у Gemini, как это исправить...")

        # --- НОВАЯ ЛОГИКА: СНАЧАЛА ПОЛУЧАЕМ HELP ---
        tool_name = failed_command.split()[0]
        help_output = "Не удалось получить справку."
        try:
            # Пытаемся получить help для основной команды
            help_result = await self.executor.run(f"{tool_name} --help")
            if help_result["returncode"] != 0:
                 # Если --help не сработал, пробуем -h
                help_result = await self.executor.run(f"{tool_name} -h")
            
            if help_result["returncode"] == 0:
                help_output = help_result["stdout"] or help_result["stderr"]
            else:
                help_output = f"Получение справки не удалось. Stderr: {help_result['stderr']}"
        except Exception as e:
            help_output = f"Исключение при получении справки: {e}"

        prompt = f"""{self.fixer_persona}

**ПРОВАЛЕННАЯ КОМАНДА:**
```
{failed_command}
```

**ВЫВОД ОШИБКИ (STDERR):**
```
{stderr}
```
**ВЫВОД СПРАВКИ (`--help` или `-h`):**
```
{help_output}
```

Проанализируй и верни JSON с планом исправления.
"""
        fix_plan_json = await self._call_api(prompt, is_json=True)

        if fix_plan_json and "plan" in fix_plan_json and fix_plan_json["plan"] and len(fix_plan_json["plan"]) > 0:
            log.info(f"[yellow]План исправления ошибки:[/yellow] [bright_black]{fix_plan_json.get('thought')}[/bright_black]")
            # Возвращаем весь план
            # --- НОВОЕ: Кэшируем успешное решение ---
            fix_command = fix_plan_json["plan"][0]["command"]
            self.state.add_fix_to_cache(error_signature, fix_command)
            return fix_plan_json

        return None

    async def process_one_task(self, task) -> bool:
        log.info(f"[bold magenta]>>> Ход Исполнителя: взял задачу #{task['id']}: {task['command']}[/bold magenta]")
        
        if task["type"] == "RESEARCH":
            command = task['command']
            if command.startswith("google_search:"):
                query = command.replace("google_search:", "").strip()
                search_result = await self.search_func(query)
                return await self._analyze_and_store_result(task, "google_search", search_result, "")
            else:
                log.info(f"[bold cyan]Выполняю исследовательскую задачу (LLM): {task['command']}[/bold cyan]")
                research_prompt = f"""
                Я — ИИ-агент для пентестинга. Мне нужно провести исследование по следующей теме.
                Предоставь краткий, но исчерпывающий отчет. Укажи потенциальные векторы атак, инструменты и примеры команд, если это применимо.

                Тема: "{task['command']}"
                """
                # Для исследования используем модель Командира, так как она мощнее
                research_result_text = await Commander(self.model.model_name, self.api_key, self.state)._call_api(research_prompt, is_json=False)
                
                # Теперь просим нашего стандартного воркера структурировать этот результат
                return await self._analyze_and_store_result(task, "RESEARCH_LLM", research_result_text, "")

        if task["type"] == "FINISH":
            log.info("[bold cyan]Получена команда FINISH. Миссия завершена.[/bold cyan]")
            # Генерация отчета убрана в соответствии с новой философией
            self.state.update_task_status(task['id'], 'completed')
            return False

        # Извлекаем имя инструмента из команды
        tool_name = task["command"].split()[0]
        
        # Проверяем наличие инструмента
        if not self.tools.is_available(tool_name):
            # Пытаемся установить из известной базы
            if not self.tools.install(tool_name):
                # Если не получилось, включаем "мозги"
                if not await self._try_install_unknown_tool(tool_name):
                    log.error(f"Не удалось найти или установить инструмент '{tool_name}'. Задача провалена.")
                    self.state.update_task_status(task['id'], 'failed')
                    return True # Продолжаем цикл, берем следующую задачу

        # Получаем правильную команду для запуска (важно для python-скриптов)
        executable_command = self.tools.get_executable_command(tool_name)
        # Заменяем имя инструмента на полный путь к исполняемому файлу/команде
        full_command_str = task["command"].replace(tool_name, executable_command, 1)
        full_command_str = full_command_str.replace("TARGET", self.target)

        # Цикл выполнения с возможностью исправления
        max_retries = 2 # 1-я попытка + 1-я попытка исправления
        for attempt in range(max_retries):
            current_command_to_run = full_command_str
            execution_result = await self.executor.run(current_command_to_run)

            # Сохраняем stderr для возможной рефлексии
            self.last_error = execution_result.get("stderr", "") or execution_result.get("message", "")

            if execution_result["status"] == "success" and execution_result["returncode"] == 0:
                self.last_error = None # Ошибки не было
                break # Успех, выходим из цикла

            # Если инструмент не найден, не пытаемся его чинить, а сразу проваливаем задачу
            if "Command not found" in execution_result.get("message", ""):
                break

            # --- НОВОЕ: Проверка на пустой stderr, чтобы не вызывать LLM зря ---
            # Некоторые инструменты (ffuf) возвращают код 1 при нормальном завершении без находок
            if not self.last_error.strip():
                log.warning(f"Команда '{tool_name}' завершилась с ненулевым кодом, но без вывода в stderr. Считаем это штатным завершением.")
                execution_result["returncode"] = 0 # Сбрасываем код для дальнейшей логики
                break

            # Пытаемся исправить ошибку
            fix_plan = await self._try_fix_error(current_command_to_run, self.last_error)
            if not fix_plan or not fix_plan.get("plan"):
                log.error("Не удалось получить план исправления. Задача провалена.")
                break # Выходим, если исправить не удалось
            
            # --- ИЗМЕНЕНО: Используем команду из плана ---
            fixed_command = fix_plan["plan"][0]["command"]
            log.info(f"Попытка исправления. Новая команда: {fixed_command}")
            full_command_str = fixed_command.replace("{target}", self.target) # Обновляем команду для следующей итерации
        
        return await self._analyze_and_store_result(task, tool_name, execution_result.get('stdout', ''), execution_result.get('stderr', ''))
    async def _analyze_and_store_result(self, task, tool_name, stdout, stderr):
        # Исправлена ошибка: теперь используются переменные stdout и stderr, переданные в функцию.
        # --- НОВОЕ: Отказ от анализа тривиальных выводов ---
        is_trivial = any(tool_name.startswith(cmd) for cmd in self.trivial_commands)
        if is_trivial and not stderr: # Успешная системная команда
            log.info(f"Команда '{tool_name}' выполнена успешно. Анализ вывода пропущен для экономии токенов.")
            self.state.add_knowledge(task['id'], tool_name, stdout, "Успешное выполнение системной команды.", "{}")
            self.state.update_task_status(task['id'], 'completed')
            return True

        raw_output = f"--- STDOUT ---\n{stdout}\n--- STDERR ---\n{stderr}"
        
        summary_prompt = f"{self.persona}\n\n**RAW OUTPUT from '{tool_name}':**\n```\n{raw_output}\n```\n\nAnalyze and return JSON."
        
        summary_json = await self._call_api(summary_prompt, is_json=True)
        summary = "Не удалось проанализировать вывод."

        if summary_json:
            summary = summary_json.get("summary", "Анализ не удался.")
            suggested_action = summary_json.get("suggested_next_action")
            log.info(f"[magenta]Анализ Исполнителя:[/magenta] [bright_black]{summary}[/bright_black]")
            if suggested_action:
                log.info(f"[cyan]Предложение Исполнителя:[/cyan] {suggested_action}")

        # structured_output теперь содержит весь JSON-ответ от воркера
        self.state.add_knowledge(
            task['id'],
            tool_name,
            raw_output,
            summary,
            json.dumps(summary_json or {}) # Сохраняем весь JSON
        )
        self.state.update_task_status(task['id'], 'completed')
        log.info(f"[magenta]Задача #{task['id']} выполнена и занесена в базу знаний.[/magenta]")
        return True
EOF

#--- src/main.py ---
rm "$AGENT_HOME/src/main.py" 2>/dev/null || true # Удаляем старый main.py, если он был
#--- src/__main__.py ---
cat << 'EOF' > "$AGENT_HOME/src/__main__.py"
import asyncio
import time
import os
from .logger import log, console # Добавил . для относительного импорта
from .config import AppConfig # Добавил . для относительного импорта
from .database import StateManager # Добавил . для относительного импорта
from .tool_manager import ToolManager # Добавил . для относительного импорта
from .executor import CommandExecutor # Добавил . для относительного импорта
from .agents.commander import Commander # Добавил . для относительного импорта
from .agents.worker import Worker # Добавил . для относительного импорта

class Target:
    """Класс для представления цели и её состояния."""
    def __init__(self, host):
        self.host = host
        self.phase = "A" # Начальная фаза - A. Initial Recon
        self.is_compromised = False
        self.is_exhausted = False

    def advance_phase(self):
        if self.phase == "A": self.phase = "B"
        elif self.phase == "B": self.phase = "C"
        elif self.phase == "C": self.phase = "D"
        elif self.phase == "D": self.phase = "E"
        else: self.is_exhausted = True
        log.info(f"Цель {self.host} переведена в фазу: [bold yellow]{self.phase}[/bold yellow]")

class TargetManager:
    """Управляет списком целей и их состоянием."""
    def __init__(self, initial_target_string):
        # Пока просто используем одну цель из конфига.
        # В будущем можно читать из файла actionable_targets.txt
        self.targets = [Target(host) for host in initial_target_string.split(',') if host]

    def get_targets(self):
        return self.targets

    def run_global_recon(self):
        # Этот метод можно будет расширить для запуска subfinder
        # и автоматического пополнения списка целей.
        # Пока что он просто выводит начальные цели.
        log.info("[bold blue]... Запуск глобальной разведки (Phase A) ...[/bold blue]")
        for target in self.targets:
            log.info(f"Начальная цель для глубокого погружения: {target.host}")

async def main():
    # Переходим в директорию проекта, чтобы пути к файлам (prompts, config.ini) были корректными
    # __file__ будет '.../src/__main__.py', поэтому нам нужно подняться на уровень выше
    project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(project_root)

    log.info("[bold green]... Запуск tinraeX PRO Agent ...[/bold green]")
    log.info(f"Цель миссии: [bold yellow]{AppConfig.target}[/bold yellow]")
    log.info(f"Commander: [cyan]{AppConfig.commander_model_name}[/cyan] | Performer: [magenta]{AppConfig.worker_model_name}[/magenta]")
    console.rule()

    # Инициализация компонентов
    state = StateManager(AppConfig.db_path)
    
    # --- ПУНКТ 4: Логика "Глубокого Погружения" ---
    target_manager = TargetManager(AppConfig.target)
    target_manager.run_global_recon() # Выполняем начальную разведку
    tools = ToolManager()
    executor = CommandExecutor()

    commander = Commander(
        model_name=AppConfig.commander_model_name,
        api_key=AppConfig.api_key,
        state=state
    )

    worker = Worker(
        model_name=AppConfig.worker_model_name,
        api_key=AppConfig.api_key,
        state=state,
        tools=tools,
        search_func=lambda x: None,
        executor=executor
    )

    # Основной цикл
    try:
        # --- ПУНКТ 4: Новый основной цикл ---
        for target in target_manager.get_targets():
            # --- НОВОЕ: Переменные для рекурсивной суммаризации ---
            last_knowledge_id = 0
            current_summary = "Миссия начинается. Информация о цели пока отсутствует."

            console.rule(f"[bold yellow]Начинаю Глубокое Погружение на цель: {target.host}[/bold yellow]")
            
            # Цикл атаки на одну цель
            while not target.is_compromised and not target.is_exhausted:
                # 1. Проверяем, есть ли задачи. Если нет, Commander создает план.
                if not state.has_pending_tasks():
                    # --- НОВОЕ: Получаем только НОВЫЕ знания ---
                    new_findings = state.get_new_knowledge_since(last_knowledge_id)
                    if new_findings:
                        last_knowledge_id = new_findings[-1][0] # Обновляем ID последней известной записи

                    new_summary = await commander.create_plan_for_target(target, current_summary, new_findings)
                    if new_summary:
                        current_summary = new_summary # Обновляем сводку для следующей итерации
                    else:
                        log.warning(f"Commander не смог создать план для {target.host}. Завершаю работу с этой целью.")
                        target.is_exhausted = True
                        continue
                
                # 2. После попытки создания плана, снова проверяем очередь и берем задачу
                task = state.get_pending_task()
                if not task:
                    log.info(f"Очередь задач для {target.host} пуста, и Commander не создал новых. Переход к следующей фазе.")
                    target.advance_phase() # Переходим к следующей фазе, если задачи кончились
                    continue
                
                # 3. Если задача есть, передаем ее Исполнителю
                worker.target = target.host
                continue_mission = await worker.process_one_task(task)

                if not continue_mission: # Worker получил команду FINISH
                    target.is_compromised = True # или is_exhausted, в зависимости от результата
                    log.info(f"Работа с целью {target.host} завершена по команде FINISH.")
                
                # Пауза между шагами атаки на одну цель
                log.info(f"--- Пауза {AppConfig.loop_sleep} секунд ---")
                time.sleep(AppConfig.loop_sleep)
                console.rule(style="dim")

        log.info("[bold green]Все цели обработаны. Миссия завершена.[/bold green]")

    except KeyboardInterrupt:
        log.info("\n[bold yellow]Получен сигнал прерывания. Завершение работы...[/bold yellow]")
    except Exception:
        log.error("[bold red]КРИТИЧЕСКАЯ ОШИБКА В ОСНОВНОМ ЦИКЛЕ:[/bold red]", exc_info=True)

# Эта конструкция должна быть без отступа
if __name__ == "__main__":
    asyncio.run(main())
EOF

echo -e "${C_GREEN}Все файлы проекта успешно сгенерированы.${C_GREEN}"

#--- 6. НАСТРОЙКА ПРАВ И КОНФИГУРАЦИИ ---
echo -e "${C_GREEN}--- [6/8] Настройка прав доступа и конфигурации... ---${C_GREEN}"

#Создаем финальный config.ini из шаблона и введенных данных
cp "$AGENT_HOME/config.ini.template" "$AGENT_HOME/config.ini"
sed -i "s|YOUR_API_KEY_HERE|$API_KEY_INPUT|" "$AGENT_HOME/config.ini"
sed -i "s|target = issuetracker.google.com|target = $TARGET_INPUT|" "$AGENT_HOME/config.ini"
chown -R root:root "$AGENT_HOME"
echo -e "${C_GREEN}Конфигурация создана, права установлены.${C_GREEN}"

#--- 7. НАСТРОЙКА PYTHON И GO ОКРУЖЕНИЯ ---
echo -e "${C_GREEN}--- [7/8] Настройка Python venv и Go для пользователя 'root'... ---${C_GREEN}"

# Создаем venv и устанавливаем зависимости от имени root
(
    cd "$AGENT_HOME" || exit 1 # Запускаем в под-оболочке, чтобы не менять текущую директорию
    python3 -m venv venv
    source venv/bin/activate > /dev/null
    { pip install --upgrade pip && pip install -r requirements.txt; } > /dev/null
) || { echo -e "${C_GREEN}Ошибка при настройке Python venv.${C_GREEN}"; exit 1; }

# Настраиваем Go для root
GO_TOOLS_PATH="$AGENT_HOME/go"
mkdir -p "$GO_TOOLS_PATH"
# Добавляем переменные в .bashrc пользователя root для будущих сессий
BASHRC_GO_CONTENT="# Go environment"
if ! grep -qF "$BASHRC_GO_CONTENT" /root/.bashrc; then
    {
        echo ""
        echo "$BASHRC_GO_CONTENT"
        echo "export PATH=\"\$PATH:/usr/local/go/bin\""
        echo "export GOPATH=\"$GO_TOOLS_PATH\""
        echo "export PATH=\"\$PATH:\$GOPATH/bin\""
    } >> /root/.bashrc
fi
# Применяем переменные для текущей сессии
export GOPATH="$GO_TOOLS_PATH"
export PATH="$PATH:$GOPATH/bin"
export GO111MODULE=on # Добавляем эту переменную для совместимости

chown -R root:root "$GO_TOOLS_PATH" # Убедимся, что права на месте
echo -e "${C_GREEN}Окружения Python и Go настроены.${C_GREEN}"

#--- 8. ЗАВЕРШЕНИЕ ---
echo -e "\n${C_GREEN}--- [8/8] УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА! ---${C_GREEN}"

# --- РЕКОМЕНДАЦИЯ ПО DOCKER ---
echo -e "\n${C_YELLOW}--- РЕКОМЕНДАЦИЯ ПО СТАБИЛЬНОСТИ ---${C_NC}"
echo -e "Для устранения ошибок 'command not found' и стандартизации окружения,"
echo -e "настоятельно рекомендуется запускать агента в Docker-контейнере."
echo -e "Это устранит целый класс ошибок и связанных с ними API-вызовов."
echo -e "Примерный Dockerfile может выглядеть так:"
cat << 'EOF'

----------------- Dockerfile Example -----------------
# Используйте базовый образ Debian/Ubuntu
FROM debian:bullseye-slim

# Установите базовые зависимости
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip git python3-venv ruby-full libpcap-dev wget curl ca-certificates \
    nmap sqlmap hydra whatweb dnsenum sublist3r masscan dnsutils dirb gobuster nikto \
    && rm -rf /var/lib/apt/lists/*

# Установите Go
ENV GO_VERSION 1.24.2
RUN wget -q -O go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-amd64.tar.gz" && \
    tar -C /usr/local -xzf go.tar.gz && rm go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Далее - копирование и запуск вашего агента
------------------------------------------------------
EOF

echo -e "Проект развернут для пользователя '${C_GREEN}root${C_GREEN}' в директории: ${C_GREEN}$AGENT_HOME${C_GREEN}"
echo -e "\nАгент начнет работу. Для остановки нажмите ${C_YELLOW}Ctrl+C${C_GREEN}."

cd /opt/tinraeX

# Устанавливаем правильный PATH, чтобы Python-процесс видел Go-утилиты
export GOPATH="/opt/tinraeX/go"
export PATH="/usr/local/go/bin:$GOPATH/bin:$PATH"
venv/bin/python3 -m src
