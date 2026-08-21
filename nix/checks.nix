# Checks run by `nix flake check`.
#
# Two tiers. Everything except `integration` is hermetic, needs no database and
# finishes in seconds; `integration` starts a PostGIS cluster in the build
# sandbox and runs the Django suite, so it takes minutes.
#
# No test logic lives in this file: each check reads a committed script from
# tests/nix and passes it what it needs through the derivation environment.
{
  pkgs,
  pythonEnv,
  qgisfeed,
  postgresql,
}:

let
  # The package installs the Django project one level below the share
  # directory; settings.py resolves BASE_DIR and webpack-stats.json from it.
  appPythonPath = "${qgisfeed}/share/qgisfeed/qgisfeedproject";

  # Attributes every check that drives the application needs. Reading the
  # program names off passthru rather than repeating them means a rename shows
  # up as a failing check instead of a check that quietly tests nothing.
  appAttrs = {
    app = qgisfeed;
    inherit (qgisfeed)
      manageProgram
      uwsgiProgram
      uwsgiIni
      wsgiModule
      settingsModule
      fetchGeoip
      ;
  };

  check =
    name: attrs: script:
    pkgs.runCommand "check-${name}" attrs (builtins.readFile script);
in
{
  # Fails the build if any committed shell script has a syntax error or a
  # shellcheck finding. SC1091 is excluded because common.sh is sourced through
  # a path resolved at runtime, which shellcheck cannot follow.
  shellcheck = pkgs.runCommand "shellcheck-scripts" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    shellcheck -e SC1091 ${../scripts/nix}/*.sh ${../tests/nix}/*.sh
    touch $out
  '';

  # The same formatting the pre-commit hook applies, enforced where CI can see
  # it, so a checkout that never installed the hooks cannot drift.
  nixfmt = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    nixfmt --check ${../flake.nix} ${../nix}/*.nix
    touch $out
  '';

  # The deployment interface: everything passthru advertises must exist.
  passthru-contract = check "passthru-contract" appAttrs ../tests/nix/passthru-contract.sh;

  # The environment variables settings.py reads, which the infrastructure
  # depends on and CONTRIBUTING.md documents.
  settings-contract = check "settings-contract" {
    nativeBuildInputs = [ pythonEnv ];
    testScript = ../tests/nix/settings_contract.py;
    inherit appPythonPath;
  } ../tests/nix/settings-contract.sh;

  # Models and migrations agree.
  migration-drift = check "migration-drift" appAttrs ../tests/nix/migration-drift.sh;

  # The WSGI callable imports inside uWSGI's embedded interpreter.
  uwsgi-app-load = check "uwsgi-app-load" appAttrs ../tests/nix/uwsgi-app-load.sh;

  # Slow tier: the Django test suite and one real request, against PostGIS.
  integration = check "integration" (
    appAttrs
    // {
      nativeBuildInputs = [
        postgresql
        pythonEnv
        pkgs.curl
        pkgs.coreutils
      ];
      # The package drops the media directory, so the test fixture image
      # comes from the source tree.
      fixtureImage = ../qgisfeedproject/media/feedimages/rust.png;
    }
  ) ../tests/nix/integration.sh;
}
