# Checks run by `nix flake check`.
{
  self,
  pkgs,
  nixpkgs,
}:

let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # Evaluates the NixOS module into a complete system configuration and asserts
  # the important properties of the generated unit. This catches option type
  # errors, typos in serviceConfig keys and accidental loosening of the
  # hardening or of ALLOWED_HOSTS, without needing to boot a VM.
  #
  # It is not a substitute for nixosTest: it proves the unit is generated
  # correctly, not that the service starts. Booting a VM needs KVM, which is
  # not available in every CI runner, so that test lives in
  # nix/nixos-test.nix and is run explicitly.
  nixos-module-eval =
    let
      machine = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.qgisfeed
          {
            boot.loader.grub.enable = false;
            fileSystems."/" = {
              device = "/dev/sda1";
              fsType = "ext4";
            };
            system.stateVersion = "26.05";
            services.qgisfeed = {
              enable = true;
              domain = "feed.qgis.org";
              environmentFile = "/run/secrets/qgisfeed.env";
            };
          }
        ];
      };

      unit = machine.config.systemd.services.qgisfeed;
      sc = unit.serviceConfig;

      assertions = [
        {
          name = "gunicorn is not started under Type=notify, which it does not implement";
          ok = sc.Type == "exec";
        }
        {
          name = "the service runs as an unprivileged dynamic user";
          ok = sc.DynamicUser == true;
        }
        {
          name = "the filesystem is protected";
          ok = sc.ProtectSystem == "strict";
        }
        {
          name = "no capabilities are retained";
          ok = sc.CapabilityBoundingSet == [ "" ];
        }
        {
          name = "secrets come from an EnvironmentFile, not the Nix store";
          ok = sc.EnvironmentFile == "/run/secrets/qgisfeed.env";
        }
        {
          name = "ALLOWED_HOSTS is restricted to the configured domain";
          ok = unit.environment.QGISFEED_ALLOWED_HOSTS == "feed.qgis.org";
        }
        {
          name = "the production settings module is used";
          ok = unit.environment.DJANGO_SETTINGS_MODULE == "qgisfeedproject.settings_nix_production";
        }
        {
          name = "no secret is passed through the unit environment";
          ok = !(builtins.hasAttr "QGISFEED_SECRET_KEY" unit.environment);
        }
        {
          name = "migrations and collectstatic run before the server starts";
          ok = builtins.length sc.ExecStartPre == 2;
        }
      ];

      failures = builtins.filter (a: !a.ok) assertions;
    in
    if failures == [ ] then
      pkgs.runCommand "nixos-module-eval-ok" { } ''
        echo "${toString (builtins.length assertions)} assertions passed" > $out
      ''
    else
      throw ''
        NixOS module assertions failed:
        ${builtins.concatStringsSep "\n" (map (f: "  - ${f.name}") failures)}
      '';

  # Fails the build if any committed shell script has a syntax error or a
  # shellcheck finding. SC1091 is excluded because common.sh is sourced through
  # a path resolved at runtime, which shellcheck cannot follow.
  shellcheck = pkgs.runCommand "shellcheck-scripts" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
    shellcheck -e SC1091 ${../scripts/nix}/*.sh
    touch $out
  '';
}
