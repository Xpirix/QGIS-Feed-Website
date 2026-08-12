# Checks run by `nix flake check`.
#
# The application itself is checked by nix/package.nix, whose installCheckPhase
# runs `qgisfeed-manage check` and exercises the uWSGI wrapper. Building
# packages.qgisfeed therefore already proves the closure imports.
{ pkgs }:

{
  # Fails the build if any committed shell script has a syntax error or a
  # shellcheck finding. SC1091 is excluded because common.sh is sourced through
  # a path resolved at runtime, which shellcheck cannot follow.
  shellcheck = pkgs.runCommand "shellcheck-scripts" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    shellcheck -e SC1091 ${../scripts/nix}/*.sh
    touch $out
  '';
}
