"""Settings for the Nix development environment.

Unlike settings_dev.py, this module does not redefine DATABASES. The block in
settings.py is already driven by the QGISFEED_DOCKER_DB* environment variables,
and scripts/nix/common.sh points QGISFEED_DOCKER_DBHOST at the project-local
unix socket directory, so the inherited configuration connects to the local
cluster without any docker networking.
"""

import os

from .settings import *  # noqa: F401,F403

# The dev server is reached as localhost or 127.0.0.1 depending on the browser.
ALLOWED_HOSTS = ["*"]

# GeoDjango looks these up as Django settings, not as environment variables
# (see django/contrib/gis/gdal/libgdal.py, which reads
# settings.GDAL_LIBRARY_PATH). Under Nix the libraries are in the store, where
# ctypes.util.find_library cannot find them, so the paths exported by the
# devShell have to be promoted into settings here.
GDAL_LIBRARY_PATH = os.environ.get("GDAL_LIBRARY_PATH")
GEOS_LIBRARY_PATH = os.environ.get("GEOS_LIBRARY_PATH")

# settings.py hardcodes GEOIP_PATH = "/var/opt/maxmind/", which is the docker
# image layout and does not exist on a developer machine. Django reads this as a
# setting, so exporting GEOIP_PATH from common.sh alone has no effect; point it
# at the directory fetch-geoip.sh writes into.
GEOIP_PATH = os.environ.get("GEOIP_PATH", GEOIP_PATH)  # noqa: F405

# Media follows QGISFEED_MEDIA_VOLUME (resolved into QGISFEED_MEDIA_ROOT by
# common.sh), the same host directory docker compose bind-mounts to
# /shared-volume/media. Without an override this stays at the settings.py
# default of <checkout>/qgisfeedproject/media.
MEDIA_ROOT = os.environ.get("QGISFEED_MEDIA_ROOT", MEDIA_ROOT)  # noqa: F405

# settings.py sets STATIC_URL but never STATIC_ROOT, so collectstatic has
# nowhere to write. The fallback only applies when the helpers were bypassed.
STATIC_ROOT = os.environ.get("QGISFEED_STATIC_ROOT") or os.path.join(
    BASE_DIR, "static_collected"  # noqa: F405
)
