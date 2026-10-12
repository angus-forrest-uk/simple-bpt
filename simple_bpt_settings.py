# Headless simple-bpt: import BPT's stock settings, then relax
# ALLOWED_HOSTS. Upstream hardcodes ['127.0.0.1'], so the server 400s any
# request whose Host header is not loopback -- e.g. when BPT_BIND points at
# a tailscale or LAN address. BPT has no authentication either way; the
# bind address is the real access control. inject-settings.py puts this
# file inside the zip appended to rti.linux, and bin/simple-bpt points
# DJANGO_SETTINGS_MODULE at it.
from mysite.settings import *
ALLOWED_HOSTS = ['*']
