"""Settings for the Nix development environment.

Almost everything is inherited. settings.py reads the database connection,
MEDIA_ROOT, STATIC_ROOT and GEOIP_PATH from the environment, and
scripts/nix/common.sh exports all of them pointing at the project-local
cluster and state directory - so this module only has to relax ALLOWED_HOSTS
and tell GeoDjango where its libraries are.

settings_dev.py is deliberately not reused: it hardcodes HOST = "postgis",
which only exists inside the docker compose network.
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
