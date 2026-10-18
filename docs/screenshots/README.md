# PYP UI Showcase & Screenshot Capture Guide

This directory holds visual assets, emulator screenshots, and demonstration GIFs for the **PYP — Pick Your Photographer** marketplace.

---

## Required Showcase Screenshots

When capturing screenshots on an Android emulator or physical device, use consistent dimensions (e.g. 1080x2400 / Pixel 7 aspect ratio) and light/dark theme consistency:

| Image File Name | Screen / Feature | Description |
| :--- | :--- | :--- |
| `01_auth_screen.png` | **Authentication Screen** | Branded sign-in & sign-up card with PYP logo and password toggle. |
| `02_discover_marketplace.png` | **Discover Screen** | Hero section, search input, category chips, and photographer cards. |
| `03_photographer_profile.png` | **Photographer Profile** | Public details, private contact info, and portfolio showcase manager. |
| `04_booking_dialog.png` | **Booking Reservation Modal** | Date picker, event details, and 5% fee breakdown summary. |
| `05_bookings_list.png` | **My Bookings Screen** | Booking cards with readable status badges and action buttons. |
| `06_invoice_pdf.png` | **Invoice PDF Preview** | Authoritative A4 invoice / receipt modal with print & export actions. |
| `07_realtime_chat.png` | **Realtime Session Chat** | Participant-only chat unlocked strictly for confirmed bookings. |
| `08_admin_dashboard.png` | **Admin Governance** | Realtime platform statistics, photographer moderation, and client directory. |
| `booking_flow_demo.gif` | **Booking & Payment Demo** | Short 10-15s screen recording showing request creation, payment, and chat unlock. |

---

## How to Capture Android Emulator Screenshots via ADB

```bash
# Capture screenshot from connected Android emulator
adb shell screencap -p /sdcard/screenshot.png

# Pull image to local repository
adb pull /sdcard/screenshot.png docs/screenshots/01_auth_screen.png

# Clean up temporary device file
adb shell rm /sdcard/screenshot.png
```

---

## How to Record Demo GIF via ScreenToGif or FFmpeg

```bash
# Record MP4 screen recording via ADB (max 3 mins)
adb shell screenrecord /sdcard/demo.mp4

# Pull MP4 recording to local host
adb pull /sdcard/demo.mp4 docs/screenshots/demo.mp4

# Convert MP4 to optimized GIF using FFmpeg
ffmpeg -i docs/screenshots/demo.mp4 -vf "fps=15,scale=480:-1:flags=lanczos" -c:v gif docs/screenshots/booking_flow_demo.gif
```
