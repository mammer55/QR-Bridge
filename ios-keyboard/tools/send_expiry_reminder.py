#!/usr/bin/env python3
"""
Expiry clock for the ClipKeyboard app.

Apps signed with a free Apple ID stop working about 7 days after install. This
script is run daily by a launchd job. When the current install is 5 or more days
old, it emails a reminder (once per day) with a ready to paste prompt that tells
a fresh Claude Code session exactly how to reinstall the app.

Secrets live in ~/.clipkeyboard/notify_config.json (never in the repo):
    {
        "sender":       "you@gmail.com",
        "app_password": "xxxx xxxx xxxx xxxx",
        "recipient":    "you@wherever.com"
    }
"""
import json
import os
import smtplib
import ssl
import sys
import time
from datetime import date
from email.message import EmailMessage

STATE = os.path.expanduser("~/.clipkeyboard")
CONFIG = os.path.join(STATE, "notify_config.json")
LAST_INSTALL = os.path.join(STATE, "last_install")
LAST_REMINDED = os.path.join(STATE, "last_reminded")

REMIND_AFTER_DAYS = 5          # start reminding at day 5 (buffer before day 7)
REINSTALL_SCRIPT = "/Users/mustafaalbaree/Code/qr-bridge/ios-keyboard/tools/reinstall_clipkeyboard.sh"

CLAUDE_PROMPT = f"""Reinstall my ClipKeyboard iPhone app. The free Apple ID provisioning is expiring. My iPhone is plugged in and unlocked. Please:
1. Run: bash {REINSTALL_SCRIPT}
2. If it reports the device was not found, tell me to unlock the phone and plug it in, then run it again.
3. If signing fails because there is no team, tell me to open Xcode once and sign in with my Apple ID under Settings then Accounts, then run it again.
Report the result when done."""


def read_text(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


def main():
    install = read_text(LAST_INSTALL)
    if not install:
        print("No install timestamp yet; nothing to do.")
        return

    age_days = (time.time() - int(install)) / 86400
    if age_days < REMIND_AFTER_DAYS:
        print(f"Install is {age_days:.1f} days old; too early to remind.")
        return

    today = date.today().isoformat()
    if read_text(LAST_REMINDED) == today:
        print("Already reminded today.")
        return

    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
    except FileNotFoundError:
        print(f"No config at {CONFIG}; cannot send email.")
        sys.exit(1)

    days_left = max(0, 7 - int(age_days))
    msg = EmailMessage()
    msg["Subject"] = f"ClipKeyboard expires in about {days_left} day(s). Reinstall it."
    msg["From"] = cfg["sender"]
    msg["To"] = cfg["recipient"]
    msg.set_content(
        "Your ClipKeyboard app is about to stop working (free Apple ID lasts 7 days).\n\n"
        "Plug your iPhone into the Mac, unlock it, open Claude Code in the project, "
        "and paste this prompt:\n\n"
        "==================================================\n"
        f"{CLAUDE_PROMPT}\n"
        "==================================================\n\n"
        "That will rebuild and reinstall the app and reset this reminder.\n"
    )

    ctx = ssl.create_default_context()
    with smtplib.SMTP_SSL("smtp.gmail.com", 465, context=ctx) as s:
        s.login(cfg["sender"], cfg["app_password"])
        s.send_message(msg)

    with open(LAST_REMINDED, "w") as f:
        f.write(today)
    print(f"Reminder sent to {cfg['recipient']} ({age_days:.1f} days old).")


if __name__ == "__main__":
    main()
