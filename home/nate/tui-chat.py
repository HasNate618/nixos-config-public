#!/usr/bin/env python3
"""
tui-chat — minimal AI chat client via bifrost
"""
import argparse, json, re, signal, sys, time, threading, shutil, select, tty, termios

# ── ANSI ──────────────────────────────────────────────────────
CLEAR_LINE  = "\033[2K"
HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
RESET  = "\033[0m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
CYAN   = "\033[36m"
GREEN  = "\033[32m"
RED    = "\033[31m"

BRAILLE = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
SPINNER_DELAY = 0.08

INDENT = ""
GUTTER  = f"{DIM}│{RESET} "
PROMPT = f" {GREEN}→{RESET}  "

SYSTEM_PROMPT = (
    "Be concise. Use plain text only — NO markdown, NO tables, NO code fences, "
    "NO horizontal rules (---), NO headers (#). Use dashes for bullet points "
    "(- item). Keep responses short and direct."
)


def fmt_display(text: str, at_line_start: bool) -> str:
    """Clean and format a chunk of streaming text for terminal display."""
    # Strip noise
    text = text.replace("`", "")
    text = text.replace("**", "").replace("__", "")

    # Strip horizontal rules (lines that are just ---, ***, etc.)
    if at_line_start:
        text = re.sub(r"^[-*_]{3,}\s*$", "", text)

    # Strip code fence lines (``` or ```lang)
    if at_line_start:
        text = re.sub(r"^```\w*\s*$", "", text)

    # Strip table rows (lines starting/ending with |)
    if at_line_start and "|" in text:
        text = re.sub(r"^\|.+\|$", "", text)

    # Strip checklist markers (- [ ] or - [x])
    text = text.replace("[ ]", "").replace("[x]", "")

    # Bold # headers
    if at_line_start and text.startswith("#"):
        stripped = re.sub(r"^#+\s*", "", text)
        if stripped:
            text = f"{BOLD}{stripped}{RESET}"

    return text


class Spinner:
    """Background spinner that runs until stopped."""
    def __init__(self):
        self._running = False
        self._thread = None

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._spin, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=0.5)

    def _spin(self):
        i = 0
        while self._running:
            s = BRAILLE[i % len(BRAILLE)]
            sys.stdout.write(f"\r{CLEAR_LINE}{GUTTER}{DIM}{s}{RESET}")
            sys.stdout.flush()
            i += 1
            time.sleep(SPINNER_DELAY)


def stream_response(resp, content_out: list, spinner: Spinner):
    """Stream AI response with manual line wrapping for gutter alignment."""
    first_token = False
    content = ""
    at_line_start = True

    tw = shutil.get_terminal_size().columns
    gutter_w = 2  # "│ "
    max_col = max(tw - 1, 40)
    col = gutter_w
    word_buf = ""  # buffer word across SSE chunks

    def _flush_word():
        nonlocal col, word_buf
        if not word_buf:
            return
        if col + len(word_buf) > max_col and col > gutter_w:
            sys.stdout.write("\n" + GUTTER)
            col = gutter_w
        sys.stdout.write(word_buf)
        col += len(word_buf)
        word_buf = ""

    def _write_ch(ch):
        nonlocal col, word_buf
        if ch in (" ", "\n"):
            _flush_word()
            if ch == "\n":
                sys.stdout.write(ch)
                sys.stdout.write(GUTTER)
                col = gutter_w
            else:
                if col >= max_col:
                    sys.stdout.write("\n" + GUTTER)
                    col = gutter_w
                sys.stdout.write(ch)
                col += 1
        else:
            word_buf += ch

    print(HIDE_CURSOR, end="", flush=True)

    for line_bytes in resp:
        line = line_bytes.decode("utf-8", errors="replace").strip()
        if not line.startswith("data: "):
            continue
        payload = line[6:]
        if payload == "[DONE]":
            break
        try:
            chunk = json.loads(payload)
        except json.JSONDecodeError:
            continue

        delta = chunk.get("choices", [{}])[0].get("delta", {})
        reasoning = delta.get("reasoning_content") or delta.get("reasoning")
        text = delta.get("content")

        if reasoning or text:
            if not first_token:
                spinner.stop()
                sys.stdout.write(f"\r{CLEAR_LINE}{GUTTER}")
                first_token = True
                col = gutter_w

        if reasoning:
            continue

        if text:
            content += text
            display = fmt_display(text, at_line_start)

            for ch in display:
                _write_ch(ch)

            sys.stdout.flush()
            at_line_start = text.endswith("\n") if text else at_line_start

    # Flush any remaining word
    _flush_word()
    print(SHOW_CURSOR, end="")
    content_out[0] = content
    return first_token


def paste_aware_input(prompt: str) -> str:
    """Read a line with bracketed paste support. Falls back to input() if not a TTY."""
    if not sys.stdin.isatty():
        return input(prompt)

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        # Enable bracketed paste mode
        sys.stdout.write("\033[?2004h")
        sys.stdout.write(prompt)
        sys.stdout.flush()

        buf = ""
        paste_mode = False
        paste_buf = ""
        esc_buf = ""

        while True:
            ch = sys.stdin.read(1)
            if not ch:
                break

            # ESC sequence detection
            if ch == "\x1b" and not esc_buf:
                esc_buf = ch
                continue
            if esc_buf:
                esc_buf += ch
                # Bracketed paste start: \033[200~
                if esc_buf == "\x1b[200~":
                    paste_mode = True
                    paste_buf = ""
                    esc_buf = ""
                    continue
                # Bracketed paste end: \033[201~
                if esc_buf == "\x1b[201~":
                    paste_mode = False
                    esc_buf = ""
                    continue
                # Other escape sequences — treat as literal if incomplete
                if len(esc_buf) >= 6:
                    buf += esc_buf
                    esc_buf = ""
                continue

            if paste_mode:
                paste_buf += ch
                # Echo the character
                sys.stdout.write(ch)
                sys.stdout.flush()
                continue

            if ch == "\r" or ch == "\n":
                # Enter pressed
                if paste_buf:
                    # Just finished a paste — return the paste content
                    result = paste_buf.rstrip("\n\r")
                else:
                    result = buf.rstrip("\n\r")
                sys.stdout.write("\r\n")
                sys.stdout.flush()
                return result
            elif ch == "\x7f":  # Backspace
                if buf:
                    buf = buf[:-1]
                    sys.stdout.write("\b \b")
                    sys.stdout.flush()
            elif ch == "\x03":  # Ctrl-C
                sys.stdout.write("^C\r\n")
                sys.stdout.flush()
                raise KeyboardInterrupt()
            elif ch == "\x04":  # Ctrl-D
                if not buf:
                    sys.stdout.write("\r\n")
                    sys.stdout.flush()
                    raise EOFError()
            elif ord(ch) >= 32 or ch == "\t":
                buf += ch
                sys.stdout.write(ch)
                sys.stdout.flush()
    finally:
        # Disable bracketed paste, restore terminal
        sys.stdout.write("\033[?2004l")
        sys.stdout.flush()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="opencode-zen/north-mini-code-free")
    parser.add_argument("--endpoint", default="http://bifrost.home.lab/v1/chat/completions")
    args = parser.parse_args()

    print(f"\n{BOLD}{CYAN}  tui-chat{RESET}  {DIM}{args.model}{RESET}\n")

    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    import urllib.request
    import urllib.error

    while True:
        try:
            user_input = paste_aware_input(PROMPT)
        except (KeyboardInterrupt, EOFError):
            print(f"\n{DIM}bye{RESET}\n")
            break

        user_input = user_input.strip()
        if not user_input:
            continue

        if user_input == "/exit":
            break
        if user_input == "/help":
            print(f"  {DIM}/exit /clear /model NAME /last{RESET}\n")
            continue
        if user_input.startswith("/model "):
            args.model = user_input[7:].strip()
            print(f"  {DIM}→ {args.model}{RESET}\n")
            continue
        if user_input == "/clear":
            messages = [{"role": "system", "content": SYSTEM_PROMPT}]
            print(f"  {DIM}Cleared{RESET}\n")
            continue
        if user_input == "/last":
            ai = [m for m in messages if m["role"] == "assistant"]
            if ai:
                # Post-process stored content
                text = ai[-1]["content"]
                text = text.replace("`", "").replace("**", "").replace("__", "")
                text = re.sub(r"^#{1,6}\s+", "", text, flags=re.MULTILINE)
                text = re.sub(r"^[-*_]{3,}\s*$", "", text, flags=re.MULTILINE)
                text = re.sub(r"^```\w*\s*$", "", text, flags=re.MULTILINE)
                for line in text.split("\n"):
                    print(f"{GUTTER}{line}")
            else:
                print(f"  {DIM}No response yet{RESET}")
            print()
            continue

        messages.append({"role": "user", "content": user_input})

        body = {
            "model": args.model,
            "messages": messages,
            "stream": True,
            "temperature": 0.3,
            "max_tokens": 2048,
        }
        # Disable reasoning for models that support it (north, mimo)
        if any(m in args.model for m in ("north", "mimo")):
            body["reasoning"] = {"effort": "none"}

        req = urllib.request.Request(
            args.endpoint,
            json.dumps(body).encode(),
            headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
        )

        t_start = time.time()

        # Start spinner immediately — covers connection + TTFT
        spinner = Spinner()
        spinner.start()

        try:
            resp = urllib.request.urlopen(req, timeout=120)
        except Exception as e:
            spinner.stop()
            print(f"\r{CLEAR_LINE}{GUTTER}{RED}✗ {e}{RESET}\n")
            messages.pop()
            continue

        content_ref = [""]
        got_content = stream_response(resp, content_ref, spinner)
        spinner.stop()
        content = content_ref[0]
        elapsed = time.time() - t_start

        if got_content:
            print()
            ts = f"{elapsed:.1f}s" if elapsed >= 1.0 else f"{elapsed*1000:.0f}ms"
            print(f"{GUTTER}{DIM}{ts}{RESET}")
        else:
            print(f"\r{CLEAR_LINE}{GUTTER}{DIM}[no content, {elapsed:.1f}s]{RESET}")

        messages.append({"role": "assistant", "content": content})
        print()


if __name__ == "__main__":
    def _restore(sig=None, frame=None):
        print(SHOW_CURSOR, end="", flush=True)
        if sig:
            sys.exit(0)
    signal.signal(signal.SIGINT, _restore)
    signal.signal(signal.SIGTERM, _restore)
    try:
        main()
    finally:
        print(SHOW_CURSOR, end="", flush=True)
