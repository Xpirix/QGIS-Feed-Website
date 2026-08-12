{
  description = "QGIS Home Page News Feed - development environment and application package";

  inputs = {
    # nixpkgs is pinned centrally for all QGIS infrastructure repositories so
    # that projects share a binary cache and stay on compatible package sets.
    # Bump the version there, not here.
    nixpkgs-version.url = "github:QGIS/qgis-nixpkgs-version";
    nixpkgs.follows = "nixpkgs-version/nixpkgs-26-05";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      # PostGIS has to be built into the PostgreSQL environment, not merely
      # placed alongside it on PATH: the server resolves extension control
      # files under its own share/postgresql/extension, so a separate postgis
      # package is invisible to it and CREATE EXTENSION fails with
      # 'extension "postgis" is not available'.
      postgresqlFor = pkgs: pkgs.postgresql_16.withPackages (ps: [ ps.postgis ]);
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          inherit (import ./nix/python.nix { inherit pkgs; }) pythonEnv;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pythonEnv
              pkgs.nodejs_22
              (postgresqlFor pkgs)
              pkgs.gdal
              pkgs.geos
              pkgs.proj
              pkgs.libmaxminddb
              pkgs.pre-commit
              pkgs.curl
              pkgs.git
              pkgs.nixfmt
              pkgs.shellcheck
            ];

            # GeoDjango resolves these libraries with ctypes at import time and
            # cannot find them inside the Nix store without an explicit path.
            GDAL_LIBRARY_PATH = "${pkgs.gdal}/lib/libgdal${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
            GEOS_LIBRARY_PATH = "${pkgs.geos}/lib/libgeos_c${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";
            PROJ_LIB = "${pkgs.proj}/share/proj";

            # The hook sources scripts/nix/common.sh, which needs to know where
            # the checkout is before PROJECT_ROOT has been established.
            shellHook = ''
              export PROJECT_ROOT_HINT="$PWD"
              source ${./scripts/nix/shell-hook.sh}
            '';
          };
        }
      );

      apps = forAllSystems (
        pkgs:
        let
          inherit (import ./nix/python.nix { inherit pkgs; }) pythonEnv;

          # Every helper is a committed dotfile under scripts/nix, wrapped so it
          # runs with a known set of tools on PATH. No shell logic lives in Nix.
          mkScript =
            name: runtimeInputs:
            pkgs.writeShellApplication {
              inherit name runtimeInputs;
              text = builtins.readFile (./scripts/nix + "/${name}.sh");
              # common.sh is sourced at runtime from the checkout, so shellcheck
              # cannot see the variables it defines.
              excludeShellChecks = [ "SC1091" ];
            };

          baseTools = [
            pythonEnv
            pkgs.git
            (postgresqlFor pkgs)
          ];

          mkApp = drv: {
            type = "app";
            program = "${drv}/bin/${drv.name}";
          };
        in
        {
          db-start = mkApp (mkScript "db-start" baseTools);
          db-stop = mkApp (mkScript "db-stop" baseTools);
          db-reset = mkApp (mkScript "db-reset" baseTools);
          # coreutils supplies du/cut for the dump size shown in the prompt.
          db-restore = mkApp (mkScript "db-restore" (baseTools ++ [ pkgs.coreutils ]));
          manage = mkApp (mkScript "manage" baseTools);
          dev = mkApp (mkScript "dev" (baseTools ++ [ pkgs.nodejs_22 ]));
          test = mkApp (mkScript "test" baseTools);
          fetch-geoip = mkApp (mkScript "fetch-geoip" (baseTools ++ [ pkgs.curl ]));
        }
      );

      packages = forAllSystems (
        pkgs:
        let
          inherit (import ./nix/python.nix { inherit pkgs; }) pythonEnv;
          staticAssets = import ./nix/static-assets.nix { inherit pkgs; };
          qgisfeed = import ./nix/package.nix { inherit pkgs pythonEnv staticAssets; };
        in
        {
          inherit staticAssets qgisfeed;
          default = qgisfeed;
        }
      );

      nixosModules = {
        qgisfeed = import ./nix/nixos-module.nix { inherit self; };
        default = self.nixosModules.qgisfeed;
      };

      checks = forAllSystems (pkgs: import ./nix/checks.nix { inherit self pkgs nixpkgs; });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
