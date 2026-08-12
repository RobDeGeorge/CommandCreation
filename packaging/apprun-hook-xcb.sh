# Sourced by the AppImage's AppRun, from AppDir/apprun-hooks/.
#
# The AppImage carries the xcb platform plugin and not the Wayland one. That is
# deliberate: a bundled Wayland stack is not one plugin but a client library and
# three more plugin directories, and the EGL half of it has to agree with the
# mesa on the machine it lands on — which is exactly the assumption an AppImage
# exists to avoid. Bundling it was tried and failed on the first Wayland
# session it met, on "Failed to load client buffer integration".
#
# Qt does not fall back. On a Wayland session it selects the Wayland plugin,
# does not find it, and aborts before anything is drawn — no window, and a
# message only if the app was started from a terminal. So the choice is made
# here instead: on Wayland, ask for xcb, which XWayland serves and which every
# Wayland desktop ships.
#
# Only when nothing has been asked for already. Someone who sets QT_QPA_PLATFORM
# themselves — to run it under a nested compositor, or to test the fallback —
# means it, and this must not overrule them.
if [ -z "${QT_QPA_PLATFORM:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
    export QT_QPA_PLATFORM=xcb
fi
