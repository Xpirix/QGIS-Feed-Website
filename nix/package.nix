# The deployable QGIS Feed application.
#
# Produces:
#   $out/share/qgisfeed/qgisfeedproject  - the Django project
#   $out/share/qgisfeed/webpack-stats.json
#   $out/bin/qgisfeed-manage             - manage.py wrapper
#   $out/bin/qgisfeed-gunicorn           - gunicorn wrapper
#
# The layout mirrors the docker image on purpose: settings.py computes
# BASE_DIR as the qgisfeedproject directory and looks for webpack-stats.json
# one level above it, so the two must stay in that relationship.
{
  pkgs,
  pythonEnv,
  staticAssets,
}:

let
  version = "1.0.0";

  # GeoDjango loads these with ctypes at import time and cannot find them in the
  # Nix store on its own, so the wrappers below bake the paths in. Without them
  # `import django.contrib.gis` fails on the deployment host.
  soExt = pkgs.stdenv.hostPlatform.extensions.sharedLibrary;
  gdalLib = "${pkgs.gdal}/lib/libgdal${soExt}";
  geosLib = "${pkgs.geos}/lib/libgeos_c${soExt}";

  # Only the sources the application actually needs. Excluding the docker,
  # node_modules and .nix trees keeps the closure small and stops unrelated
  # edits from triggering a rebuild.
  src = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [
      ../qgisfeedproject
      ../REQUIREMENTS.txt
    ];
  };
in
pkgs.stdenv.mkDerivation {
  pname = "qgisfeed";
  inherit version src;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    appdir=$out/share/qgisfeed
    mkdir -p "$appdir"
    cp -r qgisfeedproject "$appdir/qgisfeedproject"

    # Webpack output. The bundles live inside STATICFILES_DIRS so that
    # collectstatic picks them up; the stats file sits one level above
    # BASE_DIR, where settings.py expects it.
    mkdir -p "$appdir/qgisfeedproject/static/bundles"
    cp -r ${staticAssets}/bundles/. "$appdir/qgisfeedproject/static/bundles/"
    cp ${staticAssets}/webpack-stats.json "$appdir/webpack-stats.json"

    # Media and static roots are runtime state and come from the systemd
    # StateDirectory, so drop anything that shipped in the source tree.
    rm -rf "$appdir/qgisfeedproject/media"

    mkdir -p $out/bin

    makeWrapper ${pythonEnv}/bin/python $out/bin/qgisfeed-manage \
      --add-flags "$appdir/qgisfeedproject/manage.py" \
      --prefix PYTHONPATH : "$appdir/qgisfeedproject" \
      --set-default DJANGO_SETTINGS_MODULE qgisfeedproject.settings_nix_production \
      --set GDAL_LIBRARY_PATH ${gdalLib} \
      --set GEOS_LIBRARY_PATH ${geosLib} \
      --set PROJ_LIB ${pkgs.proj}/share/proj

    makeWrapper ${pythonEnv}/bin/gunicorn $out/bin/qgisfeed-gunicorn \
      --prefix PYTHONPATH : "$appdir/qgisfeedproject" \
      --set-default DJANGO_SETTINGS_MODULE qgisfeedproject.settings_nix_production \
      --set GDAL_LIBRARY_PATH ${gdalLib} \
      --set GEOS_LIBRARY_PATH ${geosLib} \
      --set PROJ_LIB ${pkgs.proj}/share/proj \
      --chdir "$appdir"

    runHook postInstall
  '';

  # Catches import errors and missing dependencies at build time rather than on
  # the deployment host. Uses a throwaway SECRET_KEY because
  # settings_nix_production refuses to start without one.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export QGISFEED_SECRET_KEY=build-time-check-not-a-real-secret
    export QGISFEED_ALLOWED_HOSTS=localhost
    export STATE_DIRECTORY=$TMPDIR/state
    mkdir -p "$STATE_DIRECTORY"

    $out/bin/qgisfeed-manage check

    runHook postInstallCheck
  '';

  meta = {
    description = "QGIS Home Page News Feed - Django application";
    homepage = "https://github.com/qgis/QGIS-Feed-Website";
    mainProgram = "qgisfeed-gunicorn";
  };
}
