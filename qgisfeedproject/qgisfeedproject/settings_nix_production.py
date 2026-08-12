"""Production settings for the NixOS deployment.

Equivalent to settings_docker_production.py, but every path and secret is taken
from the environment instead of being tied to the /shared-volume layout of the
docker compose stack. The systemd unit in nix/nixos-module.nix supplies these
via its StateDirectory and an EnvironmentFile.

PostgreSQL and Metabase are provided by the surrounding infrastructure, so this
module configures the Django application only.
"""

import os

from .settings import *  # noqa: F401,F403


def _required(name):
    """Read a mandatory setting, failing loudly rather than falling back."""
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"{name} must be set in production. The systemd unit reads it from "
            f"services.qgisfeed.environmentFile."
        )
    return value


DEBUG = False

# GeoDjango looks these up as Django settings, not as environment variables
# (see django/contrib/gis/gdal/libgdal.py, which reads
# settings.GDAL_LIBRARY_PATH). Under Nix the libraries are in the store, where
# ctypes.util.find_library cannot find them, so the paths baked into the
# package wrappers have to be promoted into settings here.
GDAL_LIBRARY_PATH = os.environ.get("GDAL_LIBRARY_PATH")
GEOS_LIBRARY_PATH = os.environ.get("GEOS_LIBRARY_PATH")

# Never inherit the development SECRET_KEY committed in settings.py: it is
# public, so reusing it would let anyone forge sessions and password reset
# tokens.
SECRET_KEY = _required("QGISFEED_SECRET_KEY")

# Comma separated list, e.g. "feed.qgis.org". Defaults to the public hostname
# rather than "*" so a misconfigured proxy cannot be used for host header
# poisoning.
ALLOWED_HOSTS = [
    host.strip()
    for host in os.environ.get("QGISFEED_ALLOWED_HOSTS", "").split(",")
    if host.strip()
]

DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": os.environ.get("QGISFEED_DOCKER_DBNAME", "qgisfeed"),
        "USER": os.environ.get("QGISFEED_DOCKER_DBUSER", "qgisfeed"),
        "PASSWORD": os.environ.get("QGISFEED_DOCKER_DBPASSWORD", ""),
        "HOST": os.environ.get("QGISFEED_DOCKER_DBHOST", "/run/postgresql"),
        "PORT": os.environ.get("QGISFEED_DOCKER_DBPORT", "5432"),
    }
}

# systemd StateDirectory=qgisfeed gives us /var/lib/qgisfeed.
_state_dir = os.environ.get("STATE_DIRECTORY", "/var/lib/qgisfeed")

MEDIA_ROOT = os.environ.get("QGISFEED_MEDIA_ROOT", os.path.join(_state_dir, "media"))
MEDIA_URL = "/media/"
STATIC_ROOT = os.environ.get("QGISFEED_STATIC_ROOT", os.path.join(_state_dir, "static"))
STATIC_URL = "/static/"

os.makedirs(MEDIA_ROOT, exist_ok=True)
os.makedirs(STATIC_ROOT, exist_ok=True)

# Terminating TLS at the reverse proxy.
USE_X_FORWARDED_PORT = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

QGIS_FEED_PROD_URL = os.environ.get("QGIS_FEED_PROD_URL", "")
CSRF_TRUSTED_ORIGINS = [
    "https://" + QGIS_FEED_PROD_URL for _ in [None] if QGIS_FEED_PROD_URL
]
CORS_ORIGIN_WHITELIST = CSRF_TRUSTED_ORIGINS

# Cookies are only ever sent over TLS in production.
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
