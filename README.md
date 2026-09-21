# Lock In Bud

An AI-powered daily planner for iOS. It shows the events already in your Apple Calendar, then recommends which tasks you can realistically complete each day based on your free time, task durations, priorities, and due dates — no forced time slots, just smart guidance.

- **iOS app** — SwiftUI, offline-first with local storage and background sync
- **Backend API** — Python FastAPI + PostgreSQL, AI scheduling via Google Gemini, deployed on Vercel

## Features

- **Calendar view** — displays only the Apple Calendars you've selected (Settings → Calendars), with day / week / month modes
- **Daily recommendations** — below each day's calendar events, see the tasks you should be able to complete that day, computed from free time between events, working hours, estimated duration, priority, and deadlines, with the recommended time block shown when one fits
- **Quick add** — type a natural-language task ("catch up on lectures by tomorrow 9pm, should take an hour") on the Today screen; Gemini parses the deadline, duration, and priority and creates the task (`POST /api/v1/tasks/parse`, with a heuristic offline fallback)
- **Description-aware breakdown** — tasks with structured descriptions ("1. … 2. …" or sentences) are automatically split into named parts; long tasks are chunked into ≤90-minute pieces spread across days
- **Overload detection** — anything that doesn't fit the selected window is surfaced in a separate "Doesn't fit this window" section
- **Tasks** — titles, notes, priorities, statuses, deadlines, categories, repeating weekday schedules, estimated durations, plus a per-task checklist (inline-editable from the task detail screen, persisted as JSON)
- **Task progress** — percent complete computed from checked-off blocks
- **Today planner** — shows today's priorities, what's up next, a quick-add field, and day progress
- **Missed-deadline recovery** — detects overdue tasks, lets you reschedule them into the remaining time, records why you missed them, and surfaces patterns in "Why did I miss tasks?"
- **Daily summary** — hours worked, schedule adherence, tasks completed/remaining/rescheduled, and what was missed today
- **Habits** — build and track daily habits
- **Focus** — start/stop a focus timer (wall-clock based, so it survives app backgrounding and relaunches), then review your sessions as a chart across **1D / 3D / 5D / 1W / 2W / 4W** ranges
- **Reflections** — write a short daily reflection and get an AI-powered analysis of your focus trends
- **Notifications** — local + push (APNs) reminders
- **Offline-first iOS** — local store, connectivity monitoring, and a sync manager that reconciles changes when you're back online

## Notifications

### Local (iOS) reminders — no server required

On-device notifications are scheduled whenever the task list refreshes or notification settings change, provided the user granted permission (onboarding or Settings → Notifications). Reminders whose trigger time has already passed are skipped.

| When | Copy | Toggle |
| --- | --- | --- |
| 15 minutes before a task's deadline | "… is due in 15 minutes." | `fifteen_minute_reminder_enabled` |
| `deadline_reminder_lead_hours` (default 24h) before the deadline | "… is due in N h." | `deadline_reminder_enabled` |
| 1 hour before the deadline (only when lead > 1h) | "… is due in 1 hour." | `deadline_reminder_enabled` |
| At the earliest task's deadline | "… is due now." | `deadline_reminder_enabled` |
| 30 minutes before the end of your configured work hours (skipped if you already reflected today) | "The day is wrapping up — take a minute to reflect…" | always on |
| 30 minutes before any selected Apple Calendar event (next 48h, all-day events skipped) | "… starts at …." | always on |
| At the start of an accepted schedule block with no focus timer running | "… is starting now — start your focus timer…" | always on (auto-off during a focus session) |
| Top of every hour during work hours | "How's your to-do list? Make progress…" | always on |

### Push (server → APNs)

The backend can push reminders outside the app. Delivery requires APNs credentials (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_KEY_PATH`, `APNS_ENVIRONMENT`) and the `h2` + `PyJWT` packages; without them sends are logged, not delivered.

| Job | When | Toggle |
| --- | --- | --- |
| Morning briefing | At the user's configured local time (default 07:30), summarizing today's tasks, high-priority count, scheduled focus time, and deadlines | `morning_briefing_enabled` |
| Deadline reminder | When a task's deadline is within `deadline_reminder_lead_hours` (default 24h) | `deadline_reminder_enabled` |
| Overdue alert | Within 24h of a task becoming overdue | `overdue_alerts_enabled` |
| Reschedule alert | When a schedule generation can't fit all tasks | `reschedule_alerts_enabled` |

> **Note:** the scheduled jobs (morning briefing, deadline reminders, overdue alerts) are exposed via `NotificationService.run_all_jobs()` for a cron trigger but are not invoked automatically by the deployed app yet. The reschedule alert fires inline from `POST /api/v1/schedule/generate`.

## Architecture

```
.
├── backend/                  FastAPI service
│   ├── api/index.py          Vercel serverless entry (runs DB migrations on cold start)
│   ├── app/
│   │   ├── api/              Routers + auth dependency
│   │   ├── core/             App settings (env-driven)
│   │   ├── db/               SQLAlchemy session + base
│   │   ├── models/           SQLAlchemy models (User, Task, CalendarBlock, TaskMiss, ...)
│   │   ├── repositories/     Data access layer
│   │   ├── schemas/          Pydantic request/response schemas
│   │   ├── security/         JWT access + refresh tokens
│   │   ├── services/         Business logic, AI scheduling, Google + APNs clients
│   ├── alembic/              Database migrations
│   ├── tests/                pytest suite
│   └── docker-compose.yml    Local PostgreSQL
├── ios/MyApp/                SwiftUI app
│   ├── App/                  Entry point, app delegate
│   ├── Models/               Codable models mirroring the API
│   ├── Networking/           API client + endpoints
│   ├── Services/             Auth, tasks, schedule, planner, sync, offline store
│   ├── Views/                SwiftUI screens
│   └── Utilities/            Shared helpers
├── .github/workflows/ci.yml  Backend CI (migrations + tests against Postgres)
└── docs/                     PRD + system architecture
```

### API

All endpoints are under `/api/v1`:

| Prefix | Description |
| --- | --- |
| `/auth` | Google sign-in, dev login, token refresh, `/me` |
| `/tasks` | CRUD, overdue list, snooze, reschedule, `POST /parse` (Gemini natural-language quick add) |
| `/calendar` | Time blocks, block completion (`/blocks/{id}/complete`, `/reopen`) |
| `/schedule` | AI schedule generation + per-item accept/reject/redo (legacy flow) |
| `/recommendations` | **New:** `POST /daily` per-day task recommendations from free time/priority/deadlines; `POST /breakdown/{task_id}` splits a task description into parts |
| `/preferences` | Scheduling preferences |
| `/planner` | Today view, daily summary (incl. `missed_today`), `missed-reasons` |
| `/devices`, `/notifications` | Push notification device tokens + preferences |
| `/habits` | Habit tracking |
| `/focus` | Focus timer sessions + range-aware summary stats |
| `/reflections` | Daily reflections + AI analysis |

Interactive docs are available at `/docs` when running locally.

### Database

PostgreSQL with SQLAlchemy 2.0 and Alembic for migrations. In addition to the core tables, this update adds:

- `task_breakdowns` — stores description-derived subtask parts per task
- `daily_task_recommendations` — persisted daily recommendation rows (per user/date/task/subtask)
- `tasks.is_broken_down` — flag marking tasks whose description has been analyzed into parts
- `tasks.checklist` — JSON list of `{"text", "done"}` items per task (inline-edited in the app)
- `focus_sessions` — focus timer sessions (start/end, billed minutes)
- `reflections` — daily reflections plus AI-generated analysis

## Getting Started

### Backend

1. **Start PostgreSQL**

   ```sh
   cd backend
   docker compose up -d
   ```

2. **Configure environment** — copy the settings from the repo's environment template into `backend/.env` (or export them). Required values:

   | Variable | Purpose |
   | --- | --- |
   | `DATABASE_URL` | PostgreSQL connection string (e.g. `postgresql+psycopg://user:pass@localhost:5432/myapp_db`) |
   | `JWT_SECRET` | Secret used to sign access/refresh tokens |
   | `GEMINI_API_KEY` | Google Gemini key for AI schedule generation |
   | `GOOGLE_CLIENT_ID` | OAuth client ID for Google sign-in |
   | `ENABLE_DEV_AUTH` | Set `true` to allow the dev-only sign-in endpoint |
   | `APNS_*` | Push notification credentials (key id, team id, bundle id, key path, environment) |

3. **Run**

   ```sh
   python -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   alembic upgrade head
   uvicorn app.main:app --reload
   ```

4. **Test**

   ```sh
   python -m pytest tests -q
   ```

   CI runs the same suite against a fresh PostgreSQL instance on every push (`.github/workflows/ci.yml`).

### iOS

Open `ios/MyApp.xcodeproj` in Xcode, select the **MyApp** scheme, and run on a simulator or device.

- The API base URL is read from the `API_BASE_URL` Info.plist key (fallback: `http://localhost:8000`). Point it at the deployed API to test against production.
- The project uses `PBXFileSystemSynchronizedRootGroup`, so new Swift files under `ios/MyApp/` are picked up automatically — no `.pbxproj` edits needed.

## Deployment

The backend deploys to **Vercel** (project `lock-in-bud`). The project is Git-connected: every push to `main` auto-deploys production with the backend root at `backend/`.

- `backend/api/index.py` runs `alembic upgrade head` on cold start, so migrations apply automatically before requests are served.
- Live URL: `https://lock-in-bud.vercel.app`
