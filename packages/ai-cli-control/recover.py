#!/usr/bin/env python3
"""Transporta historiales locales de Codex, Grok, Antigravity y Claude Code.

Este programa solo lee los almacenes de cada CLI. Antigravity se consulta siempre
desde una copia temporal abierta por SQLite en modo de solo lectura.
"""

import argparse
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote


HOME = Path.home()
PROVIDERS = {"codex", "grok", "agy", "claude"}
ALIASES = {"antigravity": "agy"}
UUID_SHAPE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)
LONG_HEX_RUN = re.compile(r"[0-9a-fA-F]{24,}")
LONG_DECIMAL_RUN = re.compile(r"[0-9]{12,}")
OPAQUE_TOKEN = re.compile(r"(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])[A-Za-z0-9_-]{20,}")


def warn(message):
    print("Aviso: " + message, file=sys.stderr)


def compact(text, limit=None):
    text = " ".join(str(text or "").split())
    if limit is not None and len(text) > limit:
        return text[: max(0, limit - 1)] + "…"
    return text


def iso_mtime(path):
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat().replace("+00:00", "Z")


def iso_value(value, fallback):
    if not value:
        return fallback
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
    except ValueError:
        return fallback


def read_json_lines(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    warn(f"se omitió JSON inválido en {path}:{number} ({error.msg})")
                    continue
                if isinstance(value, dict):
                    yield value
                else:
                    warn(f"se omitió registro no objeto en {path}:{number}")
    except OSError as error:
        warn(f"no se pudo leer {path}: {error}")


def first_json_line(path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as error:
                    warn(f"se omitió JSON inválido en {path}:{number} ({error.msg})")
                    return None
                return value if isinstance(value, dict) else None
    except OSError as error:
        warn(f"no se pudo leer {path}: {error}")
    return None


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, dict):
        text = content.get("text")
        if isinstance(text, str):
            return text
        return ""
    if isinstance(content, list):
        return "\n".join(part for part in (content_text(item) for item in content) if part)
    return ""


def add_text_turn(turns, role, text):
    text = str(text or "").strip()
    if text:
        turns.append((role, text))


def tool_notice(count):
    suffix = "llamada" if count == 1 else "llamadas"
    return f"[herramientas: {count} {suffix}]"


def render_turns(turns):
    rendered = []
    pending_tools = 0
    for role, value in turns:
        if role == "tool":
            pending_tools += int(value)
            continue
        if pending_tools:
            rendered.append(tool_notice(pending_tools))
            pending_tools = 0
        label = "Usuario" if role == "user" else "Asistente"
        rendered.append(f"### {label}:\n{value}")
    if pending_tools:
        rendered.append(tool_notice(pending_tools))
    return "\n\n".join(rendered)


def parse_provider_list(raw):
    names = []
    for name in raw.replace("|", ",").split(","):
        name = name.strip().lower()
        if not name:
            continue
        name = ALIASES.get(name, name)
        if name not in PROVIDERS:
            raise ValueError(f"proveedor desconocido: {name}. Usa codex, grok, agy, antigravity o claude.")
        if name not in names:
            names.append(name)
    if not names:
        raise ValueError("indica al menos un proveedor")
    return names


def is_subagent(meta):
    source = meta.get("source")
    if source == "subagent":
        return True
    if isinstance(source, dict) and source.get("subagent"):
        return True
    return bool(meta.get("subagent"))


KNOWN_SYNTHETIC_TAGS = {
    "recommended_plugins", "user_instructions", "environment_context",
    "system-reminder", "permissions", "workspace", "user_info",
}


def is_synthetic_user_message(text):
    """Identifica el contexto inyectado por el harness, no prompts del usuario."""
    stripped = str(text or "").lstrip()
    if not stripped.startswith("<"):
        return False
    closing = stripped.find(">")
    if closing < 2:
        return False
    tag = stripped[1:closing].split(None, 1)[0].lower()
    if not tag or not all(character.isalnum() or character in "_-" for character in tag):
        return False
    if tag in KNOWN_SYNTHETIC_TAGS:
        return True
    # Los tags personalizados del harness llevan un nombre compuesto y texto de
    # configuración, no una pregunta XML breve del usuario.
    boilerplate = stripped[closing + 1:closing + 500].lower()
    markers = ("instructions", "context", "permissions", "workspace", "plugins", "environment", "you are", "system")
    return ("_" in tag or "-" in tag) and any(marker in boilerplate for marker in markers)


def codex_session(path):
    records = list(read_json_lines(path))
    if not records:
        return None
    first = records[0]
    if first.get("type") != "session_meta" or not isinstance(first.get("payload"), dict):
        warn(f"se omitió sesión Codex sin session_meta válido: {path}")
        return None
    meta = first["payload"]
    session_id = str(meta.get("session_id") or meta.get("id") or path.stem.removeprefix("rollout-"))
    turns = []
    latest = iso_value(meta.get("timestamp"), iso_mtime(path))
    for record in records[1:]:
        latest = iso_value(record.get("timestamp"), latest)
        if record.get("type") != "response_item" or not isinstance(record.get("payload"), dict):
            continue
        item = record["payload"]
        item_type = item.get("type")
        if item_type in {"function_call", "custom_tool_call", "tool_call"} or str(item_type).endswith("_call"):
            turns.append(("tool", 1))
            continue
        if item_type != "message":
            continue
        role = item.get("role")
        if role not in {"user", "assistant"}:
            continue
        text = content_text(item.get("content"))
        if role == "user" and is_synthetic_user_message(text):
            continue
        add_text_turn(turns, role, text)
    users = [text for role, text in turns if role == "user"]
    return {
        "provider": "codex", "id": session_id, "cwd": str(meta.get("cwd") or ""),
        "started": iso_value(meta.get("timestamp"), iso_mtime(path)), "last": latest,
        "count": len(users), "kind": "subagent" if is_subagent(meta) else "main",
        "first": users[0] if users else "", "turns": turns, "path": path,
    }


def codex_sessions(cwd):
    root = HOME / ".codex"
    paths = list((root / "sessions").glob("**/rollout-*.jsonl")) + list((root / "archived_sessions").glob("**/rollout-*.jsonl"))
    sessions = []
    for path in paths:
        first = first_json_line(path)
        meta = first.get("payload") if isinstance(first, dict) else None
        if first is None or first.get("type") != "session_meta" or not isinstance(meta, dict):
            continue
        if meta.get("cwd") != str(cwd):
            continue
        session = codex_session(path)
        if session:
            sessions.append(session)
    return sessions


def grok_history(path):
    turns = []
    for record in read_json_lines(path):
        role = record.get("role") or record.get("type")
        if role in {"user", "assistant"}:
            text = content_text(record.get("content"))
            if role == "user" and text.lstrip().startswith(("<system-reminder>", "<user_info>")):
                continue
            add_text_turn(turns, role, text)
        elif role in {"tool", "tool_call", "function_call"}:
            turns.append(("tool", 1))
    return turns


def grok_sessions(cwd):
    encoded = quote(str(cwd), safe="")
    root = HOME / ".grok" / "sessions" / encoded
    if not root.is_dir():
        return []
    prompts = {}
    prompt_history = root / "prompt_history.jsonl"
    for record in read_json_lines(prompt_history) if prompt_history.is_file() else ():
        session_id = record.get("session_id")
        prompt = record.get("prompt")
        if session_id and isinstance(prompt, str) and not record.get("is_bash"):
            prompts.setdefault(str(session_id), []).append(prompt)
    sessions = []
    for entry in root.iterdir():
        if not entry.is_dir():
            continue
        summary_path = entry / "summary.json"
        summary = {}
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.is_file() else {}
        except (OSError, json.JSONDecodeError) as error:
            warn(f"se omitió summary Grok inválido en {summary_path}: {error}")
        info = summary.get("info") if isinstance(summary, dict) else {}
        if not isinstance(info, dict):
            info = {}
        session_id = str(info.get("id") or entry.name)
        transcript_path = entry / "chat_history.jsonl"
        turns = grok_history(transcript_path) if transcript_path.is_file() else []
        users = [text for role, text in turns if role == "user"]
        prompt_values = prompts.get(session_id, [])
        fallback_time = iso_mtime(entry)
        sessions.append({
            "provider": "grok", "id": session_id, "cwd": str(info.get("cwd") or cwd),
            "started": iso_value(summary.get("created_at") if isinstance(summary, dict) else None, fallback_time),
            "last": iso_value(summary.get("updated_at") if isinstance(summary, dict) else None, fallback_time),
            "count": len(users) or len(prompt_values), "kind": "unknown",
            "first": (users[0] if users else (prompt_values[0] if prompt_values else "")),
            "turns": turns, "path": entry,
        })
    return sessions


def copy_sqlite(source, temporary):
    destination = temporary / source.name
    destination.write_bytes(source.read_bytes())
    for suffix in ("-wal", "-shm"):
        sibling = Path(str(source) + suffix)
        if sibling.is_file():
            Path(str(destination) + suffix).write_bytes(sibling.read_bytes())
    return destination


def sqlite_connection(path):
    return sqlite3.connect("file:" + quote(str(path), safe="/") + "?mode=ro&cache=private", uri=True)


def protobuf_varint(data, offset):
    value = 0
    shift = 0
    while offset < len(data) and shift <= 63:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if not byte & 128:
            return value, offset
        shift += 7
    return None, offset


def protobuf_strings(data, depth=0, output=None):
    output = [] if output is None else output
    offset = 0
    while offset < len(data):
        key, offset = protobuf_varint(data, offset)
        if key is None:
            break
        wire = key & 7
        if wire == 0:
            _, offset = protobuf_varint(data, offset)
        elif wire == 1:
            offset += 8
        elif wire == 5:
            offset += 4
        elif wire == 2:
            length, offset = protobuf_varint(data, offset)
            if length is None or offset + length > len(data):
                break
            value = data[offset:offset + length]
            offset += length
            try:
                text = value.decode("utf-8")
            except UnicodeDecodeError:
                text = ""
            text = strip_leading_nonprintable(text)
            if text and printable_ratio(text) >= 0.85:
                output.append(text)
            if depth < 5 and len(value) > 1:
                protobuf_strings(value, depth + 1, output)
        else:
            break
    return output


def strip_leading_nonprintable(text):
    """Quita únicamente bytes de control iniciales, sin mutilar texto ASCII."""
    index = 0
    while index < len(text):
        character = text[index]
        if ord(character) < 32 and character not in "\n\r\t":
            index += 1
            continue
        break
    return text[index:]


def printable_ratio(text):
    if not text:
        return 0.0
    printable = sum(character.isprintable() or character in "\n\r\t" for character in text)
    return printable / len(text)


def useful_protobuf_text(blob):
    candidates = []
    seen = set()
    for text in protobuf_strings(blob or b""):
        text = strip_leading_nonprintable(text)
        if not text or printable_ratio(text) < 0.85:
            continue
        if text in seen:
            continue
        seen.add(text)
        # Un envoltorio protobuf puede ser mayormente ASCII por contener rutas o
        # UUID, pero sus controles internos no forman parte de un turno humano.
        if any(ord(character) < 32 and character not in "\n\r\t" for character in text):
            continue
        if text.startswith(("{", "[")) or "trajectory_id" in text or "sessionID" in text:
            continue
        candidates.append(text)
    if not candidates:
        return ""
    # Un payload suele mezclar el turno con IDs internos. Los envoltorios
    # protobuf parcialmente legibles pueden incluir una etiqueta de campo
    # imprimible antes del texto, por lo que el texto limpio anidado debe ganar.
    def candidate_score(value):
        identifier_noise = (
            UUID_SHAPE.search(value)
            or LONG_HEX_RUN.search(value)
            or LONG_DECIMAL_RUN.search(value)
            or OPAQUE_TOKEN.search(value)
            or value.startswith(("file://", "http://", "https://", "/"))
        )
        has_internal_space = any(character.isspace() for character in value.strip())
        clean = not any(ord(character) < 32 for character in value)
        return not identifier_noise, has_internal_space, clean, len(value)

    return max(candidates, key=candidate_score)


def agy_summary_map(temporary):
    source = HOME / ".gemini" / "antigravity-cli" / "conversation_summaries.db"
    if not source.is_file():
        return {}
    try:
        copied = copy_sqlite(source, temporary)
        with sqlite_connection(copied) as connection:
            columns = {row[1] for row in connection.execute("PRAGMA table_info(conversation_summaries)")}
            required = {"conversation_id", "title", "preview", "last_modified_time", "workspace_uris"}
            if not required.issubset(columns):
                return {}
            return {
                str(row[0]): {"title": row[1], "preview": row[2], "last": row[3], "workspace": row[4]}
                for row in connection.execute("SELECT conversation_id, title, preview, last_modified_time, workspace_uris FROM conversation_summaries")
            }
    except (OSError, sqlite3.Error) as error:
        warn(f"no se pudo consultar el índice de Antigravity: {error}")
        return {}


def agy_sessions(cwd):
    root = HOME / ".gemini" / "antigravity-cli" / "conversations"
    if not root.is_dir():
        return []
    sessions = []
    with tempfile.TemporaryDirectory(prefix="recover-chat-") as directory:
        temporary = Path(directory)
        summaries = agy_summary_map(temporary)
        for source in root.glob("*.db"):
            try:
                copied = copy_sqlite(source, temporary)
                with sqlite_connection(copied) as connection:
                    tables = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                    if "steps" not in tables:
                        continue
                    rows = list(connection.execute("SELECT idx, step_type, step_payload FROM steps ORDER BY idx"))
            except (OSError, sqlite3.Error) as error:
                warn(f"se omitió conversación Antigravity {source.name}: {error}")
                continue
            session_id = source.stem
            turns = []
            for _, step_type, payload in rows:
                if step_type == 14:
                    add_text_turn(turns, "user", useful_protobuf_text(payload))
                elif step_type == 15:
                    add_text_turn(turns, "assistant", useful_protobuf_text(payload))
                else:
                    turns.append(("tool", 1))
            users = [text for role, text in turns if role == "user"]
            summary = summaries.get(session_id, {})
            fallback_time = iso_mtime(source)
            sessions.append({
                "provider": "agy", "id": session_id, "cwd": "", "started": fallback_time,
                "last": iso_value(summary.get("last"), fallback_time), "count": len(users),
                "kind": "unknown", "first": users[0] if users else str(summary.get("preview") or summary.get("title") or ""),
                "turns": turns, "path": source,
            })
    return sessions


def claude_session(path):
    records = list(read_json_lines(path))
    turns = []
    cwd = ""
    started = iso_mtime(path)
    last = started
    subagent = False
    for record in records:
        if not cwd and record.get("cwd"):
            cwd = str(record["cwd"])
        timestamp = record.get("timestamp")
        if timestamp:
            if started == iso_mtime(path):
                started = iso_value(timestamp, started)
            last = iso_value(timestamp, last)
        subagent = subagent or bool(record.get("isSidechain")) or bool(record.get("agentId"))
        record_type = record.get("type")
        message = record.get("message")
        if record_type not in {"user", "assistant"} or not isinstance(message, dict):
            continue
        role = message.get("role")
        if role not in {"user", "assistant"}:
            continue
        content = message.get("content")
        if isinstance(content, list):
            texts = []
            tool_count = 0
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") in {"text", "input_text", "output_text"}:
                    text = content_text(block)
                    if text:
                        texts.append(text)
                elif role == "assistant":
                    tool_count += 1
            add_text_turn(turns, role, "\n".join(texts))
            if tool_count:
                turns.append(("tool", tool_count))
        else:
            add_text_turn(turns, role, content_text(content))
    users = [text for role, text in turns if role == "user"]
    return {
        "provider": "claude", "id": path.stem, "cwd": cwd, "started": started, "last": last,
        "count": len(users), "kind": "subagent" if subagent else "main", "first": users[0] if users else "",
        "turns": turns, "path": path,
    }


def claude_sessions(cwd):
    root = HOME / ".claude" / "projects"
    if not root.is_dir():
        return []
    flattened = str(cwd).replace("/", "-").replace(".", "-")
    candidates = []
    exact = root / flattened
    if exact.is_dir():
        candidates = list(exact.glob("*.jsonl"))
    else:
        candidates = list(root.glob("*/*.jsonl"))
    sessions = []
    for path in candidates:
        session = claude_session(path)
        if session["cwd"] == str(cwd):
            sessions.append(session)
    return sessions


LOADERS = {"codex": codex_sessions, "grok": grok_sessions, "agy": agy_sessions, "claude": claude_sessions}


def sessions_for(provider, cwd):
    try:
        return LOADERS[provider](cwd)
    except OSError as error:
        warn(f"no se pudo explorar {provider}: {error}")
        return []


def newest(sessions):
    return sorted(sessions, key=lambda item: item["last"], reverse=True)


def has_text_turns(session):
    return any(role in {"user", "assistant"} and str(value).strip() for role, value in session["turns"])


def listed_sessions(provider, cwd, limit):
    return newest(sessions_for(provider, cwd))[:limit]


def command_list(args):
    providers = parse_provider_list(args.provider)
    cwd = Path(args.cwd).expanduser().resolve()
    all_sessions = []
    for provider in providers:
        selected = listed_sessions(provider, cwd, args.limit)
        all_sessions.extend(selected)
    all_sessions = newest(all_sessions)
    if "agy" in providers:
        warn("Antigravity no expone un mapeo fiable por proyecto en este equipo, se muestran conversaciones globales.")
    if not all_sessions:
        print("No se encontraron conversaciones para ese proyecto.", file=sys.stderr)
        return 0
    for item in all_sessions:
        print("\t".join((item["provider"], item["id"], item["last"], str(item["count"]), item["kind"], compact(item["first"], 100))))
    return 0


def latest_eligible_session(provider, sessions):
    eligible = [item for item in sessions if item["kind"] != "subagent" and has_text_turns(item)]
    if provider == "claude":
        cutoff = time.time() - 180
        past_sessions = [item for item in eligible if item["path"].stat().st_mtime <= cutoff]
        if past_sessions:
            eligible = past_sessions
        else:
            by_mtime = sorted(eligible, key=lambda item: item["path"].stat().st_mtime, reverse=True)
            eligible = by_mtime[1:]
    if not eligible:
        raise ValueError(f"no hay una sesión pasada reciente de {provider} para ese proyecto")
    return eligible[0]


def resolve_selector(selector, provider, sessions, indexed_sessions=None):
    """Return a session selected by last, a 1-based listing index, or its ID."""
    if selector == "last":
        return latest_eligible_session(provider, sessions)
    if indexed_sessions is not None and selector.isdigit():
        index = int(selector)
        if 1 <= index <= len(indexed_sessions):
            return indexed_sessions[index - 1]
        raise ValueError(f"el índice {selector} no corresponde a una sesión listada de {provider}")
    selected = next((item for item in sessions if item["id"] == selector), None)
    if selected is None:
        raise ValueError(f"no se encontró la sesión {selector} de {provider} para ese proyecto")
    return selected


def normalized_dump(selected, max_chars):
    header = "\n".join((
        "Proveedor: " + selected["provider"], "Sesión: " + selected["id"],
        "Proyecto: " + (selected["cwd"] or "(no disponible)"), "Inicio: " + selected["started"],
        "Última actividad: " + selected["last"], "",
    ))
    transcript = render_turns(selected["turns"])
    output = header + transcript
    if len(output) > max_chars:
        available = max_chars - len(header)
        if available <= 0:
            tail_size = min(len(transcript), max(0, max_chars))
        else:
            tail_size = min(len(transcript), available)
            for _ in range(2):
                omitted = len(transcript) - tail_size
                marker = f"[TRUNCADO: se omitieron los primeros {omitted} caracteres de la conversación]\n\n"
                tail_size = min(len(transcript), max(0, available - len(marker)))
        omitted = len(transcript) - tail_size
        marker = f"[TRUNCADO: se omitieron los primeros {omitted} caracteres de la conversación]\n\n"
        tail = transcript[-tail_size:] if tail_size else ""
        output = header + marker + tail
    return output


def command_dump(args):
    providers = parse_provider_list(args.provider)
    if len(providers) != 1:
        raise ValueError("dump acepta un solo proveedor")
    provider = providers[0]
    cwd = Path(args.cwd).expanduser().resolve()
    selected = resolve_selector(args.id, provider, newest(sessions_for(provider, cwd)))
    print(normalized_dump(selected, args.max_chars))
    return 0


def dump_header(provider, session_id, project, now=None):
    date = (now or datetime.now(timezone.utc)).astimezone().isoformat(timespec="seconds")
    return "\n".join((
        "# Conversación recuperada", "", f"- Proveedor: {provider}",
        f"- Sesión: {session_id}", f"- Fecha: {date}", f"- Proyecto: {project}",
        "", "---", "",
    ))


def default_save_path(provider, now=None, directory=None):
    timestamp = (now or datetime.now()).strftime("%Y%m%d-%H%M%S")
    return (directory or Path.cwd()) / f"recover-{provider}-{timestamp}.md"


def available_path(path):
    if not path.exists():
        return path
    suffix = 1
    while True:
        candidate = path.with_name(f"{path.stem}-{suffix}{path.suffix}")
        if not candidate.exists():
            return candidate
        suffix += 1


def save_markdown(dump, provider, session_id, project, destination=None, now=None):
    path = Path(destination).expanduser() if destination else default_save_path(provider, now=now)
    path = available_path(path)
    content = dump_header(provider, session_id, project, now=now) + dump + "\n"
    path.write_text(content, encoding="utf-8")
    return path


class ClipboardUnavailable(ValueError):
    pass


def copy_to_clipboard(dump, provider, session_id):
    candidates = (("wl-copy",), ("xclip", "-selection", "clipboard"), ("xsel", "--clipboard", "--input"))
    copied = dump + "\n"
    for command in candidates:
        if shutil.which(command[0]) is None:
            continue
        try:
            result = subprocess.run(command, input=copied, text=True, check=False)
        except OSError as error:
            raise ClipboardUnavailable(f"no se pudo ejecutar {command[0]}: {error}") from error
        if result.returncode == 0:
            print(f"Copiados {len(copied)} caracteres al portapapeles de {provider}, sesión {session_id}.")
            return command[0]
        raise ClipboardUnavailable(f"{command[0]} no pudo copiar al portapapeles")
    raise ClipboardUnavailable("no se encontró wl-copy, xclip ni xsel para copiar al portapapeles")


def destination_menu(input_fn=input, output=None):
    output = output or sys.stderr
    print("1) Copiar al portapapeles", file=output)
    print("2) Guardar como Markdown", file=output)
    print("3) Mostrar aquí", file=output)
    while True:
        print("Destino [1-3]: ", end="", file=output, flush=True)
        answer = input_fn()
        if answer == "":
            return "stdout"
        answer = answer.strip()
        if answer == "1":
            return "copy"
        if answer == "2":
            return "save"
        if answer == "3":
            return "stdout"
        print("Opción inválida. Elige 1, 2 o 3.", file=output)


def positional_destination(args):
    if args.copy:
        return "copy"
    if args.save is not None:
        return "save"
    if args.stdout:
        return "stdout"
    return None


def export_positional_dump(args, selected, dump):
    destination = positional_destination(args)
    while destination is None or destination == "copy":
        if destination is None:
            destination = destination_menu()
        if destination == "copy":
            try:
                copy_to_clipboard(dump, selected["provider"], selected["id"])
                return 0
            except ClipboardUnavailable as error:
                if positional_destination(args) == "copy":
                    raise
                print(f"No se pudo copiar: {error}. Elige Guardar como Markdown o Mostrar aquí.", file=sys.stderr)
                destination = None
    if destination == "save":
        supplied = args.save
        if supplied is None:
            default = default_save_path(selected["provider"])
            print(f"Ruta de archivo [{default}]: ", end="", file=sys.stderr, flush=True)
            supplied = input().strip() or str(default)
        path = save_markdown(dump, selected["provider"], selected["id"], selected["cwd"] or "(no disponible)", supplied)
        print(f"Guardado en {path}.")
        return 0
    print(dump)
    return 0


def build_help_parser():
    return argparse.ArgumentParser(
        prog="ai recover",
        usage="ai recover [-h] <proveedor> [selector] [opciones]\n       ai recover {list,dump} ...",
        description="Recupera conversaciones locales por proyecto.",
        epilog="""ejemplos:
  ai recover claude
  ai recover claude last
  ai recover codex 3 --save
  ai recover list --provider codex
  ai recover dump --provider antigravity --id <ID> --max-chars 50000

el proyecto es el directorio actual salvo que uses --cwd.
sin destino y en una terminal, puedes copiar, guardar o mostrar la conversación.
la salida con pipe o redirección es el dump normal, sin menú.""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )


def build_legacy_parser():
    parser = build_help_parser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    listing = subparsers.add_parser("list", help="lista sesiones recientes")
    listing.add_argument("--provider", required=True, help="codex, grok, agy, antigravity o claude")
    listing.add_argument("--cwd", default=".", help="proyecto, por defecto el directorio actual")
    listing.add_argument("--limit", type=int, default=10, help="máximo por proveedor, por defecto 10")
    dumping = subparsers.add_parser("dump", help="muestra una conversación normalizada")
    dumping.add_argument("--provider", required=True, help="un proveedor")
    dumping.add_argument("--id", required=True, help="identificador de sesión o last")
    dumping.add_argument("--cwd", default=".", help="proyecto, por defecto el directorio actual")
    dumping.add_argument("--max-chars", type=int, default=100000, help="máximo de caracteres, por defecto 100000")
    return parser


def build_positional_parser():
    parser = argparse.ArgumentParser(prog="ai recover", description="Recupera conversaciones locales por proyecto.")
    parser.add_argument("provider", help="codex, grok, agy, antigravity o claude")
    parser.add_argument("selector", nargs="?", help="last, índice de la lista o identificador de sesión")
    parser.add_argument("--cwd", default=".", help="proyecto, por defecto el directorio actual")
    parser.add_argument("--limit", type=int, default=10, help="máximo de sesiones listadas, por defecto 10")
    parser.add_argument("--max-chars", type=int, default=100000, help="máximo de caracteres, por defecto 100000")
    destinations = parser.add_mutually_exclusive_group()
    destinations.add_argument("--copy", action="store_true", help="copia el dump al portapapeles")
    destinations.add_argument("--save", nargs="?", const="", default=None, metavar="PATH", help="guarda Markdown, con ruta opcional")
    destinations.add_argument("--stdout", action="store_true", help="muestra el dump en stdout")
    return parser


def command_positional(args):
    providers = parse_provider_list(args.provider)
    if len(providers) != 1:
        raise ValueError("la sintaxis posicional acepta un solo proveedor")
    provider = providers[0]
    cwd = Path(args.cwd).expanduser().resolve()
    sessions = newest(sessions_for(provider, cwd))
    if args.selector is None:
        selected = sessions[:args.limit]
        if provider == "agy":
            warn("Antigravity no expone un mapeo fiable por proyecto en este equipo, se muestran conversaciones globales.")
        if not selected:
            print("No se encontraron conversaciones para ese proyecto.", file=sys.stderr)
            return 0
        for index, item in enumerate(selected, start=1):
            print("\t".join((str(index), item["provider"], item["id"], item["last"], str(item["count"]), item["kind"], compact(item["first"], 100))))
        return 0
    indexed = sessions[:args.limit]
    selected = resolve_selector(args.selector, provider, sessions, indexed)
    dump = normalized_dump(selected, args.max_chars)
    if positional_destination(args) is None and not sys.stdout.isatty():
        print(dump)
        return 0
    return export_positional_dump(args, selected, dump)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] in {"-h", "--help"}:
        build_help_parser().parse_args(argv)
        return 0
    if argv[0] in {"list", "dump"}:
        parser = build_legacy_parser()
        args = parser.parse_args(argv)
        if getattr(args, "limit", 1) < 1 or getattr(args, "max_chars", 1) < 1:
            parser.error("--limit y --max-chars deben ser mayores que cero")
        command = command_list if args.command == "list" else command_dump
    else:
        parser = build_positional_parser()
        args = parser.parse_args(argv)
        if args.limit < 1 or args.max_chars < 1:
            parser.error("--limit y --max-chars deben ser mayores que cero")
        command = command_positional
    try:
        return command(args)
    except ValueError as error:
        print("Error de uso: " + str(error), file=sys.stderr)
        return 2
    except Exception as error:
        print("Error inesperado: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
