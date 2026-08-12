# The deployable QGIS Feed application.
#
# Produces:
#   $out/share/qgisfeed/qgisfeedproject  - the Django project
#   $out/share/qgisfeed/webpack-stats.json
#   $out/bin/qgisfeed-manage             - manage.py wrapper
#   $out/bin/qgisfeed-uwsgi              - uWSGI wrapper, the deployment entry
#   $out/bin/qgisfeed-gunicorn           - gunicorn wrapper, for local runs
#
# The deployment speaks the uwsgi protocol to nginx, so qgisfeed-uwsgi is what
# the infrastructure runs. gunicorn is kept because it is what
# REQUIREMENTS_PRODUCTION.txt pins for the docker image.
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

  python = pkgs.python312;

  # uWSGI is built with only the python3 plugin. It embeds its own interpreter,
  # so the application's dependencies are put on PYTHONPATH by the wrapper
  # below rather than by building uWSGI against pythonEnv directly.
  uwsgi = pkgs.uwsgi.override {
    plugins = [ "python3" ];
    python3 = python;
  };

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
      --set-default DJANGO_SETTINGS_MODULE qgisfeedproject.settings \
      --set GDAL_LIBRARY_PATH ${gdalLib} \
      --set GEOS_LIBRARY_PATH ${geosLib} \
      --set PROJ_LIB ${pkgs.proj}/share/proj

    # uWSGI embeds its own interpreter, so both the project directory and the
    # dependency environment have to be on PYTHONPATH explicitly.
    makeWrapper ${uwsgi}/bin/uwsgi $out/bin/qgisfeed-uwsgi \
      --prefix PYTHONPATH : "$appdir/qgisfeedproject" \
      --prefix PYTHONPATH : "${pythonEnv}/${python.sitePackages}" \
      --set-default DJANGO_SETTINGS_MODULE qgisfeedproject.settings \
      --set GDAL_LIBRARY_PATH ${gdalLib} \
      --set GEOS_LIBRARY_PATH ${geosLib} \
      --set PROJ_LIB ${pkgs.proj}/share/proj \
      --chdir "$appdir"

    makeWrapper ${pythonEnv}/bin/gunicorn $out/bin/qgisfeed-gunicorn \
      --prefix PYTHONPATH : "$appdir/qgisfeedproject" \
      --set-default DJANGO_SETTINGS_MODULE qgisfeedproject.settings \
      --set GDAL_LIBRARY_PATH ${gdalLib} \
      --set GEOS_LIBRARY_PATH ${geosLib} \
      --set PROJ_LIB ${pkgs.proj}/share/proj \
      --chdir "$appdir"

    runHook postInstall
  '';

  # Catches import errors and missing dependencies at build time rather than on
  # the deployment host. This is what caught GeoDjango failing to find libgdal.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export MEDIA_ROOT=$TMPDIR/media
    export STATIC_ROOT=$TMPDIR/static
    mkdir -p "$MEDIA_ROOT" "$STATIC_ROOT"

    $out/bin/qgisfeed-manage check

    # The uWSGI wrapper has its own PYTHONPATH, so prove that interpreter can
    # import the application too - a broken path here would otherwise only
    # surface when the service starts.
    $out/bin/qgisfeed-uwsgi --version >/dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "QGIS Home Page News Feed - Django application";
    homepage = "https://github.com/qgis/QGIS-Feed-Website";
    mainProgram = "qgisfeed-gunicorn";
  };
}
