# My Tasks

A fast, private to-do app built with Flutter. It runs on **Android, iOS, web, Windows, macOS and Linux**, and stores everything on the device: no account, no server.

## Features

- **Smart views:** Today (includes overdue tasks), Upcoming, Important, All tasks, Completed
- **Lists:** create your own lists with an emoji and colour; rename or delete them
- **Tasks:** title, notes, due date and time, priority (none/low/medium/high), star for Important, steps (subtasks)
- **Reminders:** at the due time or 5 min, 15 min, 30 min, 1 hour or 1 day before
- **Repeating tasks:** daily, weekdays, weekly, monthly, yearly. Completing one creates the next.
- **Quick add bar** with due date, time, priority and list, plus a full editor
- **Search** across titles, notes, steps and list names
- **Sort** by your own order (drag to reorder), due date, priority, newest or A–Z
- **Filters:** All / Active / Done, with live stats (active, due today, overdue, % done)
- **Select several tasks** to complete, delete, re-prioritise, reschedule or move them all at once
- **Swipe** right to complete, left to delete, with **Undo** for every change
- **Light, dark and system themes** and 8 accent colours
- **Backup and restore** through the clipboard; tasks from the old version are imported automatically
- **Responsive layout:** drawer on phones, permanent sidebar on tablets and desktop
- **Keyboard shortcuts:** Ctrl/⌘+N new task, Ctrl/⌘+F search, Esc cancel

### How reminders work on each platform

| Platform | Reminders |
| --- | --- |
| Android, iOS, macOS | Scheduled with the system, so they arrive even when the app is closed |
| Windows, Linux | System notification while the app is open or minimised |
| Web | Browser notification while the tab is open (after you allow notifications) |

Every platform also shows a reminder banner inside the app.

## First-time setup (Windows)

Needs Flutter 3.38.1 or newer. From the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

The script removes the old Supabase/Firebase code, recreates the platform folders for your Flutter version, configures Android notifications, generates app icons, then runs the analyzer and tests.

## Run

```powershell
flutter run -d windows   # Windows
flutter run -d chrome    # Web
flutter run              # Android phone or emulator
```

On a Mac you can also run `flutter run -d macos` and `flutter run -d ios`.

## Build and deploy

Every push to GitHub:

- **Build all platforms** (`.github/workflows/ci.yml`) analyzes, tests and builds Android, web, Windows, Linux, macOS and iOS. Download the Android APK and the Windows and Linux apps from the run's *Artifacts*.
- **Deploy web app** (`.github/workflows/deploy.yml`) publishes the web version to GitHub Pages from the `gh-pages` branch.

## Project structure

```
lib/
  main.dart                     start-up
  src/app.dart                  MaterialApp, theme, StoreScope
  src/models/                   Task, TaskList, AppSettings
  src/state/task_store.dart     all app state and actions (undo, repeat, backup)
  src/data/storage.dart         on-device storage
  src/services/                 notifications (native, web)
  src/ui/                       screens and widgets
test/widget_test.dart           unit and widget tests
```
